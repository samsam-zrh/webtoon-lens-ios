# Pack d'assets fourni par le joueur (en attente)

Lien Google Drive (~5 Go, modèles 3D de personnages Star Wars + sons) :
https://drive.google.com/file/d/1YwKqKR0gW_qEbSxL7-xltTL8EkYx7WLw/view

État : le partage doit être passé en « Tous les utilisateurs disposant du
lien » pour que le téléchargement fonctionne (actuellement : accès restreint,
Google renvoie une page de connexion).

Plan d'intégration une fois le pack accessible :
1. Inventaire complet (modèles par format, sons, textures).
2. Personnages humanoïdes → pipeline de re-rigging (tools/build_vader_rig.py)
   vers le squelette animé commun ; priorité : Han Solo, Palpatine, Chewbacca.
3. Sons de sabre/blaster courts → remplacement des WAV synthétiques.
4. Décors/props → habillage des arènes (salle du trône, hangar).
