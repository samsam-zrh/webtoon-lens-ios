# Webtoon Lens V2 — lecteur iPhone personnel

**V2 est une version separee de V1, avec deux parcours complementaires.** **Lire le chapitre** conserve l'efficacite de V1 pour les images publiques extractibles : OCR par fenetres sur le Mac, masques V1 et traduction Qwen locale. **Ouvrir / Traduire** garde le navigateur WKWebView, sa session et la capture privee de sa zone visible, sans retelecharger ses images. L'original du site n'est jamais modifie.

**La version personnelle est compilee et executee sur un simulateur iPhone 18 Pro / iOS 27.0**, avec Xcode 27.0. **NanoMachine 332 fonctionne dans le nouveau mode chapitre** : deux vraies pages et du francais ajuste dans leurs bulles ont ete verifies, pas seulement des menus ou du HTML. Le parcours prive capture WKWebView → Vision iOS → Qwen a aussi ete verifie sur des fixtures originales. Cela ne promet ni compatibilite universelle ni publication App Store. La signature et l'installation sur un iPhone physique restent a effectuer.

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

### Images publiques : Lire le chapitre

Configurer son backend local, coller le lien du chapitre puis toucher **Lire le chapitre**. Le consentement explique que le Mac charge **l'URL et ses images publiques**, et analyse aussi des crops de ces seules images. Il est distinct du consentement texte des captures privees, desactive au depart et lie a l'URL du backend. Changer de backend le revoque. Ni cookies WKWebView, identifiants, captures personnelles ni presse-papiers ne sont transmis.

Le mode utilise les APIs existantes `/v1/webtoon/extract`, `/image` et `/ocr`, sans changer V1. Les images restent dans l'ordre de l'extraction ; logos/icones evidents et ressources trop petites sont filtres par metadonnees puis dimensions, jamais par une URL CDN codee en dur. Une page sans texte reste visible et la suivante continue. Un refus d'extraction ou l'absence d'images garde le navigateur — ou le chapitre deja ouvert — avec une erreur explicite, pas un faux succes.

**Pourquoi l'ancien essai Nano ne marchait pas :** ses pages mesurent environ 690 × 22 000 pixels. L'OCR Vision de l'image entiere peut ne rien reconnaitre apres reduction ; V1 travaillait deja par fenetres. V2 reprend **2 500 pixels naturels de cœur + 400 pixels de halo**, recale `boundingBox`, `rawBoundingBox` et `textBox` sur la page complete, attribue chaque dialogue au cœur correspondant et rapproche les doublons par texte **et recouvrement reel**, pas par le texte seul. Les tests couvrent la fin de page et les petits trous, sans sauter le bas d'une longue bande.

La premiere fenetre de chaque page est prioritaire, avec une premiere requete d'un dialogue puis des lots de trois. Les fenetres restantes avancent ensuite en favorisant la page lue. **Un seul travail reseau/OCR/traduction est actif**, au maximum **trois images** sont montees dans le renderer WK, et les autres images sont sur disque dans un cache V2 propre, non dans une collection de bitmaps decodes. Limites explicites : 80 ressources extraites, 20 Mo / 32 millions de pixels par image et 240 Mo de cache pour la session. Le retour au navigateur annule le travail obsolete et nettoie les fichiers de cette session ; quitter l'onglet met les prochains appels en pause, le retour reprend. Aucune lecture externe ne demarre automatiquement.

Le rendu utilise **`PhonePreview/layout.js` identique a V1**, embarque dans une page WK locale de confiance. Le site source n'execute aucun script dans ce renderer. Alpha `maskData`, restauration `replacementData`, rectangles de texte, offsets, couleurs, style et mesure Canvas sont conserves. Aucun rectangle blanc arbitraire ni `lineLimit(5)` ne remplace un masque manquant. Une traduction qui ne tient pas garde l'image et ouvre le texte integral/source sous la page. Les erreurs par page et dialogue restent explicites ; les autres pages continuent et une page en erreur peut etre reprise. **Original**, precedent/suivant et **Dialogue** permettent de comparer et lire.

La derniere URL publique choisie est seulement memorisee dans le champ : l'app normale peut proposer NanoMachine au prochain lancement, mais ne charge ni ne traduit cette URL sans action de l'utilisateur.

### Navigateur / captures privees

