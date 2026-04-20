import XCTest

final class WebtoonLensUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingReaderAndSettingsAreReachable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Webtoon Lens"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Traduire sans tricher avec iOS"].exists)

        app.tabBars.buttons["Lecteur"].tap()
        XCTAssertTrue(app.navigationBars["Lecteur"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Choisir une image"].exists)

        app.tabBars.buttons["Reglages"].tap()
        XCTAssertTrue(app.navigationBars["Reglages"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["https://api.example.com"].exists)
    }
}
