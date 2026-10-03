import Foundation

public struct TranslationBatchOutcome: Sendable {
    public var detectedSourceLanguage: String?
    public var segments: [TranslatedSegmentPayload] = []
    public var failures: [SegmentTranslationFailure] = []
    public var glossaryUpdates: [GlossaryUpdate] = []
}

public struct TranslationBatchProcessor: Sendable {
    public static let maximumBatchSize = 32
    public static let maximumAttemptsPerBatch = 5
    private let client: TranslationClientProtocol

    public init(client: TranslationClientProtocol) {
        self.client = client
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationBatchOutcome {
        guard !request.segments.isEmpty, Set(request.segments.map(\.id)).count == request.segments.count,
              request.segments.allSatisfy({
                  $0.boundingBox.isInsideImage && $0.confidence.isFinite && (0...1).contains($0.confidence) &&
                      !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw TranslationClientError.invalidResponse
        }
        var outcome = TranslationBatchOutcome()
        for start in stride(from: 0, to: request.segments.count, by: Self.maximumBatchSize) {
            var pending = Array(request.segments[start..<min(start + Self.maximumBatchSize, request.segments.count)])
            var attempts = 0
            while !pending.isEmpty {
                try Task.checkCancellation()
                attempts += 1
                var batch = request
                batch.segments = pending
                do {
                    let response = try await client.translate(batch).validated(against: batch)
                    try Task.checkCancellation()
                    outcome.detectedSourceLanguage = outcome.detectedSourceLanguage ?? response.detectedSourceLanguage
                    outcome.segments.append(contentsOf: response.segments)
                    outcome.glossaryUpdates.append(contentsOf: response.glossaryUpdates)
                    pending.removeAll()
                } catch TranslationClientError.dialogueRejected(let id, let message) {
                    try Task.checkCancellation()
                    guard let index = pending.firstIndex(where: { $0.id == id }) else {
                        throw TranslationClientError.invalidResponse
                    }
                    let source = pending.remove(at: index)
                    outcome.failures.append(SegmentTranslationFailure(source: source, message: message, kind: .dialogueRejected))
                    if attempts == Self.maximumAttemptsPerBatch {
                        outcome.failures.append(contentsOf: pending.map {
                            SegmentTranslationFailure(
                                source: $0, message: "Traduction non terminee apres 5 tentatives pour ce lot. Original conserve ; reessaie plus tard.",
                                kind: .retryLimitReached
                            )
                        })
                        pending.removeAll()
                    }
                }
            }
        }
        let accountedIDs = outcome.segments.map(\.id) + outcome.failures.map(\.id)
        guard accountedIDs.count == request.segments.count, Set(accountedIDs) == Set(request.segments.map(\.id)) else {
            throw TranslationClientError.invalidResponse
        }
        outcome.segments.sort { $0.readingOrder < $1.readingOrder }
        outcome.failures.sort { $0.source.readingOrder < $1.source.readingOrder }
        outcome.glossaryUpdates = Dictionary(outcome.glossaryUpdates.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            .values.sorted { $0.id < $1.id }
        return outcome
    }
}
