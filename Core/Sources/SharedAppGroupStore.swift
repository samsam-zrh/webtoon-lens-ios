import Foundation

public enum SharedAppGroupStore {
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: WebtoonLensConstants.appGroupIdentifier) ?? .standard
    }

    public static var containerURL: URL {
        let fileManager = FileManager.default
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WebtoonLensConstants.appGroupIdentifier) {
            return url
        }

        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebtoonLensV2", isDirectory: true)
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}

public final class SharedSettingsStore {
    public static let shared = SharedSettingsStore()

    private enum Key {
        static let backendBaseURL = "backendBaseURL"
        static let allowImageFallback = "allowImageFallback"
        static let defaultStylePrompt = "defaultStylePrompt"
        static let consentedTextBackend = "v2.consentedTextBackend"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = SharedAppGroupStore.defaults) {
        self.defaults = defaults
        if defaults.string(forKey: Key.defaultStylePrompt) == nil {
            defaults.set(WebtoonLensConstants.defaultStylePrompt, forKey: Key.defaultStylePrompt)
        }
    }

    public var backendBaseURL: URL? {
        get {
            guard let value = defaults.string(forKey: Key.backendBaseURL), !value.isEmpty else { return nil }
            return try? LocalBackendAddress.parse(value)
        }
        set {
            backendBaseURLString = newValue?.absoluteString ?? ""
        }
    }

    public var backendBaseURLString: String {
        get { defaults.string(forKey: Key.backendBaseURL) ?? "" }
        set {
            if newValue != backendBaseURLString {
                defaults.removeObject(forKey: Key.consentedTextBackend)
            }
            defaults.set(newValue, forKey: Key.backendBaseURL)
        }
    }

    public var allowImageFallback: Bool {
        get { defaults.bool(forKey: Key.allowImageFallback) }
        set { defaults.set(newValue, forKey: Key.allowImageFallback) }
    }

    public var defaultStylePrompt: String {
        get { defaults.string(forKey: Key.defaultStylePrompt) ?? WebtoonLensConstants.defaultStylePrompt }
        set { defaults.set(newValue, forKey: Key.defaultStylePrompt) }
    }

    public var hasTextTranslationConsent: Bool {
        guard let url = backendBaseURL else { return false }
        return defaults.string(forKey: Key.consentedTextBackend) == url.absoluteString
    }

    public func setTextTranslationConsent(_ allowed: Bool) {
        if allowed, let url = backendBaseURL {
            defaults.set(url.absoluteString, forKey: Key.consentedTextBackend)
        } else {
            defaults.removeObject(forKey: Key.consentedTextBackend)
        }
    }

    public func translationBackend() throws -> URL {
        guard !backendBaseURLString.isEmpty else { throw TranslationClientError.missingBackend }
        let url = try LocalBackendAddress.parse(backendBaseURLString)
        guard hasTextTranslationConsent else { throw BrowserCaptureError.textConsentRequired }
        return url
    }
}

public struct PendingIntentImage: Codable, Hashable, Sendable {
    public var url: URL
    public var filename: String
    public var createdAt: Date

    public init(url: URL, filename: String, createdAt: Date = Date()) {
        self.url = url
        self.filename = filename
        self.createdAt = createdAt
    }
}

public enum SharedHandoffStore {
    private enum Key {
        static let pendingIntentImage = "pendingIntentImage"
        static let openLastRequested = "openLastRequested"
    }

    public static var hasPendingImage: Bool {
        SharedAppGroupStore.defaults.data(forKey: Key.pendingIntentImage) != nil
    }

    public static func savePendingImage(data: Data, filename: String) throws -> URL {
        let directory = SharedAppGroupStore.containerURL.appendingPathComponent("IntentInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeFilename = filename.isEmpty ? "shortcut-\(UUID().uuidString).png" : filename
        let targetURL = directory.appendingPathComponent(safeFilename)
        try data.write(to: targetURL, options: [.atomic])

        let pending = PendingIntentImage(url: targetURL, filename: safeFilename)
        let encoded = try JSONEncoder().encode(pending)
        SharedAppGroupStore.defaults.set(encoded, forKey: Key.pendingIntentImage)
        return targetURL
    }

    public static func consumePendingImage() throws -> PendingIntentImage? {
        guard let data = SharedAppGroupStore.defaults.data(forKey: Key.pendingIntentImage) else {
            return nil
        }
        SharedAppGroupStore.defaults.removeObject(forKey: Key.pendingIntentImage)
        return try JSONDecoder().decode(PendingIntentImage.self, from: data)
    }

    public static func requestOpenLastTranslation() {
        SharedAppGroupStore.defaults.set(true, forKey: Key.openLastRequested)
    }

    public static func consumeOpenLastTranslationRequest() -> Bool {
        let requested = SharedAppGroupStore.defaults.bool(forKey: Key.openLastRequested)
        if requested {
            SharedAppGroupStore.defaults.set(false, forKey: Key.openLastRequested)
        }
        return requested
    }
}

public struct SeriesGlossarySnapshot: Codable, Hashable, Sendable {
    public var seriesID: String
    public var terms: [GlossaryTermInstruction]
    public var updatedAt: Date

    public init(seriesID: String, terms: [GlossaryTermInstruction], updatedAt: Date = Date()) {
        self.seriesID = seriesID
        self.terms = terms
        self.updatedAt = updatedAt
    }
}

public enum SharedGlossarySnapshotStore {
    private static var snapshotURL: URL {
        SharedAppGroupStore.containerURL.appendingPathComponent("glossary-snapshots.json")
    }

    public static func save(terms: [TermMemoryEntry]) throws {
        let grouped = Dictionary(grouping: terms, by: \.seriesID)
        let snapshots = grouped.map { seriesID, terms in
            SeriesGlossarySnapshot(seriesID: seriesID, terms: GlossaryResolver.instructions(from: terms))
        }
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: snapshotURL, options: [.atomic])
    }

    public static func loadInstructions(seriesID: String?) -> [GlossaryTermInstruction] {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshots = try? JSONDecoder().decode([SeriesGlossarySnapshot].self, from: data) else {
            return []
        }

        if let seriesID, let match = snapshots.first(where: { $0.seriesID == seriesID }) {
            return match.terms
        }

        return snapshots
            .flatMap(\.terms)
            .sorted { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }
    }
}
