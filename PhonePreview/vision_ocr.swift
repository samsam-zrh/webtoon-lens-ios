import Foundation
import Vision
import ImageIO

struct Box: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct Line: Codable {
    let id: String
    let sourceText: String
    let boundingBox: Box
    let confidence: Float
    let readingOrder: Int
    let glyphs: [Glyph]
}

struct Glyph: Codable {
    let text: String
    let spaceBefore: Bool
    let boundingBox: Box
}

do {
    guard CommandLine.arguments.count >= 2 else {
        throw NSError(domain: "OCR", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Indiquez une image à reconnaître."
        ])
    }
    let language = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "auto"
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = language == "auto"
    switch language {
    case "zh": request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    case "ja": request.recognitionLanguages = ["ja-JP", "en-US"]
    case "ko": request.recognitionLanguages = ["ko-KR", "en-US"]
    case "en": request.recognitionLanguages = ["en-US"]
    default: request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
    }
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]))
    try handler.perform([request])
    let observations = (request.results ?? []).sorted {
        if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 {
            return $0.boundingBox.midY > $1.boundingBox.midY
        }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
    let lines = try observations.enumerated().compactMap { index, observation -> Line? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        let text = candidate.string
        let glyphs = try text.indices.compactMap { position -> Glyph? in
            let char = text[position]
            guard !char.isWhitespace,
                  let rectangle = try candidate.boundingBox(for: position..<text.index(after: position))
            else { return nil }
            let glyph = rectangle.boundingBox
            let spaceBefore = position != text.startIndex && text[text.index(before: position)].isWhitespace
            return Glyph(
                text: String(char), spaceBefore: spaceBefore,
                boundingBox: Box(x: glyph.minX, y: 1-glyph.maxY, width: glyph.width, height: glyph.height)
            )
        }
        return Line(
            id: "vision-\(index)", sourceText: candidate.string,
            boundingBox: Box(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height),
            confidence: candidate.confidence, readingOrder: index, glyphs: glyphs
        )
    }
    let data = try JSONEncoder().encode(lines)
    FileHandle.standardOutput.write(data)
} catch {
    FileHandle.standardError.write(Data("OCR Vision : \(error.localizedDescription)\n".utf8))
    exit(1)
}
