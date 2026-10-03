import XCTest
@testable import WebtoonLensCore
#if canImport(UIKit)
import UIKit
#endif

final class TranslationPipelineTests: XCTestCase {
    #if canImport(UIKit)
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
        let request = await client.lastRequest
        XCTAssertEqual(request?.seriesID, "series")
        XCTAssertEqual(request?.glossary.first?.source, "Astra")
    }
    #endif

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
        let missing = await cache.value(for: TranslationCacheKey(imageHash: "b", targetLanguage: "fr", glossaryChecksum: "g"))
        XCTAssertNil(missing)
    }

    #if canImport(UIKit)
    func testPartialResponsesAreNeverStoredAsCompleteCaptureCacheEntries() async throws {
        let cache = TranslationCache()
        let client = PartialFixtureClient()
        let pipeline = WebtoonTranslationPipeline(ocr: MockOCRService(segments: [
            OCRSegment(sourceText: "CONTROLLED REFUSAL", boundingBox: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05), confidence: 0.9),
            OCRSegment(sourceText: "Original valid dialogue", boundingBox: NormalizedRect(x: 0.1, y: 0.7, width: 0.5, height: 0.05), confidence: 0.9)
        ]), client: client, cache: cache)
        let data = Data("partial original fixture".utf8)
        for _ in 0..<2 {
            let result = try await pipeline.translate(image: Self.fixtureImage(), imageData: data, seriesID: nil, glossary: [], style: "test")
            XCTAssertEqual(result.segments.count, 1)
            XCTAssertEqual(result.failures.count, 1)
            XCTAssertFalse(result.segments.contains(where: { $0.id == result.failures[0].id }))
        }
        let key = TranslationCacheKey(
            imageHash: ImageHasher.sha256Hex(data), targetLanguage: "fr", glossaryChecksum: GlossaryResolver.checksum(for: []),
            styleChecksum: ImageHasher.sha256Hex(Data("test".utf8)), clientNamespace: client.cacheNamespace
        )
        let cached = await cache.value(for: key)
        XCTAssertNil(cached)
        let calls = await client.calls
        XCTAssertEqual(calls, 4)
    }

    private static func fixtureImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
    #endif
}

#if canImport(UIKit)
private final class MockOCRService: OCRRecognizing {
    let segments: [OCRSegment]

    init(segments: [OCRSegment]) {
        self.segments = segments
    }

    func recognizeText(in image: UIImage, mode: OCRMode) async throws -> [OCRSegment] {
        segments
    }
}

private actor MockTranslationClient: TranslationClientProtocol {
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

private actor PartialFixtureClient: TranslationClientProtocol {
    private(set) var calls = 0

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        calls += 1
        if let refused = request.segments.first(where: { $0.text == "CONTROLLED REFUSAL" }) {
            throw TranslationClientError.dialogueRejected(segmentID: refused.id, message: "Controlled fixture refusal")
        }
        return TranslationResponse(
            detectedSourceLanguage: "en", segments: request.segments.map {
                TranslatedSegmentPayload(
                    id: $0.id, sourceText: $0.text, translatedText: "Traduction de fixture synthetique",
                    boundingBox: $0.boundingBox, confidence: 0.9, readingOrder: $0.readingOrder
                )
            }, glossaryUpdates: [], confidence: 0.9
        )
    }
}
#endif
