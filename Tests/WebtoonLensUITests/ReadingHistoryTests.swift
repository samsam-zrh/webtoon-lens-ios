import XCTest

@MainActor
final class ReadingHistoryTests: XCTestCase {
    func testHistoryStartsEmptyAndSelectionDoesNotTranslate() throws {
        let app = XCUIApplication()
        ReaderUITestSupport.launch(in: app)
        defer { app.terminate() }
        app.tabBars.buttons["Historique"].tap()
        XCTAssertTrue(app.staticTexts["Pas encore de lecture"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.historyEntry.")).count, 0)
        app.tabBars.buttons["Lecture"].tap()
        XCTAssertTrue(app.textFields["v2.address"].exists)
        XCTAssertEqual(app.textFields["v2.address"].value as? String, "Lien du chapitre")
    }
}
