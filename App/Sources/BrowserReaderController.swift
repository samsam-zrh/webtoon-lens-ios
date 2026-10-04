import Observation
import OSLog
import SwiftUI
import UIKit
import WebKit
import WebtoonLensCore

struct BrowserViewportCapture {
    let image: UIImage
    let data: Data
    var alreadyTranslated: [TranslationSourceSegment] = []
    var region: NormalizedRect?
}

struct NativeWebtoonBrowser: UIViewRepresentable {
    let controller: BrowserReaderController

    func makeCoordinator() -> BrowserReaderController { controller }

    func makeUIView(context: Context) -> BrowserSurfaceView {
        let surface = BrowserSurfaceView()
        controller.attach(surface)
        return surface
    }

    func updateUIView(_ uiView: BrowserSurfaceView, context: Context) {}

    static func dismantleUIView(_ uiView: BrowserSurfaceView, coordinator: BrowserReaderController) {
        coordinator.detach(uiView)
    }
}

@MainActor
@Observable
final class BrowserReaderController: NSObject {
    private(set) var currentURL: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var isTranslating = false
    private(set) var wantsTranslation = false
    private(set) var autoTranslate = false
    private(set) var result: TranslationResult?
    private(set) var status = "Colle un lien HTTP ou HTTPS. La traduction et le mode Auto sont desactives au depart."
    private(set) var hasError = false
    private(set) var isCapturePending = false
    private(set) var captureProof = ""
    private(set) var documentIdentifier: String?
    var pageTitle: String? { surface?.webView.title }
    private(set) var anchorCacheProof = ""
    var diagnosticState: String {
        "active=\(active), ready=\(ready), requested=\(wantsTranslation), translating=\(isTranslating), pending=\(isCapturePending), anchors=\(anchoredCache.count); \(status)"
    }
    @ObservationIgnored var onScroll: (@MainActor (Double) -> Void)?
    @ObservationIgnored var onReady: (@MainActor () -> Void)?
    @ObservationIgnored var onNavigationStarted: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var onTranslated: (@MainActor () -> Void)?

    @ObservationIgnored private weak var surface: BrowserSurfaceView?
    @ObservationIgnored private var lifecycle = BrowserCaptureLifecycle()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var activeRunID: UUID?
    @ObservationIgnored private var pendingCapture = false
    @ObservationIgnored private var manualCaptureRequested = false
    @ObservationIgnored private var stabilizationWindow: BrowserStabilizationWindow?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var autoPausedAfterError = false
    @ObservationIgnored private var contextID = ""
    @ObservationIgnored private var documentID: String?
    @ObservationIgnored private var documentRevision = -1
    @ObservationIgnored private var contentRevision = -1
    @ObservationIgnored private var displayGuardTask: Task<Void, Never>?
    @ObservationIgnored private var displayedCapture: (BrowserCaptureToken, [(NormalizedRect, String)])?
    @ObservationIgnored private var explicitCaptureIntent = false
    @ObservationIgnored private var stabilizationRetries = 0
    @ObservationIgnored private var intentWindow: BrowserStabilizationWindow?
    @ObservationIgnored private var navigationUserInitiated = false
    @ObservationIgnored private let anchoredCache = BrowserAnchoredCache()
    @ObservationIgnored private var armedDocumentID: String?
    @ObservationIgnored private var translate: (@MainActor (BrowserViewportCapture) async throws -> TranslationResult)?

    private static let contentWorld = WKContentWorld.world(name: "WebtoonLensV2")
    private static let logger = Logger(subsystem: "com.example.webtoonlens.v2", category: "ViewportLifecycle")

