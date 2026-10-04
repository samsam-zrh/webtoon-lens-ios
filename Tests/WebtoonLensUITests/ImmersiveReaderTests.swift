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

    func testPartiallyVisibleGraphicCaptionSurvivesFractionalScrollAndReturn() async throws {
        try await runPartialGraphicCase(nested: false)
    }

    func testNestedGraphicScrollKeepsFrenchBoundToTheImage() async throws {
        try await runPartialGraphicCase(nested: true)
    }

    func testReadingWindowRotatesBeyondTwelveImagesAndReturnsCachedFrench() async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else { throw XCTSkip("Local backend fixture.") }
        let server = try ReadingCausalServer(scenario: .manyImages)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let labels = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            labels.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("ensemble") }
        }, object: app)
        let first = await XCTWaiter.fulfillment(of: [ready], timeout: 35)
        XCTAssertEqual(first, .completed, app.staticTexts["v2.status"].label)
        let old = try XCTUnwrap(labels.allElementsBoundByIndex.first { $0.label.localizedCaseInsensitiveContains("ensemble") })
        let oldID = old.identifier
        let cacheID = String(oldID.dropFirst("v2.translatedSegment.".count))
        let original = try XCTUnwrap(try anchorProof(in: app).entries.first { $0.id == cacheID })
        let web = app.webViews.firstMatch
        for _ in 0..<17 { web.swipeUp() }
        let last = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            labels.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("Astra") }
        }, object: app)
        let lastResult = await XCTWaiter.fulfillment(of: [last], timeout: 25)
        XCTAssertEqual(lastResult, .completed, app.staticTexts["v2.status"].label)
        XCTAssertNotNil(try anchorProof(in: app).entries.first { $0.id == cacheID }, "Rotation of the twelve-node window must not retire a valid source.")
        let counts = await server.recorder.snapshot()
        for _ in 0..<17 { web.swipeDown() }
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.staticTexts[oldID].exists }, object: app)
        let returnedResult = await XCTWaiter.fulfillment(of: [returned], timeout: 15)
        XCTAssertEqual(returnedResult, .completed, app.staticTexts["v2.anchorCache"].value as? String ?? "")
        let restored = try XCTUnwrap(try anchorProof(in: app).entries.first { $0.id == cacheID })
        XCTAssertEqual(restored.imageRect, original.imageRect)
        let final = await server.recorder.snapshot()
        XCTAssertEqual(final.pageLoads, 1)
        XCTAssertEqual(final.translations, counts.translations, "Returning across more than twelve source images must reuse the first French.")
    }

    func testWhiteBlackAndColoredBubbleSurfacesUseLocalSourceColors() async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else { throw XCTSkip("Local backend fixture.") }
        let server = try ReadingCausalServer(scenario: .bubbleSurfaces)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let labels = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in labels.count >= 3 }, object: app)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 40)
        XCTAssertEqual(result, .completed, app.staticTexts["v2.status"].label)
        let proof = try anchorProof(in: app)
        let colors = proof.entries.compactMap(\.fill)
        XCTAssertTrue(colors.contains { $0.red >= 245 && $0.green >= 245 && $0.blue >= 245 })
        XCTAssertTrue(colors.contains { $0.red < 35 && $0.green < 35 && $0.blue < 35 })
        XCTAssertTrue(colors.contains { $0.red > 230 && $0.green > 190 && $0.blue < 190 })
        for entry in proof.entries where entry.visuallyReplaceable == true {
            let fill = try XCTUnwrap(entry.fill), ink = try XCTUnwrap(entry.ink)
            XCTAssertGreaterThanOrEqual(fill.contrast(with: ink), 4.5)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Actual native white, black and colored source bubbles with local alpha erasure and fitted French"
        shot.lifetime = .keepAlways
        add(shot)
        let metadata = XCTAttachment(string: app.staticTexts["v2.anchorCache"].value as? String ?? "")
        metadata.name = "Actual detected source fill/ink colors and conservative visual eligibility"
        metadata.lifetime = .keepAlways
        add(metadata)
    }

    func testUnreplaceableStyledTextOnArtKeepsOriginalWithExplicitTranscript() async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else { throw XCTSkip("Local backend fixture.") }
        let server = try ReadingCausalServer(scenario: .styledArt)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in overlays.count > 0 }, object: app)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 40)
        XCTAssertEqual(result, .completed, app.staticTexts["v2.status"].label)
        let proof = try anchorProof(in: app)
        XCTAssertGreaterThan(proof.count, 0, "The real translated text remains available even when its art is not safely replaceable.")
        XCTAssertTrue(proof.entries.allSatisfy { $0.visuallyReplaceable == false })
        XCTAssertGreaterThan(app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.caption.")).count, 0,
                             "Unsafe art keeps its original pixels and shows the French as an explicit caption, not a fake repaint.")
        app.staticTexts["v2.status"].press(forDuration: 1)
        app.descendants(matching: .any)["Texte et erreurs"].tap()
        XCTAssertGreaterThan(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedText.")).count, 0)
    }

    func testCanvasMutationAfterPublicationRetiresOldFrench() async throws {
        try await runPublishedGuardCase(.publishedCanvasChange)
    }

    func testPrivacyAppearingAfterPublicationStopsAndRemovesFrench() async throws {
        try await runPublishedGuardCase(.publishedPrivacy)
    }

    func testGeometryRevisionWithSameSVGSourceButChangedWordsRejectsCachedFrench() async throws {
        try await runComposedImageGuardCase(.movingAnimatedText)
    }

    func testGeometryRevisionWithSameSVGSourceButChangedFillRejectsCachedMask() async throws {
        try await runComposedImageGuardCase(.movingAnimatedFill)
    }

    private func runComposedImageGuardCase(_ scenario: ReadingCausalServer.Scenario) async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else { throw XCTSkip("Local backend fixture.") }
        let server = try ReadingCausalServer(scenario: scenario)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let labels = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            labels.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("ensemble") }
        }, object: app)
        let initial = await XCTWaiter.fulfillment(of: [ready], timeout: 30)
        XCTAssertEqual(initial, .completed, app.staticTexts["v2.status"].label)
        let old = try XCTUnwrap(labels.allElementsBoundByIndex.first { $0.label.localizedCaseInsensitiveContains("ensemble") })
        let oldID = old.identifier
        let cacheID = String(oldID.dropFirst("v2.translatedSegment.".count))
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let proof = try? self.anchorProof(in: app) else { return false }
            return proof.scrollY > 0 && !proof.entries.contains(where: { $0.id == cacheID }) &&
                !app.staticTexts[oldID].exists
        }, object: app)
        let result = await XCTWaiter.fulfillment(of: [rejected], timeout: 20)
        XCTAssertEqual(result, .completed, app.staticTexts["v2.anchorCache"].value as? String ?? "")
        let metadata = XCTAttachment(string: app.staticTexts["v2.anchorCache"].value as? String ?? "")
        metadata.name = "Composed geometry change with unchanged image URI: old source mask rejected"
        metadata.lifetime = .keepAlways
        add(metadata)
    }

    private func runPublishedGuardCase(_ scenario: ReadingCausalServer.Scenario) async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else { throw XCTSkip("Local backend fixture.") }
        let server = try ReadingCausalServer(scenario: scenario)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let labels = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in labels.count > 0 }, object: app)
        let initial = await XCTWaiter.fulfillment(of: [ready], timeout: 35)
        XCTAssertEqual(initial, .completed, app.staticTexts["v2.status"].label)
        let before = await server.recorder.snapshot()
        app.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            labels.count == 0 && (app.staticTexts["v2.status"].label.contains("change") ||
                app.staticTexts["v2.status"].label.contains("formulaire"))
        }, object: app)
        let result = await XCTWaiter.fulfillment(of: [removed], timeout: 15)
        XCTAssertEqual(result, .completed, app.staticTexts["v2.status"].label)
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(labels.count, 0, "A canvas mutation or visible private form must not restore an old result.")
        let after = await server.recorder.snapshot()
        XCTAssertEqual(after.translations, before.translations)
    }

    private func runPartialGraphicCase(nested: Bool) async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_BACKEND"] != nil else {
            throw XCTSkip("This original graphic fixture uses the configured real local backend.")
        }
        let server = try ReadingCausalServer(scenario: nested ? .nestedGraphic : .graphicPartial)
        let endpoint = try await server.start()
        defer { server.stop() }
        let app = launchIsolated(backend: endpoint.absoluteString)
        defer { app.terminate() }
        let field = app.textFields["v2.address"]
        field.tap()
        field.typeText(endpoint.appendingPathComponent("chapter").absoluteString)
        app.buttons["v2.translate"].tap()
        let overlays = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v2.translatedSegment."))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            overlays.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("ensemble") }
        }, object: app)
        let firstResult = await XCTWaiter.fulfillment(of: [ready], timeout: 40)
        XCTAssertEqual(firstResult, .completed, app.staticTexts["v2.status"].label)
        try await Task.sleep(for: .seconds(2))
        let label = try XCTUnwrap(overlays.allElementsBoundByIndex.first { $0.label.localizedCaseInsensitiveContains("ensemble") })
        let identifier = label.identifier
        let id = String(identifier.dropFirst("v2.translatedSegment.".count))
        let initial = try anchorProof(in: app)
        let original = try XCTUnwrap(initial.entries.first { $0.id == id })
        let counts = await server.recorder.snapshot()
        let web = app.webViews.firstMatch
        let displacement = label.frame.minY - web.frame.minY + label.frame.height * 0.35
        let start = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -displacement - 0.375)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        try await Task.sleep(for: .seconds(3))
        let partial = try anchorProof(in: app)
        let partialZone = try XCTUnwrap(partial.entries.first { $0.id == id },
            "An unchanged, partially visible source must not lose its finished translation: \(app.staticTexts["v2.anchorCache"].value ?? "")")
        XCTAssertEqual(partialZone.imageRect, original.imageRect)
        XCTAssertTrue(partialZone.visible && partialZone.sourceVerified)
        XCTAssertTrue(app.staticTexts[identifier].exists)
        let expected = try XCTUnwrap(partialZone.viewportRect)
        XCTAssertEqual(app.staticTexts[identifier].frame.minY, web.frame.minY + expected.y * web.frame.height, accuracy: 2,
            "French must follow its source image, including a nested scrolling container.")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = nested ? "Original graphic in nested scroller with image-bound French" : "Original graphic caption partially visible after fractional scroll"
        shot.lifetime = .keepAlways
        add(shot)
        let back = web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        back.press(forDuration: 0.05, thenDragTo: back.withOffset(CGVector(dx: 0, dy: displacement + 0.375)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        try await Task.sleep(for: .seconds(3))
        let restored = try anchorProof(in: app)
        let returned = try XCTUnwrap(restored.entries.first { $0.id == id },
            "The same source must restore its cached caption: \(app.staticTexts["v2.anchorCache"].value ?? "")")
        XCTAssertEqual(returned.imageRect, original.imageRect)
        XCTAssertTrue(returned.visible && app.staticTexts[identifier].exists)
        let after = await server.recorder.snapshot()
        XCTAssertEqual(after.pageLoads, 1)
        XCTAssertEqual(after.translations, counts.translations, "Partial scroll and return must not retranslate the same graphic caption.")
        let metrics = XCTAttachment(string: app.staticTexts["v2.anchorCache"].value as? String ?? "")
        metrics.name = "Partial graphic source coordinates and verified cache after return"
        metrics.lifetime = .keepAlways
        add(metrics)
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
                    return label.exists && self.accessibilityText(label.label) == self.accessibilityText(french) &&
                        label.frame.intersects(web.frame)
                }, object: status)
                let returnResult = await XCTWaiter.fulfillment(of: [returned], timeout: 15)
                let label = app.staticTexts[firstID]
                XCTAssertEqual(returnResult, .completed,
                    "exists=\(label.exists), text=\(label.exists ? label.label : ""), expected=\(french), frame=\(label.exists ? label.frame : .null), web=\(web.frame); \(app.staticTexts["v2.anchorCache"].value ?? "")")
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

    private func accessibilityText(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
            let viewportRect: NormalizedRect?
            let visible: Bool
            let sourceVerified: Bool
            let fill: BubbleRGB?
            let ink: BubbleRGB?
            let visuallyReplaceable: Bool?
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
    enum Scenario: String { case offscreen, imageChange, privacyForm, canvasChange, lateClass, lateLayout, changingBadge, twoPages, fractionalImage, graphicPartial, nestedGraphic, manyImages, bubbleSurfaces, styledArt, publishedCanvasChange, publishedPrivacy, movingAnimatedText, movingAnimatedFill }
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
        const usesCanvas=['canvasChange','publishedCanvasChange'].includes('\(scenario.rawValue)');
        if(usesCanvas){
          document.querySelector('#reading').style.display='none';
          canvas.style='display:block;width:100%;max-width:360px;height:auto';
          document.body.prepend(canvas);
        }
        function paint(second){
          context.fillStyle=second?'#fff4bb':'#ffffff';context.fillRect(0,0,360,640);
          context.fillStyle='#111111';context.font='bold 24px sans-serif';
          context.fillText(second?'OUR PAGE HAS CHANGED.':'WAIT FOR THE OTHERS.',20,110);
          context.fillText(second?'KEEP THIS ORIGINAL.':'WE LEAVE TOGETHER.',20,150);
          if(!usesCanvas)document.querySelector('#reading').src=canvas.toDataURL('image/png');
        }
        paint(false);let count=0;
        if(['graphicPartial','nestedGraphic'].includes('\(scenario.rawValue)')){
          canvas.width=480;canvas.height=1900;
          const gradient=context.createLinearGradient(0,0,480,1900);
          gradient.addColorStop(0,'#496476');gradient.addColorStop(1,'#173248');
          context.fillStyle=gradient;context.fillRect(0,0,480,1900);
          for(let y=0;y<1900;y+=27){context.fillStyle=y%54?'#886048':'#64806b';context.fillRect(15+(y%130),y,45,13);}
          context.fillStyle='#163338';context.beginPath();context.ellipse(240,150,208,98,0,0,Math.PI*2);context.fill();
          context.strokeStyle='#f6eacd';context.lineWidth=3;context.stroke();
          context.fillStyle='#ffffff';context.font='bold 28px sans-serif';
          context.fillText('WAIT FOR THE OTHERS.',65,132);context.fillText('WE LEAVE TOGETHER.',70,174);
          const image=document.querySelector('#reading');
          image.src=canvas.toDataURL('image/jpeg',0.9);
          image.style.width='calc(100% - 0.375px)';image.style.maxWidth='none';
          document.body.style.padding='20.25px';
          if('\(scenario.rawValue)'==='nestedGraphic'){
            const scroller=document.createElement('div');scroller.style='height:calc(100vh - 44px);overflow-y:auto;overscroll-behavior:contain';
            image.before(scroller);scroller.append(image);document.body.style.minHeight='0';
          }
        }
        if('\(scenario.rawValue)'==='fractionalImage')document.querySelector('#reading').style.marginTop='37.25px';
        if('\(scenario.rawValue)'==='twoPages'){
          const next=document.createElement('img');next.id='next';next.style.marginTop='60px';
          context.fillStyle='#f1fff5';context.fillRect(0,0,360,640);
          context.fillStyle='#111111';context.font='bold 24px sans-serif';
          context.fillText('WE WILL FIND ASTRA.',20,110);
          next.src=canvas.toDataURL('image/png');document.querySelector('#reading').after(next);
        }
        if('\(scenario.rawValue)'==='manyImages'){
          document.body.style.minHeight='0';
          let previous=document.querySelector('#reading');
          for(let page=1;page<14;page++){
            context.fillStyle=page%2?'#f1fff5':'#fff3df';context.fillRect(0,0,360,640);
            context.fillStyle='#b9d7c2';context.fillRect(40,80,280,360);
            if(page===13){
              context.fillStyle='#ffffff';context.fillRect(0,60,360,100);
              context.fillStyle='#111111';context.font='bold 24px sans-serif';context.fillText('WE WILL FIND ASTRA.',20,110);
            }
            const next=document.createElement('img');next.style.marginTop='8px';next.src=canvas.toDataURL('image/png');
            previous.after(next);previous=next;
          }
        }
        if('\(scenario.rawValue)'==='bubbleSurfaces'){
          context.fillStyle='#3e596d';context.fillRect(0,0,360,640);
          for(const [top,fill,ink,line] of [[30,'#ffffff','#111111','WAIT FOR THE OTHERS.'],[190,'#121212','#ffffff','WE WILL FIND ASTRA.'],[350,'#f6df9b','#111111','PLEASE WAIT FOR US.']]){
            context.fillStyle=fill;context.beginPath();context.ellipse(180,top+65,160,60,0,0,Math.PI*2);context.fill();
            context.strokeStyle=ink;context.lineWidth=2;context.stroke();
            context.fillStyle=ink;context.font='bold 23px sans-serif';context.fillText(line,40,top+72);
          }
          document.querySelector('#reading').src=canvas.toDataURL('image/png');
        }
        if('\(scenario.rawValue)'==='styledArt'){
          const gradient=context.createLinearGradient(0,0,360,640);
          gradient.addColorStop(0,'#c8393c');gradient.addColorStop(.3,'#6a8599');gradient.addColorStop(1,'#195f31');
          context.fillStyle=gradient;context.fillRect(0,0,360,640);
          for(let y=0;y<640;y+=16){context.fillStyle=y%32?'#976144':'#465a85';context.fillRect(0,y,360,8);}
          context.font='italic bold 24px sans-serif';context.strokeStyle='#111111';context.lineWidth=4;
          context.strokeText('WAIT FOR THE OTHERS.',20,110);context.strokeText('WE LEAVE TOGETHER.',20,150);
          context.fillStyle='#ffffff';context.fillText('WAIT FOR THE OTHERS.',20,110);context.fillText('WE LEAVE TOGETHER.',20,150);
          document.querySelector('#reading').src=canvas.toDataURL('image/png');
        }
        if(['movingAnimatedText','movingAnimatedFill'].includes('\(scenario.rawValue)')){
          const changedWords='\(scenario.rawValue)'==='movingAnimatedText';
          const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="360" height="640">
            <rect width="360" height="640" fill="white">${changedWords?'':'<set attributeName="fill" to="#163338" begin="8s" fill="freeze"/>'}</rect>
            <g fill="#111111" font-family="Arial,sans-serif" font-size="24" font-weight="bold">
              ${changedWords?'<set attributeName="visibility" to="hidden" begin="8s" fill="freeze"/>':''}
              <text x="20" y="110">WAIT FOR THE OTHERS.</text><text x="20" y="150">WE LEAVE TOGETHER.</text>
            </g>
            ${changedWords?'<g visibility="hidden" fill="#111111" font-family="Arial,sans-serif" font-size="24" font-weight="bold"><set attributeName="visibility" to="visible" begin="8s" fill="freeze"/><text x="20" y="110">OUR PAGE HAS CHANGED.</text><text x="20" y="150">KEEP THIS ORIGINAL.</text></g>':''}
          </svg>`;
          document.querySelector('#reading').src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(svg);
          setTimeout(()=>window.scrollBy(0,5.375),8100);
        }
        setInterval(()=>document.querySelector('#timer').textContent='Offscreen '+(++count),110);
        if('\(scenario.rawValue)'==='imageChange')setTimeout(()=>paint(true),1600);
        if('\(scenario.rawValue)'==='canvasChange')setTimeout(()=>paint(true),1600);
        if('\(scenario.rawValue)'==='privacyForm')setTimeout(()=>{
          const field=document.createElement('input');field.type='password';field.value='SYNTHETIC-PRIVATE';
          field.style='position:fixed;top:160px;left:20px';document.body.append(field);
        },1600);
        if('\(scenario.rawValue)'==='publishedCanvasChange')canvas.addEventListener('pointerup',()=>paint(true),{once:true});
        if('\(scenario.rawValue)'==='publishedPrivacy')document.querySelector('#reading').addEventListener('pointerup',()=>{
          const field=document.createElement('input');field.type='password';field.value='SYNTHETIC-PRIVATE';
          field.style='position:fixed;top:160px;left:20px';document.body.append(field);
        },{once:true});
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
