import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WebtoonLensCore

final class PublicChapterTests: XCTestCase {
    func testPublicConsentIsDistinctFromPrivateTextConsentAndBoundToBackend() throws {
        let suite = "PublicChapterTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SharedSettingsStore(defaults: defaults)
        settings.backendBaseURLString = "http://127.0.0.1:8787"
        XCTAssertFalse(settings.hasPublicChapterConsent)
        XCTAssertThrowsError(try settings.publicChapterBackend())
        settings.setTextTranslationConsent(true)
        XCTAssertFalse(settings.hasPublicChapterConsent)
        settings.setTextTranslationConsent(false)
        settings.setPublicChapterConsent(true)
        XCTAssertEqual(try settings.publicChapterBackend().port, 8787)
        XCTAssertFalse(settings.hasTextTranslationConsent)
        settings.backendBaseURLString = "http://127.0.0.1:8788"
        XCTAssertFalse(settings.hasPublicChapterConsent)
        settings.setPublicChapterConsent(true)
        settings.setPublicChapterConsent(false)
        XCTAssertThrowsError(try settings.publicChapterBackend())
    }

    func testPublicURLNeverCarriesCredentialsOrPrivateNetworkAddresses() throws {
        XCTAssertNoThrow(try PublicChapterURL.parse("https://reading.example.test/chapter"))
        for address in ["http://localhost:8787", "http://192.168.1.3/chapter", "http://127.0.0.1",
                        "http://mac.local/chapter", "file:///chapter", "https://user:secret@example.test",
                        "http://127.0.0.1/chapter?title=1", "https://example.test/chapter?access_token=secret"] {
            XCTAssertThrowsError(try PublicChapterURL.parse(address))
        }
    }

    func testDecorationFilteringUsesMetadataAndDimensionsNotHardcodedChapterURLs() {
        XCTAssertTrue(PublicChapterImage(url: "https://example.test/cropped-site-270x270.jpg").isObviousDecoration)
        XCTAssertFalse(PublicChapterImage(url: "https://example.test/chapter/01.jpg").isObviousDecoration)
        XCTAssertFalse(PublicImageMetadata(width: 270, height: 270).isReadingPage)
        XCTAssertTrue(PublicImageMetadata(width: 690, height: 21587).isReadingPage)
    }

