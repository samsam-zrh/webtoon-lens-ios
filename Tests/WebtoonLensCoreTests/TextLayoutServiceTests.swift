import XCTest
@testable import WebtoonLensCore

final class TextLayoutServiceTests: XCTestCase {
    func testReadingOrderSortsTopToBottomThenLeftToRight() {
        let bottom = OCRSegment(
            sourceText: "bottom",
            boundingBox: NormalizedRect(x: 0.1, y: 0.7, width: 0.2, height: 0.06),
            confidence: 0.9
        )
        let topRight = OCRSegment(
            sourceText: "top right",
            boundingBox: NormalizedRect(x: 0.55, y: 0.1, width: 0.2, height: 0.06),
            confidence: 0.9
        )
        let topLeft = OCRSegment(
            sourceText: "top left",
            boundingBox: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.06),
            confidence: 0.9
        )

        let sorted = WebtoonReadingOrder.sort([bottom, topRight, topLeft])

        XCTAssertEqual(sorted.map(\.sourceText), ["top left", "top right", "bottom"])
        XCTAssertEqual(sorted.map(\.readingOrder), [0, 1, 2])
    }

    func testBubbleGrouperMergesNearbyLines() {
        let first = OCRSegment(
            sourceText: "line 1",
            boundingBox: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.04),
            confidence: 0.8
        )
        let second = OCRSegment(
            sourceText: "line 2",
            boundingBox: NormalizedRect(x: 0.21, y: 0.25, width: 0.28, height: 0.04),
            confidence: 0.8
        )
        let far = OCRSegment(
            sourceText: "far",
            boundingBox: NormalizedRect(x: 0.7, y: 0.75, width: 0.2, height: 0.04),
            confidence: 0.8
        )

        let groups = BubbleGrouper.makeBubbles(from: [far, second, first])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].sourceText, "line 1\nline 2")
        XCTAssertEqual(groups[1].sourceText, "far")
    }
}
