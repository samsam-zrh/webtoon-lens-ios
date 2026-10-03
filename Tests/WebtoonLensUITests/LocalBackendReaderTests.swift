import Network
import XCTest

@MainActor
final class LocalBackendReaderTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testViewportCaptureUsesVisionAndRealLocalTranslation() async throws {
        guard let backend = ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] else {
            throw XCTSkip("Run the explicit WebtoonLensV2LocalBackend scheme with a real local backend.")
        }
        XCTAssertEqual(backend, "http://127.0.0.1:8787", "This test sends only its original fixture to the authorized loopback backend.")

        let server = try OriginalChapterServer()
        let chapter = try await server.start()
        defer { server.stop() }
        let app = XCUIApplication()
        ReaderUITestSupport.launch(in: app)
        defer { app.terminate() }

        ReaderUITestSupport.configureLocalBackend(backend, in: app)
        app.tabBars.buttons["Webtoon"].tap()

        let address = app.textFields["v2.address"]
        address.tap()
        address.typeText(chapter.absoluteString)
        app.buttons["Ouvrir"].tap()
        let status = app.staticTexts["v2.status"]
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Page prete."), object: status)
        await fulfillment(of: [loaded], timeout: 20)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(app.alerts.count, 0, "Do not accept an OS or site prompt through a test.")

        app.buttons["v2.translate"].tap()
        let authorize = app.buttons["Autoriser ce backend local"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5), "Text export must request app consent for this fixture.")
        authorize.tap()

        let transcript = app.buttons["Texte"]
        let translated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            transcript.isEnabled || status.label.contains("Original conserve.") || status.label.contains("Zone modifiee.")
        }, object: transcript)
        let completion = await XCTWaiter.fulfillment(of: [translated], timeout: 45)
        let captureStatus = XCTAttachment(string: status.label)
        captureStatus.name = "Native fixture capture completion status"
        captureStatus.lifetime = .keepAlways
        add(captureStatus)
        XCTAssertEqual(completion, .completed, status.label)
        XCTAssertTrue(transcript.isEnabled, status.label)
        XCTAssertFalse(status.label.contains("Original conserve."), status.label)
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        XCTAssertGreaterThan(overlays.count, 0, "The real result must be presented over this stable, readable fixture.")
        let french = overlays.element(boundBy: 0).label
        XCTAssertTrue(french.localizedCaseInsensitiveContains("ensemble"), french)
        XCTAssertFalse(french.contains("WE LEAVE"), french)
        let evidence = XCTAttachment(string: "Vision iOS viewport OCR -> real local Qwen -> native presentation: \(french)\n\(status.label)")
        evidence.name = "Real native translation, original synthetic chapter"
        evidence.lifetime = .keepAlways
        add(evidence)

        transcript.tap()
        XCTAssertTrue(app.navigationBars["Texte de la capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[cd] %@", "ensemble")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "WE LEAVE")).firstMatch.exists,
                      "Keep the recognized source alongside its translation.")
        app.buttons["Fermer"].tap()
        app.segmentedControls["v2.presentation"].buttons["Original"].tap()
        XCTAssertEqual(overlays.count, 0, "Original removes the native translated capture.")
        XCTAssertFalse(transcript.isEnabled)
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["WAIT FOR THE OTHERS."].exists,
                      "The original page is never replaced or rewritten.")

        // Leave the chosen backend configured, but revoke fixture-only export consent.
        ReaderUITestSupport.revokeTextConsent(in: app)
    }
}

final class OriginalChapterServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "WebtoonLensV2.original-native-fixture")

    init(nextURL: URL? = nil) throws {
        let chapter: String
        if let nextURL {
            let href = nextURL.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            chapter = Self.chapter.replacingOccurrences(
                of: "</html>",
                with: "<a href=\"\(href)\" style=\"display:block;padding:14px;color:white\">Open test site</a></html>"
            )
        } else {
            chapter = Self.chapter
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue(label: "WebtoonLensV2.original-native-fixture.connection"))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                guard error == nil, let data else {
                    connection.cancel()
                    return
                }
                let isChapter = String(decoding: data, as: UTF8.self).hasPrefix("GET /chapter ")
                let body = Data((isChapter ? chapter : "Not found").utf8)
                let header = "HTTP/1.1 \(isChapter ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    func start() async throws -> URL {
        let listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)/chapter") else {
                        continuation.resume(throwing: URLError(.badURL))
                        return
                    }
                    continuation.resume(returning: url)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private static let chapter = """
    <!doctype html>
    <html lang="en">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Original native reader fixture</title>
    <style>
    body { margin: 0; padding: 28px; min-height: 1600px; background: #31465b; }
    .bubble { margin-top: 40px; padding: 28px 18px; border: 2px solid black;
      border-radius: 32px; background: white; color: black;
      font: bold 25px/1.6 -apple-system, sans-serif; text-align: center; }
    </style>
    <div class="bubble">WAIT FOR THE OTHERS.<br>WE LEAVE TOGETHER.</div>
    </html>
    """
}
