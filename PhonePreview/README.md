# Lecteur local sur macOS

Importez plusieurs pages PNG/JPEG/WebP, ou un lien de chapitre contenant des images accessibles publiquement. Les pages sont reconnues par **Apple Vision**, traduites en français par **Qwen 3 4B Instruct**, puis affichées progressivement. Les images et les dialogues restent sur le Mac : aucun service de traduction distant n’est utilisé.

## Installation et lancement

Mac Apple Silicon, macOS 14 ou plus récent, Python **3.9+** et outils de ligne de commande Apple (`xcode-select --install`). Configuration vérifiée : Apple M5, 24 Go de mémoire, Python 3.9.6, Swift 6.4, Ollama 0.35.0. Aucun Node, Homebrew, projet Xcode ou GPU externe n’est nécessaire pour ce lecteur.

Depuis la racine du dépôt :

```sh
bash ci/Install-PhonePreview.sh
bash ci/Start-PhonePreview.sh
```

Ouvrez **http://127.0.0.1:8787** et gardez le terminal ouvert. `Ctrl+C` arrête les services lancés par le script. L’installation est isolée dans `.runtime/`, ignoré par Git. Le binaire Ollama vient de sa publication GitHub officielle, avec contrôle SHA-256. Le premier lancement télécharge **un seul modèle**, `qwen3:4b-instruct-2507-q4_K_M` (environ 2,5 Go). La compilation de l’outil Vision et son tout premier appel peuvent prendre une dizaine de secondes ; les appels suivants sont plus courts.

**N’utilisez pas le tag `qwen3:4b` à sa place** : le template de la version testée impose un raisonnement et les essais produisaient du texte non traduit. Le tag Instruct testé fonctionne sans raisonnement ; `think: false` seul ne corrige pas un template qui l’impose. Le serveur contrôle les métadonnées et refuse les réponses tronquées, absentes ou comportant encore du chinois / des phrases anglaises recopiées. Ces contrôles ne constituent pas une garantie linguistique absolue.

Le lecteur sérialise ses inférences, avec un contexte de 4 096 tokens et une rétention de dix minutes. Le service Ollama **lancé par le script** est limité à une inférence et un modèle actifs. Si un service Ollama existe déjà, il est réutilisé sans modifier ses limites ni l’arrêter. Un modèle déjà installé n’est pas téléchargé de nouveau : l’import fonctionne hors ligne. Le modèle testé occupe environ **3,2 Go de mémoire GPU**, auxquels s’ajoutent Python, le navigateur et les pages. Gardez de la marge pour ces applications : un modèle 14B et plusieurs moteurs OCR lourds ne sont pas installés par ce script.

## Lecture, glossaire et rendu

