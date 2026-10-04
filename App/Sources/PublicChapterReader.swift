import Observation
import OSLog
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit
import WebtoonLensCore

@MainActor
struct PublicChapterReaderView: View {
    let reader: PublicChapterController
    let close: () -> Void

    var body: some View {
        PublicChapterWebView(controller: reader)
    }
}

@MainActor
@Observable
final class PublicChapterController: NSObject {
    private(set) var hasChapter = false
    private(set) var isLoading = false
    private(set) var status = ""
    private(set) var hasError = false
    private(set) var pageCount = 0
    private(set) var translationCount = 0
    private(set) var selectedPage = 0
    private(set) var showOriginal = false
    private(set) var renderedCount = 0
    private(set) var renderProof = ""
    private(set) var sourceErrors: [String] = []
    private(set) var displaySourceURL: URL?
    @ObservationIgnored var onScroll: (@MainActor (Double) -> Void)?
    @ObservationIgnored var onDisplayed: (@MainActor () -> Void)?
    @ObservationIgnored private var unavailable: (@MainActor (Error) -> Void)?
    @ObservationIgnored private var scrollObservation: NSKeyValueObservation?

    @ObservationIgnored private var generation = PublicChapterGeneration()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var rendererTask: Task<Void, Never>?
    @ObservationIgnored private weak var webView: WKWebView?
    @ObservationIgnored private var rendererReady = false
    @ObservationIgnored private var commands: [ChapterRenderCommand] = []
    @ObservationIgnored private var pageCommands: [ChapterRenderCommand] = []
    @ObservationIgnored private var translationCommands: [ChapterRenderCommand] = []
    @ObservationIgnored fileprivate var imageStore = PublicChapterImageStore()
    @ObservationIgnored private var client: PublicChapterClient?
    @ObservationIgnored private var translator: WebtoonTranslationClient?
    @ObservationIgnored private var referer: URL?
    @ObservationIgnored private var retryPages: [Int: (URL, PublicImageMetadata, URL)] = [:]
    @ObservationIgnored private var sourceLanguage = "auto"
    @ObservationIgnored private var style = WebtoonLensConstants.defaultStylePrompt
    @ObservationIgnored private var glossary: [GlossaryTermInstruction] = []
    @ObservationIgnored private var pageErrors: [Int: String] = [:]
    @ObservationIgnored private var coveredWindows: [Int: Set<Int>] = [:]
    @ObservationIgnored private var pageSegments: [Int: [PublicOCRSegment]] = [:]
    @ObservationIgnored private var expectedBackend: URL?
    @ObservationIgnored private var displayGeneration: UUID?
    @ObservationIgnored private var displayBackend: URL?
    @ObservationIgnored private var previousTranslations: [PreviousDialogueTranslation] = []
    @ObservationIgnored private let activity = PublicChapterActivity()
    private static let logger = Logger(subsystem: "com.example.webtoonlens.v2", category: "PublicChapter")

