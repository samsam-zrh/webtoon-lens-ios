# Build iOS depuis Windows, sans Mac personnel

Tu peux coder sur Windows, mais la compilation iOS exige obligatoirement macOS + Xcode. La solution pratique sans acheter de Mac est de laisser GitHub Actions lancer un runner macOS dans le cloud.

## Option 1: tests simulateur gratuits/simple

Installe sur Windows:

```powershell
winget install Git.Git
winget install GitHub.cli
```

Puis pousse le projet sur GitHub:

```powershell
cd C:\Users\zerah\Documents\Playground\webtoon-lens-ios
.\ci\Push-ToGitHub.ps1
```

Dans GitHub:

1. Ouvre l'onglet `Actions`.
2. Lance `Webtoon Lens iOS CI`.
3. Le runner macOS installe XcodeGen, genere `WebtoonLens.xcodeproj`, puis lance les tests iOS simulateur.

Cette option ne demande pas de compte Apple Developer payant.

## Option 2: TestFlight sans Mac

Pour TestFlight, il faut:

- Un compte Apple Developer Program.
- Une app App Store Connect.
- Deux Bundle IDs:
  - App: `com.example.webtoonlens` a remplacer par ton vrai identifiant.
  - Extension Safari: `com.example.webtoonlens.SafariExtension` a remplacer aussi.
- Un App Group identique pour les deux targets.
- Un certificat Apple Distribution.
- Deux provisioning profiles App Store: un pour l'app, un pour l'extension.

Remplace les placeholders dans:

- `project.yml`
- `App/Resources/WebtoonLens.entitlements`
- `SafariExtension/Native/WebtoonLensSafariExtension.entitlements`
- `Core/Sources/SharedAppGroupStore.swift`

## Creer un certificat depuis Windows

Installe OpenSSL:

```powershell
winget install ShiningLight.OpenSSL
```

Genere une cle et une demande CSR:

```powershell
openssl genrsa -out ios_distribution.key 2048
openssl req -new -key ios_distribution.key -out ios_distribution.csr -subj "/CN=Webtoon Lens/O=Your Name/C=FR"
```

Dans Apple Developer:

1. Va dans Certificates, Identifiers & Profiles.
2. Cree un certificat `Apple Distribution`.
3. Upload `ios_distribution.csr`.
4. Telecharge le certificat, par exemple `ios_distribution.cer`.

Convertis en `.p12`:

```powershell
openssl x509 -inform DER -in ios_distribution.cer -out ios_distribution.pem
openssl pkcs12 -export -inkey ios_distribution.key -in ios_distribution.pem -out ios_distribution.p12
```

Garde le mot de passe du `.p12`; il ira dans le secret `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`.

## Secrets GitHub a creer

Dans GitHub: `Settings > Secrets and variables > Actions > New repository secret`.

Secrets requis pour archive/TestFlight:

- `APPLE_TEAM_ID`
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_BUILD_KEYCHAIN_PASSWORD`
- `IOS_APP_PROFILE_BASE64`
- `IOS_SAFARI_EXTENSION_PROFILE_BASE64`

Secrets optionnels pour upload automatique vers App Store Connect:

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`

Encode les fichiers `.p12`, `.mobileprovision`, `.p8` depuis PowerShell:

```powershell
.\webtoon-lens-ios\ci\Encode-GitHubSecret.ps1 .\ios_distribution.p12
.\webtoon-lens-ios\ci\Encode-GitHubSecret.ps1 .\WebtoonLens_AppStore.mobileprovision
.\webtoon-lens-ios\ci\Encode-GitHubSecret.ps1 .\WebtoonLensSafari_AppStore.mobileprovision
.\webtoon-lens-ios\ci\Encode-GitHubSecret.ps1 .\AuthKey_XXXXXXXXXX.p8
```

Le script copie la valeur Base64 dans le presse-papiers.

## Lancer TestFlight

Dans GitHub:

1. Ouvre `Actions`.
2. Lance `Webtoon Lens TestFlight Archive`.
3. Si les secrets App Store Connect sont presents, le workflow upload l'IPA vers App Store Connect.
4. Le build apparait ensuite dans App Store Connect > TestFlight apres traitement par Apple.

## Limite importante

Sans Mac ni runner macOS cloud, il n'existe pas de compilation iOS native possible sur Windows. Windows suffit pour coder, pousser sur GitHub, preparer les certificats, et declencher les workflows.

La version iOS native vise maintenant le flux le plus proche de ce que tu veux: l'onglet `Webtoon` ouvre le site dans l'app, detecte les images visibles, fait OCR + traduction, puis injecte les bulles traduites au-dessus de la page. iOS n'autorise toujours pas ce comportement au-dessus des autres apps.

## Tester maintenant sur ton telephone sans Mac

Si GitHub Actions est bloque par le billing, lance la preview mobile locale:

```powershell
cd C:\Users\zerah\Documents\Playground\webtoon-lens-ios
powershell -ExecutionPolicy Bypass -File .\ci\Install-PhonePreviewAI.ps1
powershell -ExecutionPolicy Bypass -File .\ci\Start-PhonePreview.ps1
```

Le script affiche deux URLs:

- `PC`: a ouvrir sur le PC.
- `Phone`: a ouvrir sur ton telephone.

Mets le telephone sur le meme Wi-Fi que le PC, ouvre l'URL `Phone`, puis colle un lien d'episode ou importe une capture webtoon. Cette preview teste le lecteur mobile, les overlays, l'OCR locale et une traduction locale offline. Ce n'est pas encore l'app iOS native avec Safari Extension.

Par defaut, le champ `Backend OCR/IA optionnel` pointe vers le serveur local. Quand tu appuies sur `Traduire`, le telephone appelle:

```http
POST /v1/webtoon/ocr
POST /v1/webtoon/translate
```

Le serveur local utilise EasyOCR/Tesseract pour lire les bulles, un modele local anglais -> francais, et Argos Translate en fallback JP/KO/ZH -> EN. Il ne renvoie plus de fausses traductions. Pour de meilleurs resultats, choisis la bonne `Langue OCR` dans la page avant de traduire.

Si le telephone n'arrive pas a ouvrir l'URL:

1. Autorise Python dans le pare-feu Windows.
2. Verifie que le PC et le telephone sont sur le meme Wi-Fi.
3. Relance le script et essaie l'adresse `Phone` affichee.

## Pourquoi GitHub Actions peut etre bloque

Si un run GitHub dit `The job was not started because your account is locked due to a billing issue`, GitHub bloque les jobs avant meme de demarrer le Mac. Les solutions sont:

- Corriger le billing dans GitHub.
- Utiliser un autre compte GitHub non bloque.
- Utiliser un Mac emprunte/loue avec Xcode.
- Garder la preview mobile locale pour tester l'UX en attendant.
