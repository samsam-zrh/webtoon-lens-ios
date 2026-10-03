import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lis dans Webtoon Lens V2")
                        .font(.title.bold())
                    Text("Colle le lien puis Traduire. Lens choisit les images publiques quand elles sont accessibles, sinon le navigateur normal et le texte OCR de la zone lue. L'original reste intact.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                OnboardingStep(
                    number: "1",
                    title: "Une seule commande",
                    detail: "Traduire ouvre et traduit le chapitre. Les chevrons changent uniquement un numero de chapitre explicite ; un identifiant opaque garde la navigation desactivee."
                )

                OnboardingStep(
                    number: "2",
                    title: "Configure le backend",
                    detail: "Configure ton backend local. Le consentement chapitre autorise ses images publiques et leurs crops ; le consentement capture n'envoie que le texte OCR. Les captures personnelles restent sur l'iPhone."
                )

                OnboardingStep(
                    number: "3",
                    title: "Lis sans bandeau encombrant",
                    detail: "Le bandeau se retracte en defilant. Remonte legerement ou touche sa poignee pour retrouver les commandes. Maintiens le bandeau pour l'original, les erreurs et les reglages. Les images publiques gardent les masques V1 ; les captures privees restent approximatives."
                )

                Text("En cas de page incompatible, utilise Safari ou importe une capture autorisee dans Lecteur. iOS ne permet pas de dessiner librement par-dessus les autres apps. V2 est une version personnelle distincte de V1, pas une promesse de compatibilite universelle ni de publication App Store.")
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
    let detail: String

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
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
