import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PublicImageCropper {
    public static func crop(publicImage data: Data, metadata: PublicImageMetadata, window: PublicOCRWindow) throws -> Data {
        guard window.cropTop >= 0, window.cropBottom <= metadata.height, window.cropBottom > window.cropTop,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: false] as CFDictionary),
              image.width == metadata.width, image.height == metadata.height,
              let crop = image.cropping(to: CGRect(x: 0, y: window.cropTop, width: metadata.width, height: window.cropBottom - window.cropTop)) else {
            throw PublicChapterError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw PublicChapterError.invalidImage
        }
        CGImageDestinationAddImage(destination, crop, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 20_000_000 else {
            throw PublicChapterError.imageLimit
        }
        return output as Data
    }
}
