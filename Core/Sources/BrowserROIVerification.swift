import CoreGraphics
import Foundation

public enum BrowserROIVerification {
    public enum Outcome: Equatable {
        case verified
        case insufficient
        case changed
    }

    public static func compare(reference: CGImage, current: CGImage, isClipped: Bool) throws -> Outcome {
        guard reference.width > 0, reference.height > 0, current.width > 0, current.height > 0 else {
            throw BrowserCaptureError.unreadableSnapshot
        }
        if isClipped && (min(reference.width, current.width) < 12 || min(reference.height, current.height) < 12) {
            return .insufficient
        }
        if reference.width == current.width, reference.height == current.height,
           try ReadingPixelFingerprint.value(for: reference) == ReadingPixelFingerprint.value(for: current) {
            return .verified
        }
        return .changed
    }
}
