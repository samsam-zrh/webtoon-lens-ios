import Observation
import OSLog
import SwiftUI
import UIKit
import WebKit
import WebtoonLensCore

struct BrowserViewportCapture {
    let image: UIImage
    let data: Data
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
        surface.onSizeChange = { [weak self] in self?.viewportChanged(reason: "size") }
        let scrollView = webView.scrollView
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(gestureChanged(_:)))
        scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(gestureChanged(_:)))
        observations = [
            scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
                guard change.oldValue != change.newValue else { return }
                MainActor.assumeIsolated { self?.viewportChanged(reason: "offset") }
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
            invalidate()
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
        invalidate()
        wantsTranslation = true
        manualCaptureRequested = true
        stabilizationWindow = BrowserStabilizationWindow()
        autoPausedAfterError = false
        status = "Attente d'une zone stable..."
        hasError = false
        scheduleCapture()
    }

    func report(_ error: Error) {
        invalidate()
        autoPausedAfterError = true
        status = "\(error.localizedDescription) Original conserve."
        hasError = true
    }

    private func invalidate() {
        lifecycle.invalidate()
        activeTask?.cancel()
        debounceTask?.cancel()
        pendingCapture = false
        manualCaptureRequested = false
        stabilizationWindow = nil
        surface?.clearTranslation()
        result = nil
    }

    private func viewportChanged(reason: String) {
        Self.logger.debug("Viewport invalidated: \(reason, privacy: .public), pending manual: \(self.manualCaptureRequested), translating: \(self.isTranslating)")
        let shouldResumeManual = manualCaptureRequested
        let pendingWindow = stabilizationWindow
        let hadWork = result != nil || isTranslating
        invalidate()
        if hadWork {
            status = "Zone modifiee. Original conserve\(autoTranslate && !autoPausedAfterError ? " ; Auto attend la fin du mouvement." : " ; touchez Traduire.")"
            hasError = false
        }
        if shouldResumeManual {
            manualCaptureRequested = true
            stabilizationWindow = pendingWindow
            scheduleCapture()
        } else if wantsTranslation && autoTranslate && !autoPausedAfterError {
            scheduleCapture()
        }
    }

    @objc private func gestureChanged(_ gesture: UIGestureRecognizer) {
        viewportChanged(reason: "gesture")
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
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.captureAndTranslate()
            if self.activeRunID == runID {
                self.activeRunID = nil
                self.activeTask = nil
                self.isTranslating = false
                self.pump()
            }
        }
    }

    private func captureAndTranslate() async {
        var token: BrowserCaptureToken?
        let startingEpoch = lifecycle.epoch
        defer { if let token { lifecycle.finish(token) } }
        do {
            guard let surface, let translate, active, ready else { throw BrowserCaptureError.unavailablePage }
            let geometry = surface.geometry
            let document = try await readDocument()
            try Task.checkCancellation()
            guard lifecycle.epoch == startingEpoch, geometry.matches(surface.geometry) else { throw CancellationError() }
            let captureToken = try lifecycle.begin(geometry: geometry, document: document)
            token = captureToken
            status = "Capture locale et OCR sur l'iPhone..."
            let capture = try await snapshot()
            let afterCapture = try await readDocument()
            try ensureCurrent(captureToken, document: afterCapture)

            status = "Traduction du texte OCR par ton backend local..."
            let translated = try await translate(capture)
            let afterTranslation = try await readDocument()
            try ensureCurrent(captureToken, document: afterTranslation)

            // Canvas pixels can change without a DOM mutation. Recheck the source itself.
            let verification = try await snapshot()
            let beforePresentation = try await readDocument()
            try ensureCurrent(captureToken, document: beforePresentation)
            guard ImageHasher.sha256Hex(capture.data) == ImageHasher.sha256Hex(verification.data) else {
                throw BrowserCaptureError.changedContent
            }
            let count = surface.present(capture: capture.image, result: translated)
            result = translated
            hasError = !translated.failures.isEmpty
            if translated.segments.isEmpty {
                wantsTranslation = false
                status = "Aucun dialogue traduit. \(translated.failures.count) en erreur ; original conserve, details dans Texte."
            } else if !translated.failures.isEmpty {
                status = "\(translated.segments.count) dialogues traduits, \(translated.failures.count) en erreur. Leurs originaux restent visibles ; details dans Texte."
            } else if count == 0 {
                status = "Texte traduit disponible dans Texte. Zones trop petites ou incertaines : original visuel conserve."
            } else {
                let skipped = translated.segments.count - count
                status = "Capture traduite : \(count) zones\(skipped > 0 ? ", \(skipped) dans Texte" : ""). Defiler, zoomer ou choisir Original rend la page vivante."
            }
        } catch is CancellationError {
            // Never present or report an obsolete viewport result.
        } catch {
            if !Task.isCancelled, lifecycle.epoch == startingEpoch, active {
                report(error)
            }
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

    private func snapshot() async throws -> BrowserViewportCapture {
        guard let surface else { throw BrowserCaptureError.unavailablePage }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = surface.webView.bounds
        configuration.snapshotWidth = NSNumber(value: try surface.geometry.snapshotWidth(
            pixelScale: Double(surface.webView.traitCollection.displayScale)
        ))
        configuration.afterScreenUpdates = true
        let image = try await WebKitViewportCapture.snapshot(in: surface.webView, configuration: configuration)
        try Task.checkCancellation()
        guard Self.isUsable(image), let data = image.pngData(), !data.isEmpty else {
            throw BrowserCaptureError.unreadableSnapshot
        }
        return BrowserViewportCapture(image: image, data: data)
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
        invalidate()
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
                  change.revision > documentRevision else { return }
            documentID = change.documentID
            documentRevision = change.revision
            viewportChanged(reason: "document revision \(change.revision)")
        } catch {
            report(BrowserCaptureError.invalidBridge)
        }
    }
}

private struct PageChange: Decodable {
    let documentID: String
    let revision: Int
    let url: String
}

@MainActor
final class BrowserSurfaceView: UIView {
    let webView: WKWebView
    var onSizeChange: (() -> Void)?
    private let translationLayer = UIView()
    private var previousSize = CGSize.zero

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
            clearTranslation()
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
    }

    func present(capture: UIImage, result: TranslationResult) -> Int {
        clearTranslation()
        let source = UIImageView(image: capture)
        source.frame = bounds
        source.contentMode = .scaleToFill
        source.isAccessibilityElement = false
        translationLayer.addSubview(source)
        var occupied: [CGRect] = []
        for segment in result.segments {
            guard let frame = ViewportOverlayLayout.frame(for: segment, in: bounds.size),
                  !occupied.contains(where: { $0.intersects(frame) }),
                  let font = fittingFont(for: segment.translatedText, in: frame.size) else { continue }
            let label = UILabel(frame: frame)
            label.text = segment.translatedText
            label.accessibilityIdentifier = "v2.translatedSegment.\(segment.id)"
            label.font = font
            label.textAlignment = .center
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.backgroundColor = .white
            label.textColor = .black
            label.layer.cornerRadius = 2
            label.layer.masksToBounds = true
            label.layer.borderWidth = 0.5
            label.layer.borderColor = UIColor.black.withAlphaComponent(0.25).cgColor
            translationLayer.addSubview(label)
            occupied.append(frame)
        }
        if !occupied.isEmpty { translationLayer.isHidden = false }
        return occupied.count
    }

    private func fittingFont(for text: String, in size: CGSize) -> UIFont? {
        guard size.width > 8, size.height > 8 else { return nil }
        for points in stride(from: 20, through: 11, by: -1) {
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
