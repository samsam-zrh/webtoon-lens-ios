import XCTest

@MainActor
enum ReaderUITestSupport {
    static func launch(in app: XCUIApplication) {
        app.launchEnvironment["WEBTOON_LENS_TEST_PREFERENCES"] = "WebtoonLensV2.UI-\(UUID())"
        app.launchArguments += ["-v2.lastPublicChapterURL", ""]
        app.launch()
    }

    static func configureLocalBackend(_ backend: String, in app: XCUIApplication) {
        let endpoint = URLComponents(string: backend)
        XCTAssertEqual(endpoint?.host, "127.0.0.1")
        XCTAssertEqual(endpoint?.scheme, "http")
        openContext("Reglages", in: app)
        let backendField = app.textFields["v2.backend"]
        XCTAssertTrue(backendField.waitForExistence(timeout: 5))
        let existingValue = backendField.value as? String ?? ""
        if existingValue != backend {
            XCTAssertTrue(existingValue.isEmpty || existingValue == "http://mon-mac.local:8787" ||
                          URLComponents(string: existingValue)?.host == "127.0.0.1",
                          "Use a fresh V2 test install rather than overwrite another backend configuration.")
            backendField.tap()
            if existingValue.hasPrefix("http://"), existingValue != "http://mon-mac.local:8787" {
                backendField.press(forDuration: 1)
                let selectAll = [app.menuItems["Select All"], app.buttons["Select All"]].first { $0.exists }
                XCTAssertNotNil(selectAll, "The test must select the complete known fixture endpoint before replacing it.")
                selectAll?.tap()
            }
            backendField.typeText(backend + "\n")
            XCTAssertEqual(backendField.value as? String, backend)
        }
        setTextConsentOff(in: app)
        saveSettings(in: app)
    }

    static func revokeTextConsent(in app: XCUIApplication) {
        openContext("Reglages", in: app)
        setTextConsentOff(in: app)
        saveSettings(in: app)
    }

    static func open(_ url: URL, in app: XCUIApplication) {
        let field = app.textFields["v2.address"]
        XCTAssertFalse((field.value as? String)?.hasPrefix("http://") == true,
                       "Open the fixture in a fresh app process, without overwriting another page.")
        field.tap()
        field.typeText(url.absoluteString)
        XCTAssertEqual(field.value as? String, url.absoluteString)
        app.buttons["v2.translate"].tap()
    }

    static func openContext(_ label: String, in app: XCUIApplication) {
        let handle = app.descendants(matching: .any)["v2.headerHandle"]
        if handle.exists { handle.tap() }
        let status = app.staticTexts["v2.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.press(forDuration: 1)
        let action = app.buttons[label]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Context action \(label) must remain available without permanent chrome.")
        action.tap()
    }

    static func waitForPage(in app: XCUIApplication, timeout: TimeInterval) async -> Bool {
        let status = app.staticTexts["v2.status"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.label.hasPrefix("Page prete.") || status.label.contains("Original conserve.")
        }, object: status)
        return await XCTWaiter.fulfillment(of: [finished], timeout: timeout) == .completed
    }

    private static func setTextConsentOff(in app: XCUIApplication) {
        let consent = app.switches["v2.textConsent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        if switchIsOn(consent) {
            // The accessible SwiftUI switch row also contains its non-tappable label.
            consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertFalse(switchIsOn(consent), "Only each test's explicit request may authorize text export.")
    }

    private static func saveSettings(in app: XCUIApplication) {
        let save = app.buttons["Enregistrer"]
        for _ in 0..<3 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.staticTexts["Reglages V2 enregistres. Les captures ne quittent pas l'iPhone."].waitForExistence(timeout: 5))
    }

    private static func switchIsOn(_ element: XCUIElement) -> Bool {
        if let value = element.value as? String { return value == "1" }
        if let value = element.value as? NSNumber { return value.boolValue }
        XCTFail("The test cannot determine the consent switch state.")
        return false
    }
}
