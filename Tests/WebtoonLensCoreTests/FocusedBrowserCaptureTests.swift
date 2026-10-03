import XCTest
@testable import WebtoonLensCore

final class FocusedBrowserCaptureTests: XCTestCase {
    private func document(
        hardRevision: Int = 2, softRevision: Int = 1,
        source: String = "image:1", region: NormalizedRect = NormalizedRect(x: 0, y: 0.15, width: 1, height: 0.7),
        blocked: String? = nil
    ) -> BrowserDocumentState {
        BrowserDocumentState(
            documentID: "native-fixture", revision: hardRevision, url: "https://example.test/chapter",
            scrollX: 0, scrollY: 400, viewportWidth: 390, viewportHeight: 700,
            viewportLeft: 0, viewportTop: 0, viewportScale: 1, blockedReason: blocked,
            contentRevision: softRevision, captureRegion: region, readingSource: source
        )
    }

    func testUnrelatedDOMChangesDoNotInvalidateVerifiedReadingSource() throws {
        var lifecycle = BrowserCaptureLifecycle()
        let geometry = BrowserViewportGeometry(width: 390, height: 700, offsetX: 0, offsetY: 400, zoomScale: 1)
        let token = try lifecycle.begin(geometry: geometry, document: document())
        XCTAssertTrue(lifecycle.canCommit(token, geometry: geometry, document: document(softRevision: 1000)))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: document(hardRevision: 3)))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: document(source: "image:2")))
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: document(region: NormalizedRect(x: 0, y: 0.16, width: 1, height: 0.7))))
        XCTAssertThrowsError(try document(blocked: "form").validateForCapture())
        XCTAssertFalse(lifecycle.canCommit(token, geometry: geometry, document: document(blocked: "form")))
    }

    func testFingerprintDependsOnNormalizedPixelsNotPNGMetadata() throws {
        func image(_ shade: UInt8) throws -> CGImage {
            let pixels = Data(Array(repeating: [shade, shade, shade, 255], count: 20 * 20).flatMap { $0 })
            let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
            return try XCTUnwrap(CGImage(width: 20, height: 20, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 80,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        XCTAssertEqual(try ReadingPixelFingerprint.value(for: image(120)), try ReadingPixelFingerprint.value(for: image(120)))
        XCTAssertNotEqual(try ReadingPixelFingerprint.value(for: image(120)), try ReadingPixelFingerprint.value(for: image(121)))
    }

    func testRestabilizationIsBoundedAndNeverAcceptsPixelOnlyOrPrivacyChanges() {
        let original = document()
        let moved = document(region: NormalizedRect(x: 0, y: 0.16, width: 1, height: 0.7))
        XCTAssertTrue(BrowserRestabilizationPolicy.allows(previous: original, current: moved,
            explicitIntent: true, retries: 0, withinWindow: true))
        XCTAssertFalse(BrowserRestabilizationPolicy.allows(previous: original, current: original,
            explicitIntent: true, retries: 0, withinWindow: true), "Unchanged geometry with changed pixels is not a layout retry.")
        XCTAssertFalse(BrowserRestabilizationPolicy.allows(previous: original, current: moved,
            explicitIntent: true, retries: 2, withinWindow: true))
        XCTAssertFalse(BrowserRestabilizationPolicy.allows(previous: original, current: moved,
            explicitIntent: true, retries: 0, withinWindow: false))
        XCTAssertFalse(BrowserRestabilizationPolicy.allows(previous: original, current: document(hardRevision: 3),
            explicitIntent: true, retries: 0, withinWindow: true))
        XCTAssertFalse(BrowserRestabilizationPolicy.allows(previous: original, current: document(blocked: "form"),
            explicitIntent: true, retries: 0, withinWindow: true))
    }

    func testMovingNonTextBadgeOutsideOCRRegionDoesNotInvalidateThatRegion() throws {
        func image(badge: UInt8) throws -> CGImage {
            var pixels = [UInt8](repeating: 255, count: 40 * 40 * 4)
            for y in 30..<40 {
                for x in 30..<40 { pixels[(y * 40 + x) * 4] = badge }
            }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            return try XCTUnwrap(CGImage(width: 40, height: 40, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 160,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }
        let original = try image(badge: 255)
        let changed = try image(badge: 10)
        XCTAssertNotEqual(try ReadingPixelFingerprint.value(for: original), try ReadingPixelFingerprint.value(for: changed))
        let text = NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        XCTAssertEqual(try ReadingPixelFingerprint.value(for: original, region: text),
                       try ReadingPixelFingerprint.value(for: changed, region: text))
    }
}
