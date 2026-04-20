import Foundation
import SwiftData

@Model
public final class SeriesProfile: Identifiable {
    public var id: String
    public var title: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var stylePrompt: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        sourceLanguage: String = WebtoonLensConstants.autoSourceLanguage,
        targetLanguage: String = WebtoonLensConstants.defaultTargetLanguage,
        stylePrompt: String = WebtoonLensConstants.defaultStylePrompt,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.stylePrompt = stylePrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class TermMemoryEntry: Identifiable {
    public var id: String
    public var seriesID: String
    public var source: String
    public var translation: String
    public var categoryRawValue: String
    public var isLocked: Bool
    public var confidence: Double
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        seriesID: String,
        source: String,
        translation: String,
        category: TermCategory = .unknown,
        isLocked: Bool = false,
        confidence: Double = 0,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.seriesID = seriesID
        self.source = source
        self.translation = translation
        self.categoryRawValue = category.rawValue
        self.isLocked = isLocked
        self.confidence = confidence
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var category: TermCategory {
        get { TermCategory(rawValue: categoryRawValue) ?? .unknown }
        set { categoryRawValue = newValue.rawValue }
    }

    public var instruction: GlossaryTermInstruction {
        GlossaryTermInstruction(id: id, source: source, translation: translation, category: category, isLocked: isLocked)
    }
}

@Model
public final class TranslationJob: Identifiable {
    public var id: String
    public var seriesID: String?
    public var imageHash: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var status: String
    public var createdAt: Date
    public var durationMilliseconds: Int

    public init(
        id: String = UUID().uuidString,
        seriesID: String?,
        imageHash: String,
        sourceLanguage: String,
        targetLanguage: String,
        status: String,
        createdAt: Date = Date(),
        durationMilliseconds: Int
    ) {
        self.id = id
        self.seriesID = seriesID
        self.imageHash = imageHash
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.status = status
        self.createdAt = createdAt
        self.durationMilliseconds = durationMilliseconds
    }
}

@Model
public final class TranslatedSegment: Identifiable {
    public var id: String
    public var jobID: String
    public var sourceText: String
    public var translatedText: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var confidence: Double
    public var readingOrder: Int

    public init(jobID: String, payload: TranslatedSegmentPayload) {
        self.id = payload.id
        self.jobID = jobID
        self.sourceText = payload.sourceText
        self.translatedText = payload.translatedText
        self.x = payload.boundingBox.x
        self.y = payload.boundingBox.y
        self.width = payload.boundingBox.width
        self.height = payload.boundingBox.height
        self.confidence = payload.confidence
        self.readingOrder = payload.readingOrder
    }

    public var payload: TranslatedSegmentPayload {
        TranslatedSegmentPayload(
            id: id,
            sourceText: sourceText,
            translatedText: translatedText,
            boundingBox: NormalizedRect(x: x, y: y, width: width, height: height),
            confidence: confidence,
            readingOrder: readingOrder
        )
    }
}

@Model
public final class GlossaryVersion: Identifiable {
    public var id: String
    public var seriesID: String
    public var version: Int
    public var checksum: String
    public var lockedTermCount: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        seriesID: String,
        version: Int,
        checksum: String,
        lockedTermCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.seriesID = seriesID
        self.version = version
        self.checksum = checksum
        self.lockedTermCount = lockedTermCount
        self.createdAt = createdAt
    }
}