    func start(
        _ source: URL, sourceLanguage: String, glossary: [GlossaryTermInstruction], style: String,
        onUnavailable: (@MainActor (Error) -> Void)? = nil
    ) {
        let previous = task
        previous?.cancel()
        generation.advance()
        let id = generation.id
        self.sourceLanguage = sourceLanguage
        self.glossary = glossary
        self.style = style
        isLoading = true
        status = "Le Mac ouvre les images publiques du chapitre..."
        hasError = false
        unavailable = onUnavailable
        task = Task { [weak self] in
            await previous?.value
            guard let self, self.generation.accepts(id) else { return }
            var committed = false
            do {
                try await self.activity.waitUntilActive()
                let backend = try SharedSettingsStore.shared.publicChapterBackend()
                self.expectedBackend = backend
                let client = PublicChapterClient(baseURL: backend)
                let translator = WebtoonTranslationClient(baseURL: backend)
                let extraction = try await client.extract(source)
                try self.check(id)
                let referer = try PublicChapterURL.parse(extraction.pageURL)
                var accepted = 0
                var skipped = 0
                var sessionBytes = 0
                var prefetch: (index: Int, task: Task<Data, Error>)?
                defer { prefetch?.task.cancel() }
                func startPrefetch(_ nextIndex: Int) {
                    guard nextIndex < extraction.images.count, prefetch?.index != nextIndex,
                          let next = try? PublicChapterURL.parse(extraction.images[nextIndex].url) else { return }
                    prefetch = (nextIndex, Task { try await client.image(next, referer: referer) })
                }
                for (position, image) in extraction.images.enumerated() {
                    try await self.activity.waitUntilActive()
                    try self.check(id)
                    do {
                        let url = try PublicChapterURL.parse(image.url)
                        let data: Data
                        if let pending = prefetch, pending.index == position {
                            prefetch = nil
                            data = try await pending.task.value
                        } else {
                            data = try await client.image(url, referer: referer)
                        }
                        // Download the next page while this one is analyzed and translated.
                        startPrefetch(position + 1)
                        try await self.activity.waitUntilActive()
                        try self.check(id)
                        let metadata = try PublicImageMetadata(data: data)
                        guard metadata.isReadingPage else { skipped += 1; continue }
                        sessionBytes += data.count
                        guard sessionBytes <= 240_000_000 else {
                            throw PublicChapterError.backend(413, "Budget local du chapitre atteint (240 Mo). Les pages deja chargees restent lisibles.", "chapter_limit")
                        }
                        if !committed {
                            try self.commitSession(id)
                            try SharedSettingsStore.shared.rememberPublicChapter(source)
                            self.client = client
                            self.translator = translator
                            self.displayBackend = backend
                            self.referer = referer
                            self.displaySourceURL = source
                            committed = true
                            self.onDisplayed?()
                        }
                        let file = try self.imageStore.save(data, generation: id, page: accepted)
                        let page = ChapterRenderCommand.page(id: id, index: accepted, metadata: metadata, publicURL: url)
                        self.pageCommands.append(page)
                        self.enqueue(page)
                        self.pageCount += 1
                        self.retryPages[accepted] = (url, metadata, file)
                        self.status = "Page \(accepted + 1) affichee. OCR et masques sur le Mac..."
                        do {
                            try await self.analyze(url: url, data: data, metadata: metadata, page: accepted, id: id, firstWindowOnly: true)
                            try self.check(id)
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            self.pageErrors[accepted] = error.localizedDescription
                            self.enqueue(.error(id: id, index: accepted, message: error.localizedDescription))
                            self.hasError = true
                            Self.logger.error("Page \(accepted + 1), first public window: \(error.localizedDescription, privacy: .public)")
                        }
                        accepted += 1
                        self.status = "\(accepted) pages lues · \(self.translationCount) dialogues traduits. \(self.pageErrors.count) pages en erreur."
                    } catch is CancellationError { throw CancellationError() }
                    catch PublicChapterError.backend(_, let message, let code) where code == "chapter_limit" {
                        self.sourceErrors.append(message)
                        self.hasError = true
                        break
                    }
                    catch {
                        try self.check(id)
                        self.hasError = true
                        self.sourceErrors.append("\(URL(string: image.url)?.lastPathComponent ?? "Ressource") : \(error.localizedDescription)")
                        Self.logger.error("Public resource \(URL(string: image.url)?.lastPathComponent ?? "unknown", privacy: .public): \(error.localizedDescription, privacy: .public)")
                        self.status = "Ressource publique indisponible : \(error.localizedDescription). Les pages deja lues sont conservees."
                    }
                }
                try self.check(id)
                guard accepted > 0 else { throw PublicChapterError.noPages }
                while let page = self.retryPages.keys.sorted(by: {
                    abs($0 - self.selectedPage) < abs($1 - self.selectedPage)
                }).first(where: { index in
                    guard let (_, metadata, _) = self.retryPages[index], self.pageErrors[index] == nil else { return false }
                    return PublicOCRWindow.windows(height: metadata.height).contains { !(self.coveredWindows[index] ?? []).contains($0.coreTop) }
                }), let (url, metadata, file) = self.retryPages[page] {
                    try self.check(id)
                    do {
                        try await self.analyze(url: url, data: Data(contentsOf: file), metadata: metadata, page: page, id: id, firstWindowOnly: false)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        self.pageErrors[page] = error.localizedDescription
                        self.enqueue(.error(id: id, index: page, message: error.localizedDescription))
                        self.hasError = true
                        Self.logger.error("Page \(page + 1), following public window: \(error.localizedDescription, privacy: .public)")
                    }
                }
                self.status = "\(accepted) pages · \(self.translationCount) dialogues traduits. \(self.pageErrors.count) pages en erreur · \(self.sourceErrors.count) ressources indisponibles\(skipped > 0 ? (skipped == 1 ? " · 1 petite decoration ignoree" : " · \(skipped) petites decorations ignorees") : "")."
            } catch is CancellationError {
            } catch {
                if self.generation.accepts(id) {
                    self.status = "\(error.localizedDescription) \(self.hasChapter ? "Chapitre precedent conserve." : "Navigateur original conserve.")"
                    self.hasError = true
                    if !committed { onUnavailable?(error) }
                }
            }
            if self.generation.accepts(id) { self.isLoading = false }
        }
    }

