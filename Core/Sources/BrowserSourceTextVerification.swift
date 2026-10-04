import Foundation

public enum BrowserSourceTextVerification {
    public static func matches(source: TranslationSourceSegment, observations: [OCRSegment], isClipped: Bool) -> Bool {
        func normalized(_ value: String) -> String {
            value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        }
        let relevant = observations.filter { observation in
            let a = source.boundingBox, b = observation.boundingBox
            let overlap = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) *
                max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
            return observation.confidence >= 0.7 && overlap / max(0.000001, b.area) > 0.7
        }
        let text = normalized(WebtoonReadingOrder.sort(relevant).map(\.sourceText).joined(separator: " "))
        guard !text.isEmpty else { return false }
        let original = normalized(source.text)
        return isClipped ? original.contains(text) : original == text
    }
}
