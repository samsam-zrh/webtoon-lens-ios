import CoreGraphics
import Foundation

public enum WebtoonLensConstants {
    public static let appGroupIdentifier = "group.com.example.webtoonlens.v2"
    public static let displayName = "Webtoon Lens V2"
    public static let defaultTargetLanguage = "fr"
    public static let autoSourceLanguage = "auto"
    public static let supportedRecognitionLanguages = ["ja-JP", "ko-KR", "zh-Hans", "zh-Hant", "en-US"]
    public static let defaultStylePrompt = "Traduction naturelle en francais, adaptee aux webtoons. Conserve les noms propres et les noms de pouvoirs de facon stable."
}

public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { width * height }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public func union(_ other: NormalizedRect) -> NormalizedRect {
        let unionMinX = min(minX, other.minX)
        let unionMinY = min(minY, other.minY)
        let unionMaxX = max(maxX, other.maxX)
        let unionMaxY = max(maxY, other.maxY)
        return NormalizedRect(
            x: unionMinX,
            y: unionMinY,
            width: unionMaxX - unionMinX,
            height: unionMaxY - unionMinY
        )
    }
}

public struct OCRSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sourceText: String
    public var boundingBox: NormalizedRect
    public var confidence: Double
    public var readingOrder: Int

    public init(
        id: UUID = UUID(),
        sourceText: String,
        boundingBox: NormalizedRect,
        confidence: Double,
        readingOrder: Int = 0
    ) {
        self.id = id
        self.sourceText = sourceText
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.readingOrder = readingOrder
    }
}

public struct BubbleGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var frame: NormalizedRect
    public var segments: [OCRSegment]
    public var readingOrder: Int

    public init(id: UUID = UUID(), frame: NormalizedRect, segments: [OCRSegment], readingOrder: Int) {
        self.id = id
        self.frame = frame
        self.segments = segments
        self.readingOrder = readingOrder
    }

    public var sourceText: String {
        segments
            .sorted { $0.readingOrder < $1.readingOrder }
            .map(\.sourceText)
            .joined(separator: "\n")
    }
}

public enum TermCategory: String, Codable, CaseIterable, Sendable {
    case character
    case power
    case place
    case item
    case concept
    case unknown
}

public struct GlossaryTermInstruction: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var source: String
    public var translation: String
    public var category: TermCategory
    public var isLocked: Bool

    public init(id: String, source: String, translation: String, category: TermCategory, isLocked: Bool) {
        self.id = id
        self.source = source
        self.translation = translation
        self.category = category
        self.isLocked = isLocked
    }
}

public struct TranslationSourceSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var boundingBox: NormalizedRect
    public var confidence: Double
    public var readingOrder: Int

    public init(id: String, text: String, boundingBox: NormalizedRect, confidence: Double, readingOrder: Int) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.readingOrder = readingOrder
    }
}

public struct TranslatedSegmentPayload: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceText: String
    public var translatedText: String
    public var boundingBox: NormalizedRect
    public var confidence: Double
    public var readingOrder: Int

    public init(
        id: String,
        sourceText: String,
        translatedText: String,
        boundingBox: NormalizedRect,
        confidence: Double,
        readingOrder: Int
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.readingOrder = readingOrder
    }
}

public struct GlossaryUpdate: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var source: String
    public var suggestedTranslation: String
    public var category: TermCategory
    public var confidence: Double
    public var reason: String?

    public init(
        id: String,
        source: String,
        suggestedTranslation: String,
        category: TermCategory,
        confidence: Double,
        reason: String? = nil
    ) {
        self.id = id
        self.source = source
        self.suggestedTranslation = suggestedTranslation
        self.category = category
        self.confidence = confidence
        self.reason = reason
    }
}

public enum SegmentFailureKind: String, Codable, Hashable, Sendable {
    case dialogueRejected
    case retryLimitReached
    case sourceChanged
}

public struct SegmentTranslationFailure: Identifiable, Codable, Hashable, Sendable {
    public var source: TranslationSourceSegment
    public var message: String
    public var kind: SegmentFailureKind
    public var id: String { source.id }

    public init(source: TranslationSourceSegment, message: String, kind: SegmentFailureKind) {
        self.source = source
        self.message = message
        self.kind = kind
    }
}

public struct TranslationResult: Codable, Hashable, Sendable {
    public var imageHash: String
    public var detectedSourceLanguage: String?
    public var targetLanguage: String
    public var segments: [TranslatedSegmentPayload]
    public var glossaryUpdates: [GlossaryUpdate]
    public var createdAt: Date
    public var durationMilliseconds: Int
    public var failures: [SegmentTranslationFailure]

    public init(
        imageHash: String,
        detectedSourceLanguage: String?,
        targetLanguage: String,
        segments: [TranslatedSegmentPayload],
        glossaryUpdates: [GlossaryUpdate],
        createdAt: Date = Date(),
        durationMilliseconds: Int,
        failures: [SegmentTranslationFailure] = []
    ) {
        self.imageHash = imageHash
        self.detectedSourceLanguage = detectedSourceLanguage
        self.targetLanguage = targetLanguage
        self.segments = segments
        self.glossaryUpdates = glossaryUpdates
        self.createdAt = createdAt
        self.durationMilliseconds = durationMilliseconds
        self.failures = failures
    }

    private enum CodingKeys: String, CodingKey {
        case imageHash, detectedSourceLanguage, targetLanguage, segments, glossaryUpdates
        case createdAt, durationMilliseconds, failures
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        imageHash = try values.decode(String.self, forKey: .imageHash)
        detectedSourceLanguage = try values.decodeIfPresent(String.self, forKey: .detectedSourceLanguage)
        targetLanguage = try values.decode(String.self, forKey: .targetLanguage)
        segments = try values.decode([TranslatedSegmentPayload].self, forKey: .segments)
        glossaryUpdates = try values.decode([GlossaryUpdate].self, forKey: .glossaryUpdates)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        durationMilliseconds = try values.decode(Int.self, forKey: .durationMilliseconds)
        failures = try values.decodeIfPresent([SegmentTranslationFailure].self, forKey: .failures) ?? []
    }
}

public struct TranslationCacheKey: Codable, Hashable, Sendable {
    public var imageHash: String
    public var targetLanguage: String
    public var glossaryChecksum: String
    public var sourceLanguage: String
    public var seriesID: String?
    public var styleChecksum: String
    public var clientNamespace: String

    public init(
        imageHash: String, targetLanguage: String, glossaryChecksum: String,
        sourceLanguage: String = "auto", seriesID: String? = nil,
        styleChecksum: String = "", clientNamespace: String = ""
    ) {
        self.imageHash = imageHash
        self.targetLanguage = targetLanguage
        self.glossaryChecksum = glossaryChecksum
        self.sourceLanguage = sourceLanguage
        self.seriesID = seriesID
        self.styleChecksum = styleChecksum
        self.clientNamespace = clientNamespace
    }
}
