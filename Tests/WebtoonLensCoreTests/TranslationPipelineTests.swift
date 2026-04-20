import UIKit
import XCTest
@testable import WebtoonLensCore

final class TranslationPipelineTests: XCTestCase {
    func testPipelineUsesOCRGroupsAndClientResponse() async throws {
        let ocr = MockOCRService(segments: [
            OCRSegment(
                sourceText: "Astra",
                boundingBox: NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.05),
                confidence: 0.9
            )
        ])
        let client = MockTranslationClient()
        let pipeline = WebtoonTranslationPipeline(ocr: ocr, client: client)

        let result = try await pipeline.translate(
            image: Self.fixtureImage(),
            imageData: Data("image".utf8),
            seriesID: "series",
            glossary: [
                GlossaryTermInstruction(id: "1", source: "Astra", translation: "Astra", category: .power, isLocked: true)
            ],
            style: "style"
        )

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].translatedText, "Astra")
        XCTAssertEqual(client.lastRequest?.seriesID, "series")
        XCTAssertEqual(client.lastRequest?.glossary.first?.source, "Astra")
    }

    func testCacheStoresAndReturnsResult() async {
        let cache = TranslationCache()
        let key = TranslationCacheKey(imageHash: "a", targetLanguage: "fr", glossaryChecksum: "g")
        let result = TranslationResult(
            imageHash: "a",
            detectedSourceLanguage: "ja",
            targetLanguage: "fr",
            segments: [],
            glossaryUpdates: [],
            durationMilliseconds: 12
        )

        await cache.store(result, for: key)
        let cached = await cache.value(for: key)

        XCTAssertEqual(cached?.imageHash, "a")
        XCTAssertNil(await cache.value(for: TranslationCacheKey(imageHash: "b", targetLanguage: "fr", glossaryChecksum: "g")))
    }

    private static func fixtureImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}

private final class MockOCRService: OCRRecognizing {
    let segments: [OCRSegment]

    init(segments: [OCRSegment]) {
        self.segments = segments
    }

    func recognizeText(in image: UIImage, mode: OCRMode) async throws -> [OCRSegment] {
        segments
    }
}

private final class MockTranslationClient: TranslationClientProtocol {
    var lastRequest: TranslationRequest?

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        lastRequest = request
        return TranslationResponse(
            detectedSourceLanguage: "ja",
            segments: request.segments.map {
                TranslatedSegmentPayload(
                    id: $0.id,
                    sourceText: $0.text,
                    translatedText: $0.text,
                    boundingBox: $0.boundingBox,
                    confidence: 0.9,
                    readingOrder: $0.readingOrder
                )
            },
            glossaryUpdates: [],
            confidence: 0.9
        )
    }
}
