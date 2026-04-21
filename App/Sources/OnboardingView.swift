import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lis le webtoon dans Lens")
                        .font(.title.bold())
                    Text("Colle l'URL dans l'onglet Webtoon. L'app pose les bulles traduites directement sur les images pendant la lecture.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                OnboardingStep(
                    number: "1",
                    title: "Ouvre le site dans l'app",
                    body: "Utilise l'onglet Webtoon pour charger l'episode. C'est le flux le plus rapide et le plus proche d'un remplacement direct sur iPhone."
                )

                OnboardingStep(
                    number: "2",
                    title: "Configure le backend",
                    body: "Ajoute l'URL de ton serveur LLM dans Reglages. Sans URL, l'app garde un mode preview local pour tester OCR et overlays."
                )

                OnboardingStep(
                    number: "3",
                    title: "Garde le raccourci en secours",
                    body: "Pour les apps qui refusent le web ou bloquent les images, le raccourci de capture reste le plan B."
                )

                Text("Important: iOS interdit a une app App Store de lire l'ecran des autres apps en arriere-plan ou de dessiner par-dessus elles. Webtoon Lens remplace le texte dans son propre lecteur et via Safari Extension.")
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
