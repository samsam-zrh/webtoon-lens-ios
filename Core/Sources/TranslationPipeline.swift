import Foundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UIKit)
import UIKit
import Vision
#endif

public enum OCRMode: Sendable {
    case fast
    case accurate
}

#if canImport(UIKit)
public protocol OCRRecognizing {
    func recognizeText(in image: UIImage, mode: OCRMode) async throws -> [OCRSegment]
}

public final class VisionOCRService: OCRRecognizing {
    public init() {}

    public func recognizeText(in image: UIImage, mode: OCRMode) async throws -> [OCRSegment] {
        try Task.checkCancellation()
        guard let cgImage = image.cgImage else {
            throw TranslationPipelineError.invalidImage
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let segments: [OCRSegment] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = mode == .fast ? .fast : .accurate
                    request.recognitionLanguages = WebtoonLensConstants.supportedRecognitionLanguages
                    request.usesLanguageCorrection = true
                    request.minimumTextHeight = 0.008
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                    try handler.perform([request])

                    let segments = (request.results ?? []).compactMap { observation -> OCRSegment? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        let box = observation.boundingBox
                        let normalized = NormalizedRect(
                            x: box.minX,
                            y: 1 - box.maxY,
                            width: box.width,
                            height: box.height
                        )
                        return OCRSegment(
                            sourceText: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                            boundingBox: normalized,
                            confidence: Double(candidate.confidence)
                        )
                    }
                    .filter { !$0.sourceText.isEmpty }
                    continuation.resume(returning: WebtoonReadingOrder.sort(segments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()
        return segments
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
#endif

public enum TranslationPipelineError: Error, LocalizedError {
    case invalidImage
    case noTextRecognized

    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "L'image ne peut pas etre analysee."
        case .noTextRecognized:
            return "Aucun texte lisible n'a ete detecte."
        }
    }
}

public actor TranslationCache {
    public static let shared = TranslationCache()

    private var memory: [TranslationCacheKey: TranslationResult] = [:]

    public init() {}

    public func value(for key: TranslationCacheKey) -> TranslationResult? {
        memory[key]
    }

    public func store(_ result: TranslationResult, for key: TranslationCacheKey) {
        memory[key] = result
    }
}

#if canImport(UIKit)
import OSLog
public actor WebtoonTranslationPipeline {
    private static let logger = Logger(subsystem: "com.example.webtoonlens.v2", category: "PrivateTextPipeline")
    private let ocr: OCRRecognizing
    private let client: TranslationClientProtocol
    private let cache: TranslationCache

    public init(
        ocr: OCRRecognizing = VisionOCRService(),
        client: TranslationClientProtocol,
        cache: TranslationCache = .shared
    ) {
        self.ocr = ocr
        self.client = client
        self.cache = cache
    }

    public func translate(
        image: UIImage,
        imageData: Data?,
        seriesID: String?,
        sourceLanguage: String = WebtoonLensConstants.autoSourceLanguage,
        targetLanguage: String = WebtoonLensConstants.defaultTargetLanguage,
        glossary: [GlossaryTermInstruction],
        style: String,
        alreadyTranslated: [TranslationSourceSegment] = []
    ) async throws -> TranslationResult {
        try Task.checkCancellation()
        let startedAt = Date()
        guard let data = imageData ?? image.pngData(), !data.isEmpty else {
            throw TranslationPipelineError.invalidImage
        }
        let imageHash = ImageHasher.sha256Hex(data)
        let glossaryChecksum = GlossaryResolver.checksum(for: glossary)
        let cacheKey = TranslationCacheKey(
            imageHash: imageHash, targetLanguage: targetLanguage, glossaryChecksum: glossaryChecksum,
            sourceLanguage: sourceLanguage, seriesID: seriesID,
            styleChecksum: ImageHasher.sha256Hex(Data(style.utf8)) + (alreadyTranslated.isEmpty ? "" : ":" +
                ImageHasher.sha256Hex(try JSONEncoder().encode(alreadyTranslated))), clientNamespace: client.cacheNamespace
        )

        if let cached = await cache.value(for: cacheKey) {
            try Task.checkCancellation()
            return cached
        }

        Self.logger.notice("Vision OCR started.")
        let ocrSegments = try await ocr.recognizeText(in: image, mode: .accurate)
        Self.logger.notice("Vision OCR completed: \(ocrSegments.count) regions.")
        try Task.checkCancellation()
        guard !ocrSegments.isEmpty else {
            throw TranslationPipelineError.noTextRecognized
        }

        let bubbles = BubbleGrouper.makeBubbles(from: ocrSegments)
        let sourceSegments = bubbles.map { bubble in
            TranslationSourceSegment(
                id: bubble.id.uuidString,
                text: bubble.sourceText,
                boundingBox: bubble.frame,
                confidence: bubble.segments.map(\.confidence).reduce(0, +) / Double(max(1, bubble.segments.count)),
                readingOrder: bubble.readingOrder
            )
        }.filter { source in !alreadyTranslated.contains { OCRCoverage.matches(source, existing: $0) } }

        if sourceSegments.isEmpty {
            return TranslationResult(imageHash: imageHash, detectedSourceLanguage: nil, targetLanguage: targetLanguage,
                segments: [], glossaryUpdates: [], durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000))
        }

        let request = TranslationRequest(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            seriesID: seriesID,
            style: style,
            segments: sourceSegments,
            glossary: glossary
        )
        Self.logger.notice("Text translation requested: \(sourceSegments.count) dialogues.")
        let response = try await TranslationBatchProcessor(client: client).translate(request)
        Self.logger.notice("Text translation completed: \(response.segments.count) accepted, \(response.failures.count) refused.")
        try Task.checkCancellation()

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        let result = TranslationResult(
            imageHash: imageHash,
            detectedSourceLanguage: response.detectedSourceLanguage,
            targetLanguage: targetLanguage,
            segments: response.segments.sorted { $0.readingOrder < $1.readingOrder },
            glossaryUpdates: response.glossaryUpdates,
            durationMilliseconds: duration,
            failures: response.failures
        )

        if result.failures.isEmpty { await cache.store(result, for: cacheKey) }
        try Task.checkCancellation()
        return result
    }
}
#endif
