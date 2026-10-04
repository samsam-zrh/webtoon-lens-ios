import CoreGraphics
import Foundation

public enum BrowserCaptureError: Error, LocalizedError {
    case invalidAddress
    case nonLocalBackend
    case textConsentRequired
    case captureInProgress
    case invalidViewport
    case unreadableSnapshot
    case unavailablePage
    case sensitivePage
    case protectedPage
    case unsupportedFrame
    case changedContent
    case invalidBridge
    case unstableViewport

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Utilise une URL HTTP ou HTTPS sans identifiants integres."
        case .nonLocalBackend:
            return "Choisis ton backend local : localhost, une adresse IP privee ou un nom en .local, sans identifiants, requete ni fragment."
        case .textConsentRequired:
            return "Autorise explicitement l'envoi du texte OCR a ce backend local dans les reglages."
        case .captureInProgress:
            return "Une capture est deja en cours."
        case .invalidViewport:
            return "La zone visible n'est pas encore prete. Attends la fin du chargement."
        case .unreadableSnapshot:
            return "La capture est vide, opaque ou illisible. Garde l'original ou importe une capture autorisee."
        case .unavailablePage:
            return "Ouvre d'abord une page HTTP ou HTTPS accessible dans le navigateur."
        case .sensitivePage:
            return "Un formulaire est visible. Aucune capture ni traduction n'est envoyee. Termine ton interaction puis affiche uniquement le chapitre."
        case .protectedPage:
            return "Une verification ou une restriction du site est visible. Interagis normalement avec le site ; Lens ne la contourne pas."
        case .unsupportedFrame:
            return "Une frame ou une video visible ne peut pas etre verifiee. Utilise Safari ou importe une capture que tu peux legitimement lire."
        case .changedContent:
            return "Le contenu a change pendant la traduction. L'original est conserve ; attends une zone stable puis reessaie."
        case .invalidBridge:
            return "Impossible de verifier l'etat de la page. Recharge-la ou utilise l'import manuel."
        case .unstableViewport:
            return "La page change en continu depuis 10 secondes. La capture est annulee ; attends une zone stable puis reessaie, ou importe une capture autorisee."
        }
    }
}

public enum BrowserAddress {
    public static func parse(_ value: String) throws -> URL {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw BrowserCaptureError.invalidAddress
        }
        let address: String
        if value.contains("://") {
            address = value
        } else {
            guard !value.contains(":") else { throw BrowserCaptureError.invalidAddress }
            address = "https://\(value)"
        }
        guard let components = URLComponents(string: address),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else {
            throw BrowserCaptureError.invalidAddress
        }
        return url
    }
}

public enum LocalBackendAddress {
    public static func parse(_ value: String) throws -> URL {
        guard value.contains("://") else { throw BrowserCaptureError.nonLocalBackend }
        let url: URL
        do {
            url = try BrowserAddress.parse(value)
        } catch BrowserCaptureError.invalidAddress {
            throw BrowserCaptureError.nonLocalBackend
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil,
              let host = components.host, isLocalHost(host) else {
            throw BrowserCaptureError.nonLocalBackend
        }
        return url
    }

    private static func isLocalHost(_ value: String) -> Bool {
        let host = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        if host.contains(":") {
            return host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:")
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let number = Int(part),
                  (0...255).contains(number), String(number) == part else { return nil }
            return number
        }
        guard octets.count == 4 else { return false }
        return octets[0] == 127 || octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254)
    }
}

public struct BrowserViewportGeometry: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public var offsetX: Double
    public var offsetY: Double
    public var zoomScale: Double

    public init(width: Double, height: Double, offsetX: Double, offsetY: Double, zoomScale: Double) {
        self.width = width
        self.height = height
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.zoomScale = zoomScale
    }

    public var isValid: Bool {
        [width, height, offsetX, offsetY, zoomScale].allSatisfy(\.isFinite) &&
            width >= 32 && height >= 32 && zoomScale > 0
    }

    public func matches(_ other: BrowserViewportGeometry) -> Bool {
        isValid && other.isValid &&
            abs(width - other.width) < 0.01 && abs(height - other.height) < 0.01 &&
            abs(offsetX - other.offsetX) < 0.01 && abs(offsetY - other.offsetY) < 0.01 &&
            abs(zoomScale - other.zoomScale) < 0.0001
    }

    public func snapshotWidth(pixelScale: Double = 1) throws -> Double {
        guard isValid, pixelScale.isFinite, pixelScale > 0 else { throw BrowserCaptureError.invalidViewport }
        let scale = min(2, 1600 / width, sqrt(4_000_000 / (width * height)))
        guard scale.isFinite, scale > 0 else { throw BrowserCaptureError.invalidViewport }
        // WKSnapshotConfiguration uses points, not pixels, including on Retina.
        let points = floor(width * scale / pixelScale)
        guard points >= 1 else { throw BrowserCaptureError.invalidViewport }
        return points
    }
}

