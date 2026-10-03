import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lis dans Webtoon Lens V2")
                        .font(.title.bold())
                    Text("Colle le lien dans Webtoon : Lire le chapitre traite ses images publiques comme V1 ; Ouvrir garde le navigateur et sa capture privee. L'original reste intact.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                OnboardingStep(
                    number: "1",
                    title: "Ouvre le site dans l'app",
                    detail: "Pour un chapitre public extractible, choisis Lire le chapitre. Sinon Ouvrir conserve la navigation normale. Connexion, abonnement et verifications restent manuels ; aucun contournement."
                )

                OnboardingStep(
                    number: "2",
                    title: "Configure le backend",
                    detail: "Configure ton backend local. Le consentement chapitre autorise ses images publiques et leurs crops ; le consentement capture n'envoie que le texte OCR. Les captures personnelles restent sur l'iPhone."
                )

                OnboardingStep(
                    number: "3",
                    title: "Compare et continue a lire",
                    detail: "Le mode public reprend les masques Mac V1 et garde les dialogues/source sous chaque page. La capture privee reste une approximation de viewport. Original permet de comparer sans perdre le dessin."
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
