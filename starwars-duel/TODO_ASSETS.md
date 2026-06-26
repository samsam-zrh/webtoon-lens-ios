# Pack d'assets joueur : « Star Wars Virtual Museum » (5,8 Go)

Lien Drive (partage public actif) :
https://drive.google.com/file/d/1YwKqKR0gW_qEbSxL7-xltTL8EkYx7WLw/view

C'est un build Unity : extraire avec `tools/unity_inventory.py` (inventaire),
`tools/unity_tree_export.py "<GameObject>" <outdir>` (personnage complet),
`tools/unity_export.py <filtre>` (par nom). Télécharger via `gdown <id>`,
dézipper dans /tmp/pack_x.

## Fait
- ✅ Luke Skywalker (ROTJ) → `assets/models/characters/luke.glb`
  (tools/build_luke_rig.py, sabre procédural « luke_blade » lié à la main)

## File d'attente (GameObjects identifiés dans level3/sharedassets)
- « Chewbacca », « EmperorPalpatine », « Han Solo HD@Idle », « Kylo Ren »,
  « Mace Windu », « General Grievous », « Boba Fett », « Leia Full Body@Idle »
  → même pipeline que Luke (tree_export + build_luke_rig adapté).
- Décor : « Han Solo carbonite » (prop iconique), « death_star_2_inside ».
- Sons : « Lightsaber sound effect - medium », « Footstep01/02 », « QVADRBRT »
  (respiration Vador), bips R2 (QR2_D2S*) — via tools/unity_export.py.
  (Les pistes musicales John Williams du pack ne sont pas intégrées au repo.)
