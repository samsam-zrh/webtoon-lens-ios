import AppKit
import Foundation
import WebKit
import WebtoonLensCore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor
private final class Checks {
    private(set) var count = 0

    func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw CheckFailure(description: name) }
        count += 1
    }

    func rejects(_ name: String, _ action: () throws -> Void) throws {
        do {
            try action()
        } catch {
            count += 1
            return
        }
        throw CheckFailure(description: "\(name): expected an explicit error")
    }

    func core() async throws {
        try require(try BrowserAddress.parse("example.test/chapter").scheme == "https", "Bare address becomes HTTPS")
        for value in ["javascript:alert(1)", "file:///tmp/image", "data:image/png,test",
                      "https://user:pass@example.test", "https://example.test:65536", ""] {
            try rejects("Refuse address \(value)") { _ = try BrowserAddress.parse(value) }
        }
        for value in ["http://localhost:8788", "http://192.168.1.3:8787", "http://mon-mac.local:8787", "http://[::1]:8788"] {
            _ = try LocalBackendAddress.parse(value)
            count += 1
        }
        for value in ["https://translation.example.test", "http://0.0.0.0", "http://127.1", "http://127.00.0.1",
                      "http://172.32.0.1", "http://localhost?url=secret", "http://user:pass@localhost"] {
            try rejects("Refuse backend \(value)") { _ = try LocalBackendAddress.parse(value) }
        }

        let suite = "WebtoonLensV2-checks-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CheckFailure(description: "Test defaults unavailable") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SharedSettingsStore(defaults: defaults)
        try require(!settings.hasTextTranslationConsent && !settings.allowImageFallback, "No network/image consent by default")
        settings.backendBaseURLString = "http://localhost:8788"
        try rejects("No implicit text export") { _ = try settings.translationBackend() }
        settings.setTextTranslationConsent(true)
        try require(try settings.translationBackend().port == 8788, "Explicit endpoint consent")
        settings.backendBaseURLString = "http://localhost:8790"
        try require(!settings.hasTextTranslationConsent, "Changing endpoint revokes consent")
        settings.setTextTranslationConsent(true)
        settings.setTextTranslationConsent(false)
        try rejects("Revoked consent") { _ = try settings.translationBackend() }
        try require(WebtoonLensConstants.appGroupIdentifier == "group.com.example.webtoonlens.v2", "Separate V2 namespace")
        try require(BrowserBridgeScript.mainFrameOnly, "Bridge is main-frame-only")
        for forbidden in ["fetch(", "XMLHttpRequest", "document.cookie", ".value", "innerHTML"] {
            try require(!BrowserBridgeScript.source.contains(forbidden), "Bridge does not use \(forbidden)")
        }

        let page = BrowserDocumentState(
            documentID: "fixture", revision: 1, url: "https://example.test/chapter",
            scrollX: 0, scrollY: 400, viewportWidth: 390, viewportHeight: 640,
            viewportLeft: 0, viewportTop: 0, viewportScale: 1, blockedReason: nil
        )
        let geometry = BrowserViewportGeometry(width: 390, height: 640, offsetX: 0, offsetY: 400, zoomScale: 1)
        var lifecycle = BrowserCaptureLifecycle()
        let old = try lifecycle.begin(geometry: geometry, document: page)
        try require(lifecycle.canCommit(old, geometry: geometry, document: page), "Stable capture can commit")
        var scrolled = geometry
        scrolled.offsetY += 1
        var zoomed = geometry
        zoomed.zoomScale = 1.2
        var rotated = geometry
        rotated.width = 640
        for changed in [scrolled, zoomed, rotated] {
            try require(!lifecycle.canCommit(old, geometry: changed, document: page), "No stale scroll/zoom/rotation coordinates")
        }
        for _ in 0..<100 { lifecycle.invalidate() }
        try require(!lifecycle.canCommit(old, geometry: geometry, document: page), "Rapid changes cancel stale token")
        try rejects("Keep cancelled lane occupied") { _ = try lifecycle.begin(geometry: geometry, document: page) }
        lifecycle.finish(old)
        let current = try lifecycle.begin(geometry: geometry, document: page)
        lifecycle.finish(old)
        try require(lifecycle.canCommit(current, geometry: geometry, document: page), "Old completion cannot clear new lane")
        lifecycle.finish(current)
        for (width, height) in [(390.0, 844.0), (1024.0, 1366.0), (4096.0, 8192.0)] {
            let size = BrowserViewportGeometry(width: width, height: height, offsetX: 0, offsetY: 0, zoomScale: 1)
            let pixels = try size.snapshotWidth()
            try require(pixels <= 1600 && pixels * pixels * height / width <= 4_000_000, "Exact snapshot pixel budget")
        }
        let white = [UInt8](repeating: 255, count: 64)
        let black = Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 255), count: 16).flatMap { $0 }
        try require(!ViewportPixelValidator.isUsable(rgba: white), "Opaque blank capture is not success")
        try require(!ViewportPixelValidator.isUsable(rgba: black), "Black capture is not success")
        try require(!ViewportPixelValidator.isUsable(rgba: [UInt8](repeating: 0, count: 64)), "Transparent capture is not success")
        try require(ViewportPixelValidator.isUsable(rgba: white + black), "Readable pixels pass capture gate")

        let source = TranslationSourceSegment(
            id: "bubble", text: "Hello", boundingBox: NormalizedRect(x: 0.2, y: 0.3, width: 0.1, height: 0.05),
            confidence: 0.9, readingOrder: 0
        )
        let request = TranslationRequest(seriesID: nil, style: "fixture", segments: [source], glossary: [])
        var response = TranslationResponse(
            detectedSourceLanguage: "en", segments: [
                TranslatedSegmentPayload(
                    id: "bubble", sourceText: "Invented", translatedText: "Bonjour",
                    boundingBox: NormalizedRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1), confidence: 0.9, readingOrder: 9
                )
            ], glossaryUpdates: [], confidence: 0.9
        )
        let validated = try response.validated(against: request)
        try require(validated.segments[0].boundingBox == source.boundingBox && validated.segments[0].sourceText == source.text,
                    "Model cannot relocate source coordinates or invent source")
        try require(ViewportOverlayLayout.frame(for: validated.segments[0], in: CGSize(width: 400, height: 800)) ==
                    CGRect(x: 80, y: 240, width: 40, height: 40), "No oversized overlays")
        response.segments[0].confidence = 0.4
        try require(ViewportOverlayLayout.frame(for: response.segments[0], in: CGSize(width: 400, height: 800)) == nil,
                    "Uncertain translation leaves original untouched")
        response.segments[0].translatedText = ""
        try rejects("Empty translation is failure") { _ = try response.validated(against: request) }
        response.segments = []
        try rejects("Partial response is failure") { _ = try response.validated(against: request) }

        let cache = TranslationCache()
        let key = TranslationCacheKey(imageHash: "fixture", targetLanguage: "fr", glossaryChecksum: "terms", clientNamespace: "local-1")
        let result = TranslationResult(
            imageHash: "fixture", detectedSourceLanguage: "en", targetLanguage: "fr",
            segments: validated.segments, glossaryUpdates: [], durationMilliseconds: 1
        )
        await cache.store(result, for: key)
        let cached = await cache.value(for: key)
        try require(cached == result, "Existing cache returns result")
        for field in ["backend", "style", "source", "series"] {
            var different = key
            switch field {
            case "backend": different.clientNamespace = "local-2"
            case "style": different.styleChecksum = "style-2"
            case "source": different.sourceLanguage = "zh"
            default: different.seriesID = "series-2"
            }
            let missing = await cache.value(for: different)
            try require(missing == nil, "Cache is scoped by \(field)")
        }
        let lines = [
            OCRSegment(sourceText: "first", boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.04), confidence: 0.9),
            OCRSegment(sourceText: "second", boundingBox: NormalizedRect(x: 0.21, y: 0.25, width: 0.28, height: 0.04), confidence: 0.9),
            OCRSegment(sourceText: "last", boundingBox: NormalizedRect(x: 0.7, y: 0.75, width: 0.2, height: 0.04), confidence: 0.9)
        ]
        try require(WebtoonReadingOrder.sort(Array(lines.reversed())).map(\.sourceText) == ["first", "second", "last"],
                    "Existing reading order preserved")
        try require(BubbleGrouper.makeBubbles(from: lines).map(\.sourceText) == ["first\nsecond", "last"],
                    "Existing grouping preserved without Mac-mask claims")
        let locked = TermMemoryEntry(seriesID: "series", source: "Astra", translation: "Astra", category: .power, isLocked: true)
        let unlocked = TermMemoryEntry(seriesID: "series", source: "Lio", translation: "Lio", category: .character)
        try require(GlossaryResolver.instructions(from: [unlocked, locked]).first?.isLocked == true, "Existing locked glossary priority")
        print("PASS shared core: \(count) checks (no UIKit/Vision/SwiftData persistence claims)")
    }

    func browserAndNetwork() async throws {
        let server = try FixtureServer()
        defer { server.stop() }
        let browser = BrowserHarness()
        defer { browser.close() }
        try await browser.load(server.url("chapter"))
        let page = try await browser.state()
        try page.validateForCapture()
        try require(page.blockedReason == nil, "Synthetic chapter is capturable")
        let privateBridge = try await browser.webView.evaluateJavaScript("typeof window.WebtoonLensV2") as? String
        try require(privateBridge == "undefined", "Site JavaScript cannot impersonate private bridge")
        let content = try await browser.webView.evaluateJavaScript(
            "document.querySelector('#protected').naturalWidth > 0 && document.querySelector('#blob').src.startsWith('blob:') && document.querySelector('#javascript').textContent.includes('JS-RENDERED')"
        ) as? Bool
        try require(content == true, "Session image, blob image and JS-rendered content exist")
        let originalDOM = try await browser.webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
        let before = try await server.stats()
        let first = try await browser.snapshot()
        let second = try await browser.snapshot()
        try require(first.pixelsAreUsable && second.pixelsAreUsable, "Real macOS WKWebView viewport snapshot contains readable pixels")
        try require(first.hash == second.hash, "Stable canvas/browser capture fingerprint")
        let after = try await server.stats()
        try require(before.protectedAuthorized == 1 && after.protectedAuthorized == before.protectedAuthorized,
                    "Snapshots do not re-download protected chapter image")
        let afterDOM = try await browser.webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
        try require(originalDOM == afterDOM, "Capture never mutates or paints into original DOM")
        let noCookie = URLSession(configuration: .ephemeral)
        let (_, denied) = try await noCookie.data(from: server.url("protected.svg"))
        try require((denied as? HTTPURLResponse)?.statusCode == 403, "Second-download simulation fails without browser session")
        noCookie.invalidateAndCancel()

        let geometry = BrowserViewportGeometry(width: 390, height: 800, offsetX: 0, offsetY: 0, zoomScale: 1)
        var lifecycle = BrowserCaptureLifecycle()
        let token = try lifecycle.begin(geometry: geometry, document: page)
        _ = try await browser.webView.evaluateJavaScript("window.scrollTo(0,700)")
        try await Task.sleep(for: .milliseconds(200))
        let scrolled = try await browser.state()
        try require(scrolled.revision > page.revision && scrolled.scrollY != page.scrollY, "Browser scroll changes revision and viewport")
        try require(!lifecycle.canCommit(token, geometry: geometry, document: scrolled), "Real scroll rejects stale capture")
        _ = try await browser.webView.evaluateJavaScript("document.querySelector('#nested').scrollTop = 40")
        try await Task.sleep(for: .milliseconds(100))
        let nested = try await browser.state()
        try require(nested.revision > scrolled.revision, "Nested scroll invalidates capture")
        _ = try await browser.webView.evaluateJavaScript(
            "for(let n=0;n<40;n++){window.scrollTo(0,n*8);document.querySelector('#javascript').textContent='Synthetic revision '+n;}"
        )
        try await Task.sleep(for: .milliseconds(150))
        let changed = try await browser.state()
        try require(changed.revision > nested.revision, "Rapid JS/scroll changes invalidate capture")
        lifecycle.invalidate()
        try rejects("No concurrent capture during stale translation") { _ = try lifecycle.begin(geometry: geometry, document: changed) }
        lifecycle.finish(token)
        try await browser.load(server.url("next"))
        let next = try await browser.state()
        try require(next.documentID != page.documentID, "Navigation has a distinct document session")
        try require(!lifecycle.canCommit(token, geometry: geometry, document: next), "Navigation cannot reuse old coordinates")
        try await browser.load(server.url("chapter"))
        let returned = try await server.stats()
        try require(returned.protectedAuthorized >= 2, "Legitimate browser cookie survives chapter navigation")
        _ = try await browser.webView.evaluateJavaScript("window.scrollTo(0,document.documentElement.scrollHeight)")
        try await Task.sleep(for: .milliseconds(350))
        let lazy = try await browser.webView.evaluateJavaScript("document.querySelector('#lazy').naturalWidth > 0") as? Bool
        try require(lazy == true, "Lazy-rendered content becomes accessible normally")

        for (path, reason) in [("form", "form"), ("shadow-form", "form"), ("challenge", "challenge"), ("frame", "frame")] {
            try await browser.load(server.url(path))
            let blocked = try await browser.state()
            try require(blocked.blockedReason == reason, "Refuse synthetic \(path)")
            try rejects("No capture authorization for \(path)") { try blocked.validateForCapture() }
        }
        try require(!browser.messages.contains(where: { $0.contains("SYNTHETIC-SECRET") || $0.contains("PRIVATE-IDENTITY") }),
                    "Page bridge never transmits input values or credentials")
        try await browser.load(server.url("blank"))
        let blank = try await browser.snapshot()
        try require(!blank.pixelsAreUsable, "Real opaque blank snapshot is rejected")

        let request = TranslationRequest(seriesID: "fixture", style: "fail-once", segments: [
            TranslationSourceSegment(id: "synthetic-1", text: "HELLO, ASTRA!",
                                     boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
                                     confidence: 0.9, readingOrder: 0)
        ], glossary: [])
        let client = WebtoonTranslationClient(baseURL: server.url(""))
        do {
            _ = try await client.translate(request)
            throw CheckFailure(description: "Synthetic backend failure was accepted")
        } catch TranslationClientError.backendError(let status, let message) {
            try require(status == 503 && message.contains("Synthetic backend unavailable"), "Backend errors are explicit and recoverable")
        }
        let retried = try await client.translate(request)
        try require(retried.segments.count == 1 && retried.segments[0].translatedText.contains("fixture"),
                    "Retry accepts explicitly synthetic protocol response")
        do {
            _ = try await WebtoonTranslationClient(baseURL: server.url("malformed")).translate(request)
            throw CheckFailure(description: "Malformed backend response accepted")
        } catch TranslationClientError.invalidResponse {
            count += 1
        }
        do {
            _ = try await WebtoonTranslationClient(baseURL: server.url("redirect")).translate(request)
            throw CheckFailure(description: "Redirect accepted")
        } catch TranslationClientError.serverError(let status) {
            try require(status == 307, "Backend redirects never forward OCR text")
        }
        let slow = Task { try await WebtoonTranslationClient(baseURL: server.url("slow")).translate(request) }
        try await Task.sleep(for: .milliseconds(120))
        slow.cancel()
        do {
            _ = try await slow.value
            throw CheckFailure(description: "Cancelled backend request returned success")
        } catch is CancellationError {
            count += 1
        } catch let error as URLError where error.code == .cancelled {
            count += 1
        }
        let finalStats = try await server.stats()
        try require(finalStats.sink == 0, "Redirect destination received no text")
        try require(!finalStats.posts.isEmpty && finalStats.posts.allSatisfy { $0.cookie.isEmpty && $0.authorization.isEmpty },
                    "API uses neither browser cookies nor stored credentials")
        let wire = try JSONEncoder().encode(finalStats.posts)
        let wireText = String(decoding: wire, as: UTF8.self)
        try require(!wireText.contains("imageData") && !wireText.contains("imageURL") && !wireText.contains("SYNTHETIC-SECRET"),
                    "Wire format contains text only, never screenshots, image URLs or form values")
        print("PASS macOS WebKit + local protocol fixtures: \(count) total checks; synthetic backend is NOT a real translator")
    }
}

