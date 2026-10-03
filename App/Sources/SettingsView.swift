import SwiftUI
import WebtoonLensCore

struct SettingsView: View {
    var onSaved: () -> Void = {}
    @State private var backendURL = ""
    @State private var stylePrompt = WebtoonLensConstants.defaultStylePrompt
    @State private var allowTextTranslation = false
    @State private var allowPublicChapters = false
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section("Backend local V2") {
                TextField("http://mon-mac.local:8787", text: $backendURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("v2.backend")

                Text("Indique ton propre Mac ou serveur sur le reseau prive. Sur iPhone, localhost designe l'iPhone, pas ton Mac. Aucun service tiers n'est utilise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Confidentialite") {
                Toggle("Autoriser le texte OCR vers ce backend", isOn: $allowTextTranslation)
                    .accessibilityIdentifier("v2.textConsent")
                Text("Consentement desactive au depart et revoque si l'URL change. Texte reconnu, coordonnees, style et glossaire uniquement. Les captures restent sur l'iPhone ; aucun envoi d'image, cookie ou identifiant, meme en cas d'echec OCR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Autoriser la lecture de chapitres publics sur le Mac", isOn: $allowPublicChapters)
                    .accessibilityIdentifier("v2.publicChapterConsent")
                Text("Consentement distinct : le Mac charge l'URL et les images publiques du chapitre choisi ; des crops publics sont analyses sur le Mac. Aucune capture personnelle ni cookie de connexion n'est exporte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Style") {
                TextEditor(text: $stylePrompt)
                    .frame(minHeight: 120)
            }

            Button("Enregistrer") {
                save()
            }

            if let savedMessage {
                Text(savedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
        .onChange(of: backendURL) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines) != SharedSettingsStore.shared.backendBaseURLString {
                allowTextTranslation = false
                allowPublicChapters = false
            }
        }
    }

    private func load() {
        let store = SharedSettingsStore.shared
        backendURL = store.backendBaseURLString
        stylePrompt = store.defaultStylePrompt
        allowTextTranslation = store.hasTextTranslationConsent
        allowPublicChapters = store.hasPublicChapterConsent
    }

    private func save() {
        do {
            let value = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { _ = try LocalBackendAddress.parse(value) }
            let store = SharedSettingsStore.shared
            store.backendBaseURLString = value
            store.defaultStylePrompt = stylePrompt
            store.allowImageFallback = false
            store.setTextTranslationConsent(allowTextTranslation)
            store.setPublicChapterConsent(allowPublicChapters)
            savedMessage = "Reglages V2 enregistres. Les captures ne quittent pas l'iPhone."
            onSaved()
        } catch {
            savedMessage = error.localizedDescription
        }
    }
}