public struct BrowserDocumentState: Codable, Hashable, Sendable {
    public let documentID: String
    public let revision: Int
    public let url: String
    public let scrollX: Double
    public let scrollY: Double
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let viewportLeft: Double
    public let viewportTop: Double
    public let viewportScale: Double
    public let blockedReason: String?
    public let contentRevision: Int?
    public let captureRegion: NormalizedRect?
    public let readingSource: String?
    public let readingAnchor: BrowserImageAnchor?
    public let trackedAnchors: [BrowserImageAnchor]?
    public let sourceStates: [BrowserImageSourceState]?
    public let geometryRevision: Int?

    public init(
        documentID: String, revision: Int, url: String, scrollX: Double, scrollY: Double,
        viewportWidth: Double, viewportHeight: Double, viewportLeft: Double,
        viewportTop: Double, viewportScale: Double, blockedReason: String?,
        contentRevision: Int? = nil, captureRegion: NormalizedRect? = nil, readingSource: String? = nil,
        readingAnchor: BrowserImageAnchor? = nil, trackedAnchors: [BrowserImageAnchor]? = nil,
        sourceStates: [BrowserImageSourceState]? = nil, geometryRevision: Int? = nil
    ) {
        self.documentID = documentID
        self.revision = revision
        self.url = url
        self.scrollX = scrollX
        self.scrollY = scrollY
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.viewportLeft = viewportLeft
        self.viewportTop = viewportTop
        self.viewportScale = viewportScale
        self.blockedReason = blockedReason
        self.contentRevision = contentRevision
        self.captureRegion = captureRegion
        self.readingSource = readingSource
        self.readingAnchor = readingAnchor
        self.trackedAnchors = trackedAnchors
        self.sourceStates = sourceStates
        self.geometryRevision = geometryRevision
    }

    public func validateForCapture() throws {
        guard !documentID.isEmpty, revision >= 0, (try? BrowserAddress.parse(url)) != nil,
              [scrollX, scrollY, viewportWidth, viewportHeight, viewportLeft, viewportTop, viewportScale].allSatisfy(\.isFinite),
              viewportWidth > 0, viewportHeight > 0, viewportScale > 0 else {
            throw BrowserCaptureError.invalidBridge
        }
        switch blockedReason {
        case nil: break
        case "form": throw BrowserCaptureError.sensitivePage
        case "challenge": throw BrowserCaptureError.protectedPage
        case "frame", "media": throw BrowserCaptureError.unsupportedFrame
        default: throw BrowserCaptureError.unavailablePage
        }
        guard captureRegion.map(\.isInsideImage) ?? true else { throw BrowserCaptureError.invalidViewport }
    }

    public func matchesReading(_ other: BrowserDocumentState) -> Bool {
        documentID == other.documentID && revision == other.revision && url == other.url &&
            scrollX == other.scrollX && scrollY == other.scrollY &&
            viewportWidth == other.viewportWidth && viewportHeight == other.viewportHeight &&
            viewportLeft == other.viewportLeft && viewportTop == other.viewportTop &&
            viewportScale == other.viewportScale && blockedReason == other.blockedReason &&
            captureRegion == other.captureRegion && readingSource == other.readingSource && readingAnchor == other.readingAnchor
    }

    public func capturing(in region: NormalizedRect) -> BrowserDocumentState {
        BrowserDocumentState(documentID: documentID, revision: revision, url: url, scrollX: scrollX, scrollY: scrollY,
            viewportWidth: viewportWidth, viewportHeight: viewportHeight, viewportLeft: viewportLeft,
            viewportTop: viewportTop, viewportScale: viewportScale, blockedReason: blockedReason,
            contentRevision: contentRevision, captureRegion: region, readingSource: readingSource,
            readingAnchor: readingAnchor, trackedAnchors: trackedAnchors, sourceStates: sourceStates, geometryRevision: geometryRevision)
    }

    public func focusing(on anchor: BrowserImageAnchor) -> BrowserDocumentState? {
        let visible = anchor.visibleBounds ?? anchor.bounds
        let x = max(0, visible.minX), y = max(0, visible.minY)
        let width = min(1, visible.maxX) - x, height = min(1, visible.maxY) - y
        guard width > 0, height > 0 else { return nil }
        return BrowserDocumentState(documentID: documentID, revision: revision, url: url, scrollX: scrollX, scrollY: scrollY,
            viewportWidth: viewportWidth, viewportHeight: viewportHeight, viewportLeft: viewportLeft,
            viewportTop: viewportTop, viewportScale: viewportScale, blockedReason: blockedReason,
            contentRevision: contentRevision, captureRegion: NormalizedRect(x: x, y: y, width: width, height: height),
            readingSource: "\(anchor.id):\(anchor.signature)", readingAnchor: anchor,
            trackedAnchors: trackedAnchors, sourceStates: sourceStates, geometryRevision: geometryRevision)
    }
}

