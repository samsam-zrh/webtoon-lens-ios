import XCTest
@testable import WebtoonLensCore

final class LocalBubbleSurfaceTests: XCTestCase {
    func testWhiteBlackAndColoredBubblesEraseOnlyTheirSourceInk() throws {
        for (fill, ink) in [([UInt8(255), 255, 255], [UInt8(17), 17, 17]),
                            ([UInt8(18), 18, 18], [UInt8(255), 255, 255]),
                            ([UInt8(246), 223, 155], [UInt8(17), 17, 17]),
                            ([UInt8(22), 51, 56], [UInt8(255), 255, 255])] {
            let image = try bitmap { x, y in
                (x >= 20 && x < 75 && y >= 10 && y < 20) || (x >= 25 && x < 70 && y >= 28 && y < 38) ? ink : fill
            }
            let surface = try XCTUnwrap(LocalBubbleSurface.detect(in: image, sourceText: "Original first line\nOriginal second line"))
            XCTAssertEqual(surface.fill.red, fill[0])
            XCTAssertEqual(surface.fill.green, fill[1])
            XCTAssertEqual(surface.fill.blue, fill[2])
            XCTAssertGreaterThanOrEqual(surface.ink.contrast(with: surface.fill), 4.5)
            XCTAssertEqual(surface.sourceLineCount, 2)
            let bytes = try XCTUnwrap(surface.replacement.dataProvider?.data) as Data
            XCTAssertEqual(bytes[3], 0, "The background must stay transparent, never a blanket white rectangle.")
            XCTAssertEqual(bytes[(12 * 96 + 30) * 4 + 3], 255)
            XCTAssertEqual(bytes[(24 * 96 + 30) * 4 + 3], 0, "Interline background/art must not be painted.")
        }
    }

    func testTexturedArtAndCrossingBordersDoNotGetAnOpaqueReplacement() throws {
        let art = try bitmap { x, y in [UInt8(40 + x), UInt8(30 + y * 3), UInt8(20 + (x + y) % 200)] }
        XCTAssertNil(try LocalBubbleSurface.detect(in: art, sourceText: "Narration over textured illustration"))
        let boundary = try bitmap { x, y in
            x < 2 || y < 2 || x >= 94 || y >= 46 ? [17, 17, 17] : [255, 255, 255]
        }
        XCTAssertNil(try LocalBubbleSurface.detect(in: boundary, sourceText: "Text box crossing a dark bubble border"))
    }

    func testPixelVerificationIsExactAndTinyClipsAreNotDeletedAsChanged() throws {
        let first = try bitmap { x, y in x == 30 && y == 15 ? [17, 17, 17] : [255, 255, 255] }
        let changed = try bitmap { x, y in x == 31 && y == 15 ? [17, 17, 17] : [255, 255, 255] }
        XCTAssertEqual(try BrowserROIVerification.compare(reference: first, current: first, isClipped: true), .verified)
        XCTAssertEqual(try BrowserROIVerification.compare(reference: first, current: changed, isClipped: true), .changed)
        let tip = try XCTUnwrap(first.cropping(to: CGRect(x: 0, y: 0, width: 96, height: 5)))
        XCTAssertEqual(try BrowserROIVerification.compare(reference: tip, current: tip, isClipped: true), .insufficient)
    }

    func testFractionalPhaseTextVerificationIsExactSpatialAndNeverATranslation() {
        let region = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3)
        let source = TranslationSourceSegment(id: "original", text: "Wait for the others.\nWe leave together.",
            boundingBox: region, confidence: 0.95, readingOrder: 0)
        let first = OCRSegment(sourceText: "Wait for the others.", boundingBox: NormalizedRect(x: 0.2, y: 0.11, width: 0.6, height: 0.09),
                               confidence: 0.95)
        let second = OCRSegment(sourceText: "We leave together.", boundingBox: NormalizedRect(x: 0.2, y: 0.23, width: 0.6, height: 0.09),
                                confidence: 0.95)
        XCTAssertTrue(BrowserSourceTextVerification.matches(source: source, observations: [first, second], isClipped: false))
        XCTAssertTrue(BrowserSourceTextVerification.matches(source: source, observations: [second], isClipped: true))
        XCTAssertFalse(BrowserSourceTextVerification.matches(source: source, observations: [second], isClipped: false))
        var changed = second
        changed.sourceText = "We stay together."
        XCTAssertFalse(BrowserSourceTextVerification.matches(source: source, observations: [changed], isClipped: true))
        changed.sourceText = "We leave together!"
        XCTAssertFalse(BrowserSourceTextVerification.matches(source: source, observations: [first, changed], isClipped: false))
        changed = second
        changed.boundingBox.y = 0.8
        XCTAssertFalse(BrowserSourceTextVerification.matches(source: source, observations: [changed], isClipped: true))
    }

    private func bitmap(_ color: (Int, Int) -> [UInt8]) throws -> CGImage {
        let pixels: [UInt8] = (0..<48).flatMap { y -> [UInt8] in
            (0..<96).flatMap { x -> [UInt8] in color(x, y) + [UInt8(255)] }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(width: 96, height: 48, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 96 * 4,
            space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
