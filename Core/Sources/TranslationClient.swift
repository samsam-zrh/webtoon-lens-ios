import Foundation

public struct TranslationRequest: Codable, Hashable, Sendable {
    public var sourceLanguage: String
    public var targetLanguage: String
    public var seriesID: String?
    public var style: String
    public var segments: [TranslationSourceSegment]
    public var glossary: [GlossaryTermInstruction]

    public init(
        sourceLanguage: String = WebtoonLensConstants.autoSourceLanguage,
        targetLanguage: String = WebtoonLensConstants.defaultTargetLanguage,
        seriesID: String?,
        style: String,
        segments: [TranslationSourceSegment],
        glossary: [GlossaryTermInstruction]
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.seriesID = seriesID
        self.style = style
        self.segments = segments
        self.glossary = glossary
    }
}

public struct TranslationResponse: Codable, Hashable, Sendable {
    public var detectedSourceLanguage: String?
    public var segments: [TranslatedSegmentPayload]
    public var glossaryUpdates: [GlossaryUpdate]
    public var confidence: Double

    public init(
        detectedSourceLanguage: String?,
        segments: [TranslatedSegmentPayload],
        glossaryUpdates: [GlossaryUpdate],
        confidence: Double
    ) {
        self.detectedSourceLanguage = detectedSourceLanguage
        self.segments = segments
        self.glossaryUpdates = glossaryUpdates
        self.confidence = confidence
    }
}

public enum TranslationClientError: Error, LocalizedError {
    case invalidResponse
    case serverError(Int)
    case missingBackend

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Le serveur de traduction a renvoye une reponse invalide."
        case .serverError(let statusCode):
            return "Le serveur de traduction a renvoye le statut \(statusCode)."
        case .missingBackend:
            return "Configure un backend de traduction dans les reglages. L'app ne genere plus de fausses traductions locales."
        }
    }
}

public protocol TranslationClientProtocol {
    func translate(_ request: TranslationRequest) async throws -> TranslationResponse
}

public final class WebtoonTranslationClient: TranslationClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        let endpoint = baseURL.appendingPathComponent("v1/webtoon/translate")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 12
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw TranslationClientError.serverError(httpResponse.statusCode)
        }

        return try decoder.decode(TranslationResponse.self, from: data)
    }
}

public final class LocalPreviewTranslationClient: TranslationClientProtocol {
    public init() {}

    public func translate(_: TranslationRequest) async throws -> TranslationResponse {
        throw TranslationClientError.missingBackend
    }
}
