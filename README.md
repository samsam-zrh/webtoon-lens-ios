# Webtoon Lens V2 — lecteur iPhone personnel

**V2 est une version separee de V1.** Elle ouvre normalement un site dans une `WKWebView`, conserve sa session de navigation et traduit une **capture locale de la zone visible**, sans recuperer les URL d'images par une seconde requete. L'original du site n'est jamais modifie.

**La version personnelle est compilee et executee sur un simulateur iPhone 18 Pro / iOS 27.0**, avec Xcode 27.0. Le parcours reel capture WKWebView → Vision iOS → API Qwen locale → presentation francaise a ete verifie sur des dialogues originaux de test. Ce n'est pas une promesse de compatibilite avec « n'importe quel site », de remplacement de bulles de qualite Mac, ni de publication App Store. La signature et l'installation sur un iPhone physique restent a effectuer.

## V1 reste intacte

Cette branche est `samsam-zrh-webtoon-lens-v2`, basee sur `677c6d6b68d54220c2c2ab3d1cfa894ee640ac7d`. V1 reste sur `master` dans son checkout d'origine, avec son lecteur sur `127.0.0.1:8787` et Ollama sur `127.0.0.1:11434`. Aucune fusion, migration de donnees, installation de SDK, modification de service ni publication TestFlight n'est necessaire pour ce travail.

| Identite | V2 |
|---|---|
| Nom affiche | Webtoon Lens V2 |
| Application | `com.example.webtoonlens.v2` |
| Framework | `com.example.webtoonlens.v2.core` |
| Extension optionnelle | `com.example.webtoonlens.v2.SafariExtension` |
| App Group, version avec extension | `group.com.example.webtoonlens.v2` |
| Version personnelle sans extension | Preferences et fichiers dans le sandbox propre de V2 |

Les cookies WKWebView, preferences, glossaires, historique SwiftData et captures Raccourcis ne sont pas importes depuis V1. Le [lecteur macOS historique](PhonePreview/README.md) est conserve dans la branche, **sans modification de son code ni de ses tests**. Ne lancez pas ses anciens scripts `Install-PhonePreview.sh` / `Start-PhonePreview.sh` pour installer V2 : ils peuvent installer Ollama, charger un modele ou utiliser le port de V1.

## Parcours de lecture

1. Ouvrir un lien HTTP/HTTPS dans **Webtoon**. Retour, avance, rechargement et ouverture dans Safari restent disponibles. Connexion, abonnement et verification du site restent des interactions manuelles normales.
2. Configurer son backend local dans **Reglages**. L'envoi de texte est desactive au depart. Le consentement nomme cette URL et est revoque si elle change ; aucun backend public de traduction n'est accepte.
3. Afficher uniquement le chapitre, apres ses choix ordinaires de cookies, puis toucher **Traduire**. Vision fait l'OCR sur l'iPhone ; le backend traduit reellement le texte. Sans backend, texte lisible ou reponse valide, l'original reste affiche avec une erreur, jamais une fausse traduction. Traduire une notice de cookies ou un titre n'est pas une validation de lecture du chapitre.
4. **Traduit** presente une capture figee, avec du texte uniquement dans des rectangles OCR fiables ou dans **Texte** s'il ne tient pas. **Original**, defilement, zoom, changement de page ou retour en arriere retirent la capture traduite. **Auto**, facultatif et desactive au depart, attend la fin du mouvement pour demander la zone suivante.

Le bridge est injecte uniquement dans la frame principale, dans un monde JavaScript isole du site. Une seule traduction occupe la file, meme apres annulation jusqu'a la fin du travail precedent. Un delai de stabilisation de 450 ms, les generations de navigation, revisions DOM, scroll/zoom/taille et une seconde empreinte des pixels empechent de publier un resultat obsolete. Les superpositions sont natives, **hors de WKWebView** : aucune capture ne contient sa propre traduction.