- Les imports sont limités à **20 Mo par page**. L’API limite les requêtes à 30 Mo et à 32 dialogues par traduction. Les pages longues sont analysées par fenêtres, avec un chevauchement pour ne pas couper les bulles ordinaires. Les premiers dialogues arrivent avant la fin du chapitre. Les zones visibles restent prioritaires, puis **tout le chapitre continue en arrière-plan sans devoir défiler** : un préchargement progressif vise trois pages en attente/en cours au lieu de forcer immédiatement toutes les images. Les petits trous entre fenêtres et la fin des pages ne sont plus considérés comme déjà analysés.
- **Voir l’original** masque les remplacements. **Lire les dialogues et leur original**, sous chaque image, donne la traduction intégrale et permet de comparer l’OCR.
- Sans zone de bulle fiable (par exemple une annonce sur une illustration), le panneau de traduction sous l’image s’ouvre automatiquement : le français reste visible sans effacer le dessin. **Une erreur de traduction sur un dialogue ne bloque plus les suivants, même sur la même page.** Le dialogue original et son erreur sont affichés explicitement ; ce n’est pas compté comme une traduction réussie. **Relancer la traduction** réessaie uniquement les dialogues ou pages en erreur, sans effacer les traductions déjà affichées. Changer la langue ou le glossaire relance en revanche l’ensemble.
- Le glossaire contient **188 concepts originaux** anglais/chinois, catégories et indications de sens. OpenCC fournit les variantes traditionnelles. Les termes ordinaires sont des indications contextualisées, avec accords possibles ; quelques concepts non ambigus sont littéraux. Les corrections par série sont prioritaires et vérifiées littéralement. Ajoutez les noms de personnages, lieux ou techniques propres à votre série : ce lexique n’est pas un dictionnaire de tous les webtoons.
- Les corrections restent dans le stockage local de ce navigateur, séparées par le champ **Série**. Leur modification relance la traduction. Le cache tient compte du modèle, du dialogue, du contexte et des termes réellement utilisés : une correction pertinente ne réutilise pas l’ancienne traduction.
- Le prompt ne présente des marqueurs de glossaire que lorsque le dialogue contient réellement des termes verrouillés. Une réponse invalide peut déclencher une seule nouvelle génération contrôlée ; si elle reste invalide, l’erreur est affichée, jamais remplacée par une fausse traduction.
- Le masque alpha accepte les **intérieurs uniformes blancs, noirs ou colorés**, y compris les contours irréguliers et les traits fins séparant une bulle d’un fond de même couleur. Lorsque les lignes ont des longueurs différentes, le lecteur cherche un rectangle de texte réellement inscrit plutôt que de rejeter toute la bulle. Le fond est échantillonné ; le texte devient clair ou sombre pour garder un contraste d’au moins 4,5:1. Les trous hors des lignes OCR ne sont pas effacés, sauf une petite ponctuation monochrome voisine que Vision aurait omise. Une bulle coupée sur un seul bord par une fenêtre d’analyse peut être remplacée si son rectangle de texte reste entièrement dans une zone sûre.
- Deux dialogues identiques à des positions différentes sont conservés. Les observations qui se chevauchent sont rapprochées par leur texte complet et leur position réelle ; un meilleur masque trouvé ensuite réutilise le français déjà produit, y compris dans le chevauchement entre fenêtres.
- Les bulles reliées par un col étroit gardent **des paragraphes et des placements distincts**, au lieu de vider deux bulles et de concentrer tout le français dans leur jonction. Le détecteur identifie les cœurs de chaque lobe, puis attribue les lignes et les masques à leur région. Cela couvre aussi une double bulle coupée en haut et en bas : chaque lobe est évalué séparément, sans rejeter tout l’ensemble.
- L’encre **colorée, notamment rouge avec ombre ou dégradé**, est distinguée du fond. Le rendu reprend une couleur lisible proche de l’encre source ; les grandes inscriptions utilisent une famille d’affichage et ne sont plus arbitrairement limitées à 48 pixels. Le fond sous une inscription colorée est restauré localement, plutôt que recouvert d’un aplat blanc qui écraserait une nuance ou une illustration visible dans la bulle. Vision fournit aussi les positions typographiques pour éviter de prendre plusieurs lignes pour une seule lettre géante. Les masques restent limités aux zones sûres : une illustration ou une texture réellement indéterminée n’est pas effacée pour simuler un résultat.
- Les textures, dégradés importants, aplats ouverts sur plusieurs bords, zones trop petites ou incertaines gardent **leur original**, avec la traduction complète sous la page. Ce n’est pas une détection universelle : le lecteur ne masque pas l’illustration avec un rectangle arbitraire et ne tronque pas discrètement le texte.
- Le texte français est mesuré avec Canvas, réparti en lignes et réduit si nécessaire, puis recalculé au redimensionnement. La police, la graisse et la taille source sont des **approximations**, pas une identification exacte de police scannée. Après une mise à jour du détecteur, rechargez le chapitre ou réimportez vos pages : les anciens résultats OCR ne sont pas réutilisés.

Une relecture reste utile : OCR, segmentation, noms non configurés et traduction automatique peuvent se tromper. Les tests utilisent des dialogues synthétiques originaux, pas des chapitres récupérés sur Internet.

## Réseau et confidentialité

Le serveur écoute **uniquement sur `127.0.0.1`** par défaut. Les URL `file:`, identifiants dans une URL et appels à un serveur de traduction externe depuis l’interface sont refusés. Importer une image fonctionne sans connexion après installation ; ouvrir un chapitre contacte nécessairement le site et ses hébergeurs d’images.

