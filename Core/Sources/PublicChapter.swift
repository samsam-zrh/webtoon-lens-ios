import Foundation
import ImageIO

public enum PublicChapterError: Error, LocalizedError {
    case consentRequired
    case invalidPublicURL
    case noPages
    case invalidImage
    case imageLimit
    case invalidGeometry
    case invalidSegment(String, String)
    case backend(Int, String, String?)
    case rendererUnavailable

    public var errorDescription: String? {
        switch self {
        case .consentRequired:
            return "Autorise le chargement du chapitre public par ce backend local. Les captures privees restent sur l'iPhone."
        case .invalidPublicURL:
            return "Le mode chapitre utilise uniquement des URL publiques HTTP(S), sans identifiants ni adresse reseau privee."
        case .noPages:
            return "Aucune page de chapitre publique exploitable. Le navigateur original reste disponible."
        case .invalidImage:
            return "La ressource publique n'est pas une image lisible."
        case .imageLimit:
            return "Page trop volumineuse (20 Mo ou 32 millions de pixels maximum). Original conserve."
        case .invalidGeometry:
            return "Les coordonnees ou masques OCR sont invalides. Aucun remplacement n'est applique."
        case .invalidSegment(let id, let reason):
            return "OCR \(id) : \(reason). Original conserve ; aucun masque incertain n'est applique."
        case .backend(let status, let message, _):
            return "Lecture publique (\(status)) : \(message)"
        case .rendererUnavailable:
            return "Le moteur de lecture local n'est pas disponible. Le navigateur reste accessible."
        }
    }
}

public enum PublicChapterURL {
    public static func parse(_ value: String) throws -> URL {
        let url = try BrowserAddress.parse(value)
        guard let host = url.host?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              (try? LocalBackendAddress.parse("\(url.scheme ?? "https")://\(host)")) == nil,
              !host.hasPrefix("0."), !host.hasPrefix("255."),
              !host.contains(":") else { throw PublicChapterError.invalidPublicURL }
        let sensitive = Set(["token", "access_token", "session", "sessionid", "auth", "signature", "password"])
        guard !(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .contains(where: { sensitive.contains($0.name.lowercased()) }) else { throw PublicChapterError.invalidPublicURL }
        return url
    }
}

public struct PublicChapterImage: Codable, Hashable, Sendable {
    public var url: String
    public var alt: String

    public init(url: String, alt: String = "") {
        self.url = url
        self.alt = alt
    }

    public var isObviousDecoration: Bool {
        let text = (URL(string: url)?.lastPathComponent ?? "").lowercased() + " " + alt.lowercased()
        return ["favicon", "logo", "avatar", "cropped-", "icon", "banner", "advertisement"].contains { text.contains($0) }
    }
}

public struct PublicChapterExtraction: Codable, Sendable {
    public var pageURL: String
    public var images: [PublicChapterImage]

    public init(pageURL: String, images: [PublicChapterImage]) {
        self.pageURL = pageURL
        self.images = images
    }
}

public struct PublicImageMetadata: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public init(data: Data) throws {
        guard data.count <= 20_000_000 else { throw PublicChapterError.imageLimit }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw PublicChapterError.invalidImage }
        guard width <= 16_000, height <= 100_000, width * height <= 32_000_000 else { throw PublicChapterError.imageLimit }
        self.init(width: width, height: height)
    }

    public var isReadingPage: Bool {
        width >= 320 && height >= 400 && Double(height) / Double(width) >= 0.6
    }
}

public struct PublicOCRStyle: Codable, Hashable, Sendable {
    public var fillColor: String?
    public var textColor: String?
    public var fontFamily: String?
    public var fontStyle: String?
    public var fontWeight: String?
}

