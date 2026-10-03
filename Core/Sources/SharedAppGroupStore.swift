import Foundation

public enum SharedAppGroupStore {
    public static var defaults: UserDefaults {
        #if DEBUG && targetEnvironment(simulator)
        if let suite = ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_PREFERENCES"],
           suite.hasPrefix("WebtoonLensV2.UI-"), let isolated = UserDefaults(suiteName: suite) {
            return isolated
        }
        #endif
        #if WEBTOON_LENS_PERSONAL
        return .standard
        #else
        return UserDefaults(suiteName: WebtoonLensConstants.appGroupIdentifier) ?? .standard
        #endif
    }

    public static var containerURL: URL {
        let fileManager = FileManager.default
        #if !WEBTOON_LENS_PERSONAL
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WebtoonLensConstants.appGroupIdentifier) {
            return url
        }
        #endif

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
        static let consentedPublicChapterBackend = "v2.consentedPublicChapterBackend"
        static let lastPublicChapterURL = "v2.lastPublicChapterURL"
    }

    private let defaults: UserDefaults
    private var isolatedValues: [String: Any]?

    public init(defaults: UserDefaults = SharedAppGroupStore.defaults) {
        self.defaults = defaults
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_PREFERENCES"]?.hasPrefix("WebtoonLensV2.UI-") == true {
            isolatedValues = [:]
            let arguments = ProcessInfo.processInfo.arguments
            for key in [Key.backendBaseURL, Key.defaultStylePrompt, Key.consentedTextBackend,
                        Key.consentedPublicChapterBackend, Key.lastPublicChapterURL] {
                if let index = arguments.firstIndex(of: "-\(key)"), index + 1 < arguments.count {
                    isolatedValues?[key] = arguments[index + 1]
                }
            }
        }
        #endif
        if string(for: Key.defaultStylePrompt) == nil {
            set(WebtoonLensConstants.defaultStylePrompt, for: Key.defaultStylePrompt)
        }
    }

    private func string(for key: String) -> String? {
        if let isolatedValues { return isolatedValues[key] as? String }
        return defaults.string(forKey: key)
    }

    private func set(_ value: Any?, for key: String) {
        if isolatedValues != nil { isolatedValues?[key] = value }
        else { defaults.set(value, forKey: key) }
    }

    public var backendBaseURL: URL? {
        get {
            guard let value = string(for: Key.backendBaseURL), !value.isEmpty else { return nil }
            return try? LocalBackendAddress.parse(value)
        }
        set {
            backendBaseURLString = newValue?.absoluteString ?? ""
        }
    }

    public var backendBaseURLString: String {
        get { string(for: Key.backendBaseURL) ?? "" }
        set {
            if newValue != backendBaseURLString {
                set(nil, for: Key.consentedTextBackend)
                set(nil, for: Key.consentedPublicChapterBackend)
            }
            set(newValue, for: Key.backendBaseURL)
        }
    }

    public var allowImageFallback: Bool {
        get { isolatedValues == nil ? defaults.bool(forKey: Key.allowImageFallback) : isolatedValues?[Key.allowImageFallback] as? Bool ?? false }
        set { set(newValue, for: Key.allowImageFallback) }
    }

    public var defaultStylePrompt: String {
        get { string(for: Key.defaultStylePrompt) ?? WebtoonLensConstants.defaultStylePrompt }
        set { set(newValue, for: Key.defaultStylePrompt) }
    }

    public var hasTextTranslationConsent: Bool {
        guard let url = backendBaseURL else { return false }
        return string(for: Key.consentedTextBackend) == url.absoluteString
    }

    public func setTextTranslationConsent(_ allowed: Bool) {
        if allowed, let url = backendBaseURL {
            set(url.absoluteString, for: Key.consentedTextBackend)
        } else {
            set(nil, for: Key.consentedTextBackend)
        }
    }

    public func translationBackend() throws -> URL {
        guard !backendBaseURLString.isEmpty else { throw TranslationClientError.missingBackend }
        let url = try LocalBackendAddress.parse(backendBaseURLString)
        guard hasTextTranslationConsent else { throw BrowserCaptureError.textConsentRequired }
        return url
    }

    public var hasPublicChapterConsent: Bool {
        guard let url = backendBaseURL else { return false }
        return string(for: Key.consentedPublicChapterBackend) == url.absoluteString
    }

    public func setPublicChapterConsent(_ allowed: Bool) {
        if allowed, let url = backendBaseURL {
            set(url.absoluteString, for: Key.consentedPublicChapterBackend)
        } else {
            set(nil, for: Key.consentedPublicChapterBackend)
        }
    }

    public func publicChapterBackend() throws -> URL {
        guard !backendBaseURLString.isEmpty else { throw TranslationClientError.missingBackend }
        let url = try LocalBackendAddress.parse(backendBaseURLString)
        guard hasPublicChapterConsent else { throw PublicChapterError.consentRequired }
        return url
    }

    public var lastPublicChapterURL: String {
        string(for: Key.lastPublicChapterURL) ?? ""
    }

    public func rememberPublicChapter(_ url: URL) throws {
        let validated = try PublicChapterURL.parse(url.absoluteString)
        set(validated.absoluteString, for: Key.lastPublicChapterURL)
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
