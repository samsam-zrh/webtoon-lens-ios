import XCTest
import UIKit
import UniformTypeIdentifiers

@MainActor
final class UnifiedWebnovelTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProtectedPublicExtractionFallsBackToCurrentReadableChapterImage() async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_WEBNOVEL"] == "1" else {
            throw XCTSkip("This bounded real-site check must be explicitly selected.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["WEBTOON_LENS_TEST_PREFERENCES"] = "WebtoonLensV2.UI-\(UUID())"
        app.launchArguments = [
            "-backendBaseURL", "http://127.0.0.1:8787",
            "-v2.consentedPublicChapterBackend", "http://127.0.0.1:8787",
            "-v2.consentedTextBackend", "http://127.0.0.1:8787",
            "-v2.lastPublicChapterURL", ""
        ]
        app.launch()
        defer {
            let state = XCTAttachment(string: "\(app.staticTexts["v2.browserState"].value ?? "")")
            state.name = "Native capture stage and bounded anchored-cache diagnostics (no chapter text)"
            state.lifetime = .keepAlways
            add(state)
            app.terminate()
        }
        let field = app.textFields["v2.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let source = "https://www.webnovel.com/fr/comic/wait-i-39-m-the-ultimate-demon-king_33398540708901501/chapter-1_89660822980187997"
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: source]],
                                     options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        field.tap()
        field.press(forDuration: 1)
        let paste = [app.menuItems["Paste"], app.buttons["Paste"], app.menuItems["Coller"], app.buttons["Coller"]]
            .first { $0.exists }
        XCTAssertNotNil(paste, "The URL field must keep its normal paste menu rather than open the reader's settings context.")
        paste?.tap()
        XCTAssertEqual(field.value as? String, source)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Reproduce Traduire while the real URL keyboard is still active.")
        app.buttons["v2.translate"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["v2.previousChapter"].isEnabled)
        XCTAssertFalse(app.buttons["v2.nextChapter"].isEnabled)
        let settledPage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (field.value as? String)?.contains("m.webnovel.com") == true || web.images.count > 0
        }, object: web)
        _ = await XCTWaiter.fulfillment(of: [settledPage], timeout: 15)
        let refusalLabels = ["Refuser", "Refuser: Refuser notre traitement des donn\u{00E9}es et fermer"]
        let refusalQuery = web.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", refusalLabels))
        let refusalExists = refusalQuery.firstMatch.waitForExistence(timeout: 10)
        var cookieChoice = "Ordinary cookie refusal control absent in this existing isolated browser session"
        if refusalExists {
            let refusal = try XCTUnwrap(refusalQuery.allElementsBoundByIndex.first(where: \.isHittable))
            refusal.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !refusalQuery.firstMatch.exists
            }, object: web)
            let dismissal = await XCTWaiter.fulfillment(of: [dismissed], timeout: 5)
            XCTAssertEqual(dismissal, .completed,
                "Cookie refusal must actually dismiss the ordinary banner before the reading-scroll proof.")
            cookieChoice = "Current exact AX refusal activated and ordinary banner dismissal asserted"
            app.buttons["v2.translate"].tap()
        }
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            overlays.count > 0 || app.staticTexts["v2.status"].label.contains("formulaire") ||
                app.staticTexts["v2.status"].label.contains("verification")
        }, object: web)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 35)
        if overlays.count == 0, result != .completed {
            // Exactly one ordinary user-equivalent retry on the already loaded viewport, no reload/extraction loop.
            app.buttons["v2.translate"].tap()
            let retried = await XCTWaiter.fulfillment(of: [XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in overlays.count > 0 }, object: web
            )], timeout: 25)
            if retried != .completed {
                let stage = XCTAttachment(string: "\(cookieChoice)\n\(app.staticTexts["v2.browserState"].value ?? "")\n\(app.staticTexts["v2.browserProof"].value ?? "")\n\(app.staticTexts["v2.anchorCache"].value ?? "")")
                stage.name = "Actual failure source, native stage and cache metrics; no chapter text"
                stage.lifetime = .keepAlways
                add(stage)
                let screen = XCTAttachment(screenshot: app.screenshot())
                screen.name = "Actual bounded Webnovel failure viewport (local only)"
                screen.lifetime = .keepAlways
                add(screen)
            }
            XCTAssertEqual(retried, .completed, "\(app.staticTexts["v2.status"].label); \(app.staticTexts["v2.browserState"].value ?? "")")
        }
        XCTAssertGreaterThan(overlays.count, 0, "A readable chapter image must yield a real fitted French result, not a cookie/header success.")
        try await Task.sleep(for: .seconds(5))
        XCTAssertGreaterThan(overlays.count, 0, "French must remain visible after layout/redirect settling without another translation tap.")
        let capturedProof = try XCTUnwrap(app.staticTexts["v2.browserProof"].value as? String)
        let proof = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(capturedProof.utf8)) as? [String: Any])
        XCTAssertEqual(proof["readingKind"] as? String, "IMG")
        XCTAssertTrue((proof["pageURL"] as? String ?? "").contains("webnovel.com/fr/comic/"))
        XCTAssertGreaterThan(proof["fittedSegments"] as? Int ?? 0, 0)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Webnovel current normal-session chapter viewport, focused native French capture (local only)"
        shot.lifetime = .keepAlways
        add(shot)
        let evidence = XCTAttachment(string: "\(cookieChoice). Normal public refusal -> browser fallback; fittedNativeSegments=\(overlays.count), headerContentHeight=\(app.staticTexts["v2.headerHeight"].value ?? ""), opaqueChapterArrowsDisabled=true. No chapter text included.")
        evidence.name = "Bounded real Webnovel fallback outcome"
        evidence.lifetime = .keepAlways
        add(evidence)
        let metadata = XCTAttachment(string: capturedProof)
        metadata.name = "Actual Webnovel source URL, focused image rectangle and native pixel dimensions (no chapter text)"
        metadata.lifetime = .keepAlways
        add(metadata)
        let before = overlays.element(boundBy: 0)
        let identifier = before.identifier
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = start.withOffset(CGVector(dx: 0, dy: -45))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(app.staticTexts[identifier].exists, "Partially visible narration must remain anchored while scrolling, not disappear.")
        let reverseStart = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        reverseStart.press(forDuration: 0.1, thenDragTo: reverseStart.withOffset(CGVector(dx: 0, dy: 45)),
                           withVelocity: .slow, thenHoldForDuration: 0.3)
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(app.staticTexts[identifier].exists, "Returning must recover the same verified French without retapping Traduire.")
        let returned = XCTAttachment(screenshot: app.screenshot())
        returned.name = "Webnovel anchored narration after scroll and return (local only)"
        returned.lifetime = .keepAlways
        add(returned)
        let anchored = XCTAttachment(string: app.staticTexts["v2.anchorCache"].value as? String ?? "")
        anchored.name = "Actual Webnovel image anchors after scroll and return; no chapter text"
        anchored.lifetime = .keepAlways
        add(anchored)
        let handle = app.descendants(matching: .any)["v2.headerHandle"]
        if handle.exists { handle.tap() }
        app.tabBars.buttons["Historique"].tap()
        let reading = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.historyEntry.")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "A real successful reading must be recorded locally.")
        reading.tap()
        XCTAssertTrue(app.textFields["v2.address"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textFields["v2.address"].value as? String)?.contains("webnovel.com") == true)
        XCTAssertEqual(overlays.count, 0, "Selecting history fills the URL only; it must not start another export or translation.")
    }
}