    func attach(_ surface: BrowserSurfaceView) {
        self.surface = surface
        let webView = surface.webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(self, contentWorld: Self.contentWorld, name: BrowserBridgeScript.handlerName)
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: BrowserBridgeScript.source, injectionTime: .atDocumentEnd,
            forMainFrameOnly: BrowserBridgeScript.mainFrameOnly, in: Self.contentWorld
        ))
        surface.onSizeChange = { [weak self] in self?.viewportChanged(reason: "size", settling: true, preserveFinished: true) }
        let scrollView = webView.scrollView
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(gestureChanged(_:)))
        scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(gestureChanged(_:)))
        observations = [
            scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] scroll, change in
                guard change.oldValue != change.newValue else { return }
                MainActor.assumeIsolated {
                    if let old = change.oldValue, let new = change.newValue {
                        self?.surface?.shiftAnchoredTranslations(dx: old.x - new.x, dy: old.y - new.y)
                    }
                    self?.viewportChanged(reason: "offset", settling: !scroll.isDragging && !scroll.isDecelerating,
                                          preserveFinished: true, continueDocument: true)
                    if scroll.isDragging || scroll.isDecelerating { self?.onScroll?(Double(scroll.contentOffset.y)) }
                }
            },
            scrollView.observe(\.zoomScale, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue != change.newValue else { return }
                MainActor.assumeIsolated { self?.viewportChanged(reason: "zoom") }
            },
            webView.observe(\.canGoBack) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.url) { [weak self] view, _ in
                MainActor.assumeIsolated {
                    guard self?.currentURL != view.url else { return }
                    self?.currentURL = view.url
                    self?.viewportChanged(reason: "url")
                }
            }
        ]
        if let currentURL { webView.load(URLRequest(url: currentURL)) }
    }

    func detach(_ surface: BrowserSurfaceView) {
        setActive(false)
        surface.onSizeChange = nil
        let webView = surface.webView
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.scrollView.panGestureRecognizer.removeTarget(self, action: #selector(gestureChanged(_:)))
        webView.scrollView.pinchGestureRecognizer?.removeTarget(self, action: #selector(gestureChanged(_:)))
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: BrowserBridgeScript.handlerName, contentWorld: Self.contentWorld
        )
        webView.configuration.userContentController.removeAllUserScripts()
        observations.removeAll()
        self.surface = nil
        ready = false
    }

    func configure(context: String, translate: @escaping @MainActor (BrowserViewportCapture) async throws -> TranslationResult) {
        self.translate = translate
        if contextID != context {
            contextID = context
            invalidate()
            if wantsTranslation { status = "Reglages modifies. Touchez Traduire pour cette zone." }
        }
    }

    func setActive(_ value: Bool) {
        Self.logger.debug("Reader active: \(value)")
        active = value
        if !value {
            invalidate(clearFinished: false, disarmDocument: false)
            surface?.clearTranslation()
        } else if anchoredCache.count > 0, wantsTranslation {
            startDisplayGuard()
        } else if wantsTranslation && autoTranslate && !autoPausedAfterError {
            scheduleCapture()
        }
    }

    func open(_ url: URL) {
        guard let surface else { report(BrowserCaptureError.unavailablePage); return }
        invalidate()
        wantsTranslation = false
        currentURL = url
        surface.webView.load(URLRequest(url: url))
    }

    var canCapture: Bool { ready && currentURL != nil && active }

    func goBack() {
        invalidate()
        surface?.webView.goBack()
    }

    func goForward() {
        invalidate()
        surface?.webView.goForward()
    }

    func reload() {
        invalidate()
        surface?.webView.reload()
    }

    func setAutoTranslation(_ enabled: Bool) {
        autoTranslate = enabled
        autoPausedAfterError = false
        if !enabled {
            debounceTask?.cancel()
            pendingCapture = false
        }
    }

    func showOriginal() {
        wantsTranslation = false
        invalidate()
        status = "Original. Aucune capture n'est envoyee ; les images restent sur l'iPhone."
        hasError = false
    }

    func translateVisible() {
        guard ready, currentURL != nil else { report(BrowserCaptureError.unavailablePage); return }
        invalidate(clearFinished: false, disarmDocument: false)
        wantsTranslation = true
        isCapturePending = true
        manualCaptureRequested = true
        explicitCaptureIntent = true
        stabilizationRetries = 0
        intentWindow = BrowserStabilizationWindow()
        stabilizationWindow = BrowserStabilizationWindow()
        autoPausedAfterError = false
        status = "Attente d'une zone stable..."
        hasError = false
        scheduleCapture()
    }

    func report(_ error: Error, keepFinished: Bool = false) {
        invalidate(clearFinished: !keepFinished, disarmDocument: !keepFinished)
        autoPausedAfterError = true
        status = "\(error.localizedDescription) Original conserve."
        hasError = true
    }

    private func invalidate(clearFinished: Bool = true, disarmDocument: Bool = true) {
        lifecycle.invalidate()
        activeTask?.cancel()
        debounceTask?.cancel()
        pendingCapture = false
        manualCaptureRequested = false
        stabilizationWindow = nil
        explicitCaptureIntent = false
        intentWindow = nil
        isCapturePending = false
        displayGuardTask?.cancel()
        displayedCapture = nil
        if clearFinished {
            anchoredCache.clear()
            surface?.clearTranslation()
            result = nil
        }
        if disarmDocument { armedDocumentID = nil }
    }

    private func viewportChanged(
        reason: String, settling: Bool = false, preserveFinished: Bool = false, continueDocument: Bool = false
    ) {
        Self.logger.notice("Viewport invalidated: \(reason, privacy: .public)")
        let shouldResumeManual = manualCaptureRequested
        let pendingWindow = stabilizationWindow
        let retryIntent = explicitCaptureIntent && settling && stabilizationRetries < 2 && intentWindow?.hasExpired() == false
        let retries = stabilizationRetries
        let window = intentWindow
        let hadWork = result != nil || isTranslating
        let documentGoal = armedDocumentID
        invalidate(clearFinished: !preserveFinished, disarmDocument: !preserveFinished)
        if hadWork {
            status = preserveFinished && anchoredCache.count > 0
                ? "Lecture en cours · traductions conservees."
                : "Zone modifiee. Original conserve\(autoTranslate && !autoPausedAfterError ? " ; Auto attend la fin du mouvement." : " ; touchez Traduire.")"
            hasError = false
        }
        if continueDocument, documentGoal != nil {
            armedDocumentID = documentGoal
            wantsTranslation = true
            manualCaptureRequested = true
            explicitCaptureIntent = true
            intentWindow = BrowserStabilizationWindow()
            stabilizationWindow = intentWindow
            isCapturePending = true
            scheduleCapture()
        } else if shouldResumeManual {
            manualCaptureRequested = true
            isCapturePending = true
            stabilizationWindow = pendingWindow
            explicitCaptureIntent = true
            intentWindow = window
            scheduleCapture()
        } else if retryIntent {
            explicitCaptureIntent = true
            intentWindow = window
            stabilizationRetries = retries + 1
            manualCaptureRequested = true
            wantsTranslation = true
            isCapturePending = true
            stabilizationWindow = window
            status = "Mise en page en cours · traduction apres stabilisation…"
            scheduleCapture()
        } else if wantsTranslation && autoTranslate && !autoPausedAfterError {
            scheduleCapture()
        }
        if preserveFinished, anchoredCache.count > 0, active, ready, wantsTranslation {
            startDisplayGuard()
        }
    }

    @objc private func gestureChanged(_ gesture: UIGestureRecognizer) {
        viewportChanged(reason: "gesture", preserveFinished: true, continueDocument: true)
    }

    private func scheduleCapture() {
        guard active, ready, wantsTranslation else {
            Self.logger.debug("Capture not scheduled: active \(self.active), ready \(self.ready), requested \(self.wantsTranslation)")
            return
        }
        if stabilizationWindow?.hasExpired() == true {
            report(BrowserCaptureError.unstableViewport)
            return
        }
        debounceTask?.cancel()
        let epoch = lifecycle.epoch
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                guard let self, self.active, self.ready, self.wantsTranslation, self.lifecycle.epoch == epoch else { return }
                if self.stabilizationWindow?.hasExpired() == true {
                    self.report(BrowserCaptureError.unstableViewport)
                    return
                }
                guard let scroll = self.surface?.webView.scrollView,
                      !scroll.isDragging, !scroll.isDecelerating, !scroll.isZooming else {
                    self.scheduleCapture()
                    return
                }
                self.pendingCapture = true
                self.pump()
            } catch is CancellationError {
                // A newer viewport or explicit Original action owns the next request.
            } catch {
                self?.report(error)
            }
        }
    }

    private func pump() {
        guard pendingCapture, activeTask == nil, active, ready, wantsTranslation else { return }
        pendingCapture = false
        manualCaptureRequested = false
        stabilizationWindow = nil
        let runID = UUID()
        activeRunID = runID
        isTranslating = true
        isCapturePending = true
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.captureAndTranslate()
            if self.activeRunID == runID {
                self.activeRunID = nil
                self.activeTask = nil
                self.isTranslating = false
                self.isCapturePending = false
                self.pump()
            }
        }
    }

    private func captureAndTranslate() async {
        var token: BrowserCaptureToken?
        var capturedDocument: BrowserDocumentState?
        let startingEpoch = lifecycle.epoch
        defer { if let token { lifecycle.finish(token) } }
        do {
            guard let surface, let translate, active, ready else { throw BrowserCaptureError.unavailablePage }
            Self.logger.notice("Capture stage: read document.")
            let geometry = surface.geometry
            let document = try await readDocument()
            documentIdentifier = document.documentID
            capturedDocument = document
            if armedDocumentID == nil { armedDocumentID = document.documentID }
            guard armedDocumentID == document.documentID else { throw BrowserCaptureError.changedContent }
            try Task.checkCancellation()
            guard lifecycle.epoch == startingEpoch, geometry.matches(surface.geometry) else { throw CancellationError() }
            let captureToken = try lifecycle.begin(geometry: geometry, document: document)
            token = captureToken
            status = "Capture locale et OCR sur l'iPhone..."
            if anchoredCache.count > 0 { try await refreshAnchors(document: document) }
            Self.logger.notice("Capture stage: native snapshot.")
            var capture = try await snapshot(document: document)
            let capturedRegion = capture.region ?? document.captureRegion ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
            let pixelDocument = document.capturing(in: capturedRegion)
            capture.alreadyTranslated = anchoredCache.coverage(pixelDocument)
            anchorCacheProof = try anchoredCache.diagnosticProof(document)
            let afterCapture = try await readDocument()
            try ensureCurrent(captureToken, document: afterCapture)

            status = "Traduction du texte OCR par ton backend local..."
            Self.logger.notice("Capture stage: OCR and text translation.")
            var translated = try await translate(capture)
            let afterTranslation = try await readDocument()
            try ensureCurrent(captureToken, document: afterTranslation)

            // Canvas pixels can change without a DOM mutation. Recheck the source itself.
            let verification = try await snapshot(document: afterTranslation)
            Self.logger.notice("Capture stage: verify translated regions.")
            let beforePresentation = try await readDocument()
            try ensureCurrent(captureToken, document: beforePresentation)
            guard let sourcePixels = capture.image.cgImage, let verificationPixels = verification.image.cgImage else {
                throw BrowserCaptureError.unreadableSnapshot
            }
            var accepted: [TranslatedSegmentPayload] = []
            for segment in translated.segments {
                if try ReadingPixelFingerprint.value(for: sourcePixels, region: segment.boundingBox) ==
                    ReadingPixelFingerprint.value(for: verificationPixels, region: segment.boundingBox) {
                    accepted.append(segment)
                } else {
                    translated.failures.append(SegmentTranslationFailure(
                        source: TranslationSourceSegment(id: segment.id, text: segment.sourceText,
                            boundingBox: segment.boundingBox, confidence: segment.confidence, readingOrder: segment.readingOrder),
                        message: "Cette zone a change pendant la traduction ; son original est conserve.", kind: .sourceChanged
                    ))
                }
            }
            guard !accepted.isEmpty || translated.segments.isEmpty else { throw BrowserCaptureError.changedContent }
            translated.segments = accepted
            let rect = captureRect(document: pixelDocument)
            for segment in accepted { try anchoredCache.store(segment, document: pixelDocument, image: sourcePixels) }
            anchorCacheProof = try anchoredCache.diagnosticProof(document)
            let count: Int
            if document.readingAnchor != nil {
                count = surface.presentAnchored(anchoredCache.placements(document, size: surface.webView.bounds.size))
            } else {
                count = surface.present(capture: capture.image, result: translated, in: rect)
            }
            if !anchoredCache.segments.isEmpty { translated.segments = anchoredCache.segments }
            let proof = BrowserReadingProof(
                pageURL: document.url, region: capturedRegion,
                readingKind: document.readingSource?.split(separator: ":").dropFirst().first.map(String.init),
                pixelWidth: sourcePixels.width, pixelHeight: sourcePixels.height,
                translatedSegments: translated.segments.count, fittedSegments: count
            )
            captureProof = String(decoding: try JSONEncoder().encode(proof), as: UTF8.self)
            result = translated
            hasError = !translated.failures.isEmpty
            if translated.segments.isEmpty {
                wantsTranslation = false
                status = "Aucun dialogue traduit. \(translated.failures.count) en erreur ; original conserve, details dans Texte."
            } else if !translated.failures.isEmpty {
                status = "\(ReadingCopy.translated(translated.segments.count)) · \(translated.failures.count) en erreur. Originaux conserves."
            } else if count == 0 {
                status = "Texte traduit disponible dans Texte. Zones trop petites ou incertaines : original visuel conserve."
            } else {
                let skipped = translated.segments.count - count
                status = "\(ReadingCopy.translated(count))\(skipped > 0 ? " · \(skipped) dans Texte" : ""). Defile pour continuer la lecture."
            }
            if anchoredCache.count > 0 {
                startDisplayGuard()
                if !accepted.isEmpty { onTranslated?() }
            } else if count > 0 {
                displayedCapture = (captureToken, try accepted.filter { surface.presentedSegmentIDs.contains($0.id) }.map {
                    ($0.boundingBox, try ReadingPixelFingerprint.value(for: sourcePixels, region: $0.boundingBox))
                })
                startDisplayGuard()
                onTranslated?()
            }
        } catch is CancellationError {
            // Never present or report an obsolete viewport result.
        } catch {
            if !Task.isCancelled, lifecycle.epoch == startingEpoch, active {
                if case TranslationPipelineError.noTextRecognized = error, anchoredCache.count > 0 {
                    status = "\(anchoredCache.count) dialogues conserves · zone sans texte lisible."
                    hasError = false
                    startDisplayGuard()
                } else if case BrowserCaptureError.changedContent = error, let capturedDocument,
                   await canRestabilize(capturedDocument) {
                    viewportChanged(reason: "reading layout settled", settling: true, preserveFinished: true)
                } else {
                    let privacy = [BrowserCaptureError.sensitivePage.localizedDescription,
                                   BrowserCaptureError.protectedPage.localizedDescription,
                                   BrowserCaptureError.unsupportedFrame.localizedDescription].contains(error.localizedDescription)
                    report(error, keepFinished: !privacy && anchoredCache.count > 0)
                }
            }
        }
    }

    private func canRestabilize(_ previous: BrowserDocumentState) async -> Bool {
        guard explicitCaptureIntent, stabilizationRetries < 2, intentWindow?.hasExpired() == false else { return false }
        do {
            let current = try await readDocument()
            try current.validateForCapture()
            return BrowserRestabilizationPolicy.allows(
                previous: previous, current: current, explicitIntent: explicitCaptureIntent,
                retries: stabilizationRetries, withinWindow: intentWindow?.hasExpired() == false
            )
        } catch {
            return false
        }
    }

    private func ensureCurrent(_ token: BrowserCaptureToken, document: BrowserDocumentState) throws {
        try Task.checkCancellation()
        guard let surface, active, ready, wantsTranslation, lifecycle.epoch == token.epoch else {
            throw CancellationError()
        }
        try document.validateForCapture()
        guard lifecycle.canCommit(token, geometry: surface.geometry, document: document) else {
            throw BrowserCaptureError.changedContent
        }
    }

    private func readDocument() async throws -> BrowserDocumentState {
        guard let webView = surface?.webView else { throw BrowserCaptureError.unavailablePage }
        return try await WebKitViewportCapture.document(in: webView, world: Self.contentWorld)
    }

    private func captureRect(document: BrowserDocumentState) -> CGRect {
        guard let bounds = surface?.webView.bounds else { return .zero }
        let region = document.captureRegion ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        return CGRect(x: region.x * bounds.width, y: region.y * bounds.height,
                      width: region.width * bounds.width, height: region.height * bounds.height)
            .intersection(bounds)
    }

    private func snapshot(document: BrowserDocumentState) async throws -> BrowserViewportCapture {
        guard let surface else { throw BrowserCaptureError.unavailablePage }
        if let anchor = document.readingAnchor, anchor.pixelWidth != nil, anchor.pixelHeight != nil,
           let visible = document.captureRegion {
            let plan = try BrowserSourceSnapshotPlan(anchor: anchor, visibleRegion: visible)
            let configuration = WKSnapshotConfiguration()
            configuration.rect = captureRect(document: document.capturing(in: plan.region))
            configuration.snapshotWidth = NSNumber(value: Double(plan.pixelWidth) / Double(surface.webView.traitCollection.displayScale))
            configuration.afterScreenUpdates = true
            let image = try await WebKitViewportCapture.snapshot(in: surface.webView, configuration: configuration)
            try Task.checkCancellation()
            guard Self.isUsable(image), let pixels = image.cgImage,
                  abs(pixels.width - plan.pixelWidth) <= 1, abs(pixels.height - plan.pixelHeight) <= 1,
                  let data = image.pngData() else { throw BrowserCaptureError.unreadableSnapshot }
            return BrowserViewportCapture(image: image, data: data, region: plan.region)
        }
        let rect = surface.webView.bounds
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        let geometry = BrowserViewportGeometry(width: rect.width, height: rect.height, offsetX: 0, offsetY: 0, zoomScale: 1)
        configuration.snapshotWidth = NSNumber(value: try geometry.snapshotWidth(
            pixelScale: Double(surface.webView.traitCollection.displayScale)
        ))
        configuration.afterScreenUpdates = true
        let viewport = try await WebKitViewportCapture.snapshot(in: surface.webView, configuration: configuration)
        try Task.checkCancellation()
        guard let pixels = viewport.cgImage else { throw BrowserCaptureError.unreadableSnapshot }
        let region = document.captureRegion ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let cropRect = try BrowserPixelCrop.rect(for: region, width: pixels.width, height: pixels.height)
        guard let crop = pixels.cropping(to: cropRect) else { throw BrowserCaptureError.unreadableSnapshot }
        let image = UIImage(cgImage: crop)
        guard Self.isUsable(image), let data = image.pngData(), !data.isEmpty else {
            throw BrowserCaptureError.unreadableSnapshot
        }
        return BrowserViewportCapture(image: image, data: data,
            region: BrowserPixelCrop.normalized(cropRect, width: pixels.width, height: pixels.height))
    }

    private func startDisplayGuard() {
        displayGuardTask?.cancel()
        displayGuardTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(500))
                    guard let self, let surface = self.surface, self.active else { return }
                    if self.anchoredCache.count > 0 {
                        let scroll = surface.webView.scrollView
                        if !self.isCapturePending && !self.isTranslating && !scroll.isDragging && !scroll.isDecelerating {
                            let document = try await self.readDocument()
                            try await self.refreshAnchors(document: document)
                        }
                        continue
                    }
                    guard let (token, fingerprints) = self.displayedCapture else { return }
                    let document = try await self.readDocument()
                    try document.validateForCapture()
                    guard token.epoch == self.lifecycle.epoch, token.geometry.matches(surface.geometry),
                          token.document.matchesReading(document) else {
                        let sameSource = token.document.documentID == document.documentID &&
                            token.document.url == document.url && token.document.readingSource == document.readingSource &&
                            token.document.revision == document.revision
                        self.viewportChanged(reason: "reading geometry changed", settling: sameSource)
                        return
                    }

                    let verification = try await self.snapshot(document: document)
                    try Task.checkCancellation()
                    guard let image = verification.image.cgImage else { throw BrowserCaptureError.unreadableSnapshot }
                    for (region, fingerprint) in fingerprints {
                        if try ReadingPixelFingerprint.value(for: image, region: region) != fingerprint {
                            self.viewportChanged(reason: "reading text pixels changed")
                            return
                        }
                    }
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self?.report(error) }
            }
        }
    }

    private static func isUsable(_ image: UIImage) -> Bool {
        guard let image = image.cgImage, image.width >= 32, image.height >= 32,
              image.width * image.height <= 4_000_000 else { return false }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        return drawn && ViewportPixelValidator.isUsable(rgba: pixels)
    }

    private func refreshAnchors(document: BrowserDocumentState) async throws {
        try document.validateForCapture()
        guard let surface, armedDocumentID == document.documentID else { throw BrowserCaptureError.changedContent }
        let epoch = lifecycle.epoch
        let geometry = surface.geometry
        var removed = anchoredCache.synchronizeSources(document)
        let anchors = anchoredCache.visibleAnchors(in: document)
        for anchor in anchors {
            guard let focus = document.focusing(on: anchor), let visible = focus.captureRegion else { continue }
            if anchor.pixelWidth != nil, anchor.pixelHeight != nil,
               (try? BrowserSourceSnapshotPlan(anchor: anchor, visibleRegion: visible)) == nil {
                anchoredCache.suspend(anchorID: anchor.id)
                continue
            }
            let capture = try await snapshot(document: focus)
            try Task.checkCancellation()
            guard active, wantsTranslation, lifecycle.epoch == epoch, geometry.matches(surface.geometry) else { throw CancellationError() }
            let checked = try await readDocument()
            try checked.validateForCapture()
            guard document.matchesReading(checked) else { surface.clearTranslation(); return }
            guard let pixels = capture.image.cgImage, let region = capture.region else { throw BrowserCaptureError.unreadableSnapshot }
            let validation = try anchoredCache.validate(focus, image: pixels, captureRegion: region)
            removed.append(contentsOf: validation.removed)
            if !validation.pending.isEmpty {
                surface.presentAnchored(anchoredCache.placements(document, size: surface.webView.bounds.size))
                let observations = try await VisionOCRService().recognizeText(in: capture.image, mode: .accurate)
                let fresh = try await snapshot(document: focus)
                let afterOCR = try await readDocument()
                try afterOCR.validateForCapture()
                guard lifecycle.epoch == epoch, geometry.matches(surface.geometry), document.matchesReading(afterOCR),
                      let freshPixels = fresh.image.cgImage, let freshRegion = fresh.region else { throw CancellationError() }
                for check in validation.pending {
                    guard let rect = BrowserImageCoordinates.captureRect(image: check.imageRect, captureRegion: freshRegion, anchor: anchor),
                          let patch = freshPixels.cropping(to: try BrowserPixelCrop.rect(for: rect, width: freshPixels.width, height: freshPixels.height)) else {
                        throw BrowserCaptureError.unreadableSnapshot
                    }
                    if let invalid = try anchoredCache.finishLocalVerification(check, observations: observations, stablePatch: patch) {
                        removed.append(invalid)
                    }
                }
            }
        }
        let current = try await readDocument()
        try Task.checkCancellation()
        try current.validateForCapture()
        guard active, wantsTranslation, lifecycle.epoch == epoch, geometry.matches(surface.geometry),
              armedDocumentID == current.documentID else { throw CancellationError() }
        guard document.matchesReading(current) else {
            surface.clearTranslation()
            return
        }
        anchorCacheProof = try anchoredCache.diagnosticProof(current)
        surface.presentAnchored(anchoredCache.placements(current, size: surface.webView.bounds.size))
        updateCachedResult(removing: removed)
    }

    private func updateCachedResult(removing removed: [BrowserAnchoredCache.Entry]) {
        if var result {
            result.segments = anchoredCache.segments
            result.failures.append(contentsOf: removed.filter { entry in
                !result.failures.contains(where: { $0.id == entry.payload.id })
            }.map { entry in
                SegmentTranslationFailure(
                    source: TranslationSourceSegment(id: entry.payload.id, text: entry.payload.sourceText,
                        boundingBox: entry.imageRect, confidence: entry.payload.confidence, readingOrder: entry.payload.readingOrder),
                    message: "Le contenu de cette image a change. Original conserve.", kind: .sourceChanged
                )
            })
            self.result = result
        }
        if !removed.isEmpty {
            status = "Une image a change · original conserve pour ses anciens dialogues."
            hasError = true
        }
    }
}

