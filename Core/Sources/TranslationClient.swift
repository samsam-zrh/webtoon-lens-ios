import Foundation

public struct TranslationRequest: Codable, Hashable, Sendable {
    public var sourceLanguage: String
    public var targetLanguage: String
    public var seriesID: String?
    public var style: String
    public var segments: [TranslationSourceSegment]
    public var glossary: [GlossaryTermInstruction]
    public var contextSegments: [TranslationContextSegment]?
    public var previousTranslations: [PreviousDialogueTranslation]?

    public init(
        sourceLanguage: String = WebtoonLensConstants.autoSourceLanguage,
        targetLanguage: String = WebtoonLensConstants.defaultTargetLanguage,
        seriesID: String?,
        style: String,
        segments: [TranslationSourceSegment],
        glossary: [GlossaryTermInstruction],
        contextSegments: [TranslationContextSegment]? = nil,
        previousTranslations: [PreviousDialogueTranslation]? = nil
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.seriesID = seriesID
        self.style = style
        self.segments = segments
        self.glossary = glossary
        self.contextSegments = contextSegments
        self.previousTranslations = previousTranslations
    }
}

public struct TranslationContextSegment: Codable, Hashable, Sendable {
    public var id: String
    public var order: Int
    public var text: String

    public init(id: String, order: Int, text: String) {
        self.id = id
        self.order = order
        self.text = text
    }
}

public struct PreviousDialogueTranslation: Codable, Hashable, Sendable {
    public var source: String
    public var translation: String

    public init(source: String, translation: String) {
        self.source = source
        self.translation = translation
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
    case backendError(Int, String)
    case dialogueRejected(segmentID: String, message: String)
    case partialTranslation(Int)
    case missingBackend

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Le serveur de traduction a renvoye une reponse invalide."
        case .serverError(let statusCode):
            return "Le serveur de traduction a renvoye le statut \(statusCode)."
        case .backendError(let statusCode, let message):
            return "Backend local (\(statusCode)) : \(message)"
        case .dialogueRejected(_, let message):
            return message
        case .partialTranslation(let count):
            return "\(count) dialogues en erreur : original conserve. Le lecteur de l'app donne les details et les traductions partielles."
        case .missingBackend:
            return "Configure un backend de traduction dans les reglages. L'app ne genere plus de fausses traductions locales."
        }
    }
}

public protocol TranslationClientProtocol: Sendable {
    var cacheNamespace: String { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResponse
}

public extension TranslationClientProtocol {
    var cacheNamespace: String { String(reflecting: Self.self) }
}

public final class WebtoonTranslationClient: TranslationClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let ownsSession: Bool
    public var cacheNamespace: String { baseURL.absoluteString }

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
            self.ownsSession = false
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 180
            configuration.timeoutIntervalForResource = 240
            self.session = URLSession(configuration: configuration, delegate: NoBackendRedirects(), delegateQueue: nil)
            self.ownsSession = true
        }
    }

    deinit {
        if ownsSession { session.invalidateAndCancel() }
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResponse {
        try Task.checkCancellation()
        _ = try LocalBackendAddress.parse(baseURL.absoluteString)
        let endpoint = baseURL.appendingPathComponent("v1/webtoon/translate")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 180
        urlRequest.httpShouldHandleCookies = false
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationClientError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            if let error = try? JSONDecoder().decode(BackendFailure.self, from: data), !error.error.isEmpty {
                if error.code == "dialogue_translation_failed" {
                    guard let id = error.failedSegmentID, request.segments.contains(where: { $0.id == id }) else {
                        throw TranslationClientError.invalidResponse
                    }
                    throw TranslationClientError.dialogueRejected(segmentID: id, message: String(error.error.prefix(500)))
                }
                throw TranslationClientError.backendError(httpResponse.statusCode, String(error.error.prefix(500)))
            }
            throw TranslationClientError.serverError(httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(TranslationResponse.self, from: data)
        return try result.validated(against: request)
    }
}

private struct BackendFailure: Decodable {
    let error: String
    let code: String?
    let failedSegmentID: String?
}

final class NoBackendRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public extension TranslationResponse {
    func validated(against request: TranslationRequest) throws -> TranslationResponse {
        let sources = Dictionary(request.segments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !sources.isEmpty, sources.count == request.segments.count,
              segments.count == sources.count, Set(segments.map(\.id)).count == sources.count,
              confidence.isFinite, (0...1).contains(confidence) else {
            throw TranslationClientError.invalidResponse
        }
        var response = self
        response.segments = try segments.map { segment in
            guard let source = sources[segment.id], source.boundingBox.isInsideImage,
                  source.confidence.isFinite, (0...1).contains(source.confidence),
                  segment.boundingBox.isInsideImage, segment.confidence.isFinite,
                  (0...1).contains(segment.confidence),
                  !segment.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationClientError.invalidResponse
            }
            var copy = segment
            // Geometry and ordering belong to the captured source, never the model.
            copy.boundingBox = source.boundingBox
            copy.sourceText = source.text
            copy.readingOrder = source.readingOrder
            copy.confidence = min(source.confidence, segment.confidence)
            return copy
        }
        return response
    }
}

public final class LocalPreviewTranslationClient: TranslationClientProtocol {
    public init() {}

    public func translate(_: TranslationRequest) async throws -> TranslationResponse {
        throw TranslationClientError.missingBackend
    }
}
