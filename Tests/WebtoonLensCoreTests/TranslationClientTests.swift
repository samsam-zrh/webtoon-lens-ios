import XCTest
@testable import WebtoonLensCore

final class TranslationClientTests: XCTestCase {
    private var request: TranslationRequest {
        TranslationRequest(
            seriesID: "fixture", style: "test", segments: [
                TranslationSourceSegment(
                    id: "bubble-1", text: "Hello", boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
                    confidence: 0.9, readingOrder: 0
                )
            ], glossary: []
        )
    }

    private var response: TranslationResponse {
        TranslationResponse(
            detectedSourceLanguage: "en", segments: [
                TranslatedSegmentPayload(
                    id: "bubble-1", sourceText: "Hello", translatedText: "Bonjour",
                    boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1), confidence: 0.9, readingOrder: 0
                )
            ], glossaryUpdates: [], confidence: 0.9
        )
    }

    func testRealTextResponseUsesSourceCoordinatesNotModelCoordinates() throws {
        var shifted = response
        shifted.segments[0].boundingBox = NormalizedRect(x: 0.7, y: 0.7, width: 0.1, height: 0.1)
        shifted.segments[0].readingOrder = 99
        shifted.segments[0].sourceText = "Invented source"
        let validated = try shifted.validated(against: request)
        XCTAssertEqual(validated.segments[0].boundingBox, request.segments[0].boundingBox)
        XCTAssertEqual(validated.segments[0].sourceText, "Hello")
        XCTAssertEqual(validated.segments[0].readingOrder, 0)
    }

    func testEmptyMissingDuplicateUnexpectedOrInvalidSegmentsAreErrors() {
        var empty = response
        empty.segments = []
        XCTAssertThrowsError(try empty.validated(against: request))
        var duplicate = response
        duplicate.segments.append(duplicate.segments[0])
        XCTAssertThrowsError(try duplicate.validated(against: request))
        var unknown = response
        unknown.segments[0].id = "wrong"
        XCTAssertThrowsError(try unknown.validated(against: request))
        var blank = response
        blank.segments[0].translatedText = " \n "
        XCTAssertThrowsError(try blank.validated(against: request))
        var invalid = response
        invalid.segments[0].boundingBox.width = 1.5
        XCTAssertThrowsError(try invalid.validated(against: request))
        invalid = response
        invalid.segments[0].confidence = .nan
        XCTAssertThrowsError(try invalid.validated(against: request))
        var duplicateRequest = request
        duplicateRequest.segments.append(duplicateRequest.segments[0])
        XCTAssertThrowsError(try response.validated(against: duplicateRequest))
    }

    func testMissingBackendNeverReturnsFakeTranslation() async {
        do {
            _ = try await LocalPreviewTranslationClient().translate(request)
            XCTFail("A missing backend must be an error")
        } catch TranslationClientError.missingBackend {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPublicBackendIsRejectedBeforeNetworkRequest() async {
        do {
            _ = try await WebtoonTranslationClient(baseURL: URL(string: "https://third-party.example.test")!).translate(request)
            XCTFail("A public backend must be rejected")
        } catch BrowserCaptureError.nonLocalBackend {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBackendCannotRaiseOCRConfidence() throws {
        var lowerConfidence = request
        lowerConfidence.segments[0].confidence = 0.4
        let validated = try response.validated(against: lowerConfidence)
        XCTAssertEqual(validated.segments[0].confidence, 0.4)
        XCTAssertNil(ViewportOverlayLayout.frame(for: validated.segments[0], in: CGSize(width: 390, height: 640)))
    }
}
