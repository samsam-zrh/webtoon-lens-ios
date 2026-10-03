import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lis dans Webtoon Lens V2")
                        .font(.title.bold())
                    Text("Ouvre normalement le site dans Webtoon, puis traduis une capture de la zone visible. L'original reste intact, sans telechargement parallele des images.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                OnboardingStep(
                    number: "1",
                    title: "Ouvre le site dans l'app",
                    detail: "Colle un lien HTTP ou HTTPS. Connexion, abonnement et verifications du site restent manuels. La compatibilite depend du site ; aucun contournement n'est effectue."
                )

                OnboardingStep(
                    number: "2",
                    title: "Configure le backend",
                    detail: "Ajoute l'URL de ton backend local dans Reglages et autorise l'envoi du texte OCR. Sans backend reel, aucune traduction n'est inventee. Les captures restent sur l'iPhone."
                )

                OnboardingStep(
                    number: "3",
                    title: "Compare et continue a lire",
                    detail: "Traduit montre une capture stable, pas des masques de bulles de qualite Mac. Defiler ou zoomer remet l'original ; Auto est facultatif. Texte donne les traductions qui ne tiennent pas dans leurs zones."
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