extension BrowserReaderController: WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame != false {
            guard let url = action.request.url, (try? BrowserAddress.parse(url.absoluteString)) != nil else {
                report(BrowserCaptureError.invalidAddress)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
        if action.targetFrame?.isMainFrame != false {
            navigationUserInitiated = action.navigationType != .other
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url,
           (try? BrowserAddress.parse(url.absoluteString)) != nil {
            webView.load(action.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        ready = false
        isLoading = true
        documentID = nil
        documentRevision = -1
        contentRevision = -1
        invalidate()
        onNavigationStarted?(navigationUserInitiated)
        status = "Chargement du site. Connexion et verifications restent sous ton controle."
        hasError = false
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        currentURL = webView.url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        isLoading = false
        currentURL = webView.url
        status = "Page prete. Affiche uniquement le chapitre puis touche Traduire ; compatibilite selon le site."
        if wantsTranslation && autoTranslate && !autoPausedAfterError { scheduleCapture() }
        onReady?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        isLoading = false
        report(BrowserCaptureError.unavailablePage)
    }

    private func navigationFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        ready = false
        isLoading = false
        report(error)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == BrowserBridgeScript.handlerName, message.frameInfo.isMainFrame else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: message.body)
            let change = try JSONDecoder().decode(PageChange.self, from: data)
            guard change.url == surface?.webView.url?.absoluteString,
                  documentID == nil || documentID == change.documentID,
                  change.kind == "content" ? (change.contentRevision ?? 0) > contentRevision : change.revision > documentRevision else { return }
            documentID = change.documentID
            documentRevision = change.revision
            if change.kind == "content" {
                contentRevision = change.contentRevision ?? contentRevision
                // The source geometry/guards and normalized reading pixels are checked before commit.
            } else {
                switch change.blockedReason {
                case "form": report(BrowserCaptureError.sensitivePage)
                case "challenge": report(BrowserCaptureError.protectedPage)
                case "frame", "media": report(BrowserCaptureError.unsupportedFrame)
                case nil:
                    let scrollOrInteraction = ["scroll", "pointerdown", "keydown", "focusin"].contains(change.reason ?? "")
                    viewportChanged(reason: change.reason ?? "document revision", settling: change.reason == "layout",
                        preserveFinished: scrollOrInteraction || change.reason == "layout" || change.reason == "reading-source",
                        continueDocument: change.reason == "scroll")
                    if let document = change.document, document.documentID == armedDocumentID {
                        try document.validateForCapture()
                        updateCachedResult(removing: anchoredCache.synchronizeSources(document))
                        surface?.presentAnchored(anchoredCache.placements(document, size: surface?.webView.bounds.size ?? .zero))
                        anchorCacheProof = try anchoredCache.diagnosticProof(document)
                    }
                default: viewportChanged(reason: change.reason ?? "document revision")
                }
            }
        } catch {
            report(BrowserCaptureError.invalidBridge)
        }
    }
}

