import CoreGraphics
import UIKit
import OSLog
import WebtoonLensCore

@MainActor
final class BrowserAnchoredCache {
    private static let logger = Logger(subsystem: "com.example.webtoonlens.v2", category: "AnchoredPixels")
    struct Entry {
        let documentID: String
        let anchorID: String
        let signature: String
        let imageRect: NormalizedRect
        let payload: TranslatedSegmentPayload
        let reference: CGImage
        var verified = true
    }

    private(set) var entries: [Entry] = []
    private(set) var diagnostic = ""
    var count: Int { entries.count }

    func clear() { entries.removeAll() }

    func store(_ segment: TranslatedSegmentPayload, document: BrowserDocumentState, image: CGImage) throws {
        guard let anchor = document.readingAnchor, let capture = document.captureRegion else { return }
        let pixelRect = try BrowserPixelCrop.rect(for: segment.boundingBox, width: image.width, height: image.height)
        let actualRegion = BrowserPixelCrop.normalized(pixelRect, width: image.width, height: image.height)
        let logical = try BrowserImageCoordinates.imageRect(captured: actualRegion, captureRegion: capture, anchor: anchor)
        guard let raw = image.cropping(to: pixelRect) else { throw BrowserCaptureError.unreadableSnapshot }
        let reference = try ReadingPixelFingerprint.independentCopy(of: raw)
        var payload = segment
        payload.id = anchor.scopedSegmentID(segment.id, documentID: document.documentID)
        entries.removeAll { $0.documentID == document.documentID && $0.anchorID == anchor.id &&
            ($0.payload.id == payload.id || ($0.payload.sourceText == segment.sourceText &&
                abs($0.imageRect.midY - logical.midY) < 0.005)) }
        entries.append(Entry(documentID: document.documentID, anchorID: anchor.id, signature: anchor.signature,
                             imageRect: logical, payload: payload, reference: reference))
        diagnostic = "Stored \(entries.count) anchored regions."
        if entries.count > 40 { entries.removeFirst(entries.count - 40) }
        while referenceBytes > 16_000_000 { entries.removeFirst() }
    }

    func coverage(_ document: BrowserDocumentState) -> [TranslationSourceSegment] {
        guard let anchor = document.readingAnchor, let capture = document.captureRegion else { return [] }
        return entries.compactMap { entry in
            guard entry.verified, entry.documentID == document.documentID, entry.anchorID == anchor.id,
                  entry.signature == anchor.signature,
                  let box = BrowserImageCoordinates.captureRect(image: entry.imageRect, captureRegion: capture, anchor: anchor) else { return nil }
            return TranslationSourceSegment(id: entry.payload.id, text: entry.payload.sourceText, boundingBox: box,
                confidence: entry.payload.confidence, readingOrder: entry.payload.readingOrder)
        }
    }

    func validate(_ document: BrowserDocumentState, viewportImage: CGImage) throws -> [Entry] {
        let anchors = Dictionary((document.trackedAnchors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var invalid = Set<String>()
        for entry in entries {
            guard entry.documentID == document.documentID,
                  let anchor = anchors[entry.anchorID], anchor.signature == entry.signature else {
                invalid.insert(entry.payload.id)
                continue
            }
            let rect = BrowserImageCoordinates.viewportRect(image: entry.imageRect, anchor: anchor)
            let visible = Self.intersection(rect, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
            guard let visible else { continue }
            let x = max(0, min(1, (visible.x - rect.x) / rect.width))
            let y = max(0, min(1, (visible.y - rect.y) / rect.height))
            let relative = NormalizedRect(x: x, y: y, width: min(1 - x, visible.width / rect.width),
                                          height: min(1 - y, visible.height / rect.height))
            let expected = try Self.crop(entry.reference, region: relative)
            let actual = try Self.crop(viewportImage, region: visible)
            if try Self.normalizedPixels(expected) != Self.normalizedPixels(actual) {
                Self.logger.notice("ROI verification differs: reference \(expected.width)x\(expected.height), current \(actual.width)x\(actual.height).")
                diagnostic = "Pixel comparison removed ROI; reference \(expected.width)x\(expected.height), current \(actual.width)x\(actual.height); visible \(visible.height / rect.height)."
                invalid.insert(entry.payload.id)
            }
        }
        let removed = entries.filter { invalid.contains($0.payload.id) }
        entries.removeAll { invalid.contains($0.payload.id) }
        return removed
    }

    func placements(_ document: BrowserDocumentState, size: CGSize) -> [(TranslatedSegmentPayload, CGRect)] {
        let anchors = Dictionary((document.trackedAnchors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            guard entry.verified, entry.documentID == document.documentID,
                  let anchor = anchors[entry.anchorID], anchor.signature == entry.signature else { return nil }
            let box = BrowserImageCoordinates.viewportRect(image: entry.imageRect, anchor: anchor)
            let frame = CGRect(x: box.x * size.width, y: box.y * size.height, width: box.width * size.width, height: box.height * size.height)
            guard frame.intersects(CGRect(origin: .zero, size: size)) else { return nil }
            return (entry.payload, frame)
        }
    }

    var segments: [TranslatedSegmentPayload] { entries.map(\.payload) }
    private var referenceBytes: Int { entries.reduce(0) { $0 + $1.reference.bytesPerRow * $1.reference.height } }

    func diagnosticProof(_ document: BrowserDocumentState) throws -> String {
        let anchors = Dictionary((document.trackedAnchors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let zones = entries.map { entry in
            let anchor = anchors[entry.anchorID]
            let rect = anchor.map { BrowserImageCoordinates.viewportRect(image: entry.imageRect, anchor: $0) }
            return ZoneProof(id: entry.payload.id, anchorID: entry.anchorID, imageRect: entry.imageRect,
                viewportRect: rect, visible: rect.flatMap {
                    Self.intersection($0, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
                } != nil, sourceVerified: anchor?.signature == entry.signature)
        }
        let proof = CacheProof(documentID: document.documentID, scrollY: document.scrollY, count: entries.count,
            referenceBytes: referenceBytes, entries: zones, diagnostic: diagnostic)
        return String(decoding: try JSONEncoder().encode(proof), as: UTF8.self)
    }

    private struct CacheProof: Encodable {
        let documentID: String
        let scrollY: Double
        let count: Int
        let referenceBytes: Int
        let entries: [ZoneProof]
        let diagnostic: String
    }

    private struct ZoneProof: Encodable {
        let id: String
        let anchorID: String
        let imageRect: NormalizedRect
        let viewportRect: NormalizedRect?
        let visible: Bool
        let sourceVerified: Bool
    }

    private static func intersection(_ a: NormalizedRect, _ b: NormalizedRect) -> NormalizedRect? {
        let x = max(a.minX, b.minX), y = max(a.minY, b.minY)
        let width = min(a.maxX, b.maxX) - x, height = min(a.maxY, b.maxY) - y
        return width > 0 && height > 0 ? NormalizedRect(x: x, y: y, width: width, height: height) : nil
    }

    private static func crop(_ image: CGImage, region: NormalizedRect) throws -> CGImage {
        let rect = try BrowserPixelCrop.rect(for: region, width: image.width, height: image.height)
        guard let crop = image.cropping(to: rect) else { throw BrowserCaptureError.unreadableSnapshot }
        return crop
    }

    private static func normalizedPixels(_ image: CGImage) throws -> Data {
        let width = 128, height = max(16, min(256, Int(Double(image.height) / Double(image.width) * 128)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else { throw BrowserCaptureError.unreadableSnapshot }
        return Data(pixels)
    }

}
