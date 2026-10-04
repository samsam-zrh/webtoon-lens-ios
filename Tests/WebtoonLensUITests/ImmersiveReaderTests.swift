import Network
import WebtoonLensCore
import XCTest

@MainActor
final class ImmersiveReaderTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnlyThreeCommandsAndCompactHeaderAreVisible() {
        let app = launchIsolated()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["v2.address"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["v2.translate"].exists)
        XCTAssertTrue(app.buttons["v2.previousChapter"].exists)
        XCTAssertTrue(app.buttons["v2.nextChapter"].exists)
        XCTAssertFalse(app.buttons["Ouvrir"].exists)
        XCTAssertFalse(app.buttons["Lire le chapitre"].exists)
        XCTAssertFalse(app.buttons["Texte"].exists)
        XCTAssertFalse(app.switches["Auto"].exists)
        XCTAssertEqual(app.tabBars.count, 1)
        XCTAssertTrue(app.tabBars.buttons["Lecture"].exists)
        XCTAssertTrue(app.tabBars.buttons["Historique"].exists)
        XCTAssertFalse(app.segmentedControls["v2.presentation"].exists)
        let header = app.otherElements["v2.header"]
        XCTAssertTrue(header.exists)
        let measured = Double(app.staticTexts["v2.headerHeight"].value as? String ?? "") ?? .infinity
        XCTAssertGreaterThanOrEqual(measured, 108)
        XCTAssertLessThanOrEqual(measured, 120, "Measure app header content, excluding the system status-bar safe area.")
        XCTAssertGreaterThanOrEqual(app.buttons["v2.previousChapter"].frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["v2.nextChapter"].frame.height, 44)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Three commands and compact iPhone header"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStaticReadingImageTranslatesDespiteContinuousOffscreenMutations() async throws {
        try await runCausalCase(.offscreen)
    }

    func testVisibleReadingImageChangeRejectsOldResult() async throws {
        try await runCausalCase(.imageChange)
    }

    func testVisiblePrivacyFormBlocksPublication() async throws {
        try await runCausalCase(.privacyForm)
    }

    func testCanvasPixelChangeWithoutDOMMutationRejectsOldResult() async throws {
        try await runCausalCase(.canvasChange)
    }

    func testLateImageClassWithoutPixelChangeKeepsFrenchVisible() async throws {
        try await runCausalCase(.lateClass)
    }

    func testLateLayoutSettlingRetranslatesAutomaticallyWithoutSecondTap() async throws {
        try await runCausalCase(.lateLayout)
    }

    func testChangingBadgeOutsideDialogueDoesNotRemoveFrench() async throws {
        try await runCausalCase(.changingBadge)
    }

    func testScrollTranslatesNewImageAndReturnsCachedFrenchWithoutRetap() async throws {
        try await runCausalCase(.twoPages)
    }

    func testFractionalImageOriginUsesTheSameVerifiedPixelGridOnReturn() async throws {
        try await runCausalCase(.fractionalImage)
    }

    private func runCausalCase(_ scenario: ReadingCausalServer.Scenario) async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else {
            throw XCTSkip("Causal native tests use the explicit real-local-backend scheme.")
        }
        let server = try ReadingCausalServer(scenario: scenario)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let status = app.staticTexts["v2.status"]
        if [.offscreen, .lateClass, .lateLayout, .changingBadge, .twoPages, .fractionalImage].contains(scenario) {
            let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in overlays.count > 0 }, object: status)
            let result = await XCTWaiter.fulfillment(of: [complete], timeout: 40)
            XCTAssertEqual(result, .completed, status.label)
            let french = overlays.element(boundBy: 0).label
            XCTAssertTrue(french.localizedCaseInsensitiveContains("ensemble"), french)
            try await Task.sleep(for: .seconds(5))
            XCTAssertGreaterThan(overlays.count, 0, "Unrelated offscreen timers must not remove a verified reading overlay.")
            let state = await server.recorder.snapshot()
            XCTAssertEqual(state.pageLoads, 1)
            XCTAssertLessThanOrEqual(state.translations, scenario == .lateLayout ? 3 : 1)
            XCTAssertFalse(state.forwardedCookies)
            if scenario == .offscreen {
                app.buttons["v2.translate"].tap()
                let again = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in overlays.count > 0 }, object: status
                )], timeout: 20)
                XCTAssertEqual(again, .completed)
                let reused = await server.recorder.snapshot()
                XCTAssertEqual(reused.pageLoads, 1, "Same-page Traduire must not reload or lose browser scroll/session.")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Focused native French capture unaffected by offscreen DOM timers"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let first = overlays.element(boundBy: 0)
            let firstID = first.identifier
            let cachedID = String(firstID.dropFirst("v2.translatedSegment.".count))
            let initial = try anchorProof(in: app)
            let initialZone = try XCTUnwrap(initial.entries.first { $0.id == cachedID })
            XCTAssertTrue(initialZone.visible && initialZone.sourceVerified)
            XCTAssertLessThanOrEqual(initial.count, 40)
            XCTAssertGreaterThan(initial.referenceBytes, 0)
            XCTAssertLessThanOrEqual(initial.referenceBytes, 16_000_000)
            let beforeScroll = await server.recorder.snapshot()
            let web = app.webViews.firstMatch
            if scenario == .twoPages {
                web.swipeUp()
            } else {
                web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                    .press(forDuration: 0.05, thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                           withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            XCTAssertTrue(app.otherElements["v2.headerHandle"].waitForExistence(timeout: 5) ||
                          app.staticTexts["v2.headerHandle"].waitForExistence(timeout: 1))
            let measured = Double(app.staticTexts["v2.headerHeight"].value as? String ?? "") ?? .infinity
            XCTAssertLessThanOrEqual(measured, 24)
            let collapsed = XCTAttachment(screenshot: app.screenshot())
            collapsed.name = "Immersive header collapsed to a 20-point strip"
            collapsed.lifetime = .keepAlways
            add(collapsed)
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let proof = try? self.anchorProof(in: app),
                      let zone = proof.entries.first(where: { $0.id == cachedID }) else { return false }
                return proof.scrollY > initial.scrollY + 40 && !zone.visible
            }, object: status)
            let movedResult = await XCTWaiter.fulfillment(of: [moved], timeout: 8)
            XCTAssertEqual(movedResult, .completed,
                "Completed French must move out of view with its image, while remaining cached.")
            let scrolled = try anchorProof(in: app)
            let scrolledZone = try XCTUnwrap(scrolled.entries.first { $0.id == cachedID })
            XCTAssertEqual(scrolledZone.anchorID, initialZone.anchorID)
            XCTAssertEqual(scrolledZone.imageRect, initialZone.imageRect)
            XCTAssertFalse(scrolledZone.visible)
            let visibleFirst = app.staticTexts[firstID]
            XCTAssertFalse(visibleFirst.exists && visibleFirst.frame.intersects(web.frame),
                "An offscreen dialogue must not float over the next source.")
            if scenario == .twoPages {
                XCTAssertEqual(overlays.count, 0, "The first image's French must move offscreen with that image, not stay fixed to the viewport.")
                let fresh = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    overlays.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("Astra") }
                }, object: status)
                let nextResult = await XCTWaiter.fulfillment(of: [fresh], timeout: 35)
                XCTAssertEqual(nextResult, .completed)
                let second = overlays.allElementsBoundByIndex.first { $0.label.localizedCaseInsensitiveContains("Astra") }
                XCTAssertNotNil(second)
                let afterSecond = await server.recorder.snapshot()
                XCTAssertEqual(afterSecond.pageLoads, 1)
                app.webViews.firstMatch.swipeDown()
                let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    overlays.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("ensemble") }
                }, object: status)
                let returnResult = await XCTWaiter.fulfillment(of: [returned], timeout: 15)
                XCTAssertEqual(returnResult, .completed)
                let afterReturn = await server.recorder.snapshot()
                XCTAssertEqual(afterReturn.translations, afterSecond.translations,
                    "Returning must reuse French: \(app.staticTexts["v2.anchorCache"].value ?? "")")
            } else {
                web.swipeDown()
                let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let label = app.staticTexts[firstID]
                    return label.exists && label.label == french && label.frame.intersects(web.frame)
                }, object: status)
                let returnResult = await XCTWaiter.fulfillment(of: [returned], timeout: 15)
                XCTAssertEqual(returnResult, .completed, app.staticTexts["v2.anchorCache"].value as? String ?? "")
                try await Task.sleep(for: .seconds(2))
                let afterReturn = await server.recorder.snapshot()
                XCTAssertEqual(afterReturn.pageLoads, 1)
                XCTAssertEqual(afterReturn.translations, beforeScroll.translations,
                    "Scroll and return must reuse the completed French, not translate it again.")
                let restored = try anchorProof(in: app)
                let restoredZone = try XCTUnwrap(restored.entries.first { $0.id == cachedID })
                XCTAssertEqual(restoredZone.imageRect, initialZone.imageRect)
                XCTAssertTrue(restoredZone.visible && restoredZone.sourceVerified)
            }
            let metrics = XCTAttachment(string: app.staticTexts["v2.anchorCache"].value as? String ?? "")
            metrics.name = "Verified document/image anchors, native scroll coverage and bounded cache counters"
            metrics.lifetime = .keepAlways
            add(metrics)
            let finalCounts = await server.recorder.snapshot()
            let counters = XCTAttachment(string: String(decoding: try JSONEncoder().encode(finalCounts), as: UTF8.self))
            counters.name = "Native fixture API counters after cached scroll and return"
            counters.lifetime = .keepAlways
            add(counters)
        } else {
            let rejected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                status.label.contains("formulaire") || status.label.contains("Zone modifiee") ||
                    status.label.contains("contenu a change")
            }, object: status)
            let result = await XCTWaiter.fulfillment(of: [rejected], timeout: 30)
            XCTAssertEqual(result, .completed, status.label)
            try await Task.sleep(for: .seconds(2))
            XCTAssertEqual(overlays.count, 0, "Actual source changes or a visible form must never accept a stale result.")
            if scenario == .privacyForm { XCTAssertTrue(status.label.contains("formulaire")) }
        }
    }

    private func launchIsolated(backend: String = "http://127.0.0.1:8787") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["WEBTOON_LENS_TEST_PREFERENCES"] = "WebtoonLensV2.UI-\(UUID())"
        app.launchArguments = [
            "-backendBaseURL", backend, "-v2.consentedPublicChapterBackend", backend,
            "-v2.consentedTextBackend", backend, "-v2.lastPublicChapterURL", ""
        ]
        app.launch()
        return app
    }

    private func anchorProof(in app: XCUIApplication) throws -> AnchorProof {
        let value = try XCTUnwrap(app.staticTexts["v2.anchorCache"].value as? String)
        return try JSONDecoder().decode(AnchorProof.self, from: Data(value.utf8))
    }

    private struct AnchorProof: Decodable {
        let documentID: String
        let scrollY: Double
        let count: Int
        let referenceBytes: Int
        let entries: [Zone]

        struct Zone: Decodable {
            let id: String
            let anchorID: String
            let imageRect: NormalizedRect
            let visible: Bool
            let sourceVerified: Bool
        }
    }
}

