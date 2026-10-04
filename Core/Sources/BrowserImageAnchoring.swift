import Foundation

public struct BrowserImageAnchor: Codable, Hashable, Sendable {
    public let id: String
    public let signature: String
    public let bounds: NormalizedRect
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let rasterWidth: Int?
    public let rasterHeight: Int?
    public let visibleBounds: NormalizedRect?
    public let rasterPhaseX: Double?
    public let rasterPhaseY: Double?

    public init(id: String, signature: String, bounds: NormalizedRect, pixelWidth: Int? = nil, pixelHeight: Int? = nil,
                rasterWidth: Int? = nil, rasterHeight: Int? = nil, visibleBounds: NormalizedRect? = nil,
                rasterPhaseX: Double? = nil, rasterPhaseY: Double? = nil) {
        self.id = id
        self.signature = signature
        self.bounds = bounds
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.rasterWidth = rasterWidth
        self.rasterHeight = rasterHeight
        self.visibleBounds = visibleBounds
        self.rasterPhaseX = rasterPhaseX
        self.rasterPhaseY = rasterPhaseY
    }

    public var isValid: Bool {
        !id.isEmpty && !signature.isEmpty &&
            [bounds.x, bounds.y, bounds.width, bounds.height].allSatisfy(\.isFinite) &&
            bounds.width > 0 && bounds.height > 0 &&
            (pixelWidth.map { $0 > 0 && $0 <= 100_000 } ?? true) &&
            (pixelHeight.map { $0 > 0 && $0 <= 1_000_000 } ?? true) &&
            (rasterWidth.map { $0 > 0 && $0 <= 100_000 } ?? true) &&
            (rasterHeight.map { $0 > 0 && $0 <= 1_000_000 } ?? true) &&
            (rasterPhaseX.map { $0.isFinite && $0 >= 0 && $0 < 1 } ?? true) &&
            (rasterPhaseY.map { $0.isFinite && $0 >= 0 && $0 < 1 } ?? true)
    }

    public func scopedSegmentID(_ sourceID: String, documentID: String) -> String {
        ImageHasher.sha256Hex(Data("\(documentID)\u{1F}\(id)".utf8)) + "." + sourceID
    }
}

public struct BrowserImageSourceState: Codable, Hashable, Sendable {
    public let id: String
    public let signature: String
    public let connected: Bool
}

public enum BrowserImageCoordinates {
    public static func imageRect(
        captured: NormalizedRect, captureRegion: NormalizedRect, anchor: BrowserImageAnchor
    ) throws -> NormalizedRect {
        guard captured.isInsideImage, captureRegion.isInsideImage, anchor.isValid else {
            throw BrowserCaptureError.invalidViewport
        }
        let box = NormalizedRect(
            x: (captureRegion.x + captured.x * captureRegion.width - anchor.bounds.x) / anchor.bounds.width,
            y: (captureRegion.y + captured.y * captureRegion.height - anchor.bounds.y) / anchor.bounds.height,
            width: captured.width * captureRegion.width / anchor.bounds.width,
            height: captured.height * captureRegion.height / anchor.bounds.height
        )
        guard box.isInsideImage else { throw BrowserCaptureError.invalidViewport }
        return box
    }

    public static func viewportRect(image: NormalizedRect, anchor: BrowserImageAnchor) -> NormalizedRect {
        NormalizedRect(
            x: anchor.bounds.x + image.x * anchor.bounds.width,
            y: anchor.bounds.y + image.y * anchor.bounds.height,
            width: image.width * anchor.bounds.width,
            height: image.height * anchor.bounds.height
        )
    }

    public static func captureRect(image: NormalizedRect, captureRegion: NormalizedRect, anchor: BrowserImageAnchor) -> NormalizedRect? {
        guard image.isInsideImage, captureRegion.isInsideImage, anchor.isValid else { return nil }
        let viewport = viewportRect(image: image, anchor: anchor)
        let box = NormalizedRect(
            x: (viewport.x - captureRegion.x) / captureRegion.width,
            y: (viewport.y - captureRegion.y) / captureRegion.height,
            width: viewport.width / captureRegion.width, height: viewport.height / captureRegion.height
        )
        let x = max(0, box.minX), y = max(0, box.minY)
        let right = min(1, box.maxX), bottom = min(1, box.maxY)
        guard right > x, bottom > y else { return nil }
        return NormalizedRect(x: x, y: y, width: right - x, height: bottom - y)
    }
}

public enum OCRCoverage {
    public static func matches(_ source: TranslationSourceSegment, existing: TranslationSourceSegment) -> Bool {
        let normalize: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let a = source.boundingBox
        let b = existing.boundingBox
        let overlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) *
            max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let sourceText = normalize(source.text), cachedText = normalize(existing.text)
        return sourceText.count >= 4 && (sourceText == cachedText || cachedText.contains(sourceText)) &&
            overlap / max(0.000001, min(a.area, b.area)) > 0.7
    }
}
