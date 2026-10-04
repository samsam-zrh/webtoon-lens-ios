import CoreGraphics
import Foundation

public struct BubbleRGB: Codable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public var luminance: Double {
        func linear(_ value: UInt8) -> Double {
            let x = Double(value) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func contrast(with other: BubbleRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

public struct LocalBubbleSurface {
    public enum ClippedEdge: Hashable { case top, bottom, left, right }
    public let replacement: CGImage
    public let fill: BubbleRGB
    public let ink: BubbleRGB
    public let foregroundFraction: Double
    public let sourceLineCount: Int

    public static func detect(in image: CGImage, sourceText: String, clippedEdges: Set<ClippedEdge> = []) throws -> LocalBubbleSurface? {
        let width = image.width, height = image.height
        guard width >= 12, height >= 12, width * height <= 4_000_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw BrowserCaptureError.unreadableSnapshot }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw BrowserCaptureError.unreadableSnapshot }
        var histogram = [Int](repeating: 0, count: 4096)
        func bin(_ offset: Int) -> Int {
            Int(rgba[offset] / 16) * 256 + Int(rgba[offset + 1] / 16) * 16 + Int(rgba[offset + 2] / 16)
        }
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            guard rgba[offset + 3] >= 250 else { return nil }
            histogram[bin(offset)] += 1
        }
        guard let dominant = histogram.indices.max(by: { histogram[$0] < histogram[$1] }),
              Double(histogram[dominant]) / Double(width * height) >= 0.55 else { return nil }
        var samples = [[UInt8](), [UInt8](), [UInt8]()]
        for offset in stride(from: 0, to: rgba.count, by: 4) where bin(offset) == dominant {
            for channel in 0..<3 { samples[channel].append(rgba[offset + channel]) }
        }
        let channels = samples.map { $0.sorted()[$0.count / 2] }
        let fill = BubbleRGB(red: channels[0], green: channels[1], blue: channels[2])
        let black = BubbleRGB(red: 17, green: 17, blue: 17), white = BubbleRGB(red: 255, green: 255, blue: 255)
        let ink = fill.contrast(with: black) >= 4.5 ? black : white
        guard fill.contrast(with: ink) >= 4.5 else { return nil }
        func difference(_ offset: Int) -> Int {
            (0..<3).map { abs(Int(rgba[offset + $0]) - Int(channels[$0])) }.max() ?? 255
        }
        var borderPixels = 0, cleanBorder = 0, compatible = 0, foreground = 0
        var mask = [UInt8](repeating: 0, count: rgba.count)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let clean = difference(offset) <= 24
                if (x < 2 && !clippedEdges.contains(.left)) || (y < 2 && !clippedEdges.contains(.top)) ||
                    (x >= width - 2 && !clippedEdges.contains(.right)) || (y >= height - 2 && !clippedEdges.contains(.bottom)) {
                    borderPixels += 1
                    if clean { cleanBorder += 1 }
                }
                if clean { compatible += 1; continue }
                var letter = false
                for target in [0.0, 255.0] {
                    let direction = channels.map { target - Double($0) }
                    let length = direction.reduce(0) { $0 + $1 * $1 }
                    guard length > 0 else { continue }
                    let difference = (0..<3).map { Double(rgba[offset + $0]) - Double(channels[$0]) }
                    let amount = zip(difference, direction).reduce(0) { $0 + $1.0 * $1.1 } / length
                    let residual = (0..<3).map { abs(difference[$0] - max(0, min(1, amount)) * direction[$0]) }.max() ?? 255
                    if amount >= 0.08, amount <= 1.05, residual <= 24 { letter = true }
                }
                if letter {
                    compatible += 1
                    foreground += 1
                    mask[offset] = channels[0]
                    mask[offset + 1] = channels[1]
                    mask[offset + 2] = channels[2]
                    mask[offset + 3] = 255
                }
            }
        }
        guard Double(cleanBorder) / Double(max(1, borderPixels)) >= 0.95,
              Double(compatible) / Double(width * height) >= 0.985,
              foreground >= 8, Double(foreground) / Double(width * height) <= 0.45 else { return nil }
        let letters = mask
        var vertical = [Int](repeating: 0, count: width)
        for row in 0..<2 {
            for x in 0..<width where letters[(row * width + x) * 4 + 3] != 0 { vertical[x] += 1 }
        }
        for y in 0..<height {
            if y + 2 < height {
                for x in 0..<width where letters[((y + 2) * width + x) * 4 + 3] != 0 { vertical[x] += 1 }
            }
            if y >= 3 {
                for x in 0..<width where letters[((y - 3) * width + x) * 4 + 3] != 0 { vertical[x] -= 1 }
            }
            guard y >= 2, y < height - 2 else { continue }
            var neighbours = vertical[0] + vertical[1]
            for x in 0..<width {
                if x + 2 < width { neighbours += vertical[x + 2] }
                if x >= 3 { neighbours -= vertical[x - 3] }
                let offset = (y * width + x) * 4
                guard x >= 2, x < width - 2, neighbours > 0, difference(offset) <= 24 else { continue }
                mask[offset] = channels[0]; mask[offset + 1] = channels[1]; mask[offset + 2] = channels[2]; mask[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(mask) as CFData),
              let replacement = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return LocalBubbleSurface(replacement: replacement, fill: fill, ink: ink,
            foregroundFraction: Double(foreground) / Double(width * height),
            sourceLineCount: max(1, sourceText.split(separator: "\n").count))
    }

    public func updating(_ region: NormalizedRect, with surface: LocalBubbleSurface) throws -> LocalBubbleSurface {
        let width = replacement.width, height = replacement.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw BrowserCaptureError.unreadableSnapshot }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BrowserCaptureError.unreadableSnapshot
        }
        context.setBlendMode(.copy)
        context.draw(replacement, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rect = try BrowserPixelCrop.rect(for: region, width: width, height: height)
        context.clear(rect)
        context.interpolationQuality = .none
        context.draw(surface.replacement, in: rect)
        guard let image = context.makeImage() else { throw BrowserCaptureError.unreadableSnapshot }
        return LocalBubbleSurface(replacement: image, fill: fill, ink: ink,
            foregroundFraction: foregroundFraction, sourceLineCount: sourceLineCount)
    }
}
