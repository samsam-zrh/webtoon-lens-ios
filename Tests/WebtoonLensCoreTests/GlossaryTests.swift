import XCTest
@testable import WebtoonLensCore

final class GlossaryTests: XCTestCase {
    func testLockedTermsAreSortedBeforeUnlockedTerms() {
        let locked = TermMemoryEntry(
            seriesID: "series",
            source: "Astra",
            translation: "Astra",
            category: .power,
            isLocked: true
        )
        let unlocked = TermMemoryEntry(
            seriesID: "series",
            source: "Lio",
            translation: "Lio",
            category: .character,
            isLocked: false
        )

        let instructions = GlossaryResolver.instructions(from: [unlocked, locked])

        XCTAssertTrue(instructions[0].isLocked)
        XCTAssertEqual(instructions[0].source, "Astra")
    }

    func testChecksumChangesWhenLockedTermChanges() {
        let base = [
            GlossaryTermInstruction(id: "1", source: "Astra", translation: "Astra", category: .power, isLocked: true)
        ]
        let changed = [
            GlossaryTermInstruction(id: "1", source: "Astra", translation: "Astre", category: .power, isLocked: true)
        ]

        XCTAssertNotEqual(GlossaryResolver.checksum(for: base), GlossaryResolver.checksum(for: changed))
    }
}
