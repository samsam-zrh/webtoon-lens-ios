import XCTest
@testable import WebtoonLensCore

final class PublicChapterActivityTests: XCTestCase {
    func testPauseHoldsNextPublicRequestAndResumeReleasesIt() async throws {
        let activity = PublicChapterActivity()
        await activity.setActive(false)
        let request = Task { try await activity.waitUntilActive() }
        try await waitForWaiter(activity)
        let waiting = await activity.waitingCount
        XCTAssertEqual(waiting, 1)
        await activity.setActive(true)
        try await request.value
        let resumed = await activity.waitingCount
        XCTAssertEqual(resumed, 0)
    }

    func testCancellingPausedWorkCannotLeakOrPublishARequest() async throws {
        let activity = PublicChapterActivity()
        await activity.setActive(false)
        let request = Task { try await activity.waitUntilActive() }
        try await waitForWaiter(activity)
        request.cancel()
        do {
            try await request.value
            XCTFail("Cancelled paused work must not resume as success")
        } catch is CancellationError {
        }
        let remaining = await activity.waitingCount
        XCTAssertEqual(remaining, 0)
        await activity.setActive(true)
        try await activity.waitUntilActive()
    }

    private func waitForWaiter(_ activity: PublicChapterActivity) async throws {
        for _ in 0..<20 {
            if await activity.waitingCount == 1 { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Public work did not enter its paused state")
    }
}
