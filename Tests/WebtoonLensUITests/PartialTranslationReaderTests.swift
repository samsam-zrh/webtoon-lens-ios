import Network
import WebtoonLensCore
import XCTest

@MainActor
final class PartialTranslationReaderTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testTypedRefusalKeepsFailedOriginalAndTranslatesOnlyOtherDialogues() async throws {
        try await verify(allRejected: false)
    }

    func testEntirelyRefusedCaptureIsOriginalWithExplicitErrors() async throws {
        try await verify(allRejected: true)
    }

    private func verify(allRejected: Bool) async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] == "http://127.0.0.1:8787" else {
            throw XCTSkip("Native refusal fixtures are enabled only in the explicit local-backend scheme.")
        }
        let server = try RefusalFixtureServer(allRejected: allRejected)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = XCUIApplication()
        ReaderUITestSupport.launch(in: app)
        defer { app.terminate() }
        ReaderUITestSupport.configureLocalBackend(endpoint.absoluteString, in: app)
        app.tabBars.buttons["Webtoon"].tap()
        ReaderUITestSupport.open(endpoint.appendingPathComponent("chapter"), in: app)
        let ready = await ReaderUITestSupport.waitForPage(in: app, timeout: 15)
        XCTAssertTrue(ready)
        try await Task.sleep(for: .milliseconds(600))
        app.buttons["v2.translate"].tap()
        let authorize = app.buttons["Autoriser ce backend local"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5))
        authorize.tap()
        let transcript = app.buttons["Texte"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: transcript)
        await fulfillment(of: [completed], timeout: 45)
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        XCTAssertEqual(overlays.count, allRejected ? 0 : 2)
        if allRejected {
            XCTAssertTrue(app.segmentedControls["v2.presentation"].buttons["Original"].isSelected)
            XCTAssertTrue(app.staticTexts["v2.status"].label.contains("Aucun dialogue traduit."))
        }
        transcript.tap()
        XCTAssertTrue(app.staticTexts["CONTROLLED REFUSAL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Refus controle de la fixture originale."].exists)
        let successes = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedText."))
        XCTAssertEqual(successes.count, allRejected ? 0 : 2)
        app.buttons["Fermer"].tap()
        let batches = await server.recorder.batches
        XCTAssertEqual(batches.map(\.count), allRejected ? [3, 2, 1] : [3, 2])
        XCTAssertTrue(Set(batches[0]).isSuperset(of: Set(batches[1])))
        ReaderUITestSupport.configureLocalBackend("http://127.0.0.1:8787", in: app)
    }
}

actor RefusalFixtureRecorder {
    private(set) var batches: [[String]] = []
    func record(_ request: TranslationRequest) { batches.append(request.segments.map(\.id)) }
}

final class RefusalFixtureServer {
    let recorder = RefusalFixtureRecorder()
    private let listener: NWListener
    private let queue = DispatchQueue(label: "WebtoonLensV2.typed-refusal-fixture")

    init(allRejected: Bool) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let recorder = recorder
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue(label: "WebtoonLensV2.typed-refusal-connection"))
            Self.receive(connection, buffer: Data(), allRejected: allRejected, recorder: recorder)
        }
    }

    func start() async throws -> URL {
        let listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)") else {
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

    private static func receive(_ connection: NWConnection, buffer: Data, allRejected: Bool, recorder: RefusalFixtureRecorder) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            guard error == nil, let data, buffer.count + data.count <= 1_000_000 else {
                connection.cancel()
                return
            }
            let received = buffer + data
            if let boundary = received.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: received[..<boundary.lowerBound], as: UTF8.self)
                let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                if received.count >= boundary.upperBound + length {
                    let body = Data(received[boundary.upperBound..<(boundary.upperBound + length)])
                    Task {
                        do {
                            if header.hasPrefix("GET /chapter ") {
                                send(connection, status: 200, data: Data(chapter.utf8), type: "text/html")
                            } else if header.hasPrefix("POST /v1/webtoon/translate ") {
                                let request = try JSONDecoder().decode(TranslationRequest.self, from: body)
                                await recorder.record(request)
                                if let refused = request.segments.first(where: { allRejected || $0.text.contains("CONTROLLED") }) {
                                    let failure: [String: String] = [
                                        "error": "Refus controle de la fixture originale.", "code": "dialogue_translation_failed",
                                        "failedSegmentID": refused.id
                                    ]
                                    send(connection, status: 503, data: try JSONEncoder().encode(failure), type: "application/json")
                                } else {
                                    // Only the controlled rejection is synthetic; other text uses real local Qwen.
                                    let response = try await WebtoonTranslationClient(baseURL: URL(string: "http://127.0.0.1:8787")!).translate(request)
                                    send(connection, status: 200, data: try JSONEncoder().encode(response), type: "application/json")
                                }
                            } else {
                                send(connection, status: 404, data: Data("Not found".utf8), type: "text/plain")
                            }
                        } catch {
                            let failure = ["error": error.localizedDescription]
                            send(connection, status: 503, data: try JSONEncoder().encode(failure), type: "application/json")
                        }
                    }
                    return
                }
            }
            if complete { connection.cancel() } else { receive(connection, buffer: received, allRejected: allRejected, recorder: recorder) }
        }
    }

    private static func send(_ connection: NWConnection, status: Int, data: Data, type: String) {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static let chapter = """
    <!doctype html><html lang="en"><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Original controlled-refusal fixture</title>
    <style>body{margin:0;padding:20px;background:#31465b}
    .bubble{margin-top:24px;padding:18px;background:white;color:black;border-radius:28px;
    font:bold 20px/1.4 -apple-system,sans-serif;text-align:center}</style>
    <div class="bubble">CONTROLLED REFUSAL</div>
    <div class="bubble">WE TRAVEL TOGETHER.</div>
    <div class="bubble">WAIT FOR ASTRA.</div></html>
    """
}
