import SwiftData
import SwiftUI
import UIKit
import WebtoonLensCore

@MainActor
struct WebtoonBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \SeriesProfile.updatedAt, order: .reverse) private var profiles: [SeriesProfile]
    @Query(sort: \TermMemoryEntry.updatedAt, order: .reverse) private var terms: [TermMemoryEntry]
    @State private var reader = ImmersiveReadingController()
    @State private var selectedSeriesID = ""
    @State private var settingsRevision = 0
    @State private var settingsSnapshot = ""
    @State private var panel: ReaderPanel?
    @State private var headerHeight = 0.0
    @State private var voiceOver = UIAccessibility.isVoiceOverRunning
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(Color(uiColor: .secondarySystemBackground))
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ReaderHeaderHeight.self, value: proxy.size.height)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("v2.header")
                .animation(reduceMotion || reader.browser.isCapturePending ? nil : .easeOut(duration: 0.18),
                           value: reader.headerCollapsed)
            ZStack {
                NativeWebtoonBrowser(controller: reader.browser)
                    .opacity(reader.showPublic ? 0 : 1)
                    .allowsHitTesting(!reader.showPublic)
                if reader.browser.currentURL == nil, !reader.showPublic {
                    ContentUnavailableView(
                        "Ton chapitre, en francais",
                        systemImage: "text.viewfinder",
                        description: Text("Colle le lien puis Traduire. Maintiens le bandeau pour les reglages et la comparaison de l'original.")
                    )
                    .allowsHitTesting(false)
                }
                if reader.showPublic {
                    PublicChapterReaderView(reader: reader.chapter) {}
                }
            }
            .accessibilityIdentifier("v2.readingContent")
        }
        .overlay(alignment: .bottomLeading) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["WEBTOON_LENS_TEST_PREFERENCES"]?.hasPrefix("WebtoonLensV2.UI-") == true {
                HStack(spacing: 1) {
                    ReaderTestValue(identifier: "v2.chapterMasks", value: reader.chapter.renderProof)
                    ReaderTestValue(identifier: "v2.headerHeight", value: "\(headerHeight)")
                    ReaderTestValue(identifier: "v2.browserProof", value: reader.browser.captureProof)
                }
                .frame(width: 5, height: 1)
            }
            #endif
        }
        .onPreferenceChange(ReaderHeaderHeight.self) { headerHeight = $0 }
        .confirmationDialog("Traduire avec ton Mac ?", isPresented: Binding(
            get: { reader.needsConsent }, set: { reader.needsConsent = $0 }
        ), titleVisibility: .visible) {
            Button("Autoriser la traduction") {
                reader.approveConsent()
                settingsSnapshot = currentSettingsSnapshot
            }
            Button("Garder l'original", role: .cancel) { reader.needsConsent = false }
        } message: {
            Text(consentMessage)
        }
        .sheet(item: $panel) { panel in
            NavigationStack {
                panelContent(panel)
                    .toolbar { Button("Fermer") { self.panel = nil } }
            }
        }
        .onChange(of: panel) { old, new in
            if old == .settings, new == nil { refreshSettings() }
        }
        .onChange(of: reader.needsConfiguration) { _, needed in
            if needed { panel = .settings; reader.needsConfiguration = false }
        }
        .onAppear { refreshSettings(); reader.setActive(scenePhase == .active) }
        .onDisappear { reader.setActive(false) }
        .onChange(of: scenePhase) { _, value in reader.setActive(value == .active) }
        .onChange(of: configuration) { _, _ in configureReader() }
        .onChange(of: reader.browser.currentURL) { _, url in
            if !addressFocused, !reader.showPublic, let url { reader.address = url.absoluteString }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            voiceOver = UIAccessibility.isVoiceOverRunning
            if voiceOver { reader.revealHeader() }
        }
    }

    @ViewBuilder private var header: some View {
        if reader.headerCollapsed, !addressFocused, !voiceOver, !typeSize.isAccessibilitySize {
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .contentShape(Rectangle())
                .onTapGesture { reader.revealHeader() }
                .contextMenu { contextualActions }
                .accessibilityLabel("Commandes de lecture")
                .accessibilityAction(named: "Afficher les commandes") { reader.revealHeader() }
                .accessibilityIdentifier("v2.headerHandle")
        } else {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    TextField("Lien du chapitre", text: Binding(
                        get: { reader.address }, set: { reader.editAddress($0) }
                    ))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($addressFocused)
                    .submitLabel(.go)
                    .onSubmit(translate)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("v2.address")
                    Button("Traduire", action: translate)
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("v2.translate")
                }
                HStack(spacing: 4) {
                    ChapterStepControl(direction: -1, enabled: reader.navigation.previous != nil,
                                       explanation: reader.navigation.explanation) { stepChapter(-1) }
                        .frame(width: 44, height: 44)
                    Text(reader.status)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(reader.hasError ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(reader.status)
                        .accessibilityIdentifier("v2.status")
                    ChapterStepControl(direction: 1, enabled: reader.navigation.next != nil,
                                       explanation: reader.navigation.explanation) { stepChapter(1) }
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .contextMenu { contextualActions }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var contextualActions: some View {
        Button("Reglages") { panel = .settings }
        if reader.showPublic || reader.browser.result != nil {
            Button("Voir l'original") { reader.showOriginal() }
            Button("Voir la traduction") { reader.showTranslation() }
            if reader.showPublic { Button("Aller au dialogue") { reader.moveToDialogue() } }
        }
        if reader.showPublic || reader.browser.result != nil || reader.hasError {
            Button("Texte et erreurs") { panel = .transcript }
        }
        Button("Importer une capture") { panel = .importImage }
        Button("Series") { panel = .series }
        Button("Aide") { panel = .help }
    }

    @ViewBuilder private func panelContent(_ panel: ReaderPanel) -> some View {
        switch panel {
        case .settings:
            SettingsView(onSaved: refreshSettings).navigationTitle("Reglages")
        case .series:
            SeriesView().navigationTitle("Series")
        case .importImage:
            ReaderView().navigationTitle("Lecteur")
        case .help:
            OnboardingView().navigationTitle("Webtoon Lens V2")
        case .transcript:
            List {
                if reader.showPublic {
                    Text(reader.chapter.status)
                    ForEach(Array(reader.chapter.sourceErrors.enumerated()), id: \.offset) { _, message in Text(message) }
                    Text("Les dialogues, leurs originaux et leurs erreurs sont consultables sous chaque page.")
                } else {
                    ForEach(reader.browser.result?.segments ?? []) { segment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(segment.translatedText).accessibilityIdentifier("v2.translatedText.\(segment.id)")
                            Text(segment.sourceText).font(.caption).foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                    }
                    ForEach(reader.browser.result?.failures ?? []) { failure in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(failure.source.text)
                            Text(failure.message).font(.caption).foregroundStyle(.red)
                        }
                        .accessibilityIdentifier("v2.failedSegment.\(failure.id)")
                    }
                    if reader.browser.hasError { Text(reader.browser.status) }
                }
            }
            .navigationTitle("Texte et erreurs")
        }
    }

    private var configuration: String {
        let profile = profiles.first { $0.id == selectedSeriesID }
        return [
            selectedSeriesID, profile?.sourceLanguage ?? "auto", profile?.targetLanguage ?? "fr",
            profile?.stylePrompt ?? SharedSettingsStore.shared.defaultStylePrompt,
            GlossaryResolver.checksum(for: GlossaryResolver.instructions(from: activeTerms)),
            SharedSettingsStore.shared.backendBaseURLString, String(settingsRevision)
        ].joined(separator: "\u{1F}")
    }

    private var activeTerms: [TermMemoryEntry] {
        selectedSeriesID.isEmpty ? terms : terms.filter { $0.seriesID == selectedSeriesID }
    }

    private var consentMessage: String {
        let destination = SharedSettingsStore.shared.backendBaseURLString
        if reader.consentIncludesPublic {
            return "Destination : \(destination). Pour \(reader.consentURL?.absoluteString ?? ""), le Mac charge les images publiques et leurs crops. Si ce parcours est indisponible, Vision lit localement la zone visible du navigateur et envoie seulement son texte OCR. Deux autorisations distinctes sont donnees ici ; aucune capture privee, cookie ou identifiant n'est transmis."
        }
        return "Destination : \(destination). Vision lit localement la zone visible et envoie uniquement le texte OCR, ses coordonnees et le glossaire. Aucune image privee, cookie ou identifiant n'est transmis."
    }

    private func configureReader() {
        let profile = profiles.first { $0.id == selectedSeriesID }
        reader.configure(ReaderTranslationOptions(
            configuration: configuration, sourceLanguage: profile?.sourceLanguage ?? "auto",
            targetLanguage: profile?.targetLanguage ?? "fr", seriesID: profile?.id,
            style: profile?.stylePrompt ?? SharedSettingsStore.shared.defaultStylePrompt,
            glossary: GlossaryResolver.instructions(from: activeTerms)
        ))
    }

    private var currentSettingsSnapshot: String {
        let settings = SharedSettingsStore.shared
        return [settings.backendBaseURLString, settings.defaultStylePrompt,
                String(settings.hasTextTranslationConsent), String(settings.hasPublicChapterConsent)].joined(separator: "\u{1F}")
    }
    private func refreshSettings() {
        if settingsSnapshot != currentSettingsSnapshot {
            settingsSnapshot = currentSettingsSnapshot
            settingsRevision += 1
        }
        configureReader()
    }
    private func translate() { addressFocused = false; configureReader(); reader.translate() }
    private func stepChapter(_ direction: Int) { addressFocused = false; configureReader(); reader.stepChapter(direction) }
}

private enum ReaderPanel: String, Identifiable {
    case settings, series, importImage, help, transcript
    var id: String { rawValue }
}

private struct ReaderHeaderHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ChapterStepControl: UIViewRepresentable {
    let direction: Int
    let enabled: Bool
    let explanation: String?
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: direction < 0 ? "chevron.left" : "chevron.right"), for: .normal)
        button.accessibilityLabel = direction < 0 ? "Chapitre precedent" : "Chapitre suivant"
        button.accessibilityIdentifier = direction < 0 ? "v2.previousChapter" : "v2.nextChapter"
        button.addTarget(context.coordinator, action: #selector(Coordinator.invoke), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        button.isEnabled = enabled
        button.tintColor = enabled ? .systemBlue : .tertiaryLabel
        button.accessibilityTraits = enabled ? [.button] : [.button, .notEnabled]
        button.accessibilityHint = enabled ? nil : explanation
        context.coordinator.action = action
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct ReaderTestValue: UIViewRepresentable {
    let identifier: String
    let value: String
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = identifier
        label.accessibilityLabel = "Reader verification data"
        label.text = " "
        label.font = .systemFont(ofSize: 1)
        label.textColor = .clear
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) { label.accessibilityValue = value }
}
#endif
