import XCTest

final class WebtoonLensUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingReaderAndSettingsAreReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Webtoon V2"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["v2.address"].exists)
        XCTAssertFalse(app.buttons["v2.translate"].isEnabled)
        app.tabBars.buttons["Accueil"].tap()
        XCTAssertTrue(app.navigationBars["Webtoon Lens V2"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Lis dans Webtoon Lens V2"].exists)

        app.tabBars.buttons["Lecteur"].tap()
        XCTAssertTrue(app.navigationBars["Lecteur"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Choisir une image"].exists)

        app.tabBars.buttons["Reglages"].tap()
        XCTAssertTrue(app.navigationBars["Reglages"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["http://mon-mac.local:8787"].exists)
    }
}
