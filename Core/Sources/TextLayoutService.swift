import Foundation

public enum WebtoonReadingOrder {
    public static func sort(_ segments: [OCRSegment]) -> [OCRSegment] {
        let sorted = segments.sorted { lhs, rhs in
            let sameLineTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.75
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) <= sameLineTolerance {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return lhs.boundingBox.minY < rhs.boundingBox.minY
        }

        return sorted.enumerated().map { index, segment in
            var copy = segment
            copy.readingOrder = index
            return copy
        }
    }
}

public enum BubbleGrouper {
    public static func makeBubbles(from segments: [OCRSegment]) -> [BubbleGroup] {
        var groups: [BubbleGroup] = []

        for segment in WebtoonReadingOrder.sort(segments) {
            if let lastIndex = groups.indices.last, shouldMerge(segment, into: groups[lastIndex]) {
                var group = groups[lastIndex]
                group.frame = group.frame.union(segment.boundingBox)
                group.segments.append(segment)
                groups[lastIndex] = group
            } else {
                groups.append(BubbleGroup(frame: segment.boundingBox, segments: [segment], readingOrder: groups.count))
            }
        }

        return groups.enumerated().map { index, group in
            BubbleGroup(id: group.id, frame: group.frame, segments: group.segments, readingOrder: index)
        }
    }

    private static func shouldMerge(_ segment: OCRSegment, into group: BubbleGroup) -> Bool {
        let verticalGap = segment.boundingBox.minY - group.frame.maxY
        let closeVertically = verticalGap <= max(0.035, segment.boundingBox.height * 1.25)
        let centeredTogether = abs(segment.boundingBox.midX - group.frame.midX) <= 0.24
        let overlapsHorizontally = segment.boundingBox.minX <= group.frame.maxX + 0.08 &&
            segment.boundingBox.maxX >= group.frame.minX - 0.08

        return closeVertically && (centeredTogether || overlapsHorizontally)
    }
}

public enum GlossaryResolver {
    public static func instructions(from terms: [TermMemoryEntry]) -> [GlossaryTermInstruction] {
        terms
            .map(\.instruction)
            .sorted { lhs, rhs in
                if lhs.isLocked != rhs.isLocked {
                    return lhs.isLocked && !rhs.isLocked
                }
                return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
            }
    }

    public static func checksum(for instructions: [GlossaryTermInstruction]) -> String {
        let stable = instructions
            .sorted { $0.id < $1.id }
            .map { "\($0.id)|\($0.source)|\($0.translation)|\($0.category.rawValue)|\($0.isLocked)" }
            .joined(separator: "\n")
        return ImageHasher.sha256Hex(Data(stable.utf8))
    }

    public static func lockedInstructions(from instructions: [GlossaryTermInstruction]) -> [GlossaryTermInstruction] {
        instructions.filter(\.isLocked)
    }
}
