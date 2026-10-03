import SwiftData
import SwiftUI
import UIKit
import WebtoonLensCore

@MainActor
struct WebtoonBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SeriesProfile.updatedAt, order: .reverse) private var profiles: [SeriesProfile]
    @Query(sort: \TermMemoryEntry.updatedAt, order: .reverse) private var terms: [TermMemoryEntry]

    @State private var browser = BrowserReaderController()
    @State private var chapter = PublicChapterController()
    @State private var address = SharedSettingsStore.shared.lastPublicChapterURL
    @State private var selectedSeriesID = ""
    @State private var settingsRevision = 0
    @State private var showsConsent = false
    @State private var showsTranscript = false
    @State private var showsPublicConsent = false
    @State private var requestedPublicURL: URL?
    @FocusState private var addressIsFocused: Bool
    @ScaledMetric(relativeTo: .caption) private var statusHeight = 52.0

    var body: some View {
        @Bindable var browser = browser

        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    TextField("https://site-webtoon.com/episode", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .focused($addressIsFocused)
                        .onSubmit(loadAddress)
                        .accessibilityIdentifier("v2.address")
                    Button("Ouvrir", action: loadAddress)
                        .buttonStyle(.borderedProminent)
                }
                HStack {
                    Button("Lire le chapitre", action: requestPublicChapter)
                        .buttonStyle(.bordered)
                        .disabled(chapter.isLoading)
                        .accessibilityIdentifier("v2.readChapter")
                    Text("Images publiques chargees par ton Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !chapter.hasChapter, !chapter.status.isEmpty {
                    Text(chapter.status)
                        .font(.caption)
                        .foregroundStyle(chapter.hasError ? Color.red : Color.secondary)
                        .accessibilityIdentifier("v2.chapterStatus")
                }

                if !chapter.hasChapter {
                HStack(spacing: 12) {
                    Button(action: browser.goBack) { Image(systemName: "chevron.left") }
                        .disabled(!browser.canGoBack)
                        .accessibilityLabel("Page precedente")
                    Button(action: browser.goForward) { Image(systemName: "chevron.right") }
                        .disabled(!browser.canGoForward)
                        .accessibilityLabel("Page suivante")
                    Button(action: browser.reload) { Image(systemName: "arrow.clockwise") }
                        .disabled(browser.currentURL == nil)
                        .accessibilityLabel("Recharger la page")

                    Picker("Affichage", selection: Binding(
                        get: { browser.wantsTranslation },
                        set: { $0 ? requestTranslation() : browser.showOriginal() }
                    )) {
                        Text("Original").tag(false)
                        Text("Traduit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("v2.presentation")
                }
                .buttonStyle(.bordered)

                HStack {
                    Button(action: requestTranslation) {
                        Label(browser.isTranslating ? "Annuler" : "Traduire", systemImage: "text.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(browser.currentURL == nil || browser.isLoading)
                    .accessibilityIdentifier("v2.translate")

                    Toggle("Auto", isOn: Binding(
                        get: { browser.autoTranslate },
                        set: {
                            browser.setAutoTranslation($0)
                            if $0 { requestTranslation() }
                        }
                    ))
                    .fixedSize()
                    .accessibilityLabel("Traduire apres le defilement")

                    Spacer(minLength: 0)
                    Button("Texte") { showsTranscript = true }
                        .disabled(browser.result == nil)
                    if let url = browser.currentURL {
                        Link(destination: url) { Image(systemName: "safari") }
                            .accessibilityLabel("Ouvrir cette page dans Safari")
                    }
                }

                if !profiles.isEmpty {
                    Picker("Serie", selection: $selectedSeriesID) {
                        Text("Aucune serie").tag("")
                        ForEach(profiles) { profile in Text(profile.title).tag(profile.id) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 6) {
                    if browser.isLoading || browser.isTranslating {
                        ProgressView().controlSize(.small)
                    }
                    Text(browser.status)
                        .font(.caption)
                        .lineLimit(3)
                        .foregroundStyle(browser.hasError ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(browser.status)
                        .accessibilityIdentifier("v2.status")
                }
                .frame(height: statusHeight, alignment: .top)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))

            ZStack {
                NativeWebtoonBrowser(controller: browser)
                    .opacity(chapter.hasChapter ? 0 : 1)
                    .allowsHitTesting(!chapter.hasChapter)
                .overlay {
                    if browser.currentURL == nil, !chapter.hasChapter {
                        ContentUnavailableView(
                            "Ouvre ton chapitre",
                            systemImage: "safari",
                            description: Text("Navigue normalement sur le site, puis touche Traduire. Seule la zone visible sera capturee, sans telecharger ses images une seconde fois.")
                        )
                        .allowsHitTesting(false)
                    }
                }
                if chapter.hasChapter {
                    PublicChapterReaderView(reader: chapter) {
                        chapter.close()
                        browser.setActive(scenePhase == .active)
                    }
                }
            }
        }
        .confirmationDialog("Envoyer le texte OCR a ton Mac ?", isPresented: $showsConsent, titleVisibility: .visible) {
            Button("Autoriser ce backend local") {
                SharedSettingsStore.shared.setTextTranslationConsent(true)
                settingsRevision += 1
                configureTranslation()
                browser.translateVisible()
            }
            Button("Garder l'original", role: .cancel) {
                browser.setAutoTranslation(false)
                browser.showOriginal()
            }
        } message: {
            Text("Destination : \(SharedSettingsStore.shared.backendBaseURLString). Seuls le texte reconnu, ses coordonnees, le style et le glossaire sont envoyes. Les captures restent ici ; ni cookies, ni formulaires, ni identifiants ne sont transmis.")
        }
        .confirmationDialog("Lire les images publiques sur ton Mac ?", isPresented: $showsPublicConsent, titleVisibility: .visible) {
            Button("Autoriser la lecture publique") {
                SharedSettingsStore.shared.setPublicChapterConsent(true)
                if let requestedPublicURL { beginPublicChapter(requestedPublicURL) }
            }
            Button("Garder le navigateur", role: .cancel) {}
        } message: {
            Text("Chapitre : \(requestedPublicURL?.absoluteString ?? ""). Destination : \(SharedSettingsStore.shared.backendBaseURLString). Le Mac charge cette URL et ses images publiques, puis analyse leurs fenetres et masques. Des crops de ces seules images publiques peuvent etre transmis au Mac. Aucun cookie du navigateur, identifiant ou capture privee n'est envoye. Ce consentement est distinct du texte OCR des captures.")
        }
        .sheet(isPresented: $showsTranscript) {
            NavigationStack {
                List {
                    Section("Dialogues traduits") {
                        ForEach(browser.result?.segments ?? []) { segment in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(segment.translatedText).font(.body)
                                    .accessibilityIdentifier("v2.translatedText.\(segment.id)")
                                Text(segment.sourceText).font(.caption).foregroundStyle(.secondary)
                            }
                            .textSelection(.enabled)
                        }
                    }
                    if let failures = browser.result?.failures, !failures.isEmpty {
                        Section("Dialogues en erreur : original conserve") {
                            ForEach(failures) { failure in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(failure.source.text)
                                    Text(failure.message).font(.caption).foregroundStyle(.red)
                                }
                                .accessibilityIdentifier("v2.failedSegment.\(failure.id)")
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                .navigationTitle("Texte de la capture")
                .toolbar { Button("Fermer") { showsTranscript = false } }
            }
        }
        .onAppear {
            settingsRevision += 1
            configureTranslation()
            browser.setActive(scenePhase == .active && !chapter.hasChapter)
            chapter.setActive(scenePhase == .active)
        }
        .onDisappear { browser.setActive(false); chapter.setActive(false) }
        .onChange(of: scenePhase) { _, phase in
            browser.setActive(phase == .active && !chapter.hasChapter)
            chapter.setActive(phase == .active)
        }
        .onChange(of: chapter.hasChapter) { _, hasChapter in browser.setActive(scenePhase == .active && !hasChapter) }
        .onChange(of: translationContext) { _, _ in configureTranslation() }
        .onChange(of: browser.currentURL) { _, url in
            if !addressIsFocused, let url { address = url.absoluteString }
        }
    }

    private var translationContext: String {
        let profile = profiles.first { $0.id == selectedSeriesID }
        let activeTerms = selectedSeriesID.isEmpty ? terms : terms.filter { $0.seriesID == selectedSeriesID }
        let settings = SharedSettingsStore.shared
        return [
            selectedSeriesID, profile?.sourceLanguage ?? "auto", profile?.targetLanguage ?? "fr",
            profile?.stylePrompt ?? settings.defaultStylePrompt,
            GlossaryResolver.checksum(for: GlossaryResolver.instructions(from: activeTerms)),
            settings.backendBaseURLString, String(settings.hasTextTranslationConsent), String(settingsRevision)
        ].joined(separator: "\u{1F}")
    }

    private func configureTranslation() {
        let profile = profiles.first { $0.id == selectedSeriesID }
        let activeTerms = selectedSeriesID.isEmpty ? terms : terms.filter { $0.seriesID == selectedSeriesID }
        let seriesID = profile?.id
        let source = profile?.sourceLanguage ?? WebtoonLensConstants.autoSourceLanguage
        let target = profile?.targetLanguage ?? WebtoonLensConstants.defaultTargetLanguage
        let style = profile?.stylePrompt ?? SharedSettingsStore.shared.defaultStylePrompt
        let glossary = GlossaryResolver.instructions(from: activeTerms)

        browser.configure(context: translationContext) { capture in
            let backend = try SharedSettingsStore.shared.translationBackend()
            let pipeline = WebtoonTranslationPipeline(client: WebtoonTranslationClient(baseURL: backend))
            return try await pipeline.translate(
                image: capture.image, imageData: capture.data, seriesID: seriesID,
                sourceLanguage: source, targetLanguage: target, glossary: glossary, style: style
            )
        }
    }

    private func loadAddress() {
        do {
            let url = try BrowserAddress.parse(address)
            addressIsFocused = false
            address = url.absoluteString
            chapter.close()
            browser.open(url)
        } catch {
            browser.report(error)
        }
    }

    private func requestPublicChapter() {
        do {
            let url = try PublicChapterURL.parse(address)
            let settings = SharedSettingsStore.shared
            guard !settings.backendBaseURLString.isEmpty else { throw TranslationClientError.missingBackend }
            _ = try LocalBackendAddress.parse(settings.backendBaseURLString)
            requestedPublicURL = url
            addressIsFocused = false
            if settings.hasPublicChapterConsent {
                beginPublicChapter(url)
            } else {
                showsPublicConsent = true
            }
        } catch {
            browser.report(error)
        }
    }

    private func beginPublicChapter(_ url: URL) {
        let profile = profiles.first { $0.id == selectedSeriesID }
        let activeTerms = selectedSeriesID.isEmpty ? terms : terms.filter { $0.seriesID == selectedSeriesID }
        chapter.start(
            url, sourceLanguage: profile?.sourceLanguage ?? "auto",
            glossary: GlossaryResolver.instructions(from: activeTerms),
            style: profile?.stylePrompt ?? SharedSettingsStore.shared.defaultStylePrompt
        )
    }

    private func requestTranslation() {
        if browser.isTranslating {
            browser.showOriginal()
            return
        }
        let settings = SharedSettingsStore.shared
        do {
            guard !settings.backendBaseURLString.isEmpty else { throw TranslationClientError.missingBackend }
            _ = try LocalBackendAddress.parse(settings.backendBaseURLString)
            if !settings.hasTextTranslationConsent {
                showsConsent = true
                return
            }
            configureTranslation()
            browser.translateVisible()
        } catch {
            browser.setAutoTranslation(false)
            browser.report(error)
        }
    }
}