    func testWindowsExhaustWholeLongPageAndKeep400PixelHalos() {
        for height in [399, 2500, 2501, 6200, 21587, 22080] {
            let windows = PublicOCRWindow.windows(height: height)
            XCTAssertEqual(windows.first?.coreTop, 0)
            XCTAssertEqual(windows.last?.coreBottom, height)
            for (index, window) in windows.enumerated() {
                XCTAssertLessThanOrEqual(window.coreBottom - window.coreTop, 2500)
                XCTAssertEqual(window.cropTop, max(0, window.coreTop - 400))
                XCTAssertEqual(window.cropBottom, min(height, window.coreBottom + 400))
                if index > 0 { XCTAssertEqual(windows[index - 1].coreBottom, window.coreTop) }
            }

            func testPublicCropperPreservesNaturalWindowDimensionsAndSourcePixels() throws {
                let width = 16
                let height = 6200
                var pixels = [UInt8](repeating: 255, count: width * height * 4)
                for row in 0..<height {
                    for column in 0..<width {
                        let index = (row * width + column) * 4
                        pixels[index] = row < 3000 ? 255 : 0
                        pixels[index + 1] = 0
                        pixels[index + 2] = row < 3000 ? 0 : 255
                    }
                }
                let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
                let image = try XCTUnwrap(CGImage(
                    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
                ))
                let png = NSMutableData()
                let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(encoder, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(encoder))
                let metadata = try PublicImageMetadata(data: png as Data)
                for window in PublicOCRWindow.windows(height: height) {
                    let crop = try PublicImageCropper.crop(publicImage: png as Data, metadata: metadata, window: window)
                    let cropMetadata = try PublicImageMetadata(data: crop)
                    XCTAssertEqual(cropMetadata.width, width)
                    XCTAssertEqual(cropMetadata.height, window.cropBottom - window.cropTop)
                    let source = try XCTUnwrap(CGImageSourceCreateWithData(crop as CFData, nil))
                    let croppedImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                    var firstPixel = [UInt8](repeating: 0, count: 4)
                    let firstRow = try XCTUnwrap(croppedImage.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
                    let context = try XCTUnwrap(CGContext(
                        data: &firstPixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ))
                    context.draw(firstRow, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    XCTAssertEqual(firstPixel[0], window.cropTop < 3000 ? 255 : 0)
                    XCTAssertEqual(firstPixel[2], window.cropTop < 3000 ? 0 : 255)
                }
            }
        }
    }

    func testMappingUsesNaturalCropOffsetsAndDoesNotDoubleCountHaloDialogue() throws {
        let segment = try fixtureSegment(y: 0.75)
        let metadata = PublicImageMetadata(width: 690, height: 6200)
        let first = try XCTUnwrap(PublicOCRWindow.windows(height: metadata.height).first)
        let mapped = try XCTUnwrap(first.map(segment, page: 0, metadata: metadata))
        XCTAssertEqual(mapped.boundingBox.y, 0.75 * 2900 / 6200, accuracy: 0.00001)
        XCTAssertEqual(mapped.imageHeight, 6200)
        XCTAssertEqual(mapped.maskData, segment.maskData)
        XCTAssertEqual(mapped.style, segment.style)
        let haloOnly = try fixtureSegment(y: 0.91)
        XCTAssertNil(try first.map(haloOnly, page: 0, metadata: metadata))
    }

    func testDuplicateDialogueRequiresMatchingTextAndActualRawOverlap() throws {
        let first = try fixtureSegment(y: 0.1)
        var same = first
        same.id = "overlap"
        same.rawBoundingBox?.y += 0.001
        XCTAssertTrue(first.isSameDialogue(as: same))
        var other = first
        other.id = "another bubble"
        other.rawBoundingBox?.x = 0.7
        XCTAssertFalse(first.isSameDialogue(as: other))
        other = first
        other.rawBoundingBox?.y = 0.7
        XCTAssertFalse(first.isSameDialogue(as: other))
    }

    func testInvalidMaskOrCoordinatesAreExplicitErrors() throws {
        var invalid = try fixtureSegment(y: 0.1)
        invalid.maskData = "https://example.test/a-mask"
        XCTAssertThrowsError(try invalid.validated())
        invalid = try fixtureSegment(y: 0.1)
        invalid.textBox?.width = 2
        XCTAssertThrowsError(try invalid.validated())
    }

    func testOCRWireUsesExactImageUrlAndPublicCropFields() throws {
        let image = URL(string: "https://example.test/chapter.png")!
        let page = URL(string: "https://example.test/chapter")!
        let request = PublicOCRRequest(imageURL: image, referer: page, language: "en")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(payload["imageUrl"] as? String, image.absoluteString)
        XCTAssertNil(payload["imageURL"])
        XCTAssertNil(payload["imageData"])
        let crop = PublicOCRRequest(publicCrop: Data([1, 2, 3]), referer: page, language: "en", cacheKey: "public-window")
        let cropPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(crop)) as? [String: Any])
        XCTAssertNil(cropPayload["imageUrl"])
        XCTAssertEqual(cropPayload["imageData"] as? String, "AQID")
        XCTAssertEqual(cropPayload["referer"] as? String, page.absoluteString)
    }

    func testChangingChapterRejectsStaleSessionResults() {
        var generation = PublicChapterGeneration()
        let old = generation.id
        XCTAssertTrue(generation.accepts(old))
        generation.advance()
        XCTAssertFalse(generation.accepts(old))
        XCTAssertTrue(generation.accepts(generation.id))
    }

    func testRememberedPublicURLIsOnlyAFieldValueAndRejectsPrivateSources() throws {
        let suite = "PublicChapterBookmark-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SharedSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.lastPublicChapterURL, "")
        let publicURL = URL(string: "https://example.test/chapter")!
        try settings.rememberPublicChapter(publicURL)
        XCTAssertEqual(settings.lastPublicChapterURL, publicURL.absoluteString)
        XCTAssertFalse(settings.hasTextTranslationConsent)
        XCTAssertFalse(settings.hasPublicChapterConsent)
        XCTAssertThrowsError(try settings.rememberPublicChapter(URL(string: "http://127.0.0.1/chapter")!))
        XCTAssertEqual(settings.lastPublicChapterURL, publicURL.absoluteString)
    }

    private func fixtureSegment(y: Double) throws -> PublicOCRSegment {
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="
        let data = """
        {"id":"fixture","sourceText":"Original synthetic dialogue","boundingBox":{"x":0.1,"y":\(y),"width":0.2,"height":0.03},
         "rawBoundingBox":{"x":0.1,"y":\(y),"width":0.2,"height":0.03},
         "textBox":{"x":0.11,"y":\(y),"width":0.18,"height":0.02},"confidence":0.9,"renderMode":"replace",
         "maskData":"data:image/png;base64,\(png)","style":{"fillColor":"#ffffff","textColor":"#111111"},
         "imageWidth":690,"imageHeight":2900,"fontSizeSource":28}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PublicOCRSegment.self, from: data).validated()
    }
}