actor ReadingCausalRecorder {
    struct State: Codable, Sendable {
        var pageLoads = 0
        var translations = 0
        var forwardedCookies = false
    }
    private var state = State()
    func page() { state.pageLoads += 1 }
    func translation(cookie: Bool) { state.translations += 1; state.forwardedCookies = state.forwardedCookies || cookie }
    func snapshot() -> State { state }
}

final class ReadingCausalServer {
    enum Scenario: String { case offscreen, imageChange, privacyForm, canvasChange, lateClass, lateLayout, changingBadge, twoPages, fractionalImage }
    let recorder = ReadingCausalRecorder()
    private let listener: NWListener
    private let queue = DispatchQueue(label: "WebtoonLensV2.focused-reading-fixture")

    init(scenario: Scenario) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let recorder = recorder
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue(label: "WebtoonLensV2.focused-reading-connection"))
            Self.receive(connection, buffer: Data(), scenario: scenario, recorder: recorder)
        }
    }

    func start() async throws -> URL {
        let listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    guard let port = listener.port else { continuation.resume(throwing: URLError(.badURL)); return }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil; listener.cancel() }

    private static func receive(_ connection: NWConnection, buffer: Data, scenario: Scenario, recorder: ReadingCausalRecorder) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            guard error == nil, let data, buffer.count + data.count <= 1_000_000 else { connection.cancel(); return }
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
                                await recorder.page()
                                send(connection, status: 200, body: Data(html(scenario).utf8), type: "text/html")
                            } else if header.hasPrefix("GET /v1/webtoon/warmup ") {
                                send(connection, status: 200, body: Data(#"{"ready":true,"fixture":true}"#.utf8), type: "application/json")
                            } else if header.hasPrefix("POST /v1/webtoon/translate ") {
                                let request = try JSONDecoder().decode(TranslationRequest.self, from: body)
                                await recorder.translation(cookie: header.lowercased().contains("\r\ncookie:") || header.lowercased().contains("\r\nauthorization:"))
                                try await Task.sleep(for: .seconds(2))
                                let response = try await WebtoonTranslationClient(baseURL: URL(string: "http://127.0.0.1:8787")!).translate(request)
                                send(connection, status: 200, body: try JSONEncoder().encode(response), type: "application/json")
                            } else {
                                send(connection, status: 404, body: Data("Not found".utf8), type: "text/plain")
                            }
                        } catch {
                            let message = String(describing: error)
                            let encoded = try? JSONEncoder().encode(["error": message])
                            send(connection, status: 503, body: encoded ?? Data("Fixture failure".utf8), type: "application/json")
                        }
                    }
                    return
                }
            }
            if complete { connection.cancel() } else { receive(connection, buffer: received, scenario: scenario, recorder: recorder) }
        }
    }

    private static func send(_ connection: NWConnection, status: Int, body: Data, type: String) {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func html(_ scenario: Scenario) -> String {
        """
        <!doctype html><html lang="en"><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Original focused reading fixture</title>
        <style>body{margin:0;padding:20px;min-height:3500px;background:#31465b}
        img{display:block;width:100%;max-width:360px;height:auto}#timer{position:absolute;top:3000px}</style>
        <img id="reading" alt="Original synthetic reading page">
        <div id="timer"></div>
        <script>
        const canvas=document.createElement('canvas');canvas.width=360;canvas.height=640;
        const context=canvas.getContext('2d');
        if('\(scenario.rawValue)'==='canvasChange'){
          document.querySelector('#reading').style.display='none';
          canvas.style='display:block;width:100%;max-width:360px;height:auto';
          document.body.prepend(canvas);
        }
        function paint(second){
          context.fillStyle=second?'#fff4bb':'#ffffff';context.fillRect(0,0,360,640);
          context.fillStyle='#111111';context.font='bold 24px sans-serif';
          context.fillText(second?'OUR PAGE HAS CHANGED.':'WAIT FOR THE OTHERS.',20,110);
          context.fillText(second?'KEEP THIS ORIGINAL.':'WE LEAVE TOGETHER.',20,150);
          if('\(scenario.rawValue)'!=='canvasChange')document.querySelector('#reading').src=canvas.toDataURL('image/png');
        }
        paint(false);let count=0;
        if('\(scenario.rawValue)'==='fractionalImage')document.querySelector('#reading').style.marginTop='37.25px';
        if('\(scenario.rawValue)'==='twoPages'){
          const next=document.createElement('img');next.id='next';next.style.marginTop='60px';
          context.fillStyle='#f1fff5';context.fillRect(0,0,360,640);
          context.fillStyle='#111111';context.font='bold 24px sans-serif';
          context.fillText('WE WILL FIND ASTRA.',20,110);
          next.src=canvas.toDataURL('image/png');document.querySelector('#reading').after(next);
        }
        setInterval(()=>document.querySelector('#timer').textContent='Offscreen '+(++count),110);
        if('\(scenario.rawValue)'==='imageChange')setTimeout(()=>paint(true),1600);
        if('\(scenario.rawValue)'==='canvasChange')setTimeout(()=>paint(true),1600);
        if('\(scenario.rawValue)'==='privacyForm')setTimeout(()=>{
          const field=document.createElement('input');field.type='password';field.value='SYNTHETIC-PRIVATE';
          field.style='position:fixed;top:160px;left:20px';document.body.append(field);
        },1600);
        if('\(scenario.rawValue)'==='lateClass')setTimeout(()=>document.querySelector('#reading').className='chapter-loaded',3500);
        if('\(scenario.rawValue)'==='lateLayout')setTimeout(()=>document.querySelector('#reading').style.marginTop='32px',1600);
        if('\(scenario.rawValue)'==='changingBadge'){
          const badge=document.createElement('div');badge.style='position:absolute;top:480px;left:270px;width:44px;height:44px';
          document.body.append(badge);
          setInterval(()=>badge.style.backgroundColor='rgb('+(count*29%255)+',60,100)',110);
        }
        </script></html>
        """
    }
}