Les sites nécessitant une connexion, un lecteur JavaScript, une protection anti-bot ou un DRM ne sont pas contournés. Un refus du site (notamment **403 / Cloudflare**) ou l’absence d’images affiche une erreur en français près du lien, sans effacer les pages déjà ouvertes. **Ouvrir le site** donne accès au lecteur original dans votre navigateur ; **Importer des pages** permet de choisir des images que vous avez le droit d’utiliser. Cette récupération ne débloque pas l’extraction automatique du site protégé. La navigation précédent/suivant n’est proposée que pour les formats de chapitre explicites, pas pour un identifiant numérique arbitraire.

Pour tester sur un téléphone du **même réseau privé de confiance**, exposez volontairement le lecteur :

```sh
WEBTOON_LENS_PREVIEW_HOST=0.0.0.0 bash ci/Start-PhonePreview.sh
```

Puis ouvrez `http://ADRESSE_LOCALE_DU_MAC:8787`. Cette option n’ajoute ni authentification ni TLS : ne l’utilisez pas sur un Wi-Fi public et ne redirigez pas le port sur Internet. Ollama demeure sur loopback. Les caches locaux contiennent les textes OCR/traduits ; n’y mettez pas de documents sensibles si d’autres personnes utilisent le même compte système.

Variables utiles : `WEBTOON_LENS_PREVIEW_PORT`, `WEBTOON_LENS_PREVIEW_HOST`, `WEBTOON_LENS_CACHE`, `WEBTOON_LENS_RUNTIME`, `WEBTOON_LENS_OLLAMA_MODEL`, `WEBTOON_LENS_OLLAMA_URL`. Un changement de modèle exige de relancer le serveur.

## Tests reproductibles

Le lecteur et Ollama doivent fonctionner pour les tests réels :

```sh
.runtime/venv/bin/python -m pip install -r PhonePreview/requirements-test.txt
.runtime/venv/bin/python -m playwright install chromium
.runtime/venv/bin/python -m unittest discover -s Tests/PhonePreview -p 'test_*.py' -v
.runtime/venv/bin/python Tests/PhonePreview/runtime_check.py .runtime/evidence
.runtime/venv/bin/python Tests/PhonePreview/browser_check.py .runtime/evidence
.runtime/venv/bin/python Tests/PhonePreview/access_check.py .runtime/evidence
.runtime/venv/bin/python Tests/PhonePreview/translation_recovery_check.py .runtime/evidence
.runtime/venv/bin/python Tests/PhonePreview/coverage_check.py .runtime/evidence
.runtime/venv/bin/python Tests/PhonePreview/scan_regression_check.py .runtime/evidence
.runtime/venv/bin/python Tests/PhonePreview/benchmark.py .runtime/evidence
```

Le premier test couvre glossaire, limites, réponses invalides, cache, chinois traditionnel, alpha du masque, couleurs et conservation du dessin. Le second exécute réellement OCR et traduction EN/ZH, compare auto / langue forcée, vérifie les noms personnalisés, compare les masques aux formes originales des bulles colorées et conserve les réponses/timings. Le troisième utilise Chromium : imports, original, glossaire persistant, redimensionnement 1 280 → 390 px, texte français très long, petites/grandes pages, bulles noires hérissées et fonds bleu/jaune/rose/rouge, navigation et erreurs. Il vérifie couleurs réellement affichées, largeur/hauteur mesurées, débordement DOM et **pixels modifiés hors masque**. Captures et mesures sont conservées dans `.runtime/evidence/`.

Les fixtures sont générées par `Tests/PhonePreview/fixtures.py`. Sur un autre système, indiquez `WEBTOON_TEST_EN_FONT` et `WEBTOON_TEST_ZH_FONT` si les polices proposées n’existent pas.

`access_check.py` fait recevoir un vrai refus HTTP 403 au backend depuis un serveur local de test : message et actions accessibles, ancien chapitre intact, reprise par import et traduction chinoise réelle. Il couvre aussi l’absence d’images, les erreurs HTML anciennes, les URL invalides et l’annulation d’une ouverture pendant un import ou un changement de langue.

`translation_recovery_check.py` traduit une annonce originale sans bulle fermée, vérifie que son français est visible sous l’image, puis force une erreur sur la première page d’un import. La seconde doit continuer à se traduire, et la reprise doit conserver les dialogues déjà affichés.

