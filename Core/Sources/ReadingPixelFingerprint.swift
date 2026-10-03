import CoreGraphics
import Foundation

public enum ReadingPixelFingerprint {
    public static func value(for image: CGImage, region: NormalizedRect) throws -> String {
        guard region.isInsideImage else { throw BrowserCaptureError.invalidViewport }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: region.x * Double(image.width), y: region.y * Double(image.height),
                          width: region.width * Double(image.width), height: region.height * Double(image.height))
            .insetBy(dx: -2, dy: -2).integral.intersection(bounds)
        guard let crop = image.cropping(to: rect) else { throw BrowserCaptureError.unreadableSnapshot }
        return try value(for: crop)
    }

    public static func value(for image: CGImage) throws -> String {
        guard image.width > 0, image.height > 0, image.width * image.height <= 4_000_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw BrowserCaptureError.unreadableSnapshot
        }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw BrowserCaptureError.unreadableSnapshot }
        return "\(image.width)x\(image.height):\(ImageHasher.sha256Hex(Data(pixels)))"
    }
}