1. Ouvrir un lien HTTP/HTTPS dans **Webtoon**. Retour, avance, rechargement et ouverture dans Safari restent disponibles. Connexion, abonnement et verification du site restent des interactions manuelles normales.
2. Configurer son backend local dans **Reglages**. L'envoi de texte est desactive au depart. Le consentement nomme cette URL et est revoque si elle change ; aucun backend public de traduction n'est accepte.
3. Afficher uniquement le chapitre, apres ses choix ordinaires de cookies, puis toucher **Traduire**. Vision fait l'OCR sur l'iPhone ; le backend traduit reellement le texte. Sans backend, texte lisible ou reponse valide, l'original reste affiche avec une erreur, jamais une fausse traduction. Traduire une notice de cookies ou un titre n'est pas une validation de lecture du chapitre.
4. **Traduit** presente une capture figee, avec du texte uniquement dans des rectangles OCR fiables ou dans **Texte** s'il ne tient pas. **Original**, defilement, zoom, changement de page ou retour en arriere retirent la capture traduite. **Auto**, facultatif et desactive au depart, attend la fin du mouvement pour demander la zone suivante.

Le bridge est injecte uniquement dans la frame principale, dans un monde JavaScript isole du site. Une seule traduction occupe la file, meme apres annulation jusqu'a la fin du travail precedent. Un delai de stabilisation de 450 ms, les generations de navigation, revisions DOM, scroll/zoom/taille et une seconde empreinte des pixels empechent de publier un resultat obsolete. Les superpositions sont natives, **hors de WKWebView** : aucune capture ne contient sa propre traduction.

Une demande manuelle reste en attente pendant les petits changements de viewport, notamment a la fermeture du consentement de l'app. Les notifications KVO sans changement reel sont ignorees. Si la page change continuellement pendant **10 secondes**, la capture est annulee avec une erreur explicite et possibilite de reessayer ; le delai ne repart pas a zero a chaque mutation.

Un refus serveur `dialogue_translation_failed` est associe uniquement a son `failedSegmentID` connu. Les autres dialogues sont retentes, avec **32 segments au maximum par lot et 5 appels au maximum par lot** ; une limite atteinte est affichee pour chaque dialogue non termine. Chaque reponse conserve la validation complete des IDs du sous-lot restant. Les erreurs generiques/reseau, IDs inconnus ou reponses incompletes ne sont pas escamotes. **Texte** separe les traductions reussies des originaux en erreur. Aucun ID refuse n'est peint ou compte comme francais ; aucun resultat partiel n'est mis en cache comme capture complete. Un refus total conserve l'affichage **Original**, avec ses erreurs consultables, pas une capture identique estampillee « Traduit ».

Dans ce **parcours de capture privee**, la largeur demandee a WebKit est exprimee en points puis corrigee du facteur Retina ; les captures sont limitees a 1 600 pixels de large et 4 millions de pixels. Les zones trop petites, peu fiables ou qui se chevauchent conservent leur original. La police n'est pas reduite sous 11 pt pour simuler un texte qui tiendrait. Sa segmentation Vision native reste une approximation, **distincte des masques Mac V1 reutilises dans le mode chapitre public**.

## Confidentialite et compatibilite

Le site recoit ses propres requetes normales de navigation et conserve ses cookies dans V2. Les clients API utilisent des sessions ephemeres distinctes, sans cookies, authentification stockee ni suivi de redirection. **Les captures de navigateur et imports personnels restent text-only** : Vision est local, seul le texte/coordonnees/style/glossaire part a `/translate`, jamais leurs images, meme en fallback.

**Le mode chapitre public a son propre consentement** : le Mac recoit le lien choisi et charge les images publiques ; l'iPhone peut lui transmettre des crops de ces images publiques pour l'OCR et les masques. Ce n'est ni un export de l'ecran, ni une autorisation d'aspirer un site connecte ou protege. Les URL avec identifiants, jetons de session evidents ou adresses privees sont refusees comme sources publiques. L'OCR public emploie `imageUrl` (casse exacte) pour les images courtes et `imageData` uniquement pour les crops publics des longues pages ; jamais une capture privee.

Les formulaires visibles, y compris les champs detectables dans des shadow roots ouverts, challenges connus, frames et videos visibles sont refuses avant l'OCR/export. Ce filtrage prudent ne certifie pas toutes les constructions possibles d'un site : affichez seulement le chapitre et ne traduisez pas un ecran contenant des donnees personnelles. Une capture opaque/vide ou sans texte lisible n'est pas consideree comme un succes.

