import Foundation

public protocol PublicChapterClientProtocol: Sendable {
    func extract(_ source: URL) async throws -> PublicChapterExtraction
    func image(_ url: URL, referer: URL) async throws -> Data
    func ocr(_ request: PublicOCRRequest) async throws -> [PublicOCRSegment]
}

public final class PublicChapterClient: PublicChapterClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let ownsSession: Bool

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        ownsSession = session == nil
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: configuration, delegate: NoBackendRedirects(), delegateQueue: nil)
        }
    }

    deinit { if ownsSession { session.invalidateAndCancel() } }

    public func extract(_ source: URL) async throws -> PublicChapterExtraction {
        _ = try PublicChapterURL.parse(source.absoluteString)
        let data = try await request(path: "v1/webtoon/extract", query: [URLQueryItem(name: "url", value: source.absoluteString)])
        let result = try JSONDecoder().decode(PublicChapterExtraction.self, from: data)
        _ = try PublicChapterURL.parse(result.pageURL)
        guard !result.images.isEmpty, result.images.count <= 80 else { throw PublicChapterError.noPages }
        var seen = Set<String>()
        let images = try result.images.filter { image in
            _ = try PublicChapterURL.parse(image.url)
            return seen.insert(image.url).inserted && !image.isObviousDecoration
        }
        guard !images.isEmpty else { throw PublicChapterError.noPages }
        return PublicChapterExtraction(pageURL: result.pageURL, images: images)
    }

    public func image(_ url: URL, referer: URL) async throws -> Data {
        _ = try PublicChapterURL.parse(url.absoluteString)
        _ = try PublicChapterURL.parse(referer.absoluteString)
        let data = try await request(path: "v1/webtoon/image", query: [
            URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "referer", value: referer.absoluteString)
        ])
        _ = try PublicImageMetadata(data: data)
        return data
    }

    public func ocr(_ request: PublicOCRRequest) async throws -> [PublicOCRSegment] {
        if let source = request.imageUrl { _ = try PublicChapterURL.parse(source) }
        guard (request.imageUrl != nil) != (request.imageData != nil) else { throw PublicChapterError.invalidImage }
        let data = try await self.request(path: "v1/webtoon/ocr", body: JSONEncoder().encode(request))
        let response = try JSONDecoder().decode(PublicOCRResponse.self, from: data)
        return try response.segments.map { try $0.validated() }
    }

    public func warmup() async throws {
        _ = try await request(path: "v1/webtoon/warmup")
    }

    private func request(path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        _ = try LocalBackendAddress.parse(baseURL.absoluteString)
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw TranslationClientError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw TranslationClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 90
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw TranslationClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(PublicBackendFailure.self, from: data)
            throw PublicChapterError.backend(response.statusCode, failure?.error ?? "Le backend local a refuse cette ressource publique.", failure?.code)
        }
        return data
    }
}

private struct PublicBackendFailure: Decodable {
    var error: String
    var code: String?
}
