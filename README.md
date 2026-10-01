# Webtoon Lens

Lecteur de webtoons avec **OCR et traduction locale en français**, accompagné d’un prototype iOS 18+ respectant les contraintes de l’App Store.

## Lire sur Mac sans compiler iOS

```sh
bash ci/Install-PhonePreview.sh
bash ci/Start-PhonePreview.sh
```

Ouvrez **http://127.0.0.1:8787**. Import de pages anglaises/chinoises ou URL de chapitre, OCR Apple Vision, Qwen 4B **Instruct** local, glossaire de 188 concepts et corrections par série. Les traductions sont ajustées dans les intérieurs de bulles détectés ; les zones non fiables gardent leur original avec une traduction lisible séparément.

Installation, limites du rendu, confidentialité, réseau et tests : **[guide du lecteur macOS](PhonePreview/README.md)**. Les modèles et le serveur s’exécutent sur votre ordinateur, pas sur GitHub Pages.

## Prototype iOS

- Navigateur webtoon intégré et superpositions de traduction.
- Extension Safari avec superpositions à la demande.
- App Intent / Raccourcis pour importer des captures d’autres applications.
- OCR Vision local et requêtes de traduction textuelles vers un backend configurable.
- Mémoire de glossaire par série pour les noms, pouvoirs, lieux et concepts.

## Générer le projet Xcode

Le dépôt utilise XcodeGen pour générer le projet sur macOS :

```sh
brew install xcodegen
cd webtoon-lens-ios
xcodegen generate
open WebtoonLens.xcodeproj
```

Sans Mac : [WINDOWS_NO_MAC.md](WINDOWS_NO_MAC.md). Les workflows GitHub Actions utilisent des runners macOS.

Le lecteur portable Windows historique se lance avec :

```powershell
powershell -ExecutionPolicy Bypass -File .\ci\Install-PhonePreviewAI.ps1
powershell -ExecutionPolicy Bypass -File .\ci\Start-PhonePreview.ps1
```

L’interface et le backend local utilisent la même URL. Le mode portable conserve Tesseract, RapidOCR/EasyOCR et Argos ; le lecteur macOS recommande Vision et `qwen3:4b-instruct-2507-q4_K_M`. Aucun faux préfixe `[fr]` ne remplace une traduction manquante.

Avant d’utiliser l’application iOS sur un appareil réel, remplacez les identifiants d’exemple dans :

- `project.yml`
- `App/Resources/WebtoonLens.entitlements`
- `SafariExtension/Native/WebtoonLensSafariExtension.entitlements`
- `Core/Sources/SharedAppGroupStore.swift`

L’App Group d’exemple est `group.com.example.webtoonlens`.

## Contrat du backend

Configurez l’URL du backend dans les réglages iOS. L’application envoie des requêtes textuelles à :

```http
POST /v1/webtoon/translate
```

La requête contient la langue source `auto`, la cible `fr`, les segments OCR, les coordonnées, l’identifiant de série, les consignes de style et les termes verrouillés. La réponse fournit les segments traduits et d’éventuelles propositions de glossaire.

Sans URL de backend, l’application native affiche une erreur explicite. Pour un test sur téléphone, l’exposition LAN du lecteur local doit être activée volontairement ; voir le guide.

## Limites iOS

iOS n’autorise pas une application tierce de l’App Store à lire et dessiner en permanence au-dessus des autres applications. Hors Safari, l’utilisateur déclenche un Raccourci de capture ; Webtoon Lens reçoit l’image et ouvre le résultat dans l’application.

L’onglet `Webtoon` charge la page dans une `WKWebView`, détecte les images visibles et utilise la chaîne native Swift. Le lecteur web macOS ne remplace pas cette implémentation.

## Validation iOS sur macOS

```sh
xcodegen generate
xcodebuild test -scheme WebtoonLens -destination 'platform=iOS Simulator,name=iPhone 16'
```

L’extension Safari et les Raccourcis doivent également être vérifiés sur un iPhone physique.
