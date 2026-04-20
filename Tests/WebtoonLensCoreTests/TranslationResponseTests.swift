import XCTest
@testable import WebtoonLensCore

final class TranslationResponseTests: XCTestCase {
    func testBackendResponseDecodesSegmentsAndGlossaryUpdates() throws {
        let json = """
        {
          "detectedSourceLanguage": "ko",
          "confidence": 0.91,
          "segments": [
            {
              "id": "bubble-1",
              "sourceText": "Astra",
              "translatedText": "Astra",
              "boundingBox": { "x": 0.1, "y": 0.2, "width": 0.3, "height": 0.1 },
              "confidence": 0.88,
              "readingOrder": 0
            }
          ],
          "glossaryUpdates": [
            {
              "id": "term-1",
              "source": "Astra",
              "suggestedTranslation": "Astra",
              "category": "power",
              "confidence": 0.8,
              "reason": "Nom de pouvoir recurrent"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TranslationResponse.self, from: json)

        XCTAssertEqual(response.detectedSourceLanguage, "ko")
        XCTAssertEqual(response.segments.first?.translatedText, "Astra")
        XCTAssertEqual(response.glossaryUpdates.first?.category, .power)
    }
}