    func close() {
        task?.cancel()
        rendererTask?.cancel()
        generation.advance()
        hasChapter = false
        isLoading = false
        commands.removeAll()
        rendererReady = false
        displayGeneration = nil
        displayBackend = nil
        displaySourceURL = nil
        do { try imageStore.clear() }
        catch { status = "Nettoyage du cache public impossible : \(error.localizedDescription)"; hasError = true }
    }

    func cancelWorkPreservingDisplay() {
        task?.cancel()
        rendererTask?.cancel()
        generation.advance()
        isLoading = false
        commands.removeAll()
    }

    func setActive(_ value: Bool) {
        Task { await activity.setActive(value) }
    }

    func setOriginal(_ value: Bool) {
        showOriginal = value
        if let displayGeneration { enqueue(.original(id: displayGeneration, value: value)) }
    }

    func movePage(_ direction: Int) {
        selectedPage = max(0, min(pageCount - 1, selectedPage + direction))
        if let displayGeneration { enqueue(.scroll(id: displayGeneration, index: selectedPage)) }
    }

    func moveToDialogue() {
        if let displayGeneration { enqueue(.dialogue(id: displayGeneration, index: selectedPage)) }
    }

    func attach(_ view: WKWebView) {
        webView = view
        view.navigationDelegate = self
        view.configuration.userContentController.add(self, name: "publicChapter")
        scrollObservation = view.scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] scroll, change in
            guard change.oldValue != change.newValue, scroll.isDragging || scroll.isDecelerating else { return }
            MainActor.assumeIsolated { self?.onScroll?(Double(scroll.contentOffset.y)) }
        }
        guard let url = Bundle.main.url(forResource: "PublicChapterReader", withExtension: "html") else {
            failRenderer(PublicChapterError.rendererUnavailable)
            return
        }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func detach(_ view: WKWebView) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "publicChapter")
        view.navigationDelegate = nil
        rendererReady = false
        webView = nil
        rendererTask?.cancel()
        scrollObservation = nil
    }

    private func commitSession(_ id: UUID) throws {
        try check(id)
        try imageStore.begin(id)
        displayGeneration = id
        rendererTask?.cancel()
        commands = [.reset(id: id)]
        pageCommands.removeAll()
        translationCommands.removeAll()
        pageErrors.removeAll()
        sourceErrors.removeAll()
        previousTranslations.removeAll()
        retryPages.removeAll()
        coveredWindows.removeAll()
        pageSegments.removeAll()
        pageCount = 0
        translationCount = 0
        renderedCount = 0
        selectedPage = 0
        showOriginal = false
        hasChapter = true
        flush()
    }

    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard generation.accepts(id) else { throw CancellationError() }
        if let expectedBackend {
            guard try SharedSettingsStore.shared.publicChapterBackend() == expectedBackend else { throw PublicChapterError.consentRequired }
        }
    }

    private func analyze(url: URL, data: Data, metadata: PublicImageMetadata, page: Int, id: UUID, firstWindowOnly: Bool = false) async throws {
        guard let client, let translator, let referer else { throw PublicChapterError.rendererUnavailable }
        let allWindows = PublicOCRWindow.windows(height: metadata.height)
        let pending = allWindows.filter { !(coveredWindows[page] ?? []).contains($0.coreTop) }
        let windows = firstWindowOnly ? Array(pending.prefix(1)) : pending
        var accounted = pageSegments[page] ?? []
        var translatedOnPage = 0
        func ocrRequest(for window: PublicOCRWindow) throws -> PublicOCRRequest {
            if allWindows.count == 1 {
                return PublicOCRRequest(imageURL: url, referer: referer, language: sourceLanguage)
            }
            let crop = try PublicImageCropper.crop(publicImage: data, metadata: metadata, window: window)
            return PublicOCRRequest(publicCrop: crop, referer: referer, language: sourceLanguage,
                cacheKey: "v2-public:\(url.absoluteString):\(window.coreTop)-\(window.coreBottom)")
        }
        var nextOCR: Task<[PublicOCRSegment], Error>?
        defer { nextOCR?.cancel() }
        for (position, window) in windows.enumerated() {
            try await activity.waitUntilActive()
            try check(id)
            let recognized: [PublicOCRSegment]
            if let pending = nextOCR {
                nextOCR = nil
                recognized = try await pending.value
            } else {
                recognized = try await client.ocr(try ocrRequest(for: window))
            }
            // The Mac can OCR the next window while Ollama translates this one.
            if position + 1 < windows.count {
                let request = try ocrRequest(for: windows[position + 1])
                nextOCR = Task { try await client.ocr(request) }
            }
            try await activity.waitUntilActive()
            try check(id)
            let segments = recognized.compactMap { source -> PublicOCRSegment? in
                do { return try window.map(source, page: page, metadata: metadata) } catch {
                    Self.logger.error("Page \(page + 1) segment \(source.id, privacy: .public) ignore: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
                .filter { segment in !accounted.contains { $0.isSameDialogue(as: segment) } }
            var start = 0
            while start < segments.count {
                try await activity.waitUntilActive()
                try check(id)
                let batch = Array(segments[start..<min(start + (start == 0 ? 1 : 6), segments.count)])
                start += batch.count
                let fresh = batch.filter { candidate in !accounted.contains(where: { $0.id == candidate.id }) }
                if fresh.isEmpty { continue }
                status = "Page \(page + 1) : traduction de \(fresh.count) dialogues. La suite continue."
                let outcome = try await TranslationBatchProcessor(client: translator).translate(TranslationRequest(
                    sourceLanguage: sourceLanguage, targetLanguage: "fr", seriesID: nil, style: style,
                    segments: fresh.map(\.translationSource), glossary: glossary,
                    contextSegments: Array((accounted + segments).suffix(32)).enumerated().map {
                        TranslationContextSegment(id: $0.element.id, order: $0.offset, text: $0.element.sourceText)
                    },
                    previousTranslations: Array(previousTranslations.suffix(14))
                ))
                try await activity.waitUntilActive()
                try check(id)
                let originals = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let rendered = try outcome.segments.map { translated -> PublicOCRSegment in
                    guard var original = originals[translated.id] else { throw TranslationClientError.invalidResponse }
                    original.translatedText = translated.translatedText
                    return original
                }
                let command = ChapterRenderCommand.translation(id: displayGeneration ?? id, index: page, segments: rendered, failures: outcome.failures)
                translationCommands.append(command)
                enqueue(command)
                translationCount += rendered.count
                previousTranslations.append(contentsOf: rendered.map {
                    PreviousDialogueTranslation(source: $0.sourceText, translation: $0.translatedText ?? "")
                })
                previousTranslations = Array(previousTranslations.suffix(14))
                translatedOnPage += rendered.count
                if !outcome.failures.isEmpty { hasError = true }
                accounted.append(contentsOf: fresh)
                pageSegments[page] = accounted
            }
            coveredWindows[page, default: []].insert(window.coreTop)
            enqueue(.recovered(id: displayGeneration ?? id, index: page))
            Self.logger.info("Page \(page + 1), public core \(window.coreTop)-\(window.coreBottom): \(recognized.count) observations, \(segments.count) core dialogues.")
        }
        if translatedOnPage == 0 {
            status = "Page \(page + 1) sans dialogue traduit. Original visible ; lecture de la page suivante."
        }
    }

    private func enqueue(_ command: ChapterRenderCommand) {
        commands.append(command)
        flush()
    }

    private func flush() {
        guard rendererReady, rendererTask == nil, !commands.isEmpty, let webView else { return }
        let renderedGeneration = displayGeneration
        rendererTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !self.commands.isEmpty {
                    try Task.checkCancellation()
                    let command = self.commands.removeFirst()
                    guard command.generation == self.displayGeneration?.uuidString else { continue }
                    let data = try JSONEncoder().encode(command)
                    let object = try JSONSerialization.jsonObject(with: data)
                    _ = try await webView.callAsyncJavaScript("window.PublicChapterReader.update(command);",
                        arguments: ["command": object], in: nil, contentWorld: .page)
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled, self.displayGeneration == renderedGeneration { self.failRenderer(error) }
            }
            self.rendererTask = nil
            self.flush()
        }
    }

    private func failRenderer(_ error: Error) {
        let fallback = translationCount == 0 ? unavailable : nil
        close()
        status = "\(error.localizedDescription) Navigateur original conserve."
        hasError = true
        fallback?(error)
    }
}

extension PublicChapterController: WKNavigationDelegate, WKScriptMessageHandler {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        rendererReady = true
        guard let displayGeneration else { return }
        commands = [.reset(id: displayGeneration)] + pageCommands + translationCommands +
            pageErrors.sorted(by: { $0.key < $1.key }).map { .error(id: displayGeneration, index: $0.key, message: $0.value) }
        flush()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "publicChapter",
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "ready" { return }
        guard body["generation"] as? String == displayGeneration?.uuidString else { return }
        if type == "metrics", let metrics = body["rendered"] as? [[String: Any]] {
            renderedCount = metrics.count
            if let visible = body["visiblePage"] as? Int { selectedPage = visible }
            if let encoded = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) {
                renderProof = String(decoding: encoded, as: UTF8.self)
            }
        } else if type == "imageError", let page = body["index"] as? Int {
            status = "Image de la page \(page + 1) indisponible. Original non remplace."
            hasError = true
        } else if type == "retry", let page = body["index"] as? Int,
                  let (url, metadata, file) = retryPages[page] {
            if isLoading {
                pageErrors[page] = nil
                status = "Reprise de la page \(page + 1) demandee ; les autres pages continuent."
                return
            }
            let id = generation.id
            task = Task { [weak self] in
                guard let self else { return }
                self.isLoading = true
                defer { self.isLoading = false }
                do {
                    guard try SharedSettingsStore.shared.publicChapterBackend() == self.displayBackend else {
                        throw PublicChapterError.consentRequired
                    }
                    try await self.analyze(url: url, data: Data(contentsOf: file), metadata: metadata, page: page, id: id)
                    self.pageErrors[page] = nil
                    self.enqueue(.recovered(id: self.displayGeneration ?? id, index: page))
                } catch is CancellationError {
                } catch {
                    self.enqueue(.error(id: self.displayGeneration ?? id, index: page, message: error.localizedDescription))
                }
            }
        }
    }
}