private struct PageChange: Decodable {
    let documentID: String
    let revision: Int
    let url: String
    let kind: String?
    let contentRevision: Int?
    let blockedReason: String?
    let reason: String?
    let document: BrowserDocumentState?
}

private struct BrowserReadingProof: Encodable {
    let pageURL: String
    let region: NormalizedRect?
    let readingKind: String?
    let pixelWidth: Int
    let pixelHeight: Int
    let translatedSegments: Int
    let fittedSegments: Int
}

@MainActor
final class BrowserSurfaceView: UIView {
    let webView: WKWebView
    var onSizeChange: (() -> Void)?
    private let translationLayer = UIView()
    private var previousSize = CGSize.zero
    private(set) var presentedSegmentIDs = Set<String>()

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        clipsToBounds = true
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(webView)
        translationLayer.isUserInteractionEnabled = false
        translationLayer.clipsToBounds = true
        translationLayer.isHidden = true
        translationLayer.accessibilityIdentifier = "v2.translatedCapture"
        addSubview(translationLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize {
            if bounds.width != previousSize.width { translationLayer.isHidden = true }
            previousSize = bounds.size
            onSizeChange?()
        }
        webView.frame = bounds
        translationLayer.frame = bounds
    }

    var geometry: BrowserViewportGeometry {
        BrowserViewportGeometry(
            width: Double(webView.bounds.width), height: Double(webView.bounds.height),
            offsetX: Double(webView.scrollView.contentOffset.x), offsetY: Double(webView.scrollView.contentOffset.y),
            zoomScale: Double(webView.scrollView.zoomScale)
        )
    }

