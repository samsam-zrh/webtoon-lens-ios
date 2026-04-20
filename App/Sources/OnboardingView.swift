import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Traduire sans tricher avec iOS")
                        .font(.title.bold())
                    Text("Dans Safari, l'extension peut poser des bulles traduites sur les images visibles. Dans les autres apps, passe par un raccourci de capture d'ecran.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                OnboardingStep(
                    number: "1",
                    title: "Active l'extension Safari",
                    body: "Installe l'app, puis active Webtoon Lens dans les extensions Safari et autorise les sites de lecture."
                )

                OnboardingStep(
                    number: "2",
                    title: "Configure le backend",
                    body: "Ajoute l'URL de ton serveur LLM dans Reglages. Sans URL, l'app garde un mode preview local pour tester OCR et overlays."
                )

                OnboardingStep(
                    number: "3",
                    title: "Ajoute le raccourci",
                    body: "Dans Raccourcis, cree une action Prendre une capture d'ecran puis appelle Traduire ce webtoon avec Webtoon Lens."
                )

                Text("Important: aucune lecture cachee de l'ecran et aucun overlay systeme hors Safari. C'est la limite saine pour TestFlight et App Store.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
    }
}

private struct OnboardingStep: View {
    let number: String
    let title: String
    let body: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
