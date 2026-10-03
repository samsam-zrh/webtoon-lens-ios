import XCTest

@MainActor
final class SiteCompatibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWebnovelAccessibleViewport() async throws {
        try await checkSite(
            "Webnovel",
            url: "https://www.webnovel.com/fr/comic/wait-i-39-m-the-ultimate-demon-king_33398540708901501/chapter-1_89660822980187997"
        )
    }

    func testNanoMachineAccessibleViewport() async throws {
        try await checkSite("NanoMachine", url: "https://nanomachin.com/manga/nano-machine-chapter-332/")
    }

    func testOfficialWebtoonAccessibleViewport() async throws {
        try await checkSite(
            "WEBTOON",
            url: "https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=1"
        )
    }

    private func checkSite(_ site: String, url: String) async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_SITES"] == "1",
              let backend = ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] else {
            throw XCTSkip("Real-site checks require the explicit WebtoonLensV2SiteChecks scheme.")
        }
        let siteURL = try XCTUnwrap(URL(string: url))
        let server = try OriginalChapterServer(nextURL: siteURL)
        let originalFixture = try await server.start()
        defer { server.stop() }
        let app = XCUIApplication()
        ReaderUITestSupport.launch(in: app)
        defer { app.terminate() }
        ReaderUITestSupport.configureLocalBackend(backend, in: app)
        app.tabBars.buttons["Webtoon"].tap()
        ReaderUITestSupport.open(originalFixture, in: app)
        let fixtureReady = await ReaderUITestSupport.waitForPage(in: app, timeout: 15)
        XCTAssertTrue(fixtureReady)
        app.webViews.firstMatch.links["Open test site"].tap()

        let loaded = await ReaderUITestSupport.waitForPage(in: app, timeout: 30)
        let status = app.staticTexts["v2.status"]
        let page = app.webViews.firstMatch
        let transcript = app.buttons["Texte"]
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        var outcome = SiteOutcome(site: site, navigation: loaded ? status.label : "Navigation timeout after 30 seconds")
        if loaded, status.label.hasPrefix("Page prete."), app.alerts.count == 0 {
            try await Task.sleep(for: .milliseconds(900))
            if ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_READING_VIEWPORT"] == "1" {
                let refusalNodes = app.descendants(matching: .any).matching(NSPredicate(
                    format: "label == %@ OR label == %@", "Refuser tout", "Refuser"
                ))
                let refuse = refusalNodes.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
                if let refuse {
                    refuse.tap()
                    outcome.optionalCookiesRejected = true
                    try await Task.sleep(for: .milliseconds(900))
                }
                page.swipeUp()
                page.swipeUp()
                page.swipeUp()
                try await Task.sleep(for: .milliseconds(900))
                let viewport = XCTAttachment(screenshot: app.screenshot())
                viewport.name = "\(site) one reading viewport after normal scroll"
                viewport.lifetime = .keepAlways
                add(viewport)
                outcome.readingViewportExamined = true
            }
            outcome.visibleTextElements = page.staticTexts.allElementsBoundByIndex.prefix(8).filter(\.isHittable).count
            outcome.visibleImageElements = page.images.allElementsBoundByIndex.prefix(8).filter(\.isHittable).count
            let ageOrVerification = page.staticTexts.matching(NSPredicate(
                format: "label MATCHES[cd] %@",
                ".*(verify your age|age verification|confirm your age|mature content|verify you are human|captcha|sign in to continue|log in to continue|contenu adulte|contenu mature|verifier.*age|confirmer.*age|unlock.*chapter|read in.*app|continue in.*app|buy coins).*"
            )).allElementsBoundByIndex.contains(where: \.isHittable)
            if ageOrVerification {
                outcome.capture = "User interaction required; no verification, capture or text export attempted"
            } else {
                app.buttons["v2.translate"].tap()
                let authorize = app.buttons["Autoriser ce backend local"]
                if authorize.waitForExistence(timeout: 3) { authorize.tap() }
                var sawOCR = false
                var sawAPI = false
                let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let phase = status.label
                    sawOCR = sawOCR || phase.contains("Capture locale et OCR")
                    sawAPI = sawAPI || phase.contains("Traduction du texte OCR")
                    return transcript.isEnabled || phase.contains("Original conserve.") || phase.contains("Zone modifiee.")
                }, object: status)
                let completion = await XCTWaiter.fulfillment(of: [finished], timeout: 25)
                outcome.capture = completion == .completed ? status.label : "Viewport did not stabilize/complete within 25 seconds; original retained"
                if transcript.isEnabled {
                    outcome.ocr = "Vision recognized text in this viewport"
                    outcome.presentedSegments = overlays.count
                    transcript.tap()
                    outcome.translatedTextCount = app.staticTexts.matching(NSPredicate(
                        format: "identifier BEGINSWITH %@", "v2.translatedText."
                    )).count
                    outcome.hasFailedDialogues = app.descendants(matching: .any).matching(NSPredicate(
                        format: "identifier BEGINSWITH %@", "v2.failedSegment."
                    )).count > 0
                    app.buttons["Fermer"].tap()
                    outcome.translation = outcome.translatedTextCount > 0 ?
                        "Real local French segments accepted; failures remain explicit" : "No French segment accepted; all originals retained"
                    outcome.capture = overlays.count > 0 ? "Native capture overlay presented" : "Original retained; details available in text panel"
                } else {
                    outcome.ocr = sawAPI ? "Vision recognized text" : sawOCR ? "Vision attempted; no committed result" : "Not reached or rejected before OCR"
                    outcome.translation = sawAPI ? "API attempted; no committed result" : "Not reached"
                }
            }
        } else if app.alerts.count > 0 {
            outcome.capture = "OS/site alert requires the user; no warning or permission accepted"
        }

        if app.alerts.count == 0 {
            if page.isHittable { page.swipeUp() }
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: transcript)
            let removal = await XCTWaiter.fulfillment(of: [removed], timeout: 5)
            outcome.scrollPreservesOriginal = removal == .completed && overlays.count == 0
            XCTAssertTrue(outcome.scrollPreservesOriginal, "Scrolling must never retain translated pixels on a new viewport.")
            app.segmentedControls["v2.presentation"].buttons["Original"].tap()
            app.buttons["Recharger la page"].tap()
            outcome.reloadRemovesOverlay = overlays.count == 0 && !transcript.isEnabled
            XCTAssertTrue(outcome.reloadRemovesOverlay)
            _ = await ReaderUITestSupport.waitForPage(in: app, timeout: 10)
            let back = app.buttons["Page precedente"]
            if back.isEnabled {
                back.tap()
                let returned = await ReaderUITestSupport.waitForPage(in: app, timeout: 15)
                outcome.backPreservesOriginal = returned && overlays.count == 0 && !transcript.isEnabled &&
                    (app.textFields["v2.address"].value as? String)?.hasPrefix("http://127.0.0.1:") == true
                XCTAssertTrue(outcome.backPreservesOriginal, "Back must return to the original local fixture, not stale translated pixels.")
            }
            ReaderUITestSupport.revokeTextConsent(in: app)
        }

        let data = try JSONEncoder().encode(outcome)
        let report = String(decoding: data, as: UTF8.self)
        let attachment = XCTAttachment(string: report)
        attachment.name = "\(site) native viewport outcome (no chapter text)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("NATIVE_SITE_OUTCOME \(report)")
    }
}

private struct SiteOutcome: Encodable {
    let site: String
    let navigation: String
    var visibleTextElements = 0
    var visibleImageElements = 0
    var capture = "Not attempted after a navigation failure"
    var ocr = "Not attempted"
    var translation = "Not attempted"
    var presentedSegments = 0
    var scrollPreservesOriginal = false
    var reloadRemovesOverlay = false
    var backPreservesOriginal = false
    var readingViewportExamined = false
    var translatedTextCount = 0
    var hasFailedDialogues = false
    var optionalCookiesRejected = false
}
