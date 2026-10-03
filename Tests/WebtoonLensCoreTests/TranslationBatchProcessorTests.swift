import XCTest
@testable import WebtoonLensCore

final class TranslationBatchProcessorTests: XCTestCase {
    private func request(count: Int) -> TranslationRequest {
        TranslationRequest(seriesID: "original-fixture", style: "test", segments: (0..<count).map {
            TranslationSourceSegment(
                id: "segment-\($0)", text: "Original synthetic dialogue \($0)",
                boundingBox: NormalizedRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
                confidence: 0.9, readingOrder: $0
            )
        }, glossary: [])
    }

    func testKnownRefusalRemovesOnlyThatIDAndPreservesOriginalError() async throws {
        let client = RecoveryClient(mode: .rejectOne)
        let source = request(count: 3)
        let result = try await TranslationBatchProcessor(client: client).translate(source)
        let batches = await client.batches
        XCTAssertEqual(batches, [["segment-0", "segment-1", "segment-2"], ["segment-1", "segment-2"]])
        XCTAssertEqual(result.segments.map(\.id), ["segment-1", "segment-2"])
        XCTAssertEqual(result.failures.map(\.id), ["segment-0"])
        XCTAssertEqual(result.failures[0].source, source.segments[0])
        XCTAssertEqual(result.failures[0].message, "Controlled fixture refusal")
        XCTAssertEqual(result.segments.count + result.failures.count, source.segments.count)
    }

    func testUnknownOrAlreadyRemovedFailureIDIsAnError() async {
        for mode in [RecoveryClient.Mode.unknownID, .repeatRemovedID] {
            do {
                _ = try await TranslationBatchProcessor(client: RecoveryClient(mode: mode)).translate(request(count: 3))
                XCTFail("An unknown or already removed ID must not be silently skipped")
            } catch TranslationClientError.invalidResponse {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRetryBudgetIsBoundedAndUntranslatedSegmentsAreExplicitFailures() async throws {
        let client = RecoveryClient(mode: .rejectEveryFirst)
        let result = try await TranslationBatchProcessor(client: client).translate(request(count: 8))
        let batches = await client.batches
        XCTAssertEqual(batches.count, 5)
        XCTAssertEqual(batches.map(\.count), [8, 7, 6, 5, 4])
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertEqual(result.failures.count, 8)
        XCTAssertEqual(result.failures.filter { $0.kind == .retryLimitReached }.count, 3)
    }

    func testEachSubBatchIsLimitedTo32AndAccountsForEveryID() async throws {
        let client = RecoveryClient(mode: .success)
        let result = try await TranslationBatchProcessor(client: client).translate(request(count: 70))
        let batches = await client.batches
        XCTAssertEqual(batches.map(\.count), [32, 32, 6])
        XCTAssertEqual(Set(result.segments.map(\.id)), Set(request(count: 70).segments.map(\.id)))
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testGenericNetworkErrorIsNotConvertedToPartialSuccess() async {
        let client = RecoveryClient(mode: .networkError)
        do {
            _ = try await TranslationBatchProcessor(client: client).translate(request(count: 3))
            XCTFail("A network failure must remain explicit")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let batches = await client.batches
        XCTAssertEqual(batches.count, 1)
    }

    func testIncompleteSuccessResponseStillFailsStrictIDValidation() async {
        do {
            _ = try await TranslationBatchProcessor(client: RecoveryClient(mode: .incomplete)).translate(request(count: 3))
            XCTFail("Recovery must not weaken successful response validation")
        } catch TranslationClientError.invalidResponse {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLegacyResultWithoutFailureKeyRemainsDecodable() throws {
        let old = TranslationResult(
            imageHash: "fixture", detectedSourceLanguage: "en", targetLanguage: "fr",
            segments: [], glossaryUpdates: [], durationMilliseconds: 10
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "failures")
        let result = try JSONDecoder().decode(TranslationResult.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.imageHash, old.imageHash)
    }
}

private actor RecoveryClient: TranslationClientProtocol {
    enum Mode {
        case success, rejectOne, unknownID, repeatRemovedID, rejectEveryFirst, networkError, incomplete
    }
    let mode: Mode
    private(set) var batches: [[String]] = []

    init(mode: Mode) { self.mode = mode }

    func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        batches.append(request.segments.map(\.id))
        switch mode {
        case .rejectOne where request.segments.contains(where: { $0.id == "segment-0" }):
            throw TranslationClientError.dialogueRejected(segmentID: "segment-0", message: "Controlled fixture refusal")
        case .unknownID:
            throw TranslationClientError.dialogueRejected(segmentID: "unknown", message: "Controlled fixture refusal")
        case .repeatRemovedID:
            throw TranslationClientError.dialogueRejected(segmentID: "segment-0", message: "Controlled fixture refusal")
        case .rejectEveryFirst:
            throw TranslationClientError.dialogueRejected(segmentID: request.segments[0].id, message: "Controlled fixture refusal")
        case .networkError:
            throw URLError(.notConnectedToInternet)
        default: break
        }
        let segments = mode == .incomplete ? Array(request.segments.dropLast()) : request.segments
        return TranslationResponse(
            detectedSourceLanguage: "en", segments: segments.map {
                TranslatedSegmentPayload(
                    id: $0.id, sourceText: $0.text, translatedText: "Traduction de fixture synthetique",
                    boundingBox: $0.boundingBox, confidence: 0.9, readingOrder: $0.readingOrder
                )
            }, glossaryUpdates: [], confidence: 0.9
        )
    }
}