    func clearTranslation() {
        translationLayer.isHidden = true
        translationLayer.subviews.forEach { $0.removeFromSuperview() }
        presentedSegmentIDs.removeAll()
    }

    func present(capture: UIImage, result: TranslationResult, in region: CGRect) -> Int {
        clearTranslation()
        var occupied: [CGRect] = []
        for segment in result.segments {
            guard let localFrame = ViewportOverlayLayout.frame(for: segment, in: region.size) else { continue }
            let frame = localFrame.offsetBy(dx: region.minX, dy: region.minY)
            guard !occupied.contains(where: { $0.intersects(frame) }), let pixels = capture.cgImage,
                  let crop = pixels.cropping(to: CGRect(x: segment.boundingBox.x * Double(pixels.width),
                    y: segment.boundingBox.y * Double(pixels.height), width: segment.boundingBox.width * Double(pixels.width),
                    height: segment.boundingBox.height * Double(pixels.height))),
                  let surface = try? LocalBubbleSurface.detect(in: crop, sourceText: segment.sourceText),
                  let bubble = makeBubble(BrowserAnchoredPlacement(segment: segment, frame: frame, clipFrame: region, surface: surface)) else { continue }
            translationLayer.addSubview(bubble)
            occupied.append(frame)
            presentedSegmentIDs.insert(segment.id)
        }

        if !occupied.isEmpty { translationLayer.isHidden = false }
        return occupied.count
    }