private struct ChapterRenderCommand: Encodable {
    let type: String
    let generation: String
    var index: Int?
    var width: Int?
    var height: Int?
    var source: String?
    var publicURL: String?
    var segments: [PublicOCRSegment]?
    var failures: [SegmentTranslationFailure]?
    var message: String?
    var original: Bool?

    static func reset(id: UUID) -> Self { Self(type: "reset", generation: id.uuidString) }
    static func page(id: UUID, index: Int, metadata: PublicImageMetadata, publicURL: URL) -> Self {
        Self(type: "page", generation: id.uuidString, index: index, width: metadata.width, height: metadata.height,
             source: "v2chapter-image://\(id.uuidString)/\(index)", publicURL: publicURL.absoluteString)
    }
    static func translation(id: UUID, index: Int, segments: [PublicOCRSegment], failures: [SegmentTranslationFailure]) -> Self {
        Self(type: "translation", generation: id.uuidString, index: index, segments: segments, failures: failures)
    }
    static func error(id: UUID, index: Int, message: String) -> Self { Self(type: "pageError", generation: id.uuidString, index: index, message: message) }
    static func original(id: UUID, value: Bool) -> Self { Self(type: "original", generation: id.uuidString, original: value) }
    static func scroll(id: UUID, index: Int) -> Self { Self(type: "scroll", generation: id.uuidString, index: index) }
    static func dialogue(id: UUID, index: Int) -> Self { Self(type: "dialogue", generation: id.uuidString, index: index) }
    static func recovered(id: UUID, index: Int) -> Self { Self(type: "recovered", generation: id.uuidString, index: index) }
}

