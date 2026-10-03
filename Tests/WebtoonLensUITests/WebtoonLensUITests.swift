import XCTest

@MainActor
final class WebtoonLensUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingReaderAndSettingsAreReachable() {
        let app = XCUIApplication()
        ReaderUITestSupport.launch(in: app)

        XCTAssertTrue(app.textFields["v2.address"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["v2.translate"].isEnabled)
        XCTAssertEqual(app.tabBars.count, 0)
        ReaderUITestSupport.openContext("Aide", in: app)
        XCTAssertTrue(app.navigationBars["Webtoon Lens V2"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Lis dans Webtoon Lens V2"].exists)

        app.buttons["Fermer"].tap()
        ReaderUITestSupport.openContext("Importer une capture", in: app)
        XCTAssertTrue(app.navigationBars["Lecteur"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Choisir une image"].exists)

        app.buttons["Fermer"].tap()
        ReaderUITestSupport.openContext("Reglages", in: app)
        XCTAssertTrue(app.navigationBars["Reglages"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["http://mon-mac.local:8787"].exists)
    }
}
