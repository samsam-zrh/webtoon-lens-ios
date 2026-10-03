import XCTest

@MainActor
final class ReadingLatencyTests: XCTestCase {
    func testFirstFittedBubbleWithExistingBackendCaches() async throws {
        guard ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_PUBLIC_CHAPTER"] == "1" else {
            throw XCTSkip("The latency check uses the explicit local real-public-chapter scheme.")
        }
        var measurements: [Double] = []
        for _ in 0..<3 {
            let app = XCUIApplication()
            app.launchEnvironment["WEBTOON_LENS_TEST_PREFERENCES"] = "WebtoonLensV2.UI-\(UUID())"
            app.launchArguments = [
                "-backendBaseURL", "http://127.0.0.1:8787",
                "-v2.consentedPublicChapterBackend", "http://127.0.0.1:8787",
                "-v2.consentedTextBackend", "http://127.0.0.1:8787",
                "-v2.lastPublicChapterURL", "https://nanomachin.com/manga/nano-machine-chapter-332/"
            ]
            app.launch()
            let action = app.buttons["v2.readChapter"].exists ? app.buttons["v2.readChapter"] : app.buttons["v2.translate"]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            let start = ContinuousClock().now
            action.tap()
            let metric = app.staticTexts["v2.chapterMasks"]
            let firstFit = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard metric.exists, let value = metric.value as? String,
                      let json = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
                      let rendered = json["rendered"] as? [[String: Any]] else { return false }
                return rendered.contains { ($0["page"] as? Int) == 0 && ($0["fontSize"] as? Double ?? 0) >= 10 }
            }, object: metric)
            let completed = await XCTWaiter.fulfillment(of: [firstFit], timeout: 60)
            XCTAssertEqual(completed, .completed)
            let elapsed = start.duration(to: ContinuousClock().now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            measurements.append(seconds)
            app.terminate()
        }
        let result: [String: Any] = [
            "metric": "tap to first real fitted French mask on NanoMachine332 page01",
            "seconds": measurements,
            "measuredWarmMedian": measurements.dropFirst().reduce(0, +) / 2,
            "conditions": "same existing V1 backend/model/caches untouched; first repetition excluded as warm-up; no cache-clearing",
            "fixture": false
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "First fitted dialogue latency, matched existing caches"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("READING_LATENCY \(String(decoding: data, as: UTF8.self))")
    }
}