Une demande manuelle reste en attente pendant les petits changements de viewport, notamment a la fermeture du consentement de l'app. Les notifications KVO sans changement reel sont ignorees. Si la page change continuellement pendant **10 secondes**, la capture est annulee avec une erreur explicite et possibilite de reessayer ; le delai ne repart pas a zero a chaque mutation.

Un refus serveur `dialogue_translation_failed` est associe uniquement a son `failedSegmentID` connu. Les autres dialogues sont retentes, avec **32 segments au maximum par lot et 5 appels au maximum par lot** ; une limite atteinte est affichee pour chaque dialogue non termine. Chaque reponse conserve la validation complete des IDs du sous-lot restant. Les erreurs generiques/reseau, IDs inconnus ou reponses incompletes ne sont pas escamotes. **Texte** separe les traductions reussies des originaux en erreur. Aucun ID refuse n'est peint ou compte comme francais ; aucun resultat partiel n'est mis en cache comme capture complete. Un refus total conserve l'affichage **Original**, avec ses erreurs consultables, pas une capture identique estampillee « Traduit ».

La largeur demandee a WebKit est exprimee en points puis corrigee du facteur Retina ; les captures sont limitees a 1 600 pixels de large et 4 millions de pixels. Les zones trop petites, peu fiables ou qui se chevauchent conservent leur original. La police n'est pas reduite sous 11 pt pour simuler un texte qui tiendrait. **Pas de masques blancs/noirs/colores, de separation de lobes ni de restauration d'encre comparables au lecteur Mac V1** : la segmentation native existante reste une approximation.

## Confidentialite et compatibilite

Le site recoit ses propres requetes normales de navigation et conserve ses cookies dans V2. L'API de traduction utilise une session ephemere distincte, sans cookies, authentification stockee ni suivi de redirection. Elle recoit seulement langue, texte OCR, coordonnees, identifiant de serie, style et glossaire via `POST /v1/webtoon/translate` ; timeout de requete 180 s, erreurs serveur explicites. Les images restent en memoire sur l'iPhone. **Aucun envoi d'image, y compris en fallback ; aucun appel a `/extract`, `/image` ou `/ocr` dans le navigateur V2.**

Les formulaires visibles, y compris les champs detectables dans des shadow roots ouverts, challenges connus, frames et videos visibles sont refuses avant l'OCR/export. Ce filtrage prudent ne certifie pas toutes les constructions possibles d'un site : affichez seulement le chapitre et ne traduisez pas un ecran contenant des donnees personnelles. Une capture opaque/vide ou sans texte lisible n'est pas consideree comme un succes.

Les sites peuvent refuser WKWebView, exiger Safari ou rendre des contenus non capturables. Aucune automatisation de connexion, CAPTCHA, paiement, DRM, verification d'age, avertissement de securite ou protection anti-bot. Le choix ordinaire des cookies appartient au lecteur ; **aucune fonction d'auto-consentement n'est ajoutee en production**. Des tests natifs bornes sur les trois sites demandes distinguent navigation, contenu reellement visible, OCR et traduction ; voir le bilan ci-dessous. Le refus Cloudflare 403 de l'ancien telechargement V1 n'est pas une preuve de contournement ou de compatibilite Webnovel dans V2.

Safari et l'import manuel d'une capture autorisee dans **Lecteur** restent les solutions de secours. L'extension Safari historique est optionnelle et garde son ancien telechargement d'images : elle ne beneficie pas automatiquement du nouveau flux de capture et refuse explicitement un resultat partiel plutot que d'annoncer une traduction complete. Le lecteur d'images de l'app affiche les erreurs partielles et marque l'historique `partial` ou `failed`, jamais `completed` pour un refus total.

## Backend V2 sans toucher aux services V1

Si un backend local est deja accessible au telephone, configurez simplement son URL. Un iPhone ne peut pas joindre le `127.0.0.1` du Mac : **localhost sur iPhone designe l'iPhone**.

