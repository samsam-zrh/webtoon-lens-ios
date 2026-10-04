import XCTest
@testable import WebtoonLensCore

final class BrowserImageAnchoringTests: XCTestCase {
    func testScrollChangesViewportPositionButKeepsImageCoordinates() throws {
        let original = BrowserImageAnchor(id: "image1", signature: "img:source", bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 3))
        let capture = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        let text = NormalizedRect(x: 0.1, y: 0.4, width: 0.5, height: 0.1)
        let imageRect = try BrowserImageCoordinates.imageRect(captured: text, captureRegion: capture, anchor: original)
        let scrolled = BrowserImageAnchor(id: "image1", signature: "img:source", bounds: NormalizedRect(x: 0, y: -0.2, width: 1, height: 3))
        let moved = BrowserImageCoordinates.viewportRect(image: imageRect, anchor: scrolled)
        XCTAssertEqual(moved.y, 0.2, accuracy: 0.00001)
        XCTAssertEqual(moved.height, text.height, accuracy: 0.00001)
        XCTAssertEqual(BrowserImageCoordinates.viewportRect(image: imageRect, anchor: original), text)
    }

    func testCoverageMatchesSameTextOnlyAtSameImageRegion() {
        let a = TranslationSourceSegment(id: "a", text: "Same original dialogue", boundingBox: NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.1),
                                         confidence: 0.9, readingOrder: 0)
        var near = a
        near.id = "new-ocr-identifier"
        near.boundingBox.y += 0.001
        XCTAssertTrue(OCRCoverage.matches(near, existing: a))
        near.boundingBox.y = 0.8
        XCTAssertFalse(OCRCoverage.matches(near, existing: a))
        XCTAssertEqual(ReadingCopy.translated(1), "1 dialogue traduit")
        XCTAssertEqual(ReadingCopy.translated(2), "2 dialogues traduits")
    }

    func testClippedCoverageReusesOnlySpatiallyMatchingTextFragments() throws {
        let anchor = BrowserImageAnchor(id: "image1", signature: "source", bounds: NormalizedRect(x: 0, y: -0.3, width: 1, height: 1))
        let capture = NormalizedRect(x: 0, y: 0, width: 1, height: 0.7)
        let logical = NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.3)
        let visible = try XCTUnwrap(BrowserImageCoordinates.captureRect(image: logical, captureRegion: capture, anchor: anchor))
        XCTAssertEqual(visible.y, 0)
        XCTAssertEqual(visible.height, 2.0 / 7.0, accuracy: 0.00001)
        let full = TranslationSourceSegment(id: "cached", text: "Wait for the others. We leave together.",
            boundingBox: visible, confidence: 0.9, readingOrder: 0)
        var fragment = TranslationSourceSegment(id: "fresh", text: "We leave together.",
            boundingBox: visible, confidence: 0.9, readingOrder: 0)
        XCTAssertTrue(OCRCoverage.matches(fragment, existing: full))
        fragment.boundingBox.y = 0.65
        XCTAssertFalse(OCRCoverage.matches(fragment, existing: full))
        fragment.boundingBox = visible
        fragment.text = "Different original dialogue."
        XCTAssertFalse(OCRCoverage.matches(fragment, existing: full))
        XCTAssertNil(BrowserImageCoordinates.captureRect(image: logical,
            captureRegion: NormalizedRect(x: 0, y: 0, width: 0, height: 1), anchor: anchor))
    }

    func testIdenticalPipelineIDsStayDistinctAcrossImagesAndDocuments() {
        let a = BrowserImageAnchor(id: "image1", signature: "same-source", bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        let b = BrowserImageAnchor(id: "image2", signature: "same-source", bounds: a.bounds)
        let id = a.scopedSegmentID("cached-pipeline-id", documentID: "document1")
        XCTAssertEqual(id, a.scopedSegmentID("cached-pipeline-id", documentID: "document1"))
        XCTAssertNotEqual(id, b.scopedSegmentID("cached-pipeline-id", documentID: "document1"))
        XCTAssertNotEqual(id, a.scopedSegmentID("cached-pipeline-id", documentID: "document2"))
    }

    func testFocusedCropAndViewportShareOneIntegerPixelGrid() throws {
        let width = 804, height = 1274
        let focus = NormalizedRect(x: 0, y: 0.080078125, width: 1, height: 0.788465)
        let pixelFocus = try BrowserPixelCrop.rect(for: focus, width: width, height: height)
        let aligned = BrowserPixelCrop.normalized(pixelFocus, width: width, height: height)
        let segment = NormalizedRect(x: 0.1337, y: 0.24681, width: 0.6231, height: 0.134)
        let pixelSegment = try BrowserPixelCrop.rect(for: segment, width: Int(pixelFocus.width), height: Int(pixelFocus.height))
        let actualSegment = BrowserPixelCrop.normalized(pixelSegment, width: Int(pixelFocus.width), height: Int(pixelFocus.height))
        let anchor = BrowserImageAnchor(id: "chapter", signature: "static", bounds: NormalizedRect(x: 0, y: 0.03, width: 1, height: 1.37))
        let logical = try BrowserImageCoordinates.imageRect(captured: actualSegment, captureRegion: aligned, anchor: anchor)
        let viewport = BrowserImageCoordinates.viewportRect(image: logical, anchor: anchor)
        let fullPixels = try BrowserPixelCrop.rect(for: viewport, width: width, height: height)
        XCTAssertEqual(fullPixels, pixelSegment.offsetBy(dx: pixelFocus.minX, dy: pixelFocus.minY))
        XCTAssertEqual(try BrowserPixelCrop.rect(for: viewport, width: width, height: height), fullPixels)
    }
}
