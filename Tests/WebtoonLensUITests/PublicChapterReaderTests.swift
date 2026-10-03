import WebtoonLensCore
import XCTest

@MainActor
final class PublicChapterReaderTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNanoMachinePublicChapterShowsTwoPagesAndSafeFrenchDialogue() async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_PUBLIC_CHAPTER"] == "1" else {
            throw XCTSkip("Use the explicit public-chapter test scheme with the already-running local backend.")
        }
        let source = URL(string: "https://nanomachin.com/manga/nano-machine-chapter-332/")!
        let client = PublicChapterClient(baseURL: URL(string: "http://127.0.0.1:8787")!)
        let expected = try await client.extract(source)
        XCTAssertGreaterThanOrEqual(expected.images.count, 2)
        XCTAssertFalse(expected.images[0].isObviousDecoration)

        let app = XCUIApplication()
        ReaderUITestSupport.launch(in: app)
        defer { app.terminate() }
        ReaderUITestSupport.configureLocalBackend("http://127.0.0.1:8787", in: app)
        let publicConsent = app.switches["v2.publicChapterConsent"]
        if publicConsent.value as? String == "1" {
            publicConsent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let save = app.buttons["Enregistrer"]
            for _ in 0..<3 where !save.isHittable { app.swipeUp() }
            save.tap()
        }
        app.tabBars.buttons["Webtoon"].tap()
        let address = app.textFields["v2.address"]
        address.tap()
        address.typeText(source.absoluteString)
        app.buttons["v2.readChapter"].tap()
        let authorize = app.buttons["Autoriser la lecture publique"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5))
        authorize.tap()
        let masks = app.staticTexts["v2.chapterMasks"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard masks.exists, let value = masks.value as? String, let data = value.data(using: .utf8),
                  let proof = try? JSONDecoder().decode(PublicRenderProof.self, from: data) else { return false }
            return proof.pageCount >= 2 && proof.rendered.contains(where: { $0.page == 0 }) &&
                proof.rendered.contains(where: { $0.page == 1 })
        }, object: masks)
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 120)
        XCTAssertEqual(result, .completed, app.staticTexts["v2.chapterStatus"].label)
        let proof = try decodeProof(masks)
        XCTAssertGreaterThanOrEqual(proof.pageCount, 2)
        XCTAssertLessThanOrEqual(proof.mountedImages, 3)
        XCTAssertEqual(proof.pages[0].publicURL, expected.images[0].url)
        XCTAssertEqual(proof.pages[1].publicURL, expected.images[1].url)
        XCTAssertGreaterThan(proof.pages[0].height, 2500, "The test must exercise crop windows, not a logo or a whole-image OCR shortcut.")
        XCTAssertTrue(proof.rendered.contains(where: {
            $0.sourceLength > 10 && $0.translationLength > 10 && $0.sourceHash != $0.translationHash
        }), "A fitted dialogue must contain a real changed French response, not copied source or an icon.")
        for mask in proof.rendered {
            XCTAssertLessThanOrEqual(mask.maxLineWidth, mask.width)
            XCTAssertLessThanOrEqual(mask.usedHeight, mask.height)
            XCTAssertGreaterThanOrEqual(mask.fontSize, 10)
            XCTAssertTrue(mask.id.hasPrefix("p\(mask.page)-"))
        }
        app.buttons["Dialogue"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "NanoMachine genuine chapter viewport with safe French mask (local evidence only)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let evidence = XCTAttachment(string: masks.value as? String ?? "")
        evidence.name = "Public chapter extraction, natural windows and mask fitting metrics (no chapter text)"
        evidence.lifetime = .keepAlways
        add(evidence)
        let page = app.webViews.firstMatch
        XCTAssertGreaterThan(page.images.count, 0)
        let original = app.switches["v2.chapterOriginal"]
        original.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let originalSet = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? self.decodeProof(masks).original) == true
        }, object: masks)
        await fulfillment(of: [originalSet], timeout: 5)
        let originalScreenshot = XCTAttachment(screenshot: app.screenshot())
        originalScreenshot.name = "Same original Nano chapter viewport, overlays hidden (local evidence only)"
        originalScreenshot.lifetime = .keepAlways
        add(originalScreenshot)
        app.buttons["Suivante"].tap()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(try decodeProof(masks).pages.contains(where: { $0.index == 1 && $0.loaded }))
        app.buttons["Navigateur"].tap()
        ReaderUITestSupport.revokeTextConsent(in: app)
        let consent = app.switches["v2.publicChapterConsent"]
        if consent.value as? String == "1" { consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let save = app.buttons["Enregistrer"]
        for _ in 0..<3 where !save.isHittable { app.swipeUp() }
        save.tap()
    }

    private func decodeProof(_ field: XCUIElement) throws -> PublicRenderProof {
        let value = try XCTUnwrap(field.value as? String)
        return try JSONDecoder().decode(PublicRenderProof.self, from: Data(value.utf8))
    }
}

private struct PublicRenderProof: Decodable {
    let pageCount: Int
    let mountedImages: Int
    let original: Bool
    let rendered: [Mask]
    let pages: [Page]
    struct Mask: Decodable {
        let page: Int
        let id: String
        let fontSize: Double
        let width: Double
        let height: Double
        let maxLineWidth: Double
        let usedHeight: Double
        let sourceLength: Int
        let translationLength: Int
        let sourceHash: String
        let translationHash: String
    }
    struct Page: Decodable {
        let index: Int
        let width: Int
        let height: Int
        let publicURL: String
        let loaded: Bool
    }
}