Le simulateur iOS sur ce Mac peut joindre le backend du Mac sur **`http://127.0.0.1:8787`** : ce transport et l'API textuelle reelle ont ete testes, sans exposition LAN ni tunnel. Le backend choisi reste configure dans V2 a la fin des tests, mais le **consentement texte est revoque** et Auto desactive. L'app normale s'ouvre sur Webtoon, sans lancer automatiquement une page ou une traduction.

Pour preparer un backend V2 independant, **uniquement dans ce checkout V2**, avec Python deja installe :

```sh
python3 -m venv .runtime/venv
.runtime/venv/bin/python -m pip install -r PhonePreview/requirements.txt
bash ci/Start-V2-Backend.sh
```

Le nouveau script utilise le port **8788** et `.runtime/v2-backend/cache`, sur loopback par defaut. Il ne lance, n'arrete ni ne reconfigure Ollama, et ne telecharge aucun modele. Il consomme l'API locale existante et le tag deja installe `qwen3:4b-instruct-2507-q4_K_M`. L'absence de modele ou de service est une erreur, pas une installation automatique. Ce backend n'a pas ete lance pendant les verifications du lecteur V2.

Pour un essai iPhone, l'utilisateur peut volontairement exposer **ce backend V2 seulement** sur un reseau prive de confiance :

```sh
WEBTOON_LENS_V2_ALLOW_LAN=1 WEBTOON_LENS_V2_HOST=0.0.0.0 bash ci/Start-V2-Backend.sh
```

Configurer ensuite `http://nom-du-mac.local:8788` dans V2 et accorder sa permission reseau local. Cette exposition n'ajoute pas d'authentification/TLS ; jamais sur un Wi-Fi public, avec redirection de port Internet ou tunnel public. La configuration ATS conserve l'exception web uniquement et autorise le reseau local, **pas des requetes API HTTP arbitraires**. Pour une IP numerique HTTP, verifier les exigences ATS du systeme sur appareil ; preferer le nom `.local` ou HTTPS correctement configure. Les caches du backend contiennent du texte.

## Construire pour une installation personnelle

Prerequis : **Xcode complet avec SDK iOS 18+**, XcodeGen et, pour un iPhone physique, une identite Apple permettant la signature choisie. Validation locale effectuee avec Xcode **27.0 / 27A266a**, SDK/runtime iOS **27.0** et XcodeGen **2.46.0**. Les commandes de validation utilisent `DEVELOPER_DIR` par commande ; aucun changement de selection globale, acceptation de licence ou installation de SDK n'a ete effectue par cette session.

La version personnelle evite les capacites App Group et l'extension Safari, souvent incompatibles avec une equipe de provisionnement gratuite :

```sh
xcodegen generate --spec project-personal.yml
open WebtoonLensV2Personal.xcodeproj
```

Choisir le scheme **WebtoonLensV2**, une equipe personnelle dans Signing & Capabilities et un bundle ID V2 disponible pour cette equipe, puis un iPhone iOS 18+. Le flag `WEBTOON_LENS_PERSONAL` utilise explicitement le sandbox de V2 pour preferences et imports Raccourcis ; aucune lecture d'App Group V1. Les limites de signature personnelle et la validation des Raccourcis restent celles d'Apple et doivent etre verifiees sur l'appareil.

La configuration complete `xcodegen generate` produit `WebtoonLensV2.xcodeproj` et ajoute l'extension/App Group **V2**. Elle requiert une equipe autorisant ces capacites et des identifiants V2 coherents dans `project.yml`, les deux entitlements et `WebtoonLensConstants.appGroupIdentifier`. Ne reutilisez jamais les profils/identifiants de V1. Le workflow TestFlight historique est manuel, requiert des profils V2 distincts, et n'a pas ete execute.

## Verifications reproductibles et limites exactes

