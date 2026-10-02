import XCTest
@testable import WebtoonLensCore

final class BrowserViewportTests: XCTestCase {
    private var geometry: BrowserViewportGeometry {
        BrowserViewportGeometry(width: 390, height: 640, offsetX: 0, offsetY: 400, zoomScale: 1)
    }

    private func page(revision: Int = 0, id: String = "document-1", url: String = "https://example.test/chapter", blocked: String? = nil) -> BrowserDocumentState {
        BrowserDocumentState(
            documentID: id, revision: revision, url: url, scrollX: 0, scrollY: 400,
            viewportWidth: 390, viewportHeight: 640, viewportLeft: 0, viewportTop: 0,
            viewportScale: 1, blockedReason: blocked
        )
    }

    func testOnlyHTTPAddressesWithoutCredentialsAreAllowed() throws {
        XCTAssertEqual(try BrowserAddress.parse(" example.test/chapter ").absoluteString, "https://example.test/chapter")
        XCTAssertEqual(try BrowserAddress.parse("http://127.0.0.1:8790/chapter").scheme, "http")
        for address in ["", "javascript:alert(1)", "data:image/png,test", "file:///tmp/image", "ftp://example.test",
                        "https://user:pass@example.test", "http://", "https://example.test:0", "https://example.test:65536"] {
            XCTAssertThrowsError(try BrowserAddress.parse(address), address)
        }
    }

    func testBackendIsExplicitlyLocalAndCannotContainCredentialsOrRedirectParameters() throws {
        for value in ["http://localhost:8788", "http://127.0.0.1:8788", "http://192.168.1.3:8787",
                      "http://10.0.0.2", "http://172.16.0.1", "http://172.31.255.1",
                      "http://mon-mac.local:8787", "http://[::1]:8788", "http://[fd00::1]"] {
            XCTAssertNoThrow(try LocalBackendAddress.parse(value), value)
        }
        for value in ["https://translation.example.com", "http://192.168.1.3.evil.test", "http://172.32.0.1",
                      "http://0.0.0.0", "http://127.00.0.1", "http://127.1", "localhost:8788",
                      "http://user:pass@localhost", "http://localhost?url=https://example.test",
                      "http://localhost#secret", "https://mac.local.evil.test"] {
            XCTAssertThrowsError(try LocalBackendAddress.parse(value), value)
        }
    }

    func testConsentIsOffByDefaultBoundToEndpointAndRevocable() throws {
        let name = "WebtoonLensV2-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SharedSettingsStore(defaults: defaults)
        XCTAssertFalse(settings.hasTextTranslationConsent)
        XCTAssertFalse(settings.allowImageFallback)
        XCTAssertThrowsError(try settings.translationBackend())
        settings.backendBaseURLString = "http://localhost:8788"
        XCTAssertThrowsError(try settings.translationBackend())
        settings.setTextTranslationConsent(true)
        XCTAssertEqual(try settings.translationBackend().port, 8788)
        settings.backendBaseURLString = "http://localhost:8790"
        XCTAssertFalse(settings.hasTextTranslationConsent)
        settings.setTextTranslationConsent(true)
        settings.setTextTranslationConsent(false)
        XCTAssertThrowsError(try settings.translationBackend())
        settings.backendBaseURLString = "https://third-party.example.com"
        settings.setTextTranslationConsent(true)
        XCTAssertFalse(settings.hasTextTranslationConsent)
    }

    func testV2HasDistinctStateNamespace() {
        XCTAssertEqual(WebtoonLensConstants.appGroupIdentifier, "group.com.example.webtoonlens.v2")
        XCTAssertEqual(WebtoonLensConstants.displayName, "Webtoon Lens V2")
        XCTAssertTrue(BrowserBridgeScript.mainFrameOnly)
    }

