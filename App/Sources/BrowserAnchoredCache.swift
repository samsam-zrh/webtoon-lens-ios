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
        var surface: LocalBubbleSurface?
        let phaseX: Double?
        let phaseY: Double?
        var phaseProof: PhaseProof?
        var geometryRevision: Int?
        var verified = true
    }

    struct PhaseProof {
        let imageRect: NormalizedRect
        let reference: CGImage
        let phaseX: Double?
        let phaseY: Double?
        let geometryRevision: Int?
    }

    struct PendingSourceCheck {
        let id: String
        let source: TranslationSourceSegment
        let patch: CGImage
        let imageRect: NormalizedRect
        let relative: NormalizedRect
        let anchor: BrowserImageAnchor
        let clipped: Bool
        let geometryRevision: Int?
    }

    struct Validation {
        var removed: [Entry] = []
        var pending: [PendingSourceCheck] = []
    }

    private(set) var entries: [Entry] = []
    private(set) var diagnostic = ""
    private(set) var lastRemoval = ""
    var count: Int { entries.count }

    func clear() { entries.removeAll() }

    func store(_ segment: TranslatedSegmentPayload, document: BrowserDocumentState, image: CGImage) throws {
        guard let anchor = document.readingAnchor, let capture = document.captureRegion else { return }
        let pixelRect = try BrowserPixelCrop.rect(for: segment.boundingBox, width: image.width, height: image.height)
            .insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let actualRegion = BrowserPixelCrop.normalized(pixelRect, width: image.width, height: image.height)
        let logical = try BrowserImageCoordinates.imageRect(captured: actualRegion, captureRegion: capture, anchor: anchor)
        guard let raw = image.cropping(to: pixelRect) else { throw BrowserCaptureError.unreadableSnapshot }
        let reference = try ReadingPixelFingerprint.independentCopy(of: raw)
        let surface = try LocalBubbleSurface.detect(in: reference, sourceText: segment.sourceText)
        var payload = segment
        payload.id = anchor.scopedSegmentID(segment.id, documentID: document.documentID)
        let duplicates = entries.filter { $0.documentID == document.documentID && $0.anchorID == anchor.id &&
            ($0.payload.id == payload.id || ($0.payload.sourceText == segment.sourceText &&
                abs($0.imageRect.midY - logical.midY) < 0.005)) }
        if !duplicates.isEmpty { lastRemoval = "Fresh OCR replaced \(duplicates.count) same-text spatial entries." }
        let duplicateIDs = Set(duplicates.map(\.payload.id))
        entries.removeAll { duplicateIDs.contains($0.payload.id) }
        entries.append(Entry(documentID: document.documentID, anchorID: anchor.id, signature: anchor.signature,
                             imageRect: logical, payload: payload, reference: reference, surface: surface,
                             phaseX: anchor.rasterPhaseX, phaseY: anchor.rasterPhaseY, geometryRevision: document.geometryRevision))
        diagnostic = "Stored \(entries.count) anchored regions."
        if entries.count > 40 { entries.removeFirst(entries.count - 40) }
        while referenceBytes > 16_000_000 { entries.removeFirst() }
    }

    func coverage(_ document: BrowserDocumentState) -> [TranslationSourceSegment] {
        guard let anchor = document.readingAnchor, let capture = document.captureRegion else { return [] }
        return entries.compactMap { entry in
            guard entry.documentID == document.documentID, entry.anchorID == anchor.id,
                  entry.signature == anchor.signature,
                  let box = BrowserImageCoordinates.captureRect(image: entry.imageRect, captureRegion: capture, anchor: anchor) else { return nil }
            return TranslationSourceSegment(id: entry.payload.id, text: entry.payload.sourceText, boundingBox: box,
                confidence: entry.payload.confidence, readingOrder: entry.payload.readingOrder)
        }
    }

    func synchronizeSources(_ document: BrowserDocumentState) -> [Entry] {
        let states = Dictionary((document.sourceStates ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = entries.filter { entry in
            if entry.documentID != document.documentID { return true }
            guard let state = states[entry.anchorID] else { return false }
            return !state.connected || state.signature != entry.signature
        }
        let ids = Set(removed.map(\.payload.id))
        if !removed.isEmpty { lastRemoval = "Source document, connection or version changed for \(removed.count) entries." }
        entries.removeAll { ids.contains($0.payload.id) }
        return removed
    }

    func suspend(anchorID: String) {
        for index in entries.indices where entries[index].anchorID == anchorID { entries[index].verified = false }
        diagnostic = "Source clip too small for native verification; finished regions retained."
    }

    func visibleAnchors(in document: BrowserDocumentState) -> [BrowserImageAnchor] {
        let anchors = Dictionary((document.trackedAnchors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(entries.map(\.anchorID)).compactMap { anchors[$0] }.filter { document.focusing(on: $0) != nil }
    }

    func validate(_ document: BrowserDocumentState, image: CGImage, captureRegion: NormalizedRect) throws -> Validation {
        guard let anchor = document.readingAnchor else { throw BrowserCaptureError.invalidViewport }
        let capturedSource = try BrowserImageCoordinates.imageRect(
            captured: NormalizedRect(x: 0, y: 0, width: 1, height: 1), captureRegion: captureRegion, anchor: anchor)
        var invalid = Set<String>()
        var pending: [PendingSourceCheck] = []
        for index in entries.indices {
            let entry = entries[index]
            guard entry.documentID == document.documentID, entry.anchorID == anchor.id,
                  entry.signature == anchor.signature,
                  let visible = Self.intersection(entry.imageRect, capturedSource),
                  let currentRegion = BrowserImageCoordinates.captureRect(image: entry.imageRect, captureRegion: captureRegion, anchor: anchor) else { continue }
            let rect = entry.imageRect
            let x = max(0, min(1, (visible.x - rect.x) / rect.width))
            let y = max(0, min(1, (visible.y - rect.y) / rect.height))
            let relative = NormalizedRect(x: x, y: y, width: min(1 - x, visible.width / rect.width),
                                          height: min(1 - y, visible.height / rect.height))
            let expected = try Self.crop(entry.reference, region: relative)
            let actual = try Self.crop(image, region: currentRegion)
            let clipped = visible.height < rect.height - 0.0000001 || visible.width < rect.width - 0.0000001
            if let proof = entry.phaseProof,
               proof.geometryRevision == document.geometryRevision,
               Self.samePhase(proof.phaseX, anchor.rasterPhaseX), Self.samePhase(proof.phaseY, anchor.rasterPhaseY),
               proof.imageRect.minX <= visible.minX + 0.00000001, proof.imageRect.minY <= visible.minY + 0.00000001,
               proof.imageRect.maxX >= visible.maxX - 0.00000001, proof.imageRect.maxY >= visible.maxY - 0.00000001 {
                let local = NormalizedRect(x: (visible.x - proof.imageRect.x) / proof.imageRect.width,
                    y: (visible.y - proof.imageRect.y) / proof.imageRect.height,
                    width: visible.width / proof.imageRect.width, height: visible.height / proof.imageRect.height)
                switch try BrowserROIVerification.compare(reference: Self.crop(proof.reference, region: local), current: actual, isClipped: clipped) {
                case .verified:
                    entries[index].verified = true
                    entries[index].geometryRevision = document.geometryRevision
                    continue
                case .insufficient:
                    entries[index].verified = false
                    continue
                case .changed:
                    invalid.insert(entry.payload.id)
                    continue
                }
            }
            switch try BrowserROIVerification.compare(reference: expected, current: actual, isClipped: clipped) {
            case .verified:
                entries[index].verified = true
                entries[index].geometryRevision = document.geometryRevision
            case .insufficient:
                entries[index].verified = false
                diagnostic = "Clipped ROI temporarily hidden; source reference retained."
            case .changed:
                if anchor.signature.hasPrefix("IMG:"), entry.surface != nil,
                   entry.geometryRevision != document.geometryRevision {
                    entries[index].verified = false
                    pending.append(PendingSourceCheck(id: entry.payload.id,
                        source: TranslationSourceSegment(id: entry.payload.id, text: entry.payload.sourceText,
                            boundingBox: currentRegion, confidence: entry.payload.confidence, readingOrder: entry.payload.readingOrder),
                        patch: actual, imageRect: visible, relative: relative, anchor: anchor, clipped: clipped,
                        geometryRevision: document.geometryRevision))
                    continue
                }
                Self.logger.notice("ROI verification differs: reference \(expected.width)x\(expected.height), current \(actual.width)x\(actual.height).")
                diagnostic = "Native pixels changed at stable phase; reference \(expected.width)x\(expected.height), current \(actual.width)x\(actual.height); visible \(visible.height / rect.height); phase \(entry.phaseY ?? -1) -> \(anchor.rasterPhaseY ?? -1)."
                invalid.insert(entry.payload.id)
            }
        }
        let removed = entries.filter { invalid.contains($0.payload.id) }
        if !removed.isEmpty { lastRemoval = diagnostic }
        entries.removeAll { invalid.contains($0.payload.id) }
        return Validation(removed: removed, pending: pending)
    }

    func remove(id: String) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.payload.id == id }) else { return nil }
        lastRemoval = diagnostic
        Self.logger.notice("Cached region retired: \(self.lastRemoval, privacy: .public)")
        return entries.remove(at: index)
    }

    func finishLocalVerification(_ check: PendingSourceCheck, observations: [OCRSegment], stablePatch: CGImage) throws -> Entry? {
        guard let index = entries.firstIndex(where: { $0.payload.id == check.id }) else { return nil }
        guard try ReadingPixelFingerprint.value(for: check.patch) == ReadingPixelFingerprint.value(for: stablePatch) else {
            diagnostic = "Fractional phase rejected: pixels changed during local verification."
            return remove(id: check.id)
        }
        guard BrowserSourceTextVerification.matches(source: check.source, observations: observations, isClipped: check.clipped) else {
            diagnostic = "Fractional phase rejected: exact source OCR mismatch (\(observations.count) observations; clipped \(check.clipped))."
            return remove(id: check.id)
        }
        var edges = Set<LocalBubbleSurface.ClippedEdge>()
        if check.relative.minX > 0.00000001 { edges.insert(.left) }
        if check.relative.minY > 0.00000001 { edges.insert(.top) }
        if check.relative.maxX < 0.99999999 { edges.insert(.right) }
        if check.relative.maxY < 0.99999999 { edges.insert(.bottom) }
        guard let old = entries[index].surface,
              let surface = try LocalBubbleSurface.detect(in: stablePatch, sourceText: check.source.text, clippedEdges: edges),
              surface.fill == old.fill, surface.ink == old.ink else {
            diagnostic = "Fractional phase rejected: bubble surface not identical or not replaceable."
            return remove(id: check.id)
        }
        entries[index].surface = try old.updating(check.relative, with: surface)
        entries[index].phaseProof = PhaseProof(imageRect: check.imageRect,
            reference: try ReadingPixelFingerprint.independentCopy(of: stablePatch),
            phaseX: check.anchor.rasterPhaseX, phaseY: check.anchor.rasterPhaseY, geometryRevision: check.geometryRevision)
        entries[index].verified = true
        entries[index].geometryRevision = check.geometryRevision
        diagnostic = "Image compositor after movement reverified locally: exact source OCR, surface and stable native pixels."
        while referenceBytes > 16_000_000 { entries.removeFirst() }
        return nil
    }

    private static func samePhase(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a - b) < 0.0000001
    }

    func placements(_ document: BrowserDocumentState, size: CGSize) -> [BrowserAnchoredPlacement] {
        let anchors = Dictionary((document.trackedAnchors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            guard entry.verified, let surface = entry.surface, entry.documentID == document.documentID,
                  let anchor = anchors[entry.anchorID], anchor.signature == entry.signature else { return nil }
            let box = BrowserImageCoordinates.viewportRect(image: entry.imageRect, anchor: anchor)
            let frame = CGRect(x: box.x * size.width, y: box.y * size.height, width: box.width * size.width, height: box.height * size.height)
            guard frame.intersects(CGRect(origin: .zero, size: size)) else { return nil }
            let clip = anchor.visibleBounds ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)
            let clipFrame = CGRect(x: clip.x * size.width, y: clip.y * size.height, width: clip.width * size.width, height: clip.height * size.height)
            guard frame.intersects(clipFrame) else { return nil }
            return BrowserAnchoredPlacement(segment: entry.payload, frame: frame, clipFrame: clipFrame, surface: surface)
        }
    }

    var segments: [TranslatedSegmentPayload] { entries.map(\.payload) }
    private var referenceBytes: Int {
        entries.reduce(0) { $0 + $1.reference.bytesPerRow * $1.reference.height +
            ($1.surface.map { $0.replacement.bytesPerRow * $0.replacement.height } ?? 0) +
            ($1.phaseProof.map { $0.reference.bytesPerRow * $0.reference.height } ?? 0) }
    }

    func diagnosticProof(_ document: BrowserDocumentState) throws -> String {
        let anchors = Dictionary((document.trackedAnchors ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let zones = entries.map { entry in
            let anchor = anchors[entry.anchorID]
            let rect = anchor.map { BrowserImageCoordinates.viewportRect(image: entry.imageRect, anchor: $0) }
            return ZoneProof(id: entry.payload.id, anchorID: entry.anchorID, imageRect: entry.imageRect,
                viewportRect: rect, visible: rect.flatMap {
                    Self.intersection($0, NormalizedRect(x: 0, y: 0, width: 1, height: 1))
                } != nil, sourceVerified: anchor?.signature == entry.signature,
                fill: entry.surface?.fill, ink: entry.surface?.ink, visuallyReplaceable: entry.surface != nil, samplesVerified: entry.verified)
        }
        let proof = CacheProof(documentID: document.documentID, scrollY: document.scrollY, count: entries.count,
            referenceBytes: referenceBytes, entries: zones, diagnostic: diagnostic, lastRemoval: lastRemoval)
        return String(decoding: try JSONEncoder().encode(proof), as: UTF8.self)
    }

    private struct CacheProof: Encodable {
        let documentID: String
        let scrollY: Double
        let count: Int
        let referenceBytes: Int
        let entries: [ZoneProof]
        let diagnostic: String
        let lastRemoval: String
    }

    private struct ZoneProof: Encodable {
        let id: String
        let anchorID: String
        let imageRect: NormalizedRect
        let viewportRect: NormalizedRect?
        let visible: Bool
        let sourceVerified: Bool
        let fill: BubbleRGB?
        let ink: BubbleRGB?
        let visuallyReplaceable: Bool
        let samplesVerified: Bool
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

}

struct BrowserAnchoredPlacement {
    let segment: TranslatedSegmentPayload
    let frame: CGRect
    let clipFrame: CGRect
    let surface: LocalBubbleSurface
}
