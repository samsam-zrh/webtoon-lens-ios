import Foundation
import Observation
import WebtoonLensCore

struct ReaderTranslationOptions {
    let configuration: String
    let sourceLanguage: String
    let targetLanguage: String
    let seriesID: String?
    let style: String
    let glossary: [GlossaryTermInstruction]
}

@MainActor
@Observable
final class ImmersiveReadingController {
    let browser = BrowserReaderController()
    let chapter = PublicChapterController()
    var address = SharedSettingsStore.shared.lastPublicChapterURL
    private(set) var showPublic = false
    private(set) var headerCollapsed = false
    var needsConfiguration = false
    var needsConsent = false
    private(set) var consentIncludesPublic = false
    private(set) var consentURL: URL?
    private(set) var message = "Colle le lien, puis Traduire."
    private(set) var errorMessage: String?
    private(set) var attemptingPublic = false

    @ObservationIgnored private var intent = UUID()
    @ObservationIgnored private var options: ReaderTranslationOptions?
    @ObservationIgnored private var requestOptions: ReaderTranslationOptions?
    @ObservationIgnored private var pendingBrowserIntent: UUID?
    @ObservationIgnored private var requestedURL: URL?
    @ObservationIgnored private var fallbackContext: BrowserFallbackContext?
    @ObservationIgnored private var publicConfiguration = ""
    @ObservationIgnored private var active = true
    @ObservationIgnored private var lastScroll = 0.0
    @ObservationIgnored private var scrollTrend = 0.0
    @ObservationIgnored private var warmupTask: Task<Void, Never>?

    init() {
        browser.onScroll = { [weak self] in self?.scrolled(to: $0) }
        chapter.onScroll = { [weak self] in self?.scrolled(to: $0) }
        browser.onReady = { [weak self] in self?.browserBecameReady() }
        browser.onNavigationStarted = { [weak self] user in self?.browserNavigationStarted(userInitiated: user) }
        chapter.onDisplayed = { [weak self] in
            guard let self, self.chapter.displaySourceURL == self.requestedURL else { return }
            self.showPublic = true
            self.attemptingPublic = false
            self.browser.setActive(false)
        }
    }

    var navigation: ChapterURLNavigation { ChapterURLNavigation.derive(address) }

    var status: String {
        if let errorMessage { return errorMessage }
        if attemptingPublic { return "Ouverture et traduction du chapitre…" }
        if pendingBrowserIntent != nil {
            return browser.hasError ? browser.status : "Ouverture du chapitre dans le navigateur…"
        }
        if showPublic {
            return chapter.hasError ? chapter.status : "\(ReadingCopy.pages(chapter.pageCount)) · \(ReadingCopy.translated(chapter.translationCount))"
        }
        if browser.isTranslating { return "Traduction de la zone lue…" }
        if browser.isLoading { return "Chargement du site…" }
        if browser.hasError { return browser.status }
        if browser.result != nil {
            return browser.status
        }
        if fallbackContext != nil { return browser.status }
        return message
    }

    var hasError: Bool { errorMessage != nil || (pendingBrowserIntent != nil ? browser.hasError : showPublic ? chapter.hasError : browser.hasError) }

    func configure(_ options: ReaderTranslationOptions) {
        let changed = self.options?.configuration != options.configuration
        self.options = options
        browser.configure(context: options.configuration) { capture in
            let backend = try SharedSettingsStore.shared.translationBackend()
            let result = try await WebtoonTranslationPipeline(client: WebtoonTranslationClient(baseURL: backend)).translate(
                image: capture.image, imageData: capture.data, seriesID: options.seriesID,
                sourceLanguage: options.sourceLanguage, targetLanguage: options.targetLanguage,
                glossary: options.glossary, style: options.style, alreadyTranslated: capture.alreadyTranslated
            )
            guard try SharedSettingsStore.shared.translationBackend() == backend else {
                throw BrowserCaptureError.textConsentRequired
            }
            return result
        }
        if changed, requestOptions != nil {
            invalidateIntent()
            message = "Reglages modifies · touche Traduire."
        }
    }

    func editAddress(_ value: String) {
        guard address != value else { return }
        address = value
        invalidateIntent()
        errorMessage = nil
    }

    func selectHistoryURL(_ url: URL) {
        invalidateIntent()
        address = url.absoluteString
        errorMessage = nil
        revealHeader()
    }

    func translate() {
        do {
            guard let options else { throw TranslationClientError.missingBackend }
            let url = try BrowserAddress.parse(address)
            let settings = SharedSettingsStore.shared
            guard !settings.backendBaseURLString.isEmpty else {
                needsConfiguration = true
                throw TranslationClientError.missingBackend
            }
            _ = try LocalBackendAddress.parse(settings.backendBaseURLString)
            consentIncludesPublic = (try? PublicChapterURL.parse(url.absoluteString)) != nil
            consentURL = url
            if !settings.hasTextTranslationConsent || (consentIncludesPublic && !settings.hasPublicChapterConsent) {
                requestOptions = options
                needsConsent = true
                return
            }
            begin(url, options: options)
        } catch {
            errorMessage = error.localizedDescription
            revealHeader()
        }
    }