`coverage_check.py` vérifie les petites zones restantes, la fin des pages, les dialogues répétés et la réutilisation des meilleurs masques. Il importe cinq pages et attend leurs quinze dialogues sans défiler, puis contrôle une bulle blanche à contour fin sur bureau et mobile, avec comparaison des pixels hors masque.

`scan_regression_check.py` vérifie deux bulles reliées, un texte rouge ombré, une page de 6 200 pixels traduite jusqu’au dernier dialogue sans défiler, puis une erreur contrôlée sur un seul dialogue : les suivants continuent et la reprise ne retraduit que l’échec. Le contexte du modèle provient des dialogues voisins, pas systématiquement du bas de la page. Les interjections partagées par le français et l’anglais, comme « Ah ! Ah ! Ah ! », ne sont pas confondues avec une phrase anglaise recopiée.

### Première bulle et chargement progressif

Le préchauffage charge le modèle **sans générer un dialogue**, avec le même contexte de 4 096 tokens que la traduction. Il peut être renouvelé après une période d’inactivité, au lieu d’être définitivement désactivé après le premier lancement. Dès qu’une image arrive, son analyse démarre sans attendre le délai de défilement. Après chaque fenêtre, le lecteur redonne la priorité à la zone actuellement lue ; les autres pages restent traitées en arrière-plan. Trois premières images bloquées n’empêchent plus le chargement des suivantes.

Mesure comparative sur le Mac testé : trois imports de cinq exemplaires de la même page synthétique anglaise, modèle déjà démarré et **caches applicatifs vierges à chaque essai**. Les répétitions bénéficient du cache créé pendant le chapitre ; ce n’est donc pas une mesure de quinze dialogues différents. Médianes observées, pas garanties pour tous les chapitres :

| Mesure navigateur | Avant | Après |
|---|---:|---:|
| Première bulle ajustée visible | 3,04 s | 0,82 s |
| Quinze dialogues du chapitre terminés | 17,31 s | 4,66 s |

Le contrôle vérifie que la première traduction n’est pas un cache hit et que les quinze dialogues finissent tous. Les relevés locaux sont dans `latency-before.json` et `latency-after.json`. Un site lent, un modèle réellement déchargé ou un OCR plus difficile ajoute son propre délai.

### Mesures effectuées sur le Mac M5 / 24 Go

Trois dialogues par page, modèle déjà démarré, helper Vision compilé, caches applicatifs initialement vierges. Ces mesures ne sont pas un engagement de vitesse pour tous les chapitres :

| Page synthétique | OCR sans cache | Traduction sans cache | Chaîne complète | Même page en cache |
|---|---:|---:|---:|---:|
| Anglais | 206 ms | 1 811 ms | 2,02 s | 7,9 ms |
| Chinois | 1 461 ms | 1 867 ms | 3,33 s | 7,9 ms |

Dans Chromium, une répétition des deux imports avec caches chauds a affiché le premier dialogue en **0,79 s** et les deux pages en **1,16 s** (chargement, OCR HTTP et affichage compris). Six bulles tenaient à 1 280 et 390 px ; sept dialogues de page longue tenaient également. La petite page a conservé un texte sur l’illustration au lieu de l’effacer. La comparaison de pixels sur la première page traduite a trouvé **0 pixel modifié hors masque**, et les tests n’ont détecté ni débordement DOM ni erreur JavaScript. Les réponses et mesures sont dans les fichiers `benchmark-results.json`, `pipeline-results.json` et `browser-results.json` du dossier d’évidence généré.

## Moteurs portables

L’implémentation iOS et son contrat `POST /v1/webtoon/translate` (`segments`, `glossary`, identifiants, coordonnées) sont conservés. Le backend assemble ses réponses JSON lui-même : le petit modèle traduit un dialogue à la fois, sans contrainte JSON qui dégrade sa traduction.

Hors macOS, les moteurs Tesseract / RapidOCR / EasyOCR existants restent disponibles. Installez les dépendances de `requirements.txt`, puis le moteur et ses langues requis ; la procédure Windows historique est dans [WINDOWS_NO_MAC.md](../WINDOWS_NO_MAC.md). Ollama Instruct reste le choix recommandé. Le repli Argos local existant peut traduire si ses modèles sont installés, mais il refuse explicitement les termes littéraux qu’il ne peut pas garantir. Aucun modèle portable lourd n’est téléchargé automatiquement par le lecteur.
