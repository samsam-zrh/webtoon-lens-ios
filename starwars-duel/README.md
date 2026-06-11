# Star Wars — Duel Spatial

Un jeu de combat spatial 1 contre 1 dans l'univers Star Wars, développé avec
**Godot 4.4**. Choisis ton pilote — **Dark Vador** (Chasseur TIE),
**Anakin Skywalker** (Intercepteur Jedi) ou **Han Solo** (Faucon Millenium) —
et affronte un adversaire contrôlé par l'IA dans un champ d'astéroïdes, sous
l'ombre d'un Star Destroyer impérial.

Les vaisseaux sont de **vrais modèles 3D** créés par des artistes de la
communauté (Sketchfab / Poly Pizza) sous licences Creative Commons — voir
[CREDITS.md](CREDITS.md).

## Jouer (Windows)

Télécharger les **deux** archives du dossier `build/` :
`StarWarsDuel-Windows-1de2.zip` (le programme) et
`StarWarsDuel-Windows-2de2.zip` (les données). Extraire les deux **dans le
même dossier** (on obtient `StarWarsDuel.exe` + `StarWarsDuel.pck` côte à
côte), puis double-cliquer sur `StarWarsDuel.exe`. Aucune installation
requise. Si Windows SmartScreen s'affiche : « Informations complémentaires »
→ « Exécuter quand même » (binaire non signé, normal pour un jeu amateur).

## Lancer depuis les sources (toutes plateformes)

1. Télécharger [Godot 4.4.1](https://godotengine.org/download) (gratuit, ~100 Mo).
2. Ouvrir Godot → **Importer** → sélectionner le dossier `starwars-duel/`
   (le fichier `project.godot`).
3. Appuyer sur **F5** (ou le bouton ▶) pour jouer.

Pour recompiler un `.exe` : Projet → Exporter → Windows Desktop
(les export templates seront proposés au téléchargement par Godot).

## Commandes

| Action | Touche |
|---|---|
| Piloter (tangage / lacet) | Souris |
| Tirer | Clic gauche ou Espace |
| Boost | Maj |
| Accélérer / ralentir | W / S (Z / S sur AZERTY) |
| Tonneau gauche / droite | A / D (Q / D sur AZERTY) |
| Pause | Échap |

## Mode PERSONNAGES (style Battlefront)

Dans le menu, bouton **PERSONNAGES** : duel au sol dans un couloir impérial,
caméra à l'épaule. Luke Skywalker et le Stormtrooper sont de vrais modèles
3D **animés** (combos de sabre, parades, courses, morts) ; Dark Vador est un
modèle réaliste avec démarche et respiration mécanique.

- ZQSD : se déplacer (la caméra suit la souris)
- Clic gauche : attaque — **ré-appuie pendant le coup pour enchaîner le
  combo (3 frappes)**
- Clic droit : parade (bloque les coups de sabre → gerbe d'étincelles,
  dévie les tirs de blaster)
- Maj : esquive (dash)

## Gameplay

- Duel à mort : fais tomber la coque de l'adversaire à zéro.
- Le **réticule jaune** (losange) indique où tirer pour toucher une cible en
  mouvement — vise-le, pas le vaisseau.
- Le boost consomme une jauge qui se recharge ; sers-t'en pour fuir quand
  l'ennemi est dans ton dos.
- Évite les astéroïdes : 18 points de dégâts par impact. Une collision
  frontale entre vaisseaux fait mal aux deux.
- L'arène fait 1,6 km de rayon — au-delà, ton vaisseau fait demi-tour
  automatiquement.
- Chaque vaisseau a son caractère : le TIE est vif, l'Intercepteur Jedi est
  le plus agile, le Faucon encaisse (135 de coque) et frappe fort.

## Notes techniques

- Moteur : Godot 4.4.1, rendu Forward+ (Vulkan), bloom/glow, ciel procédural
  (étoiles + nébuleuse en shader), planète gazeuse procédurale.
- Tous les effets sonores sont générés procéduralement (synthèse).
- L'IA a trois états (poursuite, évasion, dégagement) et anticipe ta
  trajectoire en visant avec de l'erreur selon son niveau.

## Licence et crédits

Projet de fan non commercial. Star Wars est une propriété de
Lucasfilm/Disney. Les modèles 3D appartiennent à leurs auteurs respectifs —
licences et liens dans [CREDITS.md](CREDITS.md). Le modèle de l'Intercepteur
Jedi est sous licence **CC-BY-NC** : toute redistribution de ce jeu doit
rester non commerciale.

## Musique personnalisée

Le jeu peut jouer **ta propre bande-son** à la place des musiques libres
incluses. Crée un dossier `music` **à côté de `StarWarsDuel.exe`** et
déposes-y tes fichiers (`.mp3`, `.ogg` ou `.wav`) nommés :

| Fichier | Utilisé pour |
|---|---|
| `menu.mp3` | le menu principal |
| `tension.mp3` | l'approche, avant le contact |
| `battle.mp3` | le combat |
| `finale.mp3` | la fin de duel (un des deux passe sous 35 % de vie) |

Chaque fichier est optionnel : ceux qui manquent utilisent la musique
incluse. Les fichiers restent sur ta machine — ils ne font pas partie du
jeu distribué.