@MainActor
private final class FixtureServer {
    private let process = Process()
    private let port: Int

    init() throws {
        let output = Pipe()
        let script = Bundle.module.url(forResource: "server", withExtension: "py", subdirectory: "Fixtures")!
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path]
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(line), port > 0 else {
            process.terminate()
            throw CheckFailure(description: "Fixture server did not report a loopback port")
        }
        self.port = port
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)/\(path)")! }

    func stats() async throws -> FixtureStats {
        let (data, response) = try await URLSession.shared.data(from: url("stats"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CheckFailure(description: "Fixture server is not responsive") }
        return try JSONDecoder().decode(FixtureStats.self, from: data)
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}

private struct FixtureStats: Decodable {
    let protectedAuthorized: Int
    let protectedDenied: Int
    let sink: Int
    let posts: [FixturePost]
}

private struct FixturePost: Codable {
    let path: String
    let payload: TranslationRequest
    let cookie: String
    let authorization: String
}

@MainActor
private final class BrowserHarness: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private let window: NSWindow
    private let world = WKContentWorld.world(name: "WebtoonLensV2-checks")
    private var navigation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private(set) var messages: [String] = []

    override init() {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = webView
        webView.navigationDelegate = self
        configuration.userContentController.add(self, contentWorld: world, name: BrowserBridgeScript.handlerName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: BrowserBridgeScript.source, injectionTime: .atDocumentEnd,
            forMainFrameOnly: BrowserBridgeScript.mainFrameOnly, in: world
        ))
    }

    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            timeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(15))
                    self?.complete(.failure(CheckFailure(description: "WKWebView navigation timed out")))
                } catch is CancellationError {
                } catch {
                    self?.complete(.failure(error))
                }
            }
            webView.load(URLRequest(url: url))
        }
        try await Task.sleep(for: .milliseconds(300))
    }

    func state() async throws -> BrowserDocumentState {
        try await WebKitViewportCapture.document(in: webView, world: world)
    }

    func snapshot() async throws -> (hash: String, pixelsAreUsable: Bool) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.snapshotWidth = 780
        let image = try await WebKitViewportCapture.snapshot(in: webView, configuration: configuration)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw CheckFailure(description: "macOS WKWebView snapshot unavailable")
        }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        return (ImageHasher.sha256Hex(data), drawn && ViewportPixelValidator.isUsable(rgba: pixels))
    }

    func close() {
        timeout?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: BrowserBridgeScript.handlerName, contentWorld: world)
        webView.configuration.userContentController.removeAllUserScripts()
        window.contentView = nil
        window.close()
    }

    private func complete(_ result: Result<Void, Error>) {
        timeout?.cancel()
        let continuation = navigation
        navigation = nil
        continuation?.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { complete(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { complete(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { complete(.failure(error)) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let data = try? JSONSerialization.data(withJSONObject: message.body) else { return }
        messages.append(String(decoding: data, as: UTF8.self))
    }
}

@main
private struct V2ChecksMain {
    @MainActor static func main() async {
        do {
            let checks = Checks()
            try await checks.core()
            try await checks.browserAndNetwork()
            print("PASS \(checks.count) V2 checks. No iOS app, UIKit controller, device or signing validation implied.")
        } catch {
            fputs("FAIL V2 checks: \(error)\n", stderr)
            exit(1)
        }
    }
}
