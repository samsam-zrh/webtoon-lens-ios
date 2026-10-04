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

    func testIndependentROIReferencePreservesNativePixelsAndPartialCrops() throws {
        let width = 585, height = 220
        let pixels = Data((0..<(width * height)).flatMap { index -> [UInt8] in
            [UInt8(index % 253), UInt8((index / width) % 247), UInt8((index * 3) % 251), 255]
        })
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        for name in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: XCTUnwrap(CGColorSpace(name: name)),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let copy = try ReadingPixelFingerprint.independentCopy(of: image)
            XCTAssertEqual(copy.width, width)
            XCTAssertEqual(copy.height, height)
            XCTAssertEqual(copy.bitsPerComponent, image.bitsPerComponent)
            XCTAssertEqual(try ReadingPixelFingerprint.value(for: copy), try ReadingPixelFingerprint.value(for: image))
            let partial = NormalizedRect(x: 0, y: 0.35, width: 1, height: 0.4)
            XCTAssertEqual(try ReadingPixelFingerprint.value(for: copy, region: partial),
                           try ReadingPixelFingerprint.value(for: image, region: partial))
        }
        let extended = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 32,
            bytesPerRow: width * 16, space: extended,
            bitmapInfo: CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue |
                CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: extended, components: [1.2, 0.35, 0.2, 1])))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let extendedImage = try XCTUnwrap(context.makeImage())
        let extendedCopy = try ReadingPixelFingerprint.independentCopy(of: extendedImage)
        XCTAssertEqual(extendedCopy.bitsPerComponent, 32)
        XCTAssertEqual(try ReadingPixelFingerprint.value(for: extendedCopy),
                       try ReadingPixelFingerprint.value(for: extendedImage))
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
