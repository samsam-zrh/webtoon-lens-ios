import XCTest
@testable import WebtoonLensCore

final class PublicChapterClientTests: XCTestCase {
    func testExtract200PreservesPublicImageOrderAndFiltersDecoration() async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        ChapterProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/webtoon/extract")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let payload = """
            {"pageURL":"https://example.test/chapter","images":[
            {"url":"https://example.test/cropped-logo.png","alt":""},
            {"url":"https://example.test/pages/01.jpg","alt":""},{"url":"https://example.test/pages/02.jpg","alt":""}]}
            """
            return (200, Data(payload.utf8))
        }
        let response = try await PublicChapterClient(baseURL: URL(string: "http://127.0.0.1:8787")!, session: session)
            .extract(URL(string: "https://example.test/chapter")!)
        XCTAssertEqual(response.images.map { URL(string: $0.url)!.lastPathComponent }, ["01.jpg", "02.jpg"])
    }

    func test403IsExplicitAndDoesNotInventChapterSuccess() async {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        ChapterProtocol.handler = { _ in
            (502, Data(#"{"error":"Site requires normal browser interaction","code":"source_access_denied"}"#.utf8))
        }
        do {
            _ = try await PublicChapterClient(baseURL: URL(string: "http://127.0.0.1:8787")!, session: session)
                .extract(URL(string: "https://example.test/chapter")!)
            XCTFail("Denied extraction must never yield a reading result")
        } catch PublicChapterError.backend(let status, let message, let code) {
            XCTAssertEqual(status, 502)
            XCTAssertEqual(code, "source_access_denied")
            XCTAssertTrue(message.contains("interaction"))
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testEmptyExtractionCannotReplaceBrowserWithSuccess() async {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        ChapterProtocol.handler = { _ in (200, Data(#"{"pageURL":"https://example.test/chapter","images":[]}"#.utf8)) }
        do {
            _ = try await PublicChapterClient(baseURL: URL(string: "http://127.0.0.1:8787")!, session: session)
                .extract(URL(string: "https://example.test/chapter")!)
            XCTFail("An empty chapter must preserve the original mode")
        } catch PublicChapterError.noPages {
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testOCR200PreservesAlphaMasksTextBoxesAndStyles() async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="
        let mask = "data:image/png;base64,\(png)"
        ChapterProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/webtoon/ocr")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = """
            {"segments":[{"id":"original-fixture","sourceText":"Original synthetic dialogue",
            "boundingBox":{"x":0.1,"y":0.2,"width":0.3,"height":0.1},"rawBoundingBox":{"x":0.15,"y":0.23,"width":0.2,"height":0.04},
            "textBox":{"x":0.12,"y":0.21,"width":0.26,"height":0.08},"confidence":0.9,
            "maskData":"\(mask)","replacementData":"\(mask)","renderMode":"replace",
            "style":{"fillColor":"#e0f3ff","textColor":"#101010","fontFamily":"dialogue"},
            "imageWidth":690,"imageHeight":2900,"fontSizeSource":32}]}
            """
            return (200, Data(response.utf8))
        }
        let segments = try await PublicChapterClient(baseURL: URL(string: "http://127.0.0.1:8787")!, session: session)
            .ocr(PublicOCRRequest(imageURL: URL(string: "https://example.test/1.png")!,
                                 referer: URL(string: "https://example.test/chapter")!, language: "en"))
        XCTAssertEqual(segments[0].maskData, mask)
        XCTAssertEqual(segments[0].replacementData, mask)
        XCTAssertEqual(segments[0].textBox?.width, 0.26)
        XCTAssertEqual(segments[0].style?.fillColor, "#e0f3ff")
        XCTAssertEqual(segments[0].fontSizeSource, 32)
    }

    func testOneUnreadableSegmentDoesNotDiscardTheRestOfTheWindow() async throws {
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="
        let mask = "data:image/png;base64,\(png)"
        ChapterProtocol.handler = { _ in
            let response = """
            {"segments":[
            {"id":"broken","sourceText":"Broken fixture","boundingBox":{"x":0.1,"y":0.2,"width":4,"height":0.1},
             "confidence":0.9,"maskData":"\(mask)","renderMode":"replace","imageWidth":690,"imageHeight":2900},
            {"id":"kept","sourceText":"Kept synthetic dialogue","boundingBox":{"x":0.1,"y":0.5,"width":0.3,"height":0.05},
             "textBox":{"x":0.11,"y":0.51,"width":0.28,"height":0.03},"confidence":0.9,
             "maskData":"\(mask)","renderMode":"replace","imageWidth":690,"imageHeight":2900}]}
            """
            return (200, Data(response.utf8))
        }
        let segments = try await PublicChapterClient(baseURL: URL(string: "http://127.0.0.1:8787")!, session: session)
            .ocr(PublicOCRRequest(imageURL: URL(string: "https://example.test/1.png")!,
                                 referer: URL(string: "https://example.test/chapter")!, language: "en"))
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].id, "kept")
    }

    private func fixtureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChapterProtocol.self]
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }
}

private final class ChapterProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else { throw URLError(.badURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