Les sites peuvent refuser WKWebView, exiger Safari ou rendre des contenus non capturables. Aucune automatisation de connexion, CAPTCHA, paiement, DRM, verification d'age, avertissement de securite ou protection anti-bot. Le choix ordinaire des cookies appartient au lecteur ; **aucune fonction d'auto-consentement n'est ajoutee en production**. Des tests natifs bornes sur les trois sites demandes distinguent navigation, contenu reellement visible, OCR et traduction ; voir le bilan ci-dessous. Le refus Cloudflare 403 de l'ancien telechargement V1 n'est pas une preuve de contournement ou de compatibilite Webnovel dans V2.

Safari et l'import manuel d'une capture autorisee dans **Lecteur** restent les solutions de secours. L'extension Safari historique est optionnelle et garde son ancien telechargement d'images : elle ne beneficie pas automatiquement du nouveau flux de capture et refuse explicitement un resultat partiel plutot que d'annoncer une traduction complete. Le lecteur d'images de l'app affiche les erreurs partielles et marque l'historique `partial` ou `failed`, jamais `completed` pour un refus total.

## Backend V2 sans toucher aux services V1

Si un backend local est deja accessible au telephone, configurez simplement son URL. Un iPhone ne peut pas joindre le `127.0.0.1` du Mac : **localhost sur iPhone designe l'iPhone**.

Le simulateur iOS sur ce Mac peut joindre le backend du Mac sur **`http://127.0.0.1:8787`** : ce transport, les APIs de lecture publique et la traduction reelle ont ete testes, sans exposition LAN ni tunnel. Le backend choisi reste configure dans V2 a la fin des tests, mais les **deux consentements sont revoques** et Auto desactive. L'app normale s'ouvre sur Webtoon avec le dernier lien public dans le champ, sans lancer automatiquement une page ou une traduction.

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

# Parite publique NanoMachine 332 : extraction / fenetres / masques / Qwen reels.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WebtoonLensV2Personal.xcodeproj -scheme WebtoonLensV2PublicChapter \
  -destination 'platform=iOS Simulator,id=52F6BB73-EE31-4ACF-8B85-55E7ACEBC388' \
  -derivedDataPath .runtime/ios-build -parallel-testing-enabled NO \
  -only-testing:WebtoonLensCoreTests -only-testing:WebtoonLensUITests/PublicChapterReaderTests \
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
| `public-chapter-nano-render-20261003.xcresult` | **45 Core + 1 UI passent** : deux vraies pages NanoMachine, cinq masques ajustes, comparaison Original, aucun logo/menu pris pour un dialogue |
| `public-chapter-final-20261003.xcresult` | **49 Core + 2 UI passent** : crops naturels/pixels source, couverture/halo/doublons, 200/OCR masques/styles, 403/noimages, pause/reprise/annulation, Nano reel et smoke UI |
| `public-chapter-parity-verified-20261003.xcresult` | **50 Core + 5 UI passent sur le code final** : Nano reel (41,0 s pour tout le test, reglages/consentement/comparaison inclus), captures privees Vision/Qwen preservees, refus total/partiel et smoke ; zero echec |

Le renderer V1 et sa copie dans le bundle ont le meme SHA-256 : `d125c050dc9e106b2293d42bdba67de099660b2b701e908105f7ecacd85b5ac1`. Le premier essai de ce mode a revele une erreur de specification XcodeGen : l'ancienne cle `resources:` etait ignoree, les scripts/HTML n'etaient pas dans l'app. Les ressources sont maintenant declarees dans `sources` avec `buildPhase: resources`, sans copier Info.plist/entitlements. Un renderer absent ou defaillant arrete la lecture publique et garde le navigateur avec une erreur, plutot que de compter du texte invisible comme un rendu reussi.

Cet ancien essai affichait aussi « 4 pages en erreur », mais sans details journalises ; **leur cause individuelle n'est pas determinee retrospectivement**, et elles ne sont pas attribuees sans preuve aux sites ou au modele. Les erreurs actuelles indiquent page/fenetre/raison typee, conservent les reussites et permettent une reprise. La preuve publiee valide les deux premieres pages et leurs vrais dialogues, **pas la traduction sans erreur de tout le chapitre**.

La fixture originale a produit, via **Vision iOS et Qwen reel**, « Attendez les autres. Nous partons ensemble. », avec une zone francaise native, le texte source consultable, puis retrait via Original. Une seconde fixture de trois bulles injecte seulement un **refus HTTP type de test** ; les deux autres dialogues sont traduits par le vrai backend local, pas remplaces par des phrases codees. Sa variante totalement refusee finit sur Original avec zero segment francais et chaque erreur visible. Les serveurs de fixtures sont sur loopback ephemere et arretes a la fin ; ils ne recuperent aucune page tierce.