    @discardableResult
    func presentAnchored(_ placements: [BrowserAnchoredPlacement]) -> Int {
        var occupied: [CGRect] = []
        var accepted = Set<String>()
        for placement in placements {
            let segment = placement.segment, frame = placement.frame
            guard segment.confidence >= 0.7, !occupied.contains(where: { $0.intersects(frame) }) else { continue }
            if let existing = translationLayer.subviews.first(where: { $0.accessibilityIdentifier == "v2.bubble.\(segment.id)" }),
               abs(existing.bounds.width - frame.width) < 0.01, abs(existing.bounds.height - frame.height) < 0.01 {
                existing.frame = frame
                (existing.subviews.first { $0 is UIImageView } as? UIImageView)?.image = UIImage(cgImage: placement.surface.replacement)
                applyClip(to: existing, placement: placement)
            } else {
                translationLayer.subviews.filter { $0.accessibilityIdentifier == "v2.bubble.\(segment.id)" }.forEach { $0.removeFromSuperview() }
                guard let bubble = makeBubble(placement) else { continue }
                translationLayer.addSubview(bubble)
            }
            occupied.append(frame)
            accepted.insert(segment.id)
        }
        translationLayer.subviews.filter { !accepted.contains(String(($0.accessibilityIdentifier ?? "").dropFirst("v2.bubble.".count))) }
            .forEach { $0.removeFromSuperview() }
        presentedSegmentIDs = accepted
        translationLayer.isHidden = presentedSegmentIDs.isEmpty
        return presentedSegmentIDs.count
    }

