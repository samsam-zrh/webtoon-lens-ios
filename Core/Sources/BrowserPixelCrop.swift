import CoreGraphics
import Foundation

public enum BrowserPixelCrop {
    public static func rect(for region: NormalizedRect, width: Int, height: Int) throws -> CGRect {
        guard region.isInsideImage, width > 0, height > 0 else { throw BrowserCaptureError.invalidViewport }
        func snapped(_ value: Double) -> Double {
            abs(value - value.rounded()) < 0.0000001 ? value.rounded() : value
        }
        let left = floor(snapped(region.minX * Double(width)))
        let top = floor(snapped(region.minY * Double(height)))
        let right = ceil(snapped(region.maxX * Double(width)))
        let bottom = ceil(snapped(region.maxY * Double(height)))
        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isEmpty else { throw BrowserCaptureError.invalidViewport }
        return rect
    }

    public static func normalized(_ rect: CGRect, width: Int, height: Int) -> NormalizedRect {
        NormalizedRect(x: rect.minX / Double(width), y: rect.minY / Double(height),
                       width: rect.width / Double(width), height: rect.height / Double(height))
    }
}