public struct PublicOCRSegment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourceText: String
    public var text: String?
    public var boundingBox: NormalizedRect
    public var rawBoundingBox: NormalizedRect?
    public var textBox: NormalizedRect?
    public var confidence: Double
    public var readingOrder: Int?
    public var renderMode: String?
    public var maskData: String?
    public var replacementData: String?
    public var style: PublicOCRStyle?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var fontSizeSource: Double?
    public var translatedText: String?

    public func validated() throws -> PublicOCRSegment {
        guard !id.isEmpty, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublicChapterError.invalidSegment(id, "identifiant ou texte absent")
        }
        guard boundingBox.isInsideImage else { throw PublicChapterError.invalidSegment(id, "rectangle de remplacement hors image") }
        guard rawBoundingBox.map(\.isInsideImage) ?? true else { throw PublicChapterError.invalidSegment(id, "rectangle source hors image") }
        guard textBox.map(\.isInsideImage) ?? true else { throw PublicChapterError.invalidSegment(id, "rectangle de texte hors image") }
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw PublicChapterError.invalidSegment(id, "confiance OCR invalide")
        }
        for data in [maskData, replacementData].compactMap({ $0 }) {
            guard data.hasPrefix("data:image/png;base64,"), data.count <= 8_000_000,
                  let comma = data.firstIndex(of: ","),
                  let bytes = Data(base64Encoded: String(data[data.index(after: comma)...])),
                  CGImageSourceCreateWithData(bytes as CFData, nil) != nil else {
                throw PublicChapterError.invalidGeometry
            }
        }
        return self
    }

    public var translationSource: TranslationSourceSegment {
        TranslationSourceSegment(id: id, text: sourceText, boundingBox: boundingBox, confidence: confidence, readingOrder: readingOrder ?? 0)
    }

    public func isSameDialogue(as other: PublicOCRSegment) -> Bool {
        let first = rawBoundingBox ?? boundingBox
        let second = other.rawBoundingBox ?? other.boundingBox
        let intersection = max(0, min(first.maxX, second.maxX) - max(first.minX, second.minX)) *
            max(0, min(first.maxY, second.maxY) - max(first.minY, second.minY))
        return sourceText.lowercased().filter { $0.isLetter || $0.isNumber } ==
            other.sourceText.lowercased().filter { $0.isLetter || $0.isNumber } &&
            intersection / max(0.000001, min(first.area, second.area)) > 0.7
    }
}

public struct PublicOCRResponse: Codable, Sendable {
    public var segments: [PublicOCRSegment]
}

public struct PublicOCRRequest: Codable, Sendable {
    public var imageUrl: String?
    public var imageData: String?
    public var referer: String
    public var language: String
    public var cacheKey: String

    public init(imageURL: URL, referer: URL, language: String) {
        imageUrl = imageURL.absoluteString
        imageData = nil
        self.referer = referer.absoluteString
        self.language = language
        cacheKey = "v2-public:\(imageURL.absoluteString)"
    }

    public init(publicCrop: Data, referer: URL, language: String, cacheKey: String) {
        imageUrl = nil
        imageData = publicCrop.base64EncodedString()
        self.referer = referer.absoluteString
        self.language = language
        self.cacheKey = cacheKey
    }
}

public struct PublicOCRWindow: Codable, Hashable, Sendable {
    public let coreTop: Int
    public let coreBottom: Int
    public let cropTop: Int
    public let cropBottom: Int

    public static func windows(height: Int) -> [PublicOCRWindow] {
        guard height > 0 else { return [] }
        return stride(from: 0, to: height, by: 2500).map {
            let bottom = min(height, $0 + 2500)
            return PublicOCRWindow(coreTop: $0, coreBottom: bottom, cropTop: max(0, $0 - 400), cropBottom: min(height, bottom + 400))
        }
    }

    public func map(_ source: PublicOCRSegment, page: Int, metadata: PublicImageMetadata) throws -> PublicOCRSegment? {
        let source = try source.validated()
        let cropHeight = Double(cropBottom - cropTop)
        func mapped(_ rect: NormalizedRect) -> NormalizedRect {
            NormalizedRect(x: rect.x, y: (Double(cropTop) + rect.y * cropHeight) / Double(metadata.height),
                           width: rect.width, height: rect.height * cropHeight / Double(metadata.height))
        }
        let raw = mapped(source.rawBoundingBox ?? source.boundingBox)
        let centerPixels = raw.midY * Double(metadata.height)
        guard centerPixels >= Double(coreTop), centerPixels < Double(coreBottom) ||
            (coreBottom == metadata.height && centerPixels <= Double(coreBottom)) else { return nil }
        var segment = source
        segment.id = "p\(page)-\(coreTop)-\(source.id)"
        segment.boundingBox = mapped(source.boundingBox)
        segment.rawBoundingBox = raw
        segment.textBox = source.textBox.map(mapped)
        segment.imageWidth = metadata.width
        segment.imageHeight = metadata.height
        segment.readingOrder = Int(raw.minY * 100_000)
        return try segment.validated()
    }
}

public struct PublicChapterGeneration: Sendable {
    public private(set) var id = UUID()
    public init() {}
    public mutating func advance() { id = UUID() }
    public func accepts(_ candidate: UUID) -> Bool { id == candidate }
}