    func shiftAnchoredTranslations(dx: CGFloat, dy: CGFloat) {
        for view in translationLayer.subviews { view.frame = view.frame.offsetBy(dx: dx, dy: dy) }
    }

    private func makeBubble(_ placement: BrowserAnchoredPlacement) -> UIView? {
        let segment = placement.segment, frame = placement.frame, surface = placement.surface
        let maximum = min(26, max(11, frame.height / Double(surface.sourceLineCount) / 1.3))
        guard let font = fittingFont(for: segment.translatedText, in: frame.size, maximum: maximum) else { return nil }
        let bubble = UIView(frame: frame)
        bubble.accessibilityIdentifier = "v2.bubble.\(segment.id)"
        let replacement = UIImageView(image: UIImage(cgImage: surface.replacement))
        replacement.frame = bubble.bounds
        replacement.contentMode = .scaleToFill
        replacement.isAccessibilityElement = false
        bubble.addSubview(replacement)
        let label = UILabel(frame: bubble.bounds)
        label.text = segment.translatedText
        label.accessibilityIdentifier = "v2.translatedSegment.\(segment.id)"
        label.font = font
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        label.textColor = UIColor(red: Double(surface.ink.red) / 255, green: Double(surface.ink.green) / 255,
                                 blue: Double(surface.ink.blue) / 255, alpha: 1)
        bubble.addSubview(label)
        applyClip(to: bubble, placement: placement)
        return bubble
    }

    private func applyClip(to bubble: UIView, placement: BrowserAnchoredPlacement) {
        let visible = placement.frame.intersection(placement.clipFrame)
        let mask = CAShapeLayer()
        mask.frame = bubble.bounds
        mask.path = CGPath(rect: visible.offsetBy(dx: -placement.frame.minX, dy: -placement.frame.minY), transform: nil)
        bubble.layer.mask = mask
    }

    private func fittingFont(for text: String, in size: CGSize, maximum: Double = 20) -> UIFont? {
        guard size.width > 8, size.height > 8 else { return nil }
        for points in stride(from: Int(maximum), through: 11, by: -1) {
            let font = UIFont.systemFont(ofSize: CGFloat(points), weight: .semibold)
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: size.width - 4, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
            )
            if ceil(measured.height) <= size.height - 4, ceil(measured.width) <= size.width - 4 { return font }
        }
        return nil
    }
}