    func testStableViewportCanCommit() throws {
        var lifecycle = BrowserCaptureLifecycle()
        let token = try lifecycle.begin(geometry: geometry, document: page())
        XCTAssertTrue(lifecycle.canCommit(token, geometry: geometry, document: page()))
        lifecycle.finish(token)
        XCTAssertNil(lifecycle.activeCaptureID)
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: page()))
    }

    func testScrollingZoomResizingAndDOMChangesRejectOldCoordinates() throws {
        var lifecycle = BrowserCaptureLifecycle()
        let token = try lifecycle.begin(geometry: geometry, document: page())
        var scrolled = geometry
        scrolled.offsetY += 1
        var zoomed = geometry
        zoomed.zoomScale = 1.1
        var resized = geometry
        resized.width = 640
        XCTAssertFalse(lifecycle.canCommit(token, geometry: scrolled, document: page()))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: zoomed, document: page()))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: resized, document: page()))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: page(revision: 1)))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: page(id: "document-2")))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: page(url: "https://example.test/next")))
    }

    func testCancellationKeepsLaneOccupiedUntilOldTaskActuallyFinishes() throws {
        var lifecycle = BrowserCaptureLifecycle()
        let old = try lifecycle.begin(geometry: geometry, document: page())
        for _ in 0..<100 { lifecycle.invalidate() }
        XCTAssertFalse(lifecycle.canCommit(old, geometry: geometry, document: page()))
        XCTAssertThrowsError(try lifecycle.begin(geometry: geometry, document: page(revision: 100)))
        lifecycle.finish(old)
        let current = try lifecycle.begin(geometry: geometry, document: page(revision: 100))
        lifecycle.finish(old)
        XCTAssertEqual(lifecycle.activeCaptureID, current.id)
        XCTAssertTrue(lifecycle.canCommit(current, geometry: geometry, document: page(revision: 100)))
    }

    func testFormsChallengesAndFramesNeverReachCapture() {
        for reason in ["form", "challenge", "frame", "media", "scheme"] {
            var lifecycle = BrowserCaptureLifecycle()
            XCTAssertThrowsError(try lifecycle.begin(geometry: geometry, document: page(blocked: reason)))
            XCTAssertNil(lifecycle.activeCaptureID)
        }
    }

    func testSnapshotBudgetIsMeasuredInPixelsNotPoints() throws {
        for (width, height) in [(390.0, 844.0), (1024.0, 1366.0), (4096.0, 8192.0)] {
            let value = BrowserViewportGeometry(width: width, height: height, offsetX: 0, offsetY: 0, zoomScale: 2)
            let snapshotWidth = try value.snapshotWidth()
            XCTAssertLessThanOrEqual(snapshotWidth, 1600)
            XCTAssertLessThanOrEqual(snapshotWidth * snapshotWidth * height / width, 4_000_000)
        }
        var invalid = geometry
        invalid.width = .nan
        XCTAssertThrowsError(try invalid.snapshotWidth())
    }

    func testOpaqueUniformAndTransparentSnapshotsAreNotSuccess() {
        let white = [UInt8](repeating: 255, count: 64)
        let black = Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 255), count: 16).flatMap { $0 }
        XCTAssertFalse(ViewportPixelValidator.isUsable(rgba: white))
        XCTAssertFalse(ViewportPixelValidator.isUsable(rgba: black))
        XCTAssertFalse(ViewportPixelValidator.isUsable(rgba: [UInt8](repeating: 0, count: 64)))
        XCTAssertTrue(ViewportPixelValidator.isUsable(rgba: white + black))
    }

    func testOverlayNeverExpandsBeyondSourceBoxOrPaintsUncertainCoordinates() throws {
        var segment = TranslatedSegmentPayload(
            id: "bubble", sourceText: "Hello", translatedText: "Bonjour",
            boundingBox: NormalizedRect(x: 0.2, y: 0.3, width: 0.1, height: 0.05), confidence: 0.9, readingOrder: 0
        )
        let frame = try XCTUnwrap(ViewportOverlayLayout.frame(for: segment, in: CGSize(width: 400, height: 800)))
        XCTAssertEqual(frame, CGRect(x: 80, y: 240, width: 40, height: 40))
        segment.confidence = 0.69
        XCTAssertNil(ViewportOverlayLayout.frame(for: segment, in: CGSize(width: 400, height: 800)))
        segment.confidence = 0.9
        segment.boundingBox.x = -0.01
        XCTAssertNil(ViewportOverlayLayout.frame(for: segment, in: CGSize(width: 400, height: 800)))
        segment.boundingBox.x = 0.95
        XCTAssertNil(ViewportOverlayLayout.frame(for: segment, in: CGSize(width: 400, height: 800)))
        segment.boundingBox.x = .nan
        XCTAssertNil(ViewportOverlayLayout.frame(for: segment, in: CGSize(width: 400, height: 800)))
    }

    func testCacheContextsIncludeStyleSourceSeriesAndBackend() {
        let base = TranslationCacheKey(imageHash: "image", targetLanguage: "fr", glossaryChecksum: "terms")
        var changed = base
        changed.styleChecksum = "new-style"
        XCTAssertNotEqual(base, changed)
        changed = base
        changed.sourceLanguage = "zh"
        XCTAssertNotEqual(base, changed)
        changed = base
        changed.seriesID = "new-series"
        XCTAssertNotEqual(base, changed)
        changed = base
        changed.clientNamespace = "http://localhost:8790"
        XCTAssertNotEqual(base, changed)
    }
}
