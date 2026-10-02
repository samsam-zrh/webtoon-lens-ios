# Webtoon Lens V2 — lecteur iPhone personnel

**V2 est une version separee de V1.** Elle ouvre normalement un site dans une `WKWebView`, conserve sa session de navigation et traduit une **capture locale de la zone visible**, sans recuperer les URL d'images par une seconde requete. L'original du site n'est jamais modifie.

Ce n'est pas une promesse de compatibilite avec « n'importe quel site », de remplacement de bulles de qualite Mac, ni de publication App Store. Le code iOS n'a **pas encore ete compile ni execute** : Xcode/SDK iOS sont absents du Mac utilise, et la CI distante n'a pas demarre a cause d'un verrouillage de facturation GitHub. Les verifications macOS ci-dessous ne remplacent pas ces essais.

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
3. Afficher uniquement le chapitre, puis toucher **Traduire**. Vision fait l'OCR sur l'iPhone ; le backend traduit reellement le texte. Sans backend, texte lisible ou reponse complete, l'original reste affiche avec une erreur, jamais une fausse traduction.
4. **Traduit** presente une capture figee, avec du texte uniquement dans des rectangles OCR fiables ou dans **Texte** s'il ne tient pas. **Original**, defilement, zoom, changement de page ou retour en arriere retirent la capture traduite. **Auto**, facultatif et desactive au depart, attend la fin du mouvement pour demander la zone suivante.

Le bridge est injecte uniquement dans la frame principale, dans un monde JavaScript isole du site. Une seule traduction occupe la file, meme apres annulation jusqu'a la fin du travail precedent. Un delai de stabilisation de 450 ms, les generations de navigation, revisions DOM, scroll/zoom/taille et une seconde empreinte des pixels empechent de publier un resultat obsolete. Les superpositions sont natives, **hors de WKWebView** : aucune capture ne contient sa propre traduction.

La largeur demandee a WebKit est exprimee en points puis corrigee du facteur Retina ; les captures sont limitees a 1 600 pixels de large et 4 millions de pixels. Les zones trop petites, peu fiables ou qui se chevauchent conservent leur original. La police n'est pas reduite sous 11 pt pour simuler un texte qui tiendrait. **Pas de masques blancs/noirs/colores, de separation de lobes ni de restauration d'encre comparables au lecteur Mac V1** : la segmentation native existante reste une approximation.

## Confidentialite et compatibilite

Le site recoit ses propres requetes normales de navigation et conserve ses cookies dans V2. L'API de traduction utilise une session ephemere distincte, sans cookies, authentification stockee ni suivi de redirection. Elle recoit seulement langue, texte OCR, coordonnees, identifiant de serie, style et glossaire via `POST /v1/webtoon/translate` ; timeout de requete 180 s, erreurs serveur explicites. Les images restent en memoire sur l'iPhone. **Aucun envoi d'image, y compris en fallback ; aucun appel a `/extract`, `/image` ou `/ocr` dans le navigateur V2.**

Les formulaires visibles, y compris les champs detectables dans des shadow roots ouverts, challenges connus, frames et videos visibles sont refuses avant l'OCR/export. Ce filtrage prudent ne certifie pas toutes les constructions possibles d'un site : affichez seulement le chapitre et ne traduisez pas un ecran contenant des donnees personnelles. Une capture opaque/vide ou sans texte lisible n'est pas consideree comme un succes.

Les sites peuvent refuser WKWebView, exiger Safari ou rendre des contenus non capturables. Aucune automatisation de connexion, CAPTCHA, paiement, DRM, avertissement de securite ou protection anti-bot. **Webnovel n'est pas valide** : le lien precedemment teste renvoyait un challenge Cloudflare 403 a V1 ; WKWebView peut ameliorer le rendu normal, pas garantir sa resolution. Safari et l'import manuel d'une capture autorisee dans **Lecteur** restent les solutions de secours. L'extension Safari historique est optionnelle et garde son ancien telechargement d'images : elle ne beneficie pas automatiquement du nouveau flux de capture.

## Backend V2 sans toucher aux services V1

Si un backend local est deja accessible au telephone, configurez simplement son URL. Un iPhone ne peut pas joindre le `127.0.0.1` du Mac : **localhost sur iPhone designe l'iPhone**.

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

Prerequis non installes ici : **Xcode complet avec SDK iOS 18+**, XcodeGen et une identite Apple permettant la signature choisie. Ne changez pas la selection globale des outils, n'acceptez pas de licence et n'installez rien sans votre accord.

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

# Avec Xcode complet, pas disponible localement ici :
swift test
xcodegen generate
bash ci/test.sh
```

Le harness compile le core partage et les **memes helpers WebKit de capture/etat** que l'app. Il utilise une vraie WKWebView macOS sans mettre sa fenetre au premier plan, et un serveur de fixtures originales sur un port loopback ephemere, arrete en fin de test. Il couvre URL/consentement, budgets Retina, cache/glossaire/ordre, coordonnees et annulation serialisee, JS/blob/canvas/lazy, sessions, refus de retelechargement sans cookie, DOM intact, scroll imbrique/navigation, formulaires/challenges/frames, pixels opaques, 503/retry/reponse incomplete, redirection et annulation HTTP. Le backend de fixtures est **explicitement synthetique**, pas un traducteur ni une preuve linguistique.

Resultat local : **98 assertions passees** dans la configuration standard et **99 dans la version personnelle**. Les plists, YAML, scripts Bash, gardes des ports/LAN du lanceur et la syntaxe Swift sont egalement verifies. Les avertissements de chemins de frameworks CLT manquants n'empechent pas cette compilation macOS, mais ne fournissent aucun SDK iOS.

Les XCTest iOS ajoutes couvrent les frontieres de capture, le consentement, les reponses, le cache et les comportements deja existants ; ils attendent un runner Xcode. Sur macOS sans UIKit, les declarations de modeles exercitent leurs valeurs uniquement, **pas la persistence SwiftData**. Une analyse syntaxique Swift n'est pas une compilation iOS.

La CI V2 declenchee au premier push est [ce run](https://github.com/samsam-zrh/webtoon-lens-ios/actions/runs/37067720554). **Aucun runner ni aucune etape n'a demarre** ; annotation GitHub : `The job was not started because your account is locked due to a billing issue.` Ce n'est ni un resultat de compilation ni un echec de test du code. Aucun changement de facturation n'a ete entrepris.

**Encore non verifies** : compilation/type-check UIKit/SwiftUI/Vision/SwiftData de l'app et de l'extension, generation Xcode/signature, simulateur iOS, snapshots/orientation/zoom sur iPhone, permissions reseau/ATS reelles, cookies persistants apres relance d'app, retour/avance/Auto sur appareil, installation personnelle et Safari/Raccourcis. Retablir la CI GitHub ou utiliser Xcode avec autorisation permettra ces essais. Aucune compatibilite Webnovel ou autre site protege n'est declaree.