@MainActor
fileprivate final class PublicChapterImageStore: NSObject, WKURLSchemeHandler {
    private var generation: UUID?
    private var files: [Int: URL] = [:]
    private var directory: URL?

    func begin(_ id: UUID) throws {
        try clear()
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = cache.appendingPathComponent("WebtoonLensV2-Public-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        generation = id
    }

    func clear() throws {
        for file in files.values { try FileManager.default.removeItem(at: file) }
        if let directory { try FileManager.default.removeItem(at: directory) }
        self.directory = nil
        generation = nil
        files.removeAll()
    }

    func save(_ data: Data, generation id: UUID, page: Int) throws -> URL {
        guard generation == id, let directory else { throw CancellationError() }
        let file = directory.appendingPathComponent("\(page).image")
        try data.write(to: file, options: .atomic)
        files[page] = file
        return file
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        do {
            guard task.request.url?.host?.uppercased() == generation?.uuidString,
                  let path = task.request.url?.lastPathComponent, let index = Int(path), let file = files[index] else {
                throw PublicChapterError.invalidImage
            }
            let data = try Data(contentsOf: file)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source) else { throw PublicChapterError.invalidImage }
            let type = UTType(identifier as String)?.preferredMIMEType ?? "application/octet-stream"
            task.didReceive(URLResponse(url: task.request.url!, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

private struct PublicChapterWebView: UIViewRepresentable {
    let controller: PublicChapterController
    func makeCoordinator() -> PublicChapterController { controller }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(controller.imageStore, forURLScheme: "v2chapter-image")
        let view = WKWebView(frame: .zero, configuration: configuration)
        controller.attach(view)
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: PublicChapterController) { coordinator.detach(uiView) }
}
