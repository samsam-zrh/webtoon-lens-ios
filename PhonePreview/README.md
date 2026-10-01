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

- Les imports sont limités à **20 Mo par page**. L’API limite les requêtes à 30 Mo et à 32 dialogues par traduction. Les pages longues sont analysées par fenêtres, avec un chevauchement pour ne pas couper les bulles ordinaires. Les premiers dialogues arrivent avant la fin du chapitre.
- **Voir l’original** masque les remplacements. **Lire les dialogues et leur original**, sous chaque image, donne la traduction intégrale et permet de comparer l’OCR.
- Le glossaire contient **188 concepts originaux** anglais/chinois, catégories et indications de sens. OpenCC fournit les variantes traditionnelles. Les termes ordinaires sont des indications contextualisées, avec accords possibles ; quelques concepts non ambigus sont littéraux. Les corrections par série sont prioritaires et vérifiées littéralement. Ajoutez les noms de personnages, lieux ou techniques propres à votre série : ce lexique n’est pas un dictionnaire de tous les webtoons.
- Les corrections restent dans le stockage local de ce navigateur, séparées par le champ **Série**. Leur modification relance la traduction. Le cache tient compte du modèle, du dialogue, du contexte et des termes réellement utilisés : une correction pertinente ne réutilise pas l’ancienne traduction.
- Le masque alpha ne remplit qu’un **intérieur clair fermé détecté**, en conservant le contour. Le texte français est mesuré avec Canvas, réparti en lignes et réduit si nécessaire, puis recalculé au redimensionnement. La police, la graisse et la taille source sont des **approximations**, pas une identification exacte de police scannée.
- Si la zone est colorée, texturée, ouverte, trop petite ou non fiable, **l’image reste intacte** et la traduction complète est disponible sous la page. Le lecteur ne masque pas l’illustration avec un rectangle arbitraire et ne tronque pas discrètement le texte.

Une relecture reste utile : OCR, segmentation, noms non configurés et traduction automatique peuvent se tromper. Les tests utilisent des dialogues synthétiques originaux, pas des chapitres récupérés sur Internet.

## Réseau et confidentialité

Le serveur écoute **uniquement sur `127.0.0.1`** par défaut. Les URL `file:`, identifiants dans une URL et appels à un serveur de traduction externe depuis l’interface sont refusés. Importer une image fonctionne sans connexion après installation ; ouvrir un chapitre contacte nécessairement le site et ses hébergeurs d’images.

Les sites nécessitant une connexion, un lecteur JavaScript, une protection anti-bot ou un DRM ne sont pas contournés. En cas d’échec, importez des pages que vous avez le droit d’utiliser. La navigation précédent/suivant n’est proposée que pour les formats de chapitre explicites, pas pour un identifiant numérique arbitraire.

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
.runtime/venv/bin/python Tests/PhonePreview/benchmark.py .runtime/evidence
```

Le premier test couvre glossaire, limites, réponses invalides, cache, chinois traditionnel et alpha du masque. Le second exécute réellement OCR et traduction EN/ZH, compare auto / langue forcée, vérifie les noms personnalisés et conserve les réponses/timings. Le troisième utilise Chromium : imports, original, glossaire persistant, redimensionnement 1 280 → 390 px, texte français très long, petites/grandes pages, navigation et erreurs. Il vérifie largeur/hauteur mesurées, débordement DOM et **pixels modifiés hors masque**. Captures et mesures sont conservées dans `.runtime/evidence/`.

Les fixtures sont générées par `Tests/PhonePreview/fixtures.py`. Sur un autre système, indiquez `WEBTOON_TEST_EN_FONT` et `WEBTOON_TEST_ZH_FONT` si les polices proposées n’existent pas.

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
