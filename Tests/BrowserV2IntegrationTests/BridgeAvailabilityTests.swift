import XCTest
@testable import WebtoonLensCore

final class BridgeAvailabilityTests: XCTestCase {
    func testCaptureBridgeDoesNotExtractOrUploadImageURLs() {
        XCTAssertFalse(BrowserBridgeScript.source.contains("fetch("))
        XCTAssertFalse(BrowserBridgeScript.source.contains("XMLHttpRequest"))
        XCTAssertFalse(BrowserBridgeScript.source.contains("document.cookie"))
        XCTAssertFalse(BrowserBridgeScript.source.contains(".value"))
        XCTAssertFalse(BrowserBridgeScript.source.contains("innerHTML"))
        XCTAssertTrue(BrowserBridgeScript.mainFrameOnly)
    }
}