```sh
# Fonctionne avec les CLT macOS et Python, sans XCTest, Node, modele ou service V1.
swift run V2Checks
# Verifie aussi le flag de sandbox de la version personnelle.
swift run -Xswiftc -DWEBTOON_LENS_PERSONAL V2Checks

# XCTest partage, avec Xcode selectionne seulement pour cette commande :
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test

# Generer la version personnelle avec le XcodeGen deja installe dans ce worktree :
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  .runtime/tools/xcodegen.artifactbundle/xcodegen-2.46.0-macosx/bin/xcodegen \
  generate --spec project-personal.yml

# Build et tests ordinaires : les tests de reseau reel sont opt-in.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WebtoonLensV2Personal.xcodeproj -scheme WebtoonLensV2 \
  -destination 'platform=iOS Simulator,id=52F6BB73-EE31-4ACF-8B85-55E7ACEBC388' \
  -derivedDataPath .runtime/ios-build CODE_SIGNING_ALLOWED=NO build test

# Fixture originale : vrai Vision/Qwen + refus HTTP type controle sur plusieurs dialogues.
# Le backend 8787 doit deja fonctionner ; aucun service ni modele n'est installe.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WebtoonLensV2Personal.xcodeproj -scheme WebtoonLensV2LocalBackend \
  -destination 'platform=iOS Simulator,id=52F6BB73-EE31-4ACF-8B85-55E7ACEBC388' \
  -derivedDataPath .runtime/ios-build -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Le harness compile le core partage et les **memes helpers WebKit de capture/etat** que l'app. Il utilise une vraie WKWebView macOS sans mettre sa fenetre au premier plan, et un serveur de fixtures originales sur un port loopback ephemere, arrete en fin de test. Il couvre URL/consentement, budgets Retina, cache/glossaire/ordre, coordonnees et annulation serialisee, JS/blob/canvas/lazy, sessions, refus de retelechargement sans cookie, DOM intact, scroll imbrique/navigation, formulaires/challenges/frames, pixels opaques, 503/retry/reponse incomplete, redirection et annulation HTTP. Le backend de fixtures est **explicitement synthetique**, pas un traducteur ni une preuve linguistique.

Premier resultat macOS : **98 assertions passees** dans la configuration standard et **99 dans la version personnelle**. Ces anciennes verifications restent distinctes de la validation native suivante.

Validation native du **3 octobre 2026**, sur le seul simulateur iPhone 18 Pro `52F6BB73-EE31-4ACF-8B85-55E7ACEBC388` :

| Preuve locale dans `.runtime/ios-build/Results/` | Resultat |
|---|---|
| `native-smoke-20261003.xcresult` | 24 tests Core + 1 UI, tous passes : vrai build/install/launch, navigation, onboarding et reglages |
| `native-complete-sites-20261003.xcresult` | 30 tests passes : SwiftData, vrai parcours de fixture, premier lot de sites et preservation de l'original ; pas 30 preuves de compatibilite chapitre |
| `native-stability-final-20261003.xcresult` | 26 Core + NanoMachine passes ; erreur de stabilisation explicite a 10 s, pas succes de traduction NanoMachine |
| `native-typed-recovery-20261003.xcresult` | **34 Core + 2 UI passes** : isolation typed503, IDs complets, lots32, budget5, erreurs reseau, cache partiel refuse et Source/Original preserves |

La fixture originale a produit, via **Vision iOS et Qwen reel**, « Attendez les autres. Nous partons ensemble. », avec une zone francaise native, le texte source consultable, puis retrait via Original. Une seconde fixture de trois bulles injecte seulement un **refus HTTP type de test** ; les deux autres dialogues sont traduits par le vrai backend local, pas remplaces par des phrases codees. Sa variante totalement refusee finit sur Original avec zero segment francais et chaque erreur visible. Les serveurs de fixtures sont sur loopback ephemere et arretes a la fin ; ils ne recuperent aucune page tierce.

Les tests multisites sont dans le scheme **`WebtoonLensV2SiteChecks`**, volontairement separe : ils visitent uniquement les trois URL demandees, avec un viewport borne. Les tests ordinaires/CI ne contactent pas ces sites. Les captures diagnostiques restent locales et ne sont pas publiees ; les rapports ne reproduisent aucun texte de chapitre.

### Bilan des trois sites demandes

**Aucun des trois chapitres n'est declare compatible sur la seule base de son HTML, de ses images AX ou de texte d'interface traduit.** Les choix ordinaires de cookies ont ete refuses dans la session d'essai quand leur controle etait accessible, sans accepter de CGU, verifier un age, se connecter ou franchir une protection. Ce geste existe uniquement dans le test opt-in, pas dans le produit.

| Cas | Navigation native et zone observee | OCR/API et rendu | Conclusion chapitre |
|---|---|---|---|
| [NanoMachine 332](https://nanomachin.com/manga/nano-machine-chapter-332/) | WKWebView annonce la page prete, mais mutations continues du viewport initial | Capture annulee explicitement a 10 s ; aucun OCR/API ni francais annonce | **NON VALIDE** : zone stable non obtenue |
| [WEBTOON / Lore Olympus episode 1](https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=1) | Redirection normale vers le lecteur mobile ; refus « Refuser tout » effectif, episode/art d'introduction visibles | Vision et Qwen ont traite du texte d'interface ; six segments dans Texte, aucun remplacement de dialogue demontre | **NON VALIDE pour les dialogues** : l'introduction/UI n'est pas une preuve de traduction du chapitre |
| [Webnovel / chapitre fourni](https://www.webnovel.com/fr/comic/wait-i-39-m-the-ultimate-demon-king_33398540708901501/chapter-1_89660822980187997) | Redirection mobile normale ; les premiers essais restent sur la notice de cookies, pas sur des bulles | Les deux segments recuperes concernent cette interface et sont exclus du bilan chapitre | **NON VALIDE** : aucune chaine sur un dialogue de chapitre n'a ete demontree |

Le dernier essai borne de ces deux lecteurs a echoue **dans XCUITest avant la capture de lecture**, sur une cible image dont le « visible frame is empty ». Les deux echecs sont conserves dans `native-reading-controls-final-20261003.xcresult`, pas maquilles en tests passes. Le helper a ensuite ete corrige pour defiler le viewport WebView plutot qu'une image AX ambiguë ; **`build-for-testing` reussit, mais ce changement du helper n'a pas ete reexecute sur les sites**, conformement a la borne de test. Les preuves precedentes de retrait des overlays par scroll/reload/back restent distinctes de ces limites de lecture.

Les lots `native-reading-sites-final-20261003.xcresult` et `native-reading-after-cookie-refusal-20261003.xcresult` contiennent les essais d'interface/introduction et leurs captures locales ; ils ne sont pas des validations de dialogues. La verification manuelle d'une zone de chapitre legitimement accessible reste necessaire. En revanche, la chaine complete et l'isolation des erreurs sont effectivement validees sur les **fixtures originales natives** decrites plus haut.

La CI distante du premier push a ete [bloquee avant toute etape](https://github.com/samsam-zrh/webtoon-lens-ios/actions/runs/37067720554) par la facturation GitHub. Ce constat historique n'est **plus un blocage du build local**, maintenant execute avec Xcode. Aucun changement de facturation n'a ete entrepris.

**Encore non verifies** : signature et installation sur iPhone physique, execution sur iOS 18/19/26, permissions reseau/ATS sur telephone physique, rotation/zoom/Auto sur appareil reel, extension Safari et Raccourcis en usage reel, qualite linguistique et compatibilite de chapitres entiers. Le diagnostic non fatal Xcode27 « Could not archive SSU artifacts » ne constitue pas une validation des Raccourcis. Aucune compatibilite universelle ou garantie de contournement d'un site protege n'est declaree.
