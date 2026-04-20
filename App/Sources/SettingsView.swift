import SwiftUI
import WebtoonLensCore

struct SettingsView: View {
    @State private var backendURL = ""
    @State private var stylePrompt = WebtoonLensConstants.defaultStylePrompt
    @State private var allowImageFallback = false
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section("Backend") {
                TextField("https://api.example.com", text: $backendURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("L'app envoie par defaut seulement le texte OCR, les coordonnees et le glossaire.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Confidentialite") {
                Toggle("Autoriser l'envoi d'image en fallback", isOn: $allowImageFallback)
                Text("Desactive par defaut. A utiliser uniquement si ton serveur a besoin de revoir une image que l'OCR local ne comprend pas.")
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
    }

    private func load() {
        let store = SharedSettingsStore.shared
        backendURL = store.backendBaseURLString
        stylePrompt = store.defaultStylePrompt
        allowImageFallback = store.allowImageFallback
    }

    private func save() {
        let store = SharedSettingsStore.shared
        store.backendBaseURLString = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        store.defaultStylePrompt = stylePrompt
        store.allowImageFallback = allowImageFallback
        savedMessage = "Reglages enregistres."
    }
}
