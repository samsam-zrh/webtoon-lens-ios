#if canImport(UIKit)
import SwiftData
import XCTest
@testable import WebtoonLensCore

final class NativePersistenceTests: XCTestCase {
    @MainActor
    func testV2ModelsRoundTripThroughSwiftData() throws {
        let container = try ModelContainer(
            for: SeriesProfile.self, TermMemoryEntry.self, TranslationJob.self, TranslatedSegment.self, GlossaryVersion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let profile = SeriesProfile(id: "native-fixture", title: "Original native fixture")
        let term = TermMemoryEntry(seriesID: profile.id, source: "Astra", translation: "Astra", category: .character, isLocked: true)
        let reading = TranslationJob(seriesID: nil, imageHash: "url-hash", sourceLanguage: "en",
            targetLanguage: "fr", status: "completed", durationMilliseconds: 1,
            sourceURL: "https://example.test/chapter-1", sourceTitle: "Original reading", readingKey: "document:1")
        context.insert(profile)
        context.insert(term)
        context.insert(reading)
        try context.save()
        let readingContext = ModelContext(container)
        XCTAssertEqual(try readingContext.fetch(FetchDescriptor<SeriesProfile>()).first?.title, profile.title)
        let storedTerm = try XCTUnwrap(readingContext.fetch(FetchDescriptor<TermMemoryEntry>()).first)
        XCTAssertEqual(storedTerm.instruction.source, "Astra")
        XCTAssertTrue(storedTerm.isLocked)
        let storedReading = try XCTUnwrap(readingContext.fetch(FetchDescriptor<TranslationJob>()).first)
        XCTAssertEqual(storedReading.sourceURL, reading.sourceURL)
        XCTAssertEqual(storedReading.sourceTitle, "Original reading")
        XCTAssertEqual(storedReading.readingKey, "document:1")
    }
}
#endif