    func approveConsent() {
        guard let url = consentURL, let options = requestOptions,
              options.configuration == self.options?.configuration else { return }
        SharedSettingsStore.shared.setTextTranslationConsent(true)
        if consentIncludesPublic { SharedSettingsStore.shared.setPublicChapterConsent(true) }
        needsConsent = false
        begin(url, options: options)
    }

    func stepChapter(_ direction: Int) {
        guard let url = direction < 0 ? navigation.previous : navigation.next else { return }
        editAddress(url.absoluteString)
        revealHeader()
        translate()
    }

    func setActive(_ value: Bool) {
        active = value
        browser.setActive(value && !showPublic)
        chapter.setActive(value)
        if !value {
            pendingBrowserIntent = nil
        }
    }

    func revealHeader() { headerCollapsed = false }

    func showOriginal() {
        if showPublic { chapter.setOriginal(true) } else { browser.showOriginal() }
    }

    func showTranslation() {
        if showPublic { chapter.setOriginal(false) } else { translate() }
    }

    func moveToDialogue() { chapter.moveToDialogue() }
    func recordingFailed(_ error: Error) { errorMessage = "Historique non enregistre : \(error.localizedDescription)" }

    private func begin(_ url: URL, options: ReaderTranslationOptions) {
        let settings = SharedSettingsStore.shared
        if (try? PublicChapterURL.parse(url.absoluteString)) != nil {
            do { try settings.rememberPublicChapter(url) }
            catch { errorMessage = error.localizedDescription; return }
        }
        errorMessage = nil
        revealHeader()
        if showPublic, chapter.displaySourceURL == url, publicConfiguration == options.configuration {
            chapter.setOriginal(false)
            return
        }
        if let fallbackContext, fallbackContext.canCaptureCurrentPage(
            for: url, configuration: options.configuration, currentURL: browser.currentURL
        ) {
            requestedURL = url
            requestOptions = options
            showPublic = false
            browser.setActive(active)
            browser.translateVisible()
            return
        }
        invalidateIntent()
        let id = intent
        requestedURL = url
        requestOptions = options
        address = url.absoluteString
        warmupTask?.cancel()
        warmupTask = Task { [weak self] in
            do { try await PublicChapterClient(baseURL: try settings.translationBackend()).warmup() }
            catch is CancellationError {
            } catch {
                if let self, self.intent == id { self.message = "Prechauffage indisponible ; traduction normale." }
            }
        }
        if (try? PublicChapterURL.parse(url.absoluteString)) != nil {
            attemptingPublic = true
            publicConfiguration = options.configuration
            chapter.start(url, sourceLanguage: options.sourceLanguage, glossary: options.glossary, style: options.style) { [weak self] error in
                guard let self, self.intent == id else { return }
                if case PublicChapterError.consentRequired = error {
                    self.errorMessage = error.localizedDescription
                    self.attemptingPublic = false
                } else {
                    self.openBrowser(url, configuration: options.configuration, id: id, reason: error.localizedDescription)
                }
            }
        } else {
            openBrowser(url, configuration: options.configuration, id: id, reason: nil)
        }
    }

    private func openBrowser(_ url: URL, configuration: String, id: UUID, reason: String?) {
        guard intent == id else { return }
        attemptingPublic = false
        fallbackContext = BrowserFallbackContext(requestedURL: url, configuration: configuration)
        pendingBrowserIntent = id
        message = reason == nil ? "Ouverture du site…" : "Lecture dans le navigateur · acces public indisponible."
        browser.setActive(active)
        browser.open(url)
    }

    private func browserBecameReady() {
        guard let id = pendingBrowserIntent, intent == id, active,
              let options = requestOptions, options.configuration == self.options?.configuration else { return }
        pendingBrowserIntent = nil
        if let requestedHost = fallbackContext?.requestedURL.host, let resolvedHost = browser.currentURL?.host {
            let normalized: (String) -> String = { host in
                if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
                if host.hasPrefix("m.") { return String(host.dropFirst(2)) }
                return host
            }
            guard normalized(requestedHost) == normalized(resolvedHost) else {
                errorMessage = "Redirection vers un autre site. Verifie le lien puis touche Traduire."
                return
            }
        }
        fallbackContext?.resolvedURL = browser.currentURL
        showPublic = false
        chapter.close()
        browser.setActive(true)
        browser.translateVisible()
    }

    private func browserNavigationStarted(userInitiated: Bool) {
        if !userInitiated, fallbackContext != nil, requestOptions?.configuration == options?.configuration {
            pendingBrowserIntent = intent
            return
        }
        if pendingBrowserIntent == nil {
            intent = UUID()
            fallbackContext?.resolvedURL = nil
            message = "Page changee · affiche le chapitre puis Traduire."
        }
    }

    private func invalidateIntent() {
        intent = UUID()
        pendingBrowserIntent = nil
        attemptingPublic = false
        chapter.cancelWorkPreservingDisplay()
        browser.showOriginal()
        warmupTask?.cancel()
    }

    private func scrolled(to offset: Double) {
        defer { lastScroll = offset }
        guard !browser.isTranslating else { return }
        let delta = offset - lastScroll
        if delta * scrollTrend < 0 { scrollTrend = 0 }
        scrollTrend += delta
        if offset > 40, scrollTrend > 16 {
            headerCollapsed = true
            scrollTrend = 0
        } else if offset < 20 || scrollTrend < -14 {
            headerCollapsed = false
            scrollTrend = 0
        }
    }
}