Les tests multisites sont dans le scheme **`WebtoonLensV2SiteChecks`**, volontairement separe : ils visitent uniquement les trois URL demandees, avec un viewport borne. Les tests ordinaires/CI ne contactent pas ces sites. Les captures diagnostiques restent locales et ne sont pas publiees ; les rapports ne reproduisent aucun texte de chapitre.

### Bilan des trois sites demandes

**Aucun des trois chapitres n'est declare compatible sur la seule base de son HTML, de ses images AX ou de texte d'interface traduit.** Les choix ordinaires de cookies ont ete refuses dans la session d'essai quand leur controle etait accessible, sans accepter de CGU, verifier un age, se connecter ou franchir une protection. Ce geste existe uniquement dans le test opt-in, pas dans le produit.

| Cas | Navigation native et zone observee | OCR/API et rendu | Conclusion chapitre |
|---|---|---|---|
| [NanoMachine 332](https://nanomachin.com/manga/nano-machine-chapter-332/) | Ancien mode navigateur instable ; nouveau mode public charge les vraies images extraites dans l'ordre | **Deux pages de 690 × 21 587 / 22 080 pixels, cinq masques ajustant de vraies traductions francaises** ; original/source comparables | **VALIDE sur ces deux pages en mode public** ; pas une garantie sur tout le chapitre ni le mode navigateur |
| [WEBTOON / Lore Olympus episode 1](https://www.webtoons.com/en/romance/lore-olympus/episode-1/viewer?title_no=1320&episode_no=1) | Redirection normale vers le lecteur mobile ; refus « Refuser tout » effectif, episode/art d'introduction visibles | Vision et Qwen ont traite du texte d'interface ; six segments dans Texte, aucun remplacement de dialogue demontre | **NON VALIDE pour les dialogues** : l'introduction/UI n'est pas une preuve de traduction du chapitre |
| [Webnovel / chapitre fourni](https://www.webnovel.com/fr/comic/wait-i-39-m-the-ultimate-demon-king_33398540708901501/chapter-1_89660822980187997) | Redirection mobile normale ; les premiers essais restent sur la notice de cookies, pas sur des bulles | Les deux segments recuperes concernent cette interface et sont exclus du bilan chapitre | **NON VALIDE** : aucune chaine sur un dialogue de chapitre n'a ete demontree |

Le dernier essai borne de ces deux lecteurs a echoue **dans XCUITest avant la capture de lecture**, sur une cible image dont le « visible frame is empty ». Les deux echecs sont conserves dans `native-reading-controls-final-20261003.xcresult`, pas maquilles en tests passes. Le helper a ensuite ete corrige pour defiler le viewport WebView plutot qu'une image AX ambiguë ; **`build-for-testing` reussit, mais ce changement du helper n'a pas ete reexecute sur les sites**, conformement a la borne de test. Les preuves precedentes de retrait des overlays par scroll/reload/back restent distinctes de ces limites de lecture.

Les lots `native-reading-sites-final-20261003.xcresult` et `native-reading-after-cookie-refusal-20261003.xcresult` contiennent les essais d'interface/introduction et leurs captures locales ; ils ne sont pas des validations de dialogues. La verification manuelle d'une zone de chapitre legitimement accessible reste necessaire. En revanche, la chaine complete et l'isolation des erreurs sont effectivement validees sur les **fixtures originales natives** decrites plus haut.

La CI distante du premier push a ete [bloquee avant toute etape](https://github.com/samsam-zrh/webtoon-lens-ios/actions/runs/37067720554) par la facturation GitHub. Ce constat historique n'est **plus un blocage du build local**, maintenant execute avec Xcode. Aucun changement de facturation n'a ete entrepris.

**Encore non verifies** : signature et installation sur iPhone physique, execution sur iOS 18/19/26, permissions reseau/ATS sur telephone physique, rotation/zoom/Auto sur appareil reel, extension Safari et Raccourcis en usage reel, qualite linguistique et compatibilite de chapitres entiers. Le diagnostic non fatal Xcode27 « Could not archive SSU artifacts » ne constitue pas une validation des Raccourcis. Aucune compatibilite universelle ou garantie de contournement d'un site protege n'est declaree.
