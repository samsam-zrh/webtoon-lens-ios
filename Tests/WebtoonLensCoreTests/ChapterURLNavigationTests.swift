import XCTest
@testable import WebtoonLensCore

final class ChapterURLNavigationTests: XCTestCase {
    func testOnlyExplicitPathChapterTokenChanges() {
        let navigation = ChapterURLNavigation.derive("https://nanomachin.com/manga/nano-machine-chapter-332/")
        XCTAssertEqual(navigation.previous?.absoluteString, "https://nanomachin.com/manga/nano-machine-chapter-331/")
        XCTAssertEqual(navigation.next?.absoluteString, "https://nanomachin.com/manga/nano-machine-chapter-333/")
        let padded = ChapterURLNavigation.derive("https://example.test/series-45/chapter-003/page-2.jpg")
        XCTAssertEqual(padded.previous?.absoluteString, "https://example.test/series-45/chapter-002/page-2.jpg")
        XCTAssertEqual(padded.next?.absoluteString, "https://example.test/series-45/chapter-004/page-2.jpg")
        let separate = ChapterURLNavigation.derive("https://example.test/series12/chapter/009/?language=fr#page2")
        XCTAssertEqual(separate.next?.absoluteString, "https://example.test/series12/chapter/010/?language=fr#page2")
    }

    func testEpisodeQueryPreservesSeriesIDAndUnrelatedEncodedParameters() {
        let url = "https://www.webtoons.com/en/romance/series/episode-1/viewer?title_no=1320&episode_no=1"
        XCTAssertEqual(ChapterURLNavigation.derive(url).next?.absoluteString,
                       "https://www.webtoons.com/en/romance/series/episode-1/viewer?title_no=1320&episode_no=2")
        let query = ChapterURLNavigation.derive("https://www.webtoons.com/en/romance/series/viewer?title_no=1320&episode_no=003&note=a%2Fb#panel2")
        XCTAssertEqual(query.next?.absoluteString, "https://www.webtoons.com/en/romance/series/viewer?title_no=1320&episode_no=004&note=a%2Fb#panel2")
        for key in ["chapter", "chapitre", "episode", "episode_no"] {
            let result = ChapterURLNavigation.derive("https://example.test/viewer?id=45&\(key)=12")
            XCTAssertEqual(result.previous?.absoluteString, "https://example.test/viewer?id=45&\(key)=11")
        }
    }

    func testWebtoonCanonicalEpisodePathAndQueryAgreeWithoutChangingTitleID() {
        // These two explicit tokens represent the same episode on WEBTOON.
        let result = ChapterURLNavigation.derive("https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=1")
        XCTAssertEqual(result.next?.absoluteString,
                       "https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=2")
        let second = ChapterURLNavigation.derive(result.next!.absoluteString)
        XCTAssertEqual(second.next?.absoluteString,
                       "https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=3")
        XCTAssertEqual(second.previous?.absoluteString,
                       "https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=1")
        XCTAssertNil(ChapterURLNavigation.derive("https://www.webtoons.com/en/series/episode-2/viewer?title_no=1320&title_no=9&episode_no=1").next)
    }

    func testOpaqueIDsDecimalAndDuplicateParametersAreNotStepped() {
        for url in [
            "https://www.webnovel.com/fr/comic/series_33398540708901501/chapter-1_89660822980187997",
            "https://example.test/series/123456789", "https://example.test/chapter-1.5",
            "https://example.test/viewer?chapter=2&chapter=2", "https://example.test/viewer?chapter=2&episode=2",
            "https://example.test/chapter-2/episode-3/", "https://example.test/viewer?chapter=-1",
            "https://example.test/viewer?chapter=0", "https://example.test/viewer?chapter=1.5",
            "https://example.test/chapter-99999999999999999999999999999", "javascript:alert(1)"
        ] {
            let result = ChapterURLNavigation.derive(url)
            XCTAssertNil(result.previous, url)
            XCTAssertNil(result.next, url)
            XCTAssertNotNil(result.explanation, url)
        }
        XCTAssertNil(ChapterURLNavigation.derive("https://example.test/chapter-001/").previous)
        XCTAssertNil(ChapterURLNavigation.derive("https://example.test/chapter-\(Int.max)/").next)
    }

    func testSameFallbackURLDoesNotRequireExtractionReloadOrLossOfSession() throws {
        let requested = try BrowserAddress.parse("https://www.example.test/chapter")
        let resolved = try BrowserAddress.parse("https://m.example.test/chapter")
        let context = BrowserFallbackContext(requestedURL: requested, resolvedURL: resolved, configuration: "backend-and-terms")
        XCTAssertTrue(context.canCaptureCurrentPage(for: requested, configuration: "backend-and-terms", currentURL: resolved))
        XCTAssertTrue(context.canCaptureCurrentPage(for: resolved, configuration: "backend-and-terms", currentURL: resolved))
        XCTAssertFalse(context.canCaptureCurrentPage(for: requested, configuration: "changed-consent", currentURL: resolved))
        XCTAssertFalse(context.canCaptureCurrentPage(for: requested, configuration: "backend-and-terms", currentURL: URL(string: "https://m.example.test/next")))
    }
}
