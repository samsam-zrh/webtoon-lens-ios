class_name ShipsDB

# Roster of playable pilots and their ships.
# model_rot: extra Y rotation (radians) so the model's nose points to -Z (Godot forward).

const PILOTS := {
	"vader": {
		"pilot": "Dark Vador",
		"ship": "Chasseur TIE",
		"quote": "Je trouve votre manque de foi déplorable.",
		"model": "res://assets/models/tie/scene.gltf",
		"model_rot": PI,
		"target_len": 9.0,
		"laser_color": Color(0.3, 1.0, 0.35),
		"engine_color": Color(0.55, 0.85, 1.0),
		"hp": 95.0,
		"max_speed": 62.0,
		"boost_speed": 125.0,
		"turn_rate": 1.65,
		"fire_interval": 0.16,
		"laser_damage": 7.0,
		"ai_skill": 0.85,
	},
	"anakin": {
		"pilot": "Anakin Skywalker",
		"ship": "Intercepteur Jedi",
		"quote": "C'est là que la fête commence.",
		"model": "res://assets/models/jedi/scene.gltf",
		"model_rot": PI,
		"target_len": 10.0,
		"laser_color": Color(0.35, 0.6, 1.0),
		"engine_color": Color(1.0, 0.8, 0.3),
		"hp": 90.0,
		"max_speed": 66.0,
		"boost_speed": 132.0,
		"turn_rate": 1.8,
		"fire_interval": 0.15,
		"laser_damage": 6.5,
		"ai_skill": 0.9,
	},
	"han": {
		"pilot": "Han Solo",
		"ship": "Faucon Millenium",
		"quote": "Ne me dites jamais quelles sont mes chances !",
		"model": "res://assets/models/falcon/scene.gltf",
		"model_rot": PI,
		"target_len": 14.0,
		"laser_color": Color(1.0, 0.25, 0.2),
		"engine_color": Color(0.6, 0.8, 1.0),
		"hp": 135.0,
		"max_speed": 58.0,
		"boost_speed": 118.0,
		"turn_rate": 1.35,
		"fire_interval": 0.2,
		"laser_damage": 9.0,
		"ai_skill": 0.8,
	},
}

static func get_cfg(id: String) -> Dictionary:
	return PILOTS[id]