public struct BrowserCaptureToken: Hashable, Sendable {
    public let id: UUID
    public let epoch: UInt64
    public let geometry: BrowserViewportGeometry
    public let document: BrowserDocumentState
}

public struct BrowserStabilizationWindow: Sendable {
    private let deadline: ContinuousClock.Instant

    public init(now: ContinuousClock.Instant = ContinuousClock().now) {
        deadline = now.advanced(by: .seconds(10))
    }

    public func hasExpired(now: ContinuousClock.Instant = ContinuousClock().now) -> Bool {
        now >= deadline
    }
}

public enum BrowserRestabilizationPolicy {
    public static func allows(
        previous: BrowserDocumentState, current: BrowserDocumentState,
        explicitIntent: Bool, retries: Int, withinWindow: Bool
    ) -> Bool {
        explicitIntent && retries < 2 && withinWindow && current.blockedReason == nil &&
            previous.documentID == current.documentID && previous.url == current.url &&
            previous.revision == current.revision && !previous.matchesReading(current) &&
            (previous.readingSource == current.readingSource || previous.readingSource == nil)
    }
}

public struct BrowserCaptureLifecycle: Sendable {
    public private(set) var epoch: UInt64 = 0
    public private(set) var activeCaptureID: UUID?

    public init() {}

    public mutating func invalidate() {
        epoch &+= 1
    }

    public mutating func begin(geometry: BrowserViewportGeometry, document: BrowserDocumentState) throws -> BrowserCaptureToken {
        guard activeCaptureID == nil else { throw BrowserCaptureError.captureInProgress }
        guard geometry.isValid else { throw BrowserCaptureError.invalidViewport }
        try document.validateForCapture()
        let token = BrowserCaptureToken(id: UUID(), epoch: epoch, geometry: geometry, document: document)
        activeCaptureID = token.id
        return token
    }

    public func canCommit(_ token: BrowserCaptureToken, geometry: BrowserViewportGeometry, document: BrowserDocumentState) -> Bool {
        activeCaptureID == token.id && epoch == token.epoch &&
            token.geometry.matches(geometry) && token.document.matchesReading(document)
    }

    public mutating func finish(_ token: BrowserCaptureToken) {
        if activeCaptureID == token.id { activeCaptureID = nil }
    }
}

public enum ViewportPixelValidator {
    public static func isUsable(rgba: [UInt8]) -> Bool {
        guard rgba.count >= 16, rgba.count.isMultiple(of: 4) else { return false }
        var opaque = 0
        var minimum = 255
        var maximum = 0
        for index in stride(from: 0, to: rgba.count, by: 4) {
            if rgba[index + 3] >= 240 { opaque += 1 }
            let luminance = (Int(rgba[index]) * 3 + Int(rgba[index + 1]) * 6 + Int(rgba[index + 2])) / 10
            minimum = min(minimum, luminance)
            maximum = max(maximum, luminance)
        }
        return Double(opaque) / Double(rgba.count / 4) >= 0.95 && maximum - minimum >= 12
    }
}

public extension NormalizedRect {
    var isInsideImage: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 &&
            width > 0 && height > 0 && maxX <= 1 && maxY <= 1
    }

    /// Les masques du Mac debordent parfois legerement du bord de l'image (padding).
    /// Ramene le rectangle dans l'image quand la zone visible reste majoritaire ;
    /// nil quand le rectangle est degenere ou principalement hors image.
    var clampedInsideImage: NormalizedRect? {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        if isInsideImage { return self }
        let minX = max(0, x)
        let minY = max(0, y)
        let clamped = NormalizedRect(x: minX, y: minY,
                                     width: min(1, x + width) - minX, height: min(1, y + height) - minY)
        guard clamped.width >= 0.002, clamped.height >= 0.002,
              clamped.width >= width * 0.6, clamped.height >= height * 0.6 else { return nil }
        return clamped
    }
}

public enum ViewportOverlayLayout {
    public static func frame(for segment: TranslatedSegmentPayload, in size: CGSize) -> CGRect? {
        guard segment.boundingBox.isInsideImage, segment.confidence.isFinite, segment.confidence >= 0.7,
              !segment.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let box = segment.boundingBox
        return CGRect(x: box.x * size.width, y: box.y * size.height,
                      width: box.width * size.width, height: box.height * size.height)
    }
}
