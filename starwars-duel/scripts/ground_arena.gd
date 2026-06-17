class_name GroundArena
extends Node3D

# Battlefront-style 1v1 character duel inside an Imperial throne room
# (Death Star II inspired).
# Real animated character models (see CREDITS.md), over-shoulder camera,
# saber combos, blocking, clashes and blaster fire.

signal request_restart
signal request_menu
signal request_next

const ROSTER := {
	"luke": {
		"name": "Luke Skywalker", "type": "jedi", "melee": true,
		"model": "res://assets/models/characters/luke.glb",
		"model_yaw": PI, "model_scale": 1.0,
		"saber_color": Color(0.3, 1.0, 0.4),
		"blade_mesh": "luke_blade",
		"blade_always": true,
		"hp": 120.0, "speed": 5.6, "dmg": 16.0, "reach": 2.4, "lunge": 5.5, "turn_speed": 13.0,
		"attack_time": 0.7, "attack_anim_speed": 1.45, "attack_move_factor": 0.24,
		"ai_skill": 0.55, "ai_block_chance": 0.4,
		"quote": "Je suis un Jedi, comme mon père avant moi.",
		"anims": {
			"idle": "01_IdleArmed", "run_f": "03_RunningArmed", "run_b": "08_RunBack",
			"run_l": "10_RunLeft", "run_r": "09_RunRight",
			"attack": ["06_OneHandCombo01", "06_OneHandCombo02", "06_OneHandCombo03"],
			"block": "17_Block", "hit": "20_Hit", "death": "07_Death",
		},
	},
	"vader": {
		"name": "Dark Vador", "type": "jedi", "variant": "vader", "melee": true,
		"model": "res://assets/models/characters/vader.glb",
		"model_yaw": PI, "model_scale": 1.06,
		"saber_color": Color(1.0, 0.12, 0.08),
		"blade_mesh": "DARTH_Sabel svart_0",
		"blade_extra": ["DARTH_Laser_0"],
		"blade_always": true,
		"hp": 160.0, "speed": 4.6, "dmg": 22.0, "reach": 2.5, "lunge": 4.5, "turn_speed": 9.0,
		"attack_time": 0.7, "attack_anim_speed": 1.15, "attack_move_factor": 0.24,
		"ai_skill": 0.5, "ai_block_chance": 0.35,
		"quote": "Je trouve votre manque de foi déplorable.",
		"anims": {
			"idle": "01_IdleArmed", "run_f": "03_RunningArmed", "run_b": "08_RunBack",
			"run_l": "10_RunLeft", "run_r": "09_RunRight",
			"attack": ["06_OneHandCombo01", "06_OneHandCombo02", "06_OneHandCombo03"],
			"block": "17_Block", "hit": "20_Hit", "death": "07_Death",
		},
	},
	"kenobi": {
		"name": "Cullen", "type": "jedi", "variant": "kenobi", "melee": true,
		"model": "res://assets/models/characters/jedi.glb",
		"model_yaw": PI, "model_scale": 1.0,
		"saber_color": Color(0.3, 0.6, 1.0),
		"hp": 130.0, "speed": 5.2, "dmg": 17.0, "reach": 2.4, "turn_speed": 12.0,
		"attack_time": 0.7, "attack_anim_speed": 1.35, "attack_move_factor": 0.24,
		"ai_skill": 0.6, "ai_block_chance": 0.65,
		"quote": "La Force sera avec toi. Toujours.",
		"anims": {
			"idle": "01_IdleArmed", "run_f": "03_RunningArmed", "run_b": "08_RunBack",
			"run_l": "10_RunLeft", "run_r": "09_RunRight",
			"attack": ["06_OneHandCombo01", "06_OneHandCombo02", "06_OneHandCombo03"],
			"block": "17_Block", "hit": "20_Hit", "death": "07_Death",
		},
	},
	"trooper": {
		"name": "Stormtrooper", "type": "shooter", "melee": false,
		"model": "res://assets/models/characters/trooper.glb",
		"model_yaw": PI, "model_scale": 1.0,
		"saber_color": Color(1.0, 0.3, 0.2),
		"hp": 90.0, "speed": 3.1, "dmg": 8.0, "turn_speed": 11.0,
		"attack_time": 0.5, "attack_move_factor": 0.8,
		"ai_skill": 0.5, "ai_block_chance": 0.0,
		"quote": "Vous êtes en état d'arrestation, au nom de l'Empire !",
		"anims": {
			"idle": "20_FightIdle", "run_f": "14_RunForward", "run_b": "19_RunBack",
			"run_l": "17_RunLeft", "run_r": "18_RunRight",
			"attack": ["21_ShootStanding"],
			"block": "20_FightIdle", "hit": "26_HitStanding", "death": "27_DeathShot",
		},
	},
	"sith": {
		"name": "Sith Trooper", "type": "shooter", "variant": "sith", "melee": false,
		"model": "res://assets/models/characters/trooper.glb",
		"model_yaw": PI, "model_scale": 1.0,
		"saber_color": Color(1.0, 0.3, 0.2),
		"hp": 130.0, "speed": 3.6, "dmg": 11.0, "turn_speed": 12.0,
		"attack_time": 0.45, "attack_move_factor": 0.8,
		"ai_skill": 0.7, "ai_block_chance": 0.0,
		"quote": "L'Ordre Final ne connaît pas la pitié.",
		"anims": {
			"idle": "20_FightIdle", "run_f": "14_RunForward", "run_b": "19_RunBack",
			"run_l": "17_RunLeft", "run_r": "18_RunRight",
			"attack": ["21_ShootStanding"],
			"block": "20_FightIdle", "hit": "26_HitStanding", "death": "27_DeathShot",
		},
	},
}

var player: GroundFighter
var enemy: GroundFighter          # primary opponent (nearest alive)
var enemies: Array[GroundFighter] = []
var camera: Camera3D
var _spring: SpringArm3D
var _cam_pivot: Node3D
var _cam_pitch_node: Node3D
var _cam_yaw := 0.0
var _cam_pitch := -0.12
var _mouse_idle := 0.0       # seconds since the last look input
var _lock_active := false    # soft lock-on engaged this frame

var _started := false
var _ended := false
var _shake := 0.0
var _hitmark_t := 0.0
var _shake_t := 0.0
var music: MusicDirector
var campaign_next := false   # set by main: a "next chapter" exists after victory
var campaign_mode := false
var _intro_done := false
var _post_mat: ShaderMaterial
var _cine_pivot: Node3D
var _cine_target: GroundFighter
var _hud: Control
var _msg: Label
var _bolts: Array = []
var _trails: Dictionary = {}  # fighter -> {points: Array, mesh: MeshInstance3D}

func start(player_id: String, enemy_id: String, enemy_mods: Dictionary = {}, opts: Dictionary = {}) -> void:
	theme = opts.get("theme", "throne")
	_build_corridor()
	player = _spawn(player_id, true, Vector3(0, 0.1, 12), 0.0)
	player.died.connect(_on_died)
	var count: int = opts.get("count", 1)
	for i in count:
		var x := (i - (count - 1) / 2.0) * 3.2
		var e := _spawn(enemy_id, false, Vector3(x, 0.1, -12), PI, enemy_mods)
		e.enemy = player
		e.died.connect(_on_died)
		enemies.append(e)
	enemy = enemies[0]
	player.enemy = enemy

	_cam_pivot = Node3D.new()
	add_child(_cam_pivot)
	_cam_pitch_node = Node3D.new()
	_cam_pitch_node.position = Vector3(0.55, 0, 0)
	_cam_pivot.add_child(_cam_pitch_node)
	_spring = SpringArm3D.new()
	_spring.spring_length = 2.9
	_spring.margin = 0.25
	_spring.collision_mask = 1
	_cam_pitch_node.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = GameSettings.fov
	camera.near = 0.1
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 24.0
	attrs.dof_blur_far_transition = 16.0
	attrs.dof_blur_amount = 0.055
	camera.attributes = attrs
	_spring.add_child(camera)
	camera.make_current()

	_build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	music = MusicDirector.new()
	add_child(music)
	music.setup(self)
	_play_intro()

# ------------------------------------------------- cinematic duel intro
# Three shots: arena sweep, the opponent, the hero. Click skips.

var _intro_cam: Camera3D
var _subtitle: Label

func _play_intro() -> void:
	_intro_cam = Camera3D.new()
	_intro_cam.fov = 50.0
	add_child(_intro_cam)
	_intro_cam.make_current()
	# soft key light riding with the intro camera so the close-ups read
	var fill := OmniLight3D.new()
	fill.light_energy = 1.6
	fill.omni_range = 7.0
	fill.light_color = Color(0.85, 0.88, 1.0)
	fill.position = Vector3(0.4, 0.3, 0.2)
	_intro_cam.add_child(fill)
	var efwd := Vector3(-sin(enemy.face_yaw), 0, -cos(enemy.face_yaw))
	var pfwd := Vector3(-sin(player.face_yaw), 0, -cos(player.face_yaw))
	var tw := create_tween()
	# shot 1: glide along the viewport, the whole arena in frame
	_intro_shot(Vector3(-12, 4.2, -13), Vector3(0, 1.0, 0))
	tw.tween_method(func(t: float) -> void:
		if _intro_done: return
		_intro_cam.position = Vector3(-12, 4.2, -13).lerp(Vector3(-5, 2.6, -15), t)
		_intro_cam.look_at(Vector3(0, 1.0, 0)),
		0.0, 1.0, 1.7)
	# shot 2: the opponent, low angle
	tw.tween_callback(func() -> void:
		_intro_shot(enemy.global_position + efwd * 3.0 + Vector3(0, 1.1, 0),
			enemy.global_position + Vector3(0, 1.5, 0))
		_set_subtitle("« %s »" % enemy.cfg["quote"]))
	tw.tween_method(func(t: float) -> void:
		if _intro_done: return
		_intro_cam.position = enemy.global_position + efwd * (3.0 - t * 0.9) + Vector3(t * 0.7, 1.1 + t * 0.3, 0)
		_intro_cam.look_at(enemy.global_position + Vector3(0, 1.5, 0)),
		0.0, 1.0, 1.9)
	# shot 3: the hero, over the blade
	tw.tween_callback(func() -> void:
		_intro_shot(player.global_position + pfwd * 2.6 + Vector3(-0.6, 1.3, 0),
			player.global_position + Vector3(0, 1.4, 0))
		_set_subtitle("« %s »" % player.cfg["quote"]))
	tw.tween_method(func(t: float) -> void:
		if _intro_done: return
		_intro_cam.position = player.global_position + pfwd * (2.6 - t * 0.7) + Vector3(-0.6 + t * 0.5, 1.3, 0)
		_intro_cam.look_at(player.global_position + Vector3(0, 1.4, 0)),
		0.0, 1.0, 1.7)
	tw.tween_callback(_end_intro)

func _intro_shot(pos: Vector3, target: Vector3) -> void:
	_intro_cam.position = pos
	_intro_cam.look_at_from_position(pos, target, Vector3.UP)

func _set_subtitle(t: String) -> void:
	if _subtitle == null:
		return
	_subtitle.text = t
	_subtitle.visible = t != ""

func _end_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	_set_subtitle("")
	if is_instance_valid(_intro_cam):
		_intro_cam.queue_free()
	camera.make_current()
	_show_msg("EN GARDE !")
	_started = true
	player.controls_enabled = true
	for e in enemies:
		e.controls_enabled = true
	for f: GroundFighter in [player] + enemies:
		if f.cfg["melee"]:
			f.play_sound("res://assets/audio/saber_on.wav", -4.0, randf_range(0.95, 1.05))

func _spawn(id: String, is_player: bool, pos: Vector3, yaw: float, mods: Dictionary = {}) -> GroundFighter:
	var f := GroundFighter.new()
	f.collision_layer = 2
	f.collision_mask = 3
	add_child(f)
	var cfg: Dictionary = ROSTER[id].duplicate(true)
	if mods.has("name"):
		cfg["name"] = mods["name"]
	for k in mods.get("mul", {}):
		cfg[k] = cfg[k] * mods["mul"][k]
	for k in mods.get("set", {}):
		cfg[k] = mods["set"][k]
	f.setup(cfg, is_player, self)
	f.global_position = pos
	f.face_yaw = yaw
	f.rotation.y = yaw
	if f.cfg["melee"]:
		var trail := MeshInstance3D.new()
		trail.mesh = ImmediateMesh.new()
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.vertex_color_use_as_albedo = true
		tm.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = tm
		add_child(trail)
		_trails[f] = {"points": [], "mesh": trail}
	return f

# --------------------------------------------- Imperial throne room arena
# Death Star II inspired duel chamber: mirror-black floor, panoramic viewport
# onto deep space (Star Destroyer on patrol), light columns and the throne.

var theme := "throne"       # "throne" or "hangar"

const ARENA_R := 14.0       # gameplay boundary (inside the walls)
const ROOM_R := 17.0        # octagon wall radius
const ROOM_H := 10.0

func _build_corridor() -> void:
	if theme == "bespin":
		_build_bespin_environment()
		_build_bespin()
		_build_dust()
		_build_boundary()
		var amb_b := AudioStreamPlayer.new()
		var wind: AudioStreamWAV = load("res://assets/audio/wind.wav").duplicate()
		wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wind.loop_end = wind.data.size() / 2
		amb_b.stream = wind
		amb_b.volume_db = -16.0
		amb_b.bus = "SFX"
		add_child(amb_b)
		amb_b.play()
		return
	if theme == "imperial":
		_build_imperial_environment()
		_build_imperial()
		_build_dust()
		var amb_i := AudioStreamPlayer.new()
		var hum_i: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
		hum_i.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hum_i.loop_end = hum_i.data.size() / 2
		amb_i.stream = hum_i
		amb_i.volume_db = -15.0
		amb_i.bus = "SFX"
		add_child(amb_i)
		amb_i.play()
		return
	if theme == "control":
		_build_control_environment()
		_build_control()
		_build_dust()
		_build_boundary()
		var amb_c := AudioStreamPlayer.new()
		var hum_c: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
		hum_c.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hum_c.loop_end = hum_c.data.size() / 2
		amb_c.stream = hum_c
		amb_c.volume_db = -15.0
		amb_c.bus = "SFX"
		add_child(amb_c)
		amb_c.play()
		return
	_build_environment()
	if theme == "hangar":
		_build_hangar()
		_build_holotable(Vector3(16.0, 0, -5.5))
		_build_mse_droid()
	else:
		_build_floor()
		_build_walls()
		_build_ceiling()
		_build_throne()
		_build_banners()
		_build_spectators()
		_build_holotable(Vector3(-11.5, 0, 11.5))
	_build_space_view()
	_build_dust()
	_build_boundary()

	var amb := AudioStreamPlayer.new()
	var hum: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
	hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.loop_end = hum.data.size() / 2
	amb.stream = hum
	amb.volume_db = -18.0
	amb.bus = "SFX"
	add_child(amb)
	amb.play()

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = load("res://assets/textures/milky_way.jpg")
	sm.energy_multiplier = 2.2
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.24, 0.31)
	env.ambient_light_energy = 2.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.32
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	var q: int = GameSettings.quality
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 1.4
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.5
	env.sdfgi_enabled = q >= 2
	env.volumetric_fog_enabled = q >= 1
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(0.55, 0.62, 0.8)
	env.volumetric_fog_emission = Color(0.02, 0.025, 0.045)
	env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Cold starlight pouring through the viewport (north side)
	var star := DirectionalLight3D.new()
	star.light_energy = 1.5
	star.light_color = Color(0.78, 0.84, 1.0)
	star.rotation = Vector3(-0.38, PI, 0.0)
	star.shadow_enabled = true
	star.directional_shadow_max_distance = 60.0
	star.shadow_blur = 1.0
	star.light_volumetric_fog_energy = 0.45
	add_child(star)

	# Ceiling well: soft white spot over the duel ground
	var well := SpotLight3D.new()
	well.position = Vector3(0, ROOM_H + 2.0, 0)
	well.rotation.x = -PI / 2.0
	well.spot_range = ROOM_H + 4.0
	well.spot_angle = 46.0
	well.light_energy = 7.5
	well.light_color = Color(0.85, 0.9, 1.0) if theme != "hangar" else Color(1.0, 0.95, 0.85)
	well.shadow_enabled = true
	well.light_volumetric_fog_energy = 1.2
	add_child(well)

	# Imperial red rim from the throne side
	var red := OmniLight3D.new()
	red.position = Vector3(0, 4.5, ROOM_R + 1.5)
	red.omni_range = 9.0
	red.light_energy = 0.7
	red.light_color = Color(1.0, 0.16, 0.1)
	red.light_volumetric_fog_energy = 1.4
	add_child(red)

	# Crisp local reflections for the mirror floor
	var probe := ReflectionProbe.new()
	probe.size = Vector3(ROOM_R * 2.2, ROOM_H + 6.0, ROOM_R * 2.2)
	probe.position = Vector3(0, ROOM_H * 0.5, 0)
	probe.intensity = 0.9
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

func _mat_panel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.34, 0.355, 0.42)
	m.albedo_texture = load("res://assets/textures/metal_plate_diff_2k.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/metal_plate_nor_gl_2k.jpg")
	m.normal_scale = 0.7
	m.roughness_texture = load("res://assets/textures/metal_plate_rough_2k.jpg")
	m.metallic = 0.55
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.42, 0.42, 0.42)
	return m

func _mat_emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi

# Loads a downloaded prop, scales it to target_len and rests it on the floor
# at pos (pos.y is the ground height the prop's base should sit on).
func _floor_prop(path: String, target_len: float, pos: Vector3, yaw: float, darken := Color(1, 1, 1)) -> Node3D:
	var m := ModelUtil.load_model(path, target_len, yaw)
	m.position = pos
	add_child(m)
	if darken != Color(1, 1, 1):
		ModelUtil.tint(m, darken)
	var ab := ModelUtil.compute_aabb(m, Transform3D.IDENTITY)
	m.position.y += pos.y - ab.position.y
	return m

# Tiles one Kenney Space Station Kit module (1×1 unit, origin centre-bottom,
# detailed face on +z) into a wall grid cell. Scaled to fill the cell and
# rotated to face the room interior (-z in the holder's local frame).
func _station_panel(holder: Node3D, nm: String, x: float, y: float, w: float, h: float, depth := 1.7) -> void:
	var scn := load("res://assets/models/station/%s.glb" % nm)
	if scn == null:
		return
	var inst: Node3D = scn.instantiate()
	inst.position = Vector3(x, y, 0)
	inst.rotation.y = PI
	inst.scale = Vector3(w * 1.02, h, depth)
	holder.add_child(inst)

func _build_floor() -> void:
	# Mirror-black deck
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = ROOM_R + 0.6
	cm.bottom_radius = ROOM_R + 0.6
	cm.height = 0.2
	cm.radial_segments = 8
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.035, 0.037, 0.045)
	fm.metallic = 0.85
	fm.roughness = 0.13
	fm.normal_enabled = true
	fm.normal_texture = load("res://assets/models/imperial_base_floor-normal.png")
	fm.normal_scale = 0.35
	fm.uv1_scale = Vector3(6, 6, 6)
	cm.material = fm
	mi.mesh = cm
	mi.position.y = -0.1
	mi.rotation.y = PI / 8.0
	add_child(mi)
	_collision_box(Vector3(0, -0.5, 0), Vector3(ROOM_R * 2.4, 1.0, ROOM_R * 2.4))
	var pcol := GPUParticlesCollisionBox3D.new()
	pcol.size = Vector3(ROOM_R * 2.4, 0.5, ROOM_R * 2.4)
	pcol.position.y = -0.25
	add_child(pcol)

	# Inlaid light rings around the duel center
	for spec in [[5.5, Color(1.0, 0.14, 0.08), 1.6], [10.5, Color(0.75, 0.85, 1.0), 1.2]]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = spec[0] - 0.06
		tm.outer_radius = spec[0] + 0.06
		tm.rings = 64
		tm.material = _mat_emissive(spec[1], spec[2])
		ring.mesh = tm
		ring.position.y = 0.012
		ring.scale.y = 0.08
		add_child(ring)

func _build_walls() -> void:
	# Octagonal room; the three north segments are one giant viewport
	var panel := _mat_panel()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.083, 0.10)
	dark.metallic = 0.4
	dark.roughness = 0.5
	var strip_w := _mat_emissive(Color(0.8, 0.88, 1.0), 2.6)
	var strip_r := _mat_emissive(Color(1.0, 0.15, 0.08), 1.3)
	var seg_w := 2.0 * ROOM_R * tan(PI / 8.0)
	for i in 8:
		var ang := TAU * i / 8.0
		var holder := Node3D.new()
		holder.position = Vector3(sin(ang) * ROOM_R, 0, -cos(ang) * ROOM_R)
		holder.rotation.y = -ang
		add_child(holder)
		var is_window := i in [7, 0, 1]  # north-facing segments
		if is_window:
			# sill, lintel and angled mullions (Death Star II viewport)
			_box(Vector3(seg_w, 1.1, 0.5), Vector3(0, 0.55, 0), panel, holder)
			_box(Vector3(seg_w, 1.6, 0.5), Vector3(0, ROOM_H - 0.8, 0), panel, holder)
			_box(Vector3(seg_w, 0.07, 0.46), Vector3(0, 1.14, 0), strip_w, holder)
			var n_mul := 4
			for k in n_mul + 1:
				var x := -seg_w / 2.0 + seg_w * k / float(n_mul)
				_box(Vector3(0.34, ROOM_H - 2.7, 0.5), Vector3(x, (ROOM_H - 0.0) / 2.0 - 0.6, 0), panel, holder)
		else:
			_box(Vector3(seg_w, ROOM_H, 0.5), Vector3(0, ROOM_H / 2.0, 0), panel, holder)
			# recessed dark band + light strips
			_box(Vector3(seg_w - 1.6, ROOM_H - 3.4, 0.2), Vector3(0, ROOM_H / 2.0 + 0.4, -0.22), dark, holder)
			_box(Vector3(0.12, ROOM_H - 3.8, 0.2), Vector3(-seg_w / 2.0 + 1.1, ROOM_H / 2.0 + 0.4, -0.26), strip_w, holder)
			_box(Vector3(0.12, ROOM_H - 3.8, 0.2), Vector3(seg_w / 2.0 - 1.1, ROOM_H / 2.0 + 0.4, -0.26), strip_w, holder)
			_box(Vector3(seg_w - 1.6, 0.1, 0.2), Vector3(0, 1.0, -0.26), strip_r, holder)
		# wall collision (glass barrier on the window segments)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(seg_w + 1.0, ROOM_H * 2.0, 0.5)
		cs.shape = shape
		sb.add_child(cs)
		holder.add_child(sb)

func _build_ceiling() -> void:
	var panel := _mat_panel()
	# Main slab with a circular light well in the middle
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = ROOM_R + 0.6
	cm.bottom_radius = ROOM_R + 0.6
	cm.height = 0.4
	cm.radial_segments = 8
	cm.material = panel
	mi.mesh = cm
	mi.position.y = ROOM_H + 0.2
	mi.rotation.y = PI / 8.0
	add_child(mi)
	# Light well ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.4
	tm.outer_radius = 4.0
	tm.rings = 48
	tm.material = _mat_emissive(Color(0.85, 0.9, 1.0), 3.2)
	ring.mesh = tm
	ring.position.y = ROOM_H - 0.05
	add_child(ring)
	# Radial beams
	for i in 8:
		var ang := TAU * i / 8.0 + PI / 8.0
		var beam := _box(Vector3(0.6, 0.7, ROOM_R - 4.0), Vector3.ZERO, panel)
		beam.position = Vector3(sin(ang) * (ROOM_R + 8.0) / 2.0, ROOM_H - 0.3, -cos(ang) * (ROOM_R + 8.0) / 2.0)
		beam.rotation.y = -ang

func _build_throne() -> void:
	# Raised dais with the throne, facing the viewport (south side)
	var panel := _mat_panel()
	var holder := Node3D.new()
	holder.position = Vector3(0, 0, ROOM_R - 1.2)
	add_child(holder)
	for i in 3:
		var r := 4.2 - i * 0.9
		var step := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.28
		cm.radial_segments = 8
		cm.material = panel
		step.mesh = cm
		step.position.y = 0.14 + i * 0.28
		holder.add_child(step)
		var lip := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.05
		tm.outer_radius = r + 0.05
		tm.rings = 40
		tm.material = _mat_emissive(Color(1.0, 0.16, 0.1), 1.5)
		lip.mesh = tm
		lip.position.y = 0.28 * (i + 1)
		lip.scale.y = 0.1
		holder.add_child(lip)
	# The throne itself: tall back, armrests, seat
	var seat_y := 3 * 0.28
	_box(Vector3(1.5, 0.5, 1.3), Vector3(0, seat_y + 0.25, 0.4), panel, holder)
	_box(Vector3(1.6, 3.0, 0.4), Vector3(0, seat_y + 1.5, 1.05), panel, holder)
	_box(Vector3(0.32, 0.85, 1.1), Vector3(-0.92, seat_y + 0.7, 0.45), panel, holder)
	_box(Vector3(0.32, 0.85, 1.1), Vector3(0.92, seat_y + 0.7, 0.45), panel, holder)
	_box(Vector3(1.2, 0.08, 0.1), Vector3(0, seat_y + 2.6, 0.84), _mat_emissive(Color(1.0, 0.2, 0.12), 2.0), holder)
	_collision_box(holder.position + Vector3(0, 1.0, 0.3), Vector3(4.5, 2.0, 3.0))

# --------------------------------------------------- Imperial hangar arena
# Rectangular deck open onto space through a force-field bay: parked TIE
# fighter, crate stacks, overhead light banks.

const HG_W := 21.0   # half width  (x)
const HG_D := 16.0   # half depth  (z)
const HG_H := 12.0

func _build_hangar() -> void:
	var panel := _mat_panel()
	# deck: brighter plates than the throne room, with guide markings
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.42, 0.43, 0.47)
	floor_mat.albedo_texture = load("res://assets/textures/metal_plate_diff_2k.jpg")
	floor_mat.normal_enabled = true
	floor_mat.normal_texture = load("res://assets/textures/metal_plate_nor_gl_2k.jpg")
	floor_mat.normal_scale = 0.6
	floor_mat.roughness_texture = load("res://assets/textures/metal_plate_rough_2k.jpg")
	floor_mat.metallic = 0.45
	floor_mat.roughness = 0.85
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_box(Vector3(HG_W * 2, 0.3, HG_D * 2), Vector3(0, -0.15, 0), floor_mat)
	_collision_box(Vector3(0, -0.5, 0), Vector3(HG_W * 2, 1.0, HG_D * 2))
	var pcol := GPUParticlesCollisionBox3D.new()
	pcol.size = Vector3(HG_W * 2, 0.5, HG_D * 2)
	pcol.position.y = -0.25
	add_child(pcol)
	# yellow guide lines + duel circle marking
	var line_y := _mat_emissive(Color(0.95, 0.75, 0.2), 0.9)
	for x in [-12.0, 12.0]:
		_box(Vector3(0.18, 0.02, HG_D * 2 - 4), Vector3(x, 0.012, 0), line_y)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 6.4
	tm.outer_radius = 6.55
	tm.rings = 64
	tm.material = _mat_emissive(Color(0.95, 0.75, 0.2), 0.9)
	ring.mesh = tm
	ring.position = Vector3(0, 0.012, 0)
	ring.scale.y = 0.06
	add_child(ring)

	# three solid walls with strip lights; the north side is the open bay
	var strip_w := _mat_emissive(Color(0.85, 0.9, 1.0), 2.4)
	var strip_r := _mat_emissive(Color(1.0, 0.15, 0.08), 1.3)
	for spec in [[Vector3(0, HG_H / 2.0, HG_D), Vector3(HG_W * 2, HG_H, 0.6), 0.0],
			[Vector3(-HG_W, HG_H / 2.0, 0), Vector3(0.6, HG_H, HG_D * 2), 0.0],
			[Vector3(HG_W, HG_H / 2.0, 0), Vector3(0.6, HG_H, HG_D * 2), 0.0]]:
		_box(spec[1], spec[0], panel)
		_collision_box(spec[0], spec[1])
	# wall pylons + lights on the side walls
	for side in [-1.0, 1.0]:
		for i in 5:
			var z := -HG_D + 5.0 + i * 6.5
			_box(Vector3(0.9, HG_H, 1.2), Vector3(side * (HG_W - 0.6), HG_H / 2.0, z), panel)
			_box(Vector3(0.14, HG_H - 4.0, 0.14), Vector3(side * (HG_W - 1.25), HG_H / 2.0, z), strip_w)
		_box(Vector3(0.12, 0.12, HG_D * 2 - 3), Vector3(side * (HG_W - 1.0), 1.0, 0), strip_r)
	# bay frame (north, open onto space) + faint force field
	_box(Vector3(HG_W * 2, 1.8, 1.2), Vector3(0, HG_H - 0.9, -HG_D), panel)
	_box(Vector3(2.2, HG_H, 1.2), Vector3(-HG_W + 1.1, HG_H / 2.0, -HG_D), panel)
	_box(Vector3(2.2, HG_H, 1.2), Vector3(HG_W - 1.1, HG_H / 2.0, -HG_D), panel)
	_box(Vector3(HG_W * 2 - 4.4, 0.1, 0.9), Vector3(0, 0.05, -HG_D), strip_w)
	var field := MeshInstance3D.new()
	var fq := PlaneMesh.new()
	fq.size = Vector2(HG_W * 2 - 4.4, HG_H - 1.8)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(0.45, 0.65, 1.0, 0.045)
	fq.material = fmat
	field.mesh = fq
	field.rotation.x = PI / 2.0
	field.position = Vector3(0, (HG_H - 1.8) / 2.0, -HG_D)
	add_child(field)
	_collision_box(Vector3(0, HG_H / 2.0, -HG_D), Vector3(HG_W * 2, HG_H * 2, 0.5))

	# ceiling: lattice beams + hanging light banks
	_box(Vector3(HG_W * 2, 0.5, HG_D * 2), Vector3(0, HG_H + 0.25, 0), panel)
	for i in 4:
		var z2 := -HG_D + 4.0 + i * 8.0
		_box(Vector3(HG_W * 2, 0.8, 0.5), Vector3(0, HG_H - 0.4, z2), panel)
		var bank := _box(Vector3(5.0, 0.18, 0.9), Vector3(0, HG_H - 0.9, z2), _mat_emissive(Color(1.0, 0.96, 0.85), 3.2))
		var bl := SpotLight3D.new()
		bl.rotation.x = -PI / 2.0
		bl.spot_range = HG_H + 2.0
		bl.spot_angle = 50.0
		bl.light_energy = 3.4
		bl.light_color = Color(1.0, 0.95, 0.82)
		bl.position = Vector3(0, -0.2, 0)
		bank.add_child(bl)

	# parked TIE fighter on its landing circle (south-west corner)
	var tie := ModelUtil.load_model("res://assets/models/tie/scene.gltf", 8.5, 0.9)
	var tb := ModelUtil.compute_aabb(tie, Transform3D.IDENTITY)
	tie.position = Vector3(-13.5, -tb.position.y + 0.05, 9.5)
	add_child(tie)
	_collision_box(Vector3(-13.5, 2.5, 9.5), Vector3(7.0, 5.0, 7.0))
	var tring := MeshInstance3D.new()
	var trm := TorusMesh.new()
	trm.inner_radius = 5.2
	trm.outer_radius = 5.35
	trm.rings = 48
	trm.material = _mat_emissive(Color(0.85, 0.9, 1.0), 1.2)
	tring.mesh = trm
	tring.position = Vector3(-13.5, 0.012, 9.5)
	tring.scale.y = 0.06
	add_child(tring)

	# real Rebel X-wing parked on the east landing pad (high-detail model)
	var xw: Node3D = load("res://assets/models/props/xwing.glb").instantiate()
	xw.position = Vector3(14.0, 1.37, 8.0)
	xw.rotation.y = -0.6
	add_child(xw)
	_collision_box(Vector3(14.0, 1.5, 8.0), Vector3(9.0, 3.0, 10.0))
	var xring := MeshInstance3D.new()
	var xrm := TorusMesh.new()
	xrm.inner_radius = 6.0
	xrm.outer_radius = 6.15
	xrm.rings = 48
	xrm.material = _mat_emissive(Color(0.95, 0.6, 0.2), 1.0)
	xring.mesh = xrm
	xring.position = Vector3(14.0, 0.012, 8.0)
	xring.scale.y = 0.06
	add_child(xring)
	# warm pad floods on the starfighter
	var xl := SpotLight3D.new()
	xl.position = Vector3(14.0, 9.0, 8.0)
	xl.rotation.x = -PI / 2.0
	xl.spot_range = 12.0
	xl.spot_angle = 38.0
	xl.light_energy = 5.5
	xl.light_color = Color(1.0, 0.92, 0.8)
	add_child(xl)

	# crate stacks along the east wall
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.24, 0.26, 0.3)
	crate.albedo_texture = load("res://assets/textures/metal_plate_diff_2k.jpg")
	crate.metallic = 0.3
	crate.roughness = 0.7
	crate.uv1_triplanar = true
	crate.uv1_scale = Vector3(0.8, 0.8, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for spec in [[Vector3(15.5, 0, 10.0), 3], [Vector3(16.5, 0, 5.0), 2], [Vector3(14.5, 0, -8.0), 2], [Vector3(17.0, 0, -2.0), 1]]:
		var base: Vector3 = spec[0]
		for k: int in spec[1]:
			var sz := rng.randf_range(1.5, 2.2)
			var b := _box(Vector3(sz, 1.4, sz), base + Vector3(rng.randf_range(-0.3, 0.3), 0.7 + k * 1.4, rng.randf_range(-0.3, 0.3)), crate)
			b.rotation.y = rng.randf_range(-0.2, 0.2)
			_box(Vector3(sz + 0.02, 0.1, sz + 0.02), b.position + Vector3(0, 0.5, 0), strip_r)
		_collision_box(base + Vector3(0, spec[1] * 0.7, 0), Vector3(2.4, spec[1] * 1.5, 2.4))

	# honor guard: a few troopers at attention along the back wall
	var ps: PackedScene = load("res://assets/models/characters/trooper.glb")
	for x in [-7.0, -3.5, 3.5, 7.0]:
		var t: Node3D = ps.instantiate()
		t.position = Vector3(x, 0, HG_D - 1.6)
		t.rotation.y = PI    # mesh forward is +Z: face the arena (north)
		add_child(t)
		var ap: AnimationPlayer = t.find_child("AnimationPlayer", true, false)
		if ap != null and ap.has_animation("01_Idle"):
			ap.play("01_Idle")
			ap.seek(randf() * 2.0)
		_collision_box(t.position + Vector3(0, 1.0, 0), Vector3(0.8, 2.0, 0.8))

	# real downloaded machinery along the hangar side walls (CC0 props)
	for spec in [["console", 2.0, Vector3(-HG_W + 1.6, 0, -6.0), 1.57],
			["generator", 2.6, Vector3(-HG_W + 1.8, 0, 2.0), 1.57],
			["console", 2.0, Vector3(HG_W - 1.6, 0, -10.0), -1.57],
			["turbine", 2.0, Vector3(-HG_W + 1.7, 0, 11.0), 1.57]]:
		_floor_prop("res://assets/models/scifi/%s.glb" % spec[0], spec[1],
			spec[2], spec[3], Color(0.8, 0.78, 0.74))

# ---------------------------------------------------- Star Wars set pieces

func _build_holotable(at: Vector3) -> void:
	# console base with a flickering hologram of a Star Destroyer above it
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.85
	cm.bottom_radius = 1.05
	cm.height = 0.95
	cm.material = _mat_panel()
	base.mesh = cm
	base.position = at + Vector3(0, 0.475, 0)
	add_child(base)
	var lip := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.78
	tm.outer_radius = 0.88
	tm.rings = 32
	tm.material = _mat_emissive(Color(0.4, 0.75, 1.0), 2.2)
	lip.mesh = tm
	lip.position = at + Vector3(0, 0.96, 0)
	lip.scale.y = 0.18
	add_child(lip)
	_collision_box(at + Vector3(0, 0.5, 0), Vector3(1.9, 1.0, 1.9))
	var holo := ModelUtil.load_model("res://assets/models/star_destroyer.glb", 2.6, 0.0)
	var hmat := ShaderMaterial.new()
	hmat.shader = load("res://shaders/hologram.gdshader")
	var stack: Array = [holo]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			(nd as MeshInstance3D).material_override = hmat
			(nd as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for c in nd.get_children():
			stack.push_back(c)
	var spin := Node3D.new()
	spin.position = at + Vector3(0, 1.75, 0)
	spin.add_child(holo)
	add_child(spin)
	var tw := create_tween().set_loops()
	tw.tween_property(spin, "rotation:y", TAU, 24.0).as_relative()
	var hl := OmniLight3D.new()
	hl.light_color = Color(0.4, 0.75, 1.0)
	hl.light_energy = 1.0
	hl.omni_range = 4.5
	hl.position = at + Vector3(0, 1.6, 0)
	add_child(hl)

func _build_banners() -> void:
	# ceremonial banners flanking the throne
	var bmat := ShaderMaterial.new()
	bmat.shader = load("res://shaders/banner.gdshader")
	for x in [-6.5, 6.5]:
		var b := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.2, 6.5)
		pm.subdivide_depth = 16
		pm.subdivide_width = 4
		pm.orientation = PlaneMesh.FACE_Z
		b.mesh = pm
		b.material_override = bmat
		b.position = Vector3(x, ROOM_H - 3.6, ROOM_R - 1.1)
		add_child(b)

var _mse: Node3D

func _build_mse_droid() -> void:
	# little MSE mouse droid scuttling along the south wall
	_mse = Node3D.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.metallic = 0.4
	dark.roughness = 0.35
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.2, 0.5)
	bm.material = dark
	body.mesh = bm
	body.position.y = 0.16
	_mse.add_child(body)
	var top := MeshInstance3D.new()
	var tm2 := BoxMesh.new()
	tm2.size = Vector3(0.26, 0.1, 0.34)
	tm2.material = dark
	top.mesh = tm2
	top.position = Vector3(0, 0.3, -0.03)
	_mse.add_child(top)
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.2, 0.03, 0.03)
	em.material = _mat_emissive(Color(1.0, 0.3, 0.1), 2.0)
	eye.mesh = em
	eye.position = Vector3(0, 0.22, -0.26)
	_mse.add_child(eye)
	add_child(_mse)
	# patrol loop along the south wall, with little turns and beeps
	var pts := [Vector3(-16, 0, 13.5), Vector3(10, 0, 13.5), Vector3(10, 0, 11.0), Vector3(-16, 0, 11.0)]
	_mse.position = pts[0]
	var tw := create_tween().set_loops()
	for i in pts.size():
		var nxt: Vector3 = pts[(i + 1) % pts.size()]
		var cur: Vector3 = pts[i]
		tw.tween_callback(func() -> void:
			if is_instance_valid(_mse):
				_mse.look_at_from_position(_mse.position, nxt, Vector3.UP))
		tw.tween_property(_mse, "position", nxt, cur.distance_to(nxt) / 3.2)
	var beep := AudioStreamPlayer3D.new()
	beep.stream = load("res://assets/audio/mse_beep.wav")
	beep.unit_size = 5.0
	beep.volume_db = -8.0
	beep.bus = "SFX"
	_mse.add_child(beep)
	var bt := Timer.new()
	bt.wait_time = 6.5
	bt.autostart = true
	_mse.add_child(bt)
	bt.timeout.connect(func() -> void:
		beep.pitch_scale = randf_range(0.9, 1.15)
		beep.play())

func _build_space_view() -> void:
	# Star Destroyer on patrol, far beyond the viewport
	var sd := ModelUtil.load_model("res://assets/models/star_destroyer.glb", 260.0, 0.35)
	sd.position = Vector3(-110, 30, -420)
	add_child(sd)
	var drift := create_tween().set_loops()
	drift.tween_property(sd, "position:x", 60.0, 160.0)
	drift.tween_property(sd, "position:x", -110.0, 160.0)
	# the real Millennium Falcon sweeping past the viewport on patrol
	var falcon: Node3D = load("res://assets/models/props/falcon_real.glb").instantiate()
	falcon.scale = Vector3.ONE * 2.2
	falcon.position = Vector3(160, 24, -150)
	falcon.rotation = Vector3(0.2, 0.4, 0.15)
	add_child(falcon)
	var ftw := create_tween().set_loops()
	ftw.tween_interval(4.0)
	ftw.tween_property(falcon, "position", Vector3(-170, 30, -130), 13.0).set_trans(Tween.TRANS_SINE)
	ftw.parallel().tween_property(falcon, "rotation:y", 0.9, 13.0)
	ftw.tween_callback(func() -> void:
		falcon.position = Vector3(160, 24, -150)
		falcon.rotation.y = 0.4)
	ftw.tween_interval(11.0)
	# A gas giant looming on the horizon
	var planet := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 220.0
	pm.height = 440.0
	var pmm := StandardMaterial3D.new()
	pmm.albedo_texture = load("res://assets/textures/jupiter.jpg")
	pmm.roughness = 1.0
	pm.material = pmm
	planet.mesh = pm
	planet.position = Vector3(480, 140, -1100)
	planet.rotation.z = 0.4
	add_child(planet)
	# a Star Destroyer drops out of hyperspace now and then
	var jump_timer := Timer.new()
	jump_timer.wait_time = 26.0
	jump_timer.autostart = true
	add_child(jump_timer)
	jump_timer.timeout.connect(_hyperspace_arrival)
	get_tree().create_timer(7.0).timeout.connect(_hyperspace_arrival)
	# TIE fighters screaming past the viewport
	for spec in [[36.0, 26.0, -260.0, 14.0, 0.0], [26.0, 34.0, -210.0, 11.0, 6.0]]:
		var tie := ModelUtil.load_model("res://assets/models/tie/scene.gltf", spec[0], PI / 2.0)
		tie.position = Vector3(320, spec[1], spec[2])
		tie.rotation.z = 0.25
		add_child(tie)
		var tw := create_tween().set_loops()
		tw.tween_interval(spec[4])
		tw.tween_property(tie, "position:x", -320.0, spec[3])
		tw.tween_callback(func() -> void: tie.position.x = 320.0)
		tw.tween_interval(9.0)
	# a few bright stars that twinkle
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	for i in 7:
		var star := MeshInstance3D.new()
		var smm := SphereMesh.new()
		smm.radius = rng.randf_range(1.6, 2.8)
		smm.height = smm.radius * 2.0
		smm.radial_segments = 8
		smm.rings = 4
		var em := StandardMaterial3D.new()
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.albedo_color = Color(0.9, 0.94, 1.0)
		em.emission_enabled = true
		em.emission = Color(0.85, 0.9, 1.0)
		em.emission_energy_multiplier = 2.0
		smm.material = em
		star.mesh = smm
		star.position = Vector3(rng.randf_range(-700, 700), rng.randf_range(60, 420), rng.randf_range(-1000, -700))
		add_child(star)
		var stw := create_tween().set_loops()
		var period := rng.randf_range(1.4, 3.2)
		stw.tween_property(em, "emission_energy_multiplier", 5.5, period).set_trans(Tween.TRANS_SINE)
		stw.tween_property(em, "emission_energy_multiplier", 2.0, period).set_trans(Tween.TRANS_SINE)

func _build_spectators() -> void:
	# Stormtroopers at attention along the side walls
	var ps: PackedScene = load("res://assets/models/characters/trooper.glb")
	for ang_deg in [78.0, 102.0, 258.0, 282.0, 65.0, 115.0]:
		var ang := deg_to_rad(ang_deg)
		var pos := Vector3(sin(ang) * (ROOM_R - 1.6), 0, -cos(ang) * (ROOM_R - 1.6))
		var t: Node3D = ps.instantiate()
		var to_c := -pos.normalized()
		t.rotation.y = atan2(to_c.x, to_c.z)
		t.position = pos
		add_child(t)
		var ap: AnimationPlayer = t.find_child("AnimationPlayer", true, false)
		if ap != null:
			for n in ["01_Idle", "20_FightIdle"]:
				if ap.has_animation(n):
					ap.play(n)
					ap.seek(randf() * 2.0)
					break
		_collision_box(pos + Vector3(0, 1.0, 0), Vector3(0.8, 2.0, 0.8))

func _build_dust() -> void:
	# Slow dust motes drifting through the light shafts
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(ROOM_R, ROOM_H * 0.5, ROOM_R)
	mat.gravity = Vector3(0, -0.02, 0)
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.12
	mat.direction = Vector3(1, -0.2, 0)
	mat.spread = 180.0
	mat.scale_min = 0.4
	mat.scale_max = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.018)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.albedo_color = Color(0.7, 0.78, 1.0, 0.4)
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = qmat
	p.draw_pass_1 = qm
	p.process_material = mat
	p.amount = 110
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position.y = ROOM_H * 0.45
	p.visibility_aabb = AABB(Vector3(-ROOM_R - 2, -ROOM_H, -ROOM_R - 2), Vector3(ROOM_R * 2 + 4, ROOM_H * 2, ROOM_R * 2 + 4))
	add_child(p)

func _hyperspace_arrival() -> void:
	if _ended:
		return
	var spot := Vector3(randf_range(-260, 120), randf_range(50, 150), randf_range(-700, -550))
	# light streak stretching toward the arrival point
	var streak := MeshInstance3D.new()
	var sm2 := CylinderMesh.new()
	sm2.top_radius = 1.2
	sm2.bottom_radius = 1.2
	sm2.height = 1.0
	sm2.radial_segments = 8
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.albedo_color = Color(0.75, 0.85, 1.0, 0.9)
	sm2.material = smat
	streak.mesh = sm2
	streak.position = spot + Vector3(0, 0, -350)
	streak.rotation.x = PI / 2.0
	streak.scale = Vector3(1, 700, 1)
	add_child(streak)
	var sd2 := ModelUtil.load_model("res://assets/models/star_destroyer.glb", 200.0, 0.1)
	sd2.position = spot
	sd2.scale = Vector3.ONE * 0.02
	add_child(sd2)
	var tw := create_tween()
	tw.tween_property(streak, "scale:y", 2.0, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(smat, "albedo_color:a", 0.0, 0.34)
	tw.parallel().tween_property(sd2, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(streak.queue_free)
	tw.tween_property(sd2, "position:z", spot.z - 60.0, 16.0)
	tw.tween_property(sd2, "scale", Vector3.ONE * 0.01, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(sd2.queue_free)

# ------------------------------------------- Bespin carbon-freeze chamber
# The iconic Cloud City duel hall: dark industrial ring around a glowing
# carbon-freezing pit, steam, amber light, open onto the orange cloudscape.

func _build_bespin_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.55, 0.42, 0.30)
	sm.sky_horizon_color = Color(0.95, 0.62, 0.32)
	sm.ground_bottom_color = Color(0.62, 0.40, 0.26)
	sm.ground_horizon_color = Color(0.95, 0.62, 0.32)
	sm.sun_angle_max = 30.0
	sm.energy_multiplier = 1.3
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.25
	env.ambient_light_color = Color(0.68, 0.55, 0.45)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.18
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	var q: int = GameSettings.quality
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 1.6
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 40
	env.ssr_fade_out = 1.5
	env.sdfgi_enabled = q >= 2
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.62, 0.32)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = q >= 1
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color(0.9, 0.72, 0.55)
	env.volumetric_fog_emission = Color(0.05, 0.025, 0.01)
	env.volumetric_fog_length = 60.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# warm key light raking through the chamber from the cloudscape window
	var key := DirectionalLight3D.new()
	key.light_energy = 1.9
	key.light_color = Color(1.0, 0.82, 0.58)
	key.rotation = Vector3(-0.5, 2.2, 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 70.0
	key.shadow_blur = 1.2
	key.light_volumetric_fog_energy = 1.4
	add_child(key)
	# cold blue fill from the opposite side for contrast
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.6
	fill.light_color = Color(0.6, 0.72, 1.0)
	fill.rotation = Vector3(-0.35, -0.7, 0.0)
	add_child(fill)

func _build_bespin() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.085, 0.082, 0.09)
	dark.metallic = 0.6
	dark.roughness = 0.4
	var grime := StandardMaterial3D.new()
	grime.albedo_color = Color(0.14, 0.12, 0.12)
	grime.metallic = 0.5
	grime.roughness = 0.55
	var amber := _mat_emissive(Color(1.0, 0.55, 0.15), 2.4)
	var cold := _mat_emissive(Color(0.5, 0.7, 1.0), 1.6)

	# reflective deck
	var floor_mi := MeshInstance3D.new()
	var fcm := CylinderMesh.new()
	fcm.top_radius = ROOM_R + 1.0
	fcm.bottom_radius = ROOM_R + 1.0
	fcm.height = 0.3
	fcm.radial_segments = 24
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.05, 0.05, 0.06)
	fmat.metallic = 0.8
	fmat.roughness = 0.22
	fmat.normal_enabled = true
	fmat.normal_texture = load("res://assets/models/imperial_base_floor-normal.png")
	fmat.normal_scale = 0.4
	fmat.uv1_scale = Vector3(7, 7, 7)
	fcm.material = fmat
	floor_mi.mesh = fcm
	floor_mi.position.y = -0.15
	add_child(floor_mi)
	_collision_box(Vector3(0, -0.5, 0), Vector3(ROOM_R * 2.6, 1.0, ROOM_R * 2.6))
	var pcol := GPUParticlesCollisionBox3D.new()
	pcol.size = Vector3(ROOM_R * 2.6, 0.5, ROOM_R * 2.6)
	pcol.position.y = -0.25
	add_child(pcol)

	# the carbon-freezing pit: a recessed glowing grate dead centre
	var pit := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 3.4
	pm.bottom_radius = 3.4
	pm.height = 0.14
	pm.radial_segments = 32
	pm.material = _mat_emissive(Color(1.0, 0.5, 0.12), 1.3)
	pit.mesh = pm
	pit.position.y = 0.02
	add_child(pit)
	# concentric grate rings + radial bars over the pit
	for r in [1.1, 2.0, 2.9]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.12
		tm.outer_radius = r + 0.12
		tm.rings = 40
		tm.material = dark
		ring.mesh = tm
		ring.position.y = 0.08
		ring.scale.y = 0.5
		add_child(ring)
	for i in 12:
		var ang := TAU * i / 12.0
		var bar := _box(Vector3(0.16, 0.12, 3.4), Vector3(0, 0.08, 0), dark)
		bar.rotation.y = ang
	# orange glow + heat-haze light from the pit
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.6, 0)
	glow.light_color = Color(1.0, 0.5, 0.15)
	glow.light_energy = 1.8
	glow.omni_range = 10.0
	glow.light_volumetric_fog_energy = 1.2
	add_child(glow)
	# steam billowing up from the pit
	_bespin_steam(Vector3(0, 0.1, 0), 2.6, 16)

	# carbon-freezing apparatus: angled hydraulic pistons ringing the pit, the
	# machinery that drives the clamps into the chamber
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.28, 0.29, 0.33)
	steel.metallic = 0.7
	steel.roughness = 0.35
	var piston_mat := StandardMaterial3D.new()
	piston_mat.albedo_color = Color(0.55, 0.56, 0.6)
	piston_mat.metallic = 0.9
	piston_mat.roughness = 0.18
	for i in 6:
		var ang := TAU * i / 6.0 + 0.25
		var px := cos(ang) * 4.6
		var pz := sin(ang) * 4.6
		var house := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.42
		hm.bottom_radius = 0.5
		hm.height = 2.4
		hm.material = steel
		house.mesh = hm
		house.position = Vector3(px, 1.2, pz)
		add_child(house)
		var rod := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.13
		rm.bottom_radius = 0.13
		rm.height = 2.6
		rm.material = piston_mat
		rod.mesh = rm
		rod.position = Vector3(px * 0.62, 2.0, pz * 0.62)
		rod.look_at_from_position(rod.position, Vector3(0, 2.6, 0), Vector3.UP)
		rod.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		add_child(rod)
		_box(Vector3(0.34, 0.1, 0.06), Vector3(px, 2.1, pz) + Vector3(cos(ang), 0, sin(ang)) * -0.5, amber)
		_collision_box(Vector3(px, 1.2, pz), Vector3(1.0, 2.4, 1.0))

	# two control consoles at the chamber edge with glowing readouts
	for cs in [[Vector3(8.5, 0, 8.5), 2.4], [Vector3(-8.5, 0, -8.5), -0.7]]:
		var con := Node3D.new()
		con.position = cs[0]
		con.rotation.y = cs[1]
		add_child(con)
		_box(Vector3(2.4, 1.1, 0.9), Vector3(0, 0.55, 0), steel, con)
		var panel := _box(Vector3(2.2, 0.5, 0.1), Vector3(0, 1.0, -0.42), _mat_emissive(Color(0.4, 0.8, 1.0), 1.4), con)
		panel.rotation.x = -0.5
		_box(Vector3(0.5, 0.08, 0.5), Vector3(0.7, 1.16, 0.0), amber, con)
		_collision_box(cs[0] + Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 1.0))

	# cyan rim accent on the floor for cold contrast against the amber
	var rim_ring := MeshInstance3D.new()
	var rrm := TorusMesh.new()
	rrm.inner_radius = ROOM_R - 2.2
	rrm.outer_radius = ROOM_R - 2.0
	rrm.rings = 64
	rrm.material = _mat_emissive(Color(0.45, 0.7, 1.0), 1.2)
	rim_ring.mesh = rrm
	rim_ring.position.y = 0.02
	rim_ring.scale.y = 0.1
	add_child(rim_ring)

	# overhead cable conduits draping toward the pit
	for i in 5:
		var ang2 := TAU * i / 5.0 + 0.4
		var cable := MeshInstance3D.new()
		var ccm := CylinderMesh.new()
		ccm.top_radius = 0.1
		ccm.bottom_radius = 0.1
		ccm.height = 5.5
		ccm.material = dark
		cable.mesh = ccm
		cable.position = Vector3(cos(ang2) * 5.5, ROOM_H - 3.0, sin(ang2) * 5.5)
		cable.rotation = Vector3(0.4, ang2, 0.2)
		add_child(cable)

	# real downloaded sci-fi machinery (CC0/CC-BY props, see CREDITS.md) set
	# around the chamber: control consoles, generators, turbines, pipe banks
	var R := ROOM_R - 1.6
	for spec in [
			["console", 2.0, 7.0, 1.4], ["console", 2.0, -2.6, 1.0],
			["generator", 2.6, 4.4, 0.0], ["generator", 2.6, -1.1, 0.0],
			["turbine", 1.8, 5.6, 0.7], ["turbine", 1.8, 0.4, 0.7],
			["pipes_panel", 3.2, 3.5, 0.0], ["pipes_panel", 3.2, -3.6, 0.0]]:
		var nm: String = spec[0]
		var ang3: float = spec[2]
		var px := sin(ang3) * R
		var pz := -cos(ang3) * R
		_floor_prop("res://assets/models/scifi/%s.glb" % nm, spec[1],
			Vector3(px, 0.0, pz), ang3 + PI, Color(0.7, 0.65, 0.6))

	# octagonal industrial wall ring; one segment is the cloudscape window
	var seg_w := 2.0 * ROOM_R * tan(PI / 8.0)
	for i in 8:
		var ang := TAU * i / 8.0
		var holder := Node3D.new()
		holder.position = Vector3(sin(ang) * ROOM_R, 0, -cos(ang) * ROOM_R)
		holder.rotation.y = -ang
		add_child(holder)
		var is_window := i == 0
		if is_window:
			# open frame onto the orange clouds (sky shows through)
			_box(Vector3(seg_w, 1.4, 0.5), Vector3(0, 0.7, 0), dark, holder)
			_box(Vector3(seg_w, 2.4, 0.5), Vector3(0, ROOM_H - 1.2, 0), dark, holder)
			_box(Vector3(0.5, ROOM_H, 0.5), Vector3(-seg_w / 2.0 + 0.4, ROOM_H / 2.0, 0), dark, holder)
			_box(Vector3(0.5, ROOM_H, 0.5), Vector3(seg_w / 2.0 - 0.4, ROOM_H / 2.0, 0), dark, holder)
			_box(Vector3(seg_w, 0.1, 0.4), Vector3(0, 1.42, -0.05), amber, holder)
		else:
			# real paneled sci-fi wall, tiled from Kenney Space Station Kit
			# modules (CC0): structural pillar ribs at the segment edges, plain
			# panels filling the field, portholes high up and the odd doorway —
			# so the chamber reads as a built location, not a flat box.
			var cols := 4
			var rows := 3
			var cw := seg_w / float(cols)
			var ch := ROOM_H / float(rows)
			for col in cols:
				for row in rows:
					var nm := "wall"
					if col == 0 or col == cols - 1:
						nm = "wall_pillar"
					elif row == rows - 1 and (col == 1 or col == 2):
						nm = "wall_window"
					elif row == 0 and col == 1 and i % 3 == 1:
						nm = "wall_door"
					var cx := -seg_w / 2.0 + (col + 0.5) * cw
					_station_panel(holder, nm, cx, row * ch, cw, ch)
			# glowing accent strips banding the paneling
			_box(Vector3(seg_w - 1.6, 0.16, 0.2), Vector3(0, ch - 0.15, -0.62), amber if i % 2 == 0 else cold, holder)
			_box(Vector3(seg_w - 1.6, 0.16, 0.2), Vector3(0, ch * 2.0 - 0.15, -0.62), cold if i % 2 == 0 else amber, holder)
			# a real station crate + venting pipe at the base on odd segments
			if i % 2 == 1:
				var crate: Node3D = load("res://assets/models/station/container_tall.glb").instantiate()
				crate.scale = Vector3.ONE * 2.3
				crate.position = Vector3(seg_w / 2.0 - 1.4, 0, -1.0)
				crate.rotation.y = 0.4
				holder.add_child(crate)
				var pipe2: Node3D = load("res://assets/models/station/pipe.glb").instantiate()
				pipe2.scale = Vector3(2.2, 3.6, 2.2)
				pipe2.position = Vector3(-seg_w / 2.0 + 1.3, 0, -0.9)
				holder.add_child(pipe2)
				_bespin_steam(holder.position + holder.transform.basis * Vector3(seg_w / 2.0 - 1.4, 2.1, -1.0), 1.6, 14)
		# wall collision
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(seg_w + 1.0, ROOM_H * 2.0, 0.6)
		cs.shape = shape
		sb.add_child(cs)
		holder.add_child(sb)

	# ceiling ring with hanging hooks/pipes and a central light gantry
	_box(Vector3(ROOM_R * 2.2, 0.5, ROOM_R * 2.2), Vector3(0, ROOM_H + 0.25, 0), grime)
	for i in 6:
		var ang2 := TAU * i / 6.0 + 0.3
		var hook := MeshInstance3D.new()
		var hcm := CylinderMesh.new()
		hcm.top_radius = 0.08
		hcm.bottom_radius = 0.08
		hcm.height = 2.4
		hcm.material = dark
		hook.mesh = hcm
		hook.position = Vector3(cos(ang2) * 7.0, ROOM_H - 1.4, sin(ang2) * 7.0)
		add_child(hook)
	# overhead amber spot onto the pit
	var well := SpotLight3D.new()
	well.position = Vector3(0, ROOM_H, 0)
	well.rotation.x = -PI / 2.0
	well.spot_range = ROOM_H + 3.0
	well.spot_angle = 50.0
	well.light_energy = 4.0
	well.light_color = Color(1.0, 0.85, 0.6)
	well.shadow_enabled = true
	well.light_volumetric_fog_energy = 2.0
	add_child(well)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(ROOM_R * 2.4, ROOM_H + 4.0, ROOM_R * 2.4)
	probe.position = Vector3(0, ROOM_H * 0.5, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

	# the Millennium Falcon banking through the Cloud City sky beyond the bay
	var falcon: Node3D = load("res://assets/models/props/falcon_real.glb").instantiate()
	falcon.scale = Vector3.ONE * 1.4
	falcon.position = Vector3(70, 14, -60)
	falcon.rotation = Vector3(0.15, 0.3, 0.1)
	add_child(falcon)
	var ftw := create_tween().set_loops()
	ftw.tween_interval(3.0)
	ftw.tween_property(falcon, "position", Vector3(-75, 20, -55), 11.0).set_trans(Tween.TRANS_SINE)
	ftw.parallel().tween_property(falcon, "rotation:y", 0.8, 11.0)
	ftw.tween_callback(func() -> void:
		falcon.position = Vector3(70, 14, -60)
		falcon.rotation.y = 0.3)
	ftw.tween_interval(9.0)

func _bespin_steam(at: Vector3, height: float, amount: int) -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.9
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = height * 0.25
	mat.initial_velocity_max = height * 0.5
	mat.gravity = Vector3(0, 0.4, 0)
	mat.scale_min = 1.0
	mat.scale_max = 2.2
	mat.color = Color(1.0, 0.85, 0.7, 0.06)
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.albedo_color = Color(1.0, 0.7, 0.45, 0.035)
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = qmat
	p.draw_pass_1 = qm
	p.process_material = mat
	p.amount = amount
	p.lifetime = 3.5
	p.preprocess = 3.0
	p.position = at
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, height + 4, 12))
	add_child(p)

# ------------------------------------------- Imperial control room (data centre)
# A real downloaded sci-fi room model (CC-BY, see CREDITS.md): banks of mainframe
# computers, tape drives and a reactor column ringing a wide open deck. The duel
# happens on the clean central floor; the machinery is the backdrop.

func _build_control_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.54, 0.6, 0.7)
	env.ambient_light_energy = 2.1
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.34
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	var q: int = GameSettings.quality
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 1.4
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 32
	env.sdfgi_enabled = q >= 2
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.55, 0.75)
	env.fog_light_energy = 1.4
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = q >= 1
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.55, 0.66, 0.88)
	env.volumetric_fog_emission = Color(0.04, 0.05, 0.08)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# cool overhead key, like ceiling fluorescents
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.light_color = Color(0.82, 0.9, 1.0)
	key.rotation = Vector3(-1.15, -0.5, 0)
	key.shadow_enabled = true
	add_child(key)

func _build_control() -> void:
	var s := 1.5
	var model: Node3D = load("res://assets/models/swenv/control_room.glb").instantiate()
	model.scale = Vector3.ONE * s
	model.position = Vector3.ZERO
	add_child(model)
	var ab := ModelUtil.compute_aabb(model, Transform3D.IDENTITY)
	var center := ab.position + ab.size * 0.5
	# centre the open deck on the origin, rest the floor at y=0
	model.position = Vector3(-center.x, -ab.position.y, -center.z)

	# clean flat collision deck + particle collider for dust
	_collision_box(Vector3(0, -0.5, 0), Vector3(80, 1.0, 80))
	var pcol := GPUParticlesCollisionBox3D.new()
	pcol.size = Vector3(60, 0.5, 60)
	pcol.position.y = -0.25
	add_child(pcol)

	# faint reflective deck disc over the model floor so the arena reads clean
	var deck := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = ARENA_R + 0.5
	dm.bottom_radius = ARENA_R + 0.5
	dm.height = 0.06
	dm.radial_segments = 48
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.10, 0.12, 0.15)
	dmat.metallic = 0.7
	dmat.roughness = 0.3
	dm.material = dmat
	deck.mesh = dm
	deck.position.y = 0.01
	add_child(deck)
	# glowing rim so the duel circle is legible
	var rim := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = ARENA_R - 0.7
	rt.outer_radius = ARENA_R - 0.45
	rt.rings = 64
	rt.material = _mat_emissive(Color(0.4, 0.7, 1.0), 1.6)
	rim.mesh = rt
	rim.position.y = 0.05
	rim.scale.y = 0.1
	add_child(rim)

	# overhead light banks + cool console fills around the deck
	for spec in [
			[Vector3(0, 9, 0), Color(0.85, 0.92, 1.0), 4.0, 30.0],
			[Vector3(10, 5, 8), Color(0.5, 0.7, 1.0), 2.4, 16.0],
			[Vector3(-10, 5, -8), Color(0.6, 0.8, 1.0), 2.4, 16.0],
			[Vector3(-11, 4, 9), Color(0.9, 0.6, 0.3), 1.8, 14.0],
			[Vector3(11, 4, -9), Color(0.4, 0.9, 0.7), 1.8, 14.0],
			[Vector3(12, 6, 11), Color(0.8, 0.86, 1.0), 2.2, 20.0],
			[Vector3(-12, 6, -11), Color(0.8, 0.86, 1.0), 2.2, 20.0],
			[Vector3(0, 5, -13), Color(0.55, 0.72, 1.0), 3.0, 24.0],
			[Vector3(0, 5, 13), Color(0.7, 0.8, 1.0), 2.6, 24.0]]:
		var ol := OmniLight3D.new()
		ol.position = spec[0]
		ol.light_color = spec[1]
		ol.light_energy = spec[2]
		ol.omni_range = spec[3]
		ol.light_volumetric_fog_energy = 0.8
		add_child(ol)

	# dark ceiling cap so looking up reads as a roof, not the void
	var cap := MeshInstance3D.new()
	var cbm := BoxMesh.new()
	cbm.size = Vector3(60, 0.6, 60)
	var capm := StandardMaterial3D.new()
	capm.albedo_color = Color(0.04, 0.045, 0.06)
	cbm.material = capm
	cap.mesh = cbm
	cap.position.y = 13.5
	add_child(cap)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(48, 18, 48)
	probe.position = Vector3(0, 6, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

# ------------------------------------------- Imperial corridor (Death Star)
# A textured, PBR sci-fi corridor assembled from the Quaternius Modular SciFi
# MegaKit (CC0, see CREDITS.md): dark metal plating, glowing red accent bands,
# blast-door archway, wall lights and props. The classic corridor duel setting.

func _mk(nm: String, pos: Vector3, yaw: float, parent: Node = self) -> Node3D:
	var scn := load("res://assets/models/megakit/%s.gltf" % nm)
	if scn == null:
		return null
	var n: Node3D = scn.instantiate()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n

func _build_imperial_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.016, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.56)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.28
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	var q: int = GameSettings.quality
	env.ssao_enabled = q >= 1
	env.ssao_intensity = 2.0
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 48
	env.ssr_fade_out = 2.0
	env.sdfgi_enabled = q >= 2
	env.fog_enabled = true
	env.fog_light_color = Color(0.4, 0.45, 0.6)
	env.fog_density = 0.004
	env.volumetric_fog_enabled = q >= 1
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.5, 0.55, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 0.7
	key.light_color = Color(0.7, 0.78, 0.95)
	key.rotation = Vector3(-1.2, -0.4, 0)
	add_child(key)

func _build_imperial() -> void:
	var hx := 4.0                                   # wall origin x; inner faces at ±6
	var zs := [-20, -16, -12, -8, -4, 0, 4, 8, 12, 16, 20]
	var floor_cols := [-4.0, 0.0, 4.0]
	var windows := [-12, -4, 4, 12]                 # bays that open onto space
	var ribs := [-20, -12, -4, 4, 12, 20]           # column + overhead-rib stations
	# deck
	for z in zs:
		for cx in floor_cols:
			_mk("Platform_Metal", Vector3(cx, 0, z), 0)
	# long side walls + top trim; window bays where they open onto space
	for z in zs:
		for side in [-1.0, 1.0]:
			var yaw := 0.0 if side < 0 else PI
			if z in windows:
				_mk("WallWindow_Straight", Vector3(side * hx, 0, z), yaw)
				_imp_starfield(side, float(z))
			else:
				_mk("WallBand_Straight", Vector3(side * hx, 0, z), yaw)
			_mk("TopSimple_Straight", Vector3(side * hx, 0, z), yaw)
	# end caps: far end (-z) with a blast-door, near end (+z) sealed
	for cx in floor_cols:
		if cx == 0.0:
			_mk("Door_Frame_Square", Vector3(0, 0, -22), 0)
		else:
			_mk("WallBand_Straight", Vector3(cx, 0, -22), -PI / 2.0)
		_mk("WallBand_Straight", Vector3(cx, 0, 22), PI / 2.0)
		_mk("TopSimple_Straight", Vector3(cx, 0, -22), -PI / 2.0)
		_mk("TopSimple_Straight", Vector3(cx, 0, 22), PI / 2.0)

	# pilaster columns + overhead ribs giving the hall rhythm and depth
	var rib_mat := StandardMaterial3D.new()
	rib_mat.albedo_color = Color(0.09, 0.095, 0.11)
	rib_mat.metallic = 0.75
	rib_mat.roughness = 0.38
	for z in ribs:
		_mk("Column_Simple", Vector3(-5.7, 0, z), 0)
		_mk("Column_Simple", Vector3(5.7, 0, z), PI)
		var rib := MeshInstance3D.new()
		var rbm := BoxMesh.new()
		rbm.size = Vector3(12.4, 0.7, 0.8)
		rbm.material = rib_mat
		rib.mesh = rbm
		rib.position = Vector3(0, 4.55, z)
		add_child(rib)
		# a thin emissive strip under each rib for an accent line
		var strip := _box(Vector3(11.0, 0.08, 0.12), Vector3(0, 4.18, z), _mat_emissive(Color(0.5, 0.7, 1.0), 1.3))
		strip.name = "ribstrip"

	# dark metal ceiling + conduits running the length
	var ceil := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(13.5, 0.4, 48)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.06, 0.065, 0.08)
	cmat.metallic = 0.7
	cmat.roughness = 0.4
	cm.material = cmat
	ceil.mesh = cm
	ceil.position = Vector3(0, 5.0, 0)
	add_child(ceil)
	for cx2 in [-3.2, 0.0, 3.2]:
		var pipe := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.34, 0.34, 46)
		pm.material = rib_mat
		pipe.mesh = pm
		pipe.position = Vector3(cx2, 4.55, 0)
		add_child(pipe)

	# floor light-lines down both edges → strong leading lines into the depth
	for z in zs:
		_mk("Prop_Light_Floor", Vector3(-5.4, 0, z), PI / 2.0)
		_mk("Prop_Light_Floor", Vector3(5.4, 0, z), -PI / 2.0)

	# wall lights between the bays, each casting a real glow
	for z in [-16, -8, 0, 8, 16]:
		for side in [-1.0, 1.0]:
			_mk("Prop_Light_Wide", Vector3(side * 5.9, 3.1, z), 0 if side < 0 else PI)
			var ol := OmniLight3D.new()
			ol.position = Vector3(side * 5.2, 3.0, z)
			ol.light_color = Color(0.85, 0.9, 1.0)
			ol.light_energy = 2.0
			ol.omni_range = 8.5
			ol.light_volumetric_fog_energy = 0.6
			add_child(ol)
	# warm red glow washing the accent bands at floor level
	for z in [-16, -8, 0, 8, 16]:
		var rl := OmniLight3D.new()
		rl.position = Vector3(0, 0.9, z)
		rl.light_color = Color(1.0, 0.3, 0.2)
		rl.light_energy = 0.9
		rl.omni_range = 6.5
		add_child(rl)

	# greeble: computer banks, vents, access consoles, crates, barrels
	_mk("Prop_Computer", Vector3(-5.7, 0, -9), PI / 2.0)
	_mk("Prop_Computer", Vector3(-5.7, 0, 9), PI / 2.0)
	_mk("Prop_Computer", Vector3(5.7, 0, -1), -PI / 2.0)
	_mk("Prop_AccessPoint", Vector3(-5.9, 0, -1), 0)
	_mk("Prop_AccessPoint", Vector3(5.9, 0, 7), PI)
	_mk("Prop_AccessPoint", Vector3(5.9, 0, -13), PI)
	_mk("Prop_Vent_Big", Vector3(-3.0, 4.78, -6), 0)
	_mk("Prop_Vent_Big", Vector3(3.0, 4.78, 10), 0)
	_mk("Prop_Fan_Small", Vector3(0, 4.78, -16), 0)
	_mk("Prop_Fan_Small", Vector3(0, 4.78, 16), 0)
	_mk("Prop_Crate3", Vector3(5.2, 0, 17), 0.3)
	_mk("Prop_Crate4", Vector3(5.7, 0, 18.4), -0.4)
	_mk("Prop_Crate3", Vector3(-5.5, 0, -18), -0.2)
	_mk("Prop_Barrel_Large", Vector3(-5.4, 0, 19), 0)
	_mk("Prop_Barrel_Large", Vector3(-5.9, 0, 20.2), 0)
	# a soft glow from the blast-door at the far end
	var dg := OmniLight3D.new()
	dg.position = Vector3(0, 2.4, -21)
	dg.light_color = Color(0.6, 0.75, 1.0)
	dg.light_energy = 2.6
	dg.omni_range = 10.0
	add_child(dg)

	# collisions: floor, the two side walls, two end caps
	_collision_box(Vector3(0, -0.5, 0), Vector3(16, 1.0, 52))
	var pcol := GPUParticlesCollisionBox3D.new()
	pcol.size = Vector3(13, 0.5, 48)
	pcol.position.y = -0.25
	add_child(pcol)
	_collision_box(Vector3(-6.3, 2.5, 0), Vector3(0.6, 6.0, 52))
	_collision_box(Vector3(6.3, 2.5, 0), Vector3(0.6, 6.0, 52))
	_collision_box(Vector3(0, 2.5, -22.4), Vector3(14, 6.0, 0.6))
	_collision_box(Vector3(0, 2.5, 22.4), Vector3(14, 6.0, 0.6))

	var probe := ReflectionProbe.new()
	probe.size = Vector3(13, 6, 48)
	probe.position = Vector3(0, 2.5, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

# A viewport onto space behind a window bay: an emissive starfield panel just
# outside the wall, with a faint blue light spilling into the corridor.
func _imp_starfield(side: float, z: float) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.6, 2.6)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = load("res://assets/textures/milky_way.jpg")
	sm.emission_enabled = true
	sm.emission_texture = load("res://assets/textures/milky_way.jpg")
	sm.emission_energy_multiplier = 0.9
	qm.material = sm
	q.mesh = qm
	q.position = Vector3(side * 6.45, 1.9, z)
	q.rotation.y = (PI / 2.0) if side < 0 else (-PI / 2.0)
	add_child(q)
	var g := OmniLight3D.new()
	g.position = Vector3(side * 5.6, 2.0, z)
	g.light_color = Color(0.55, 0.7, 1.0)
	g.light_energy = 1.3
	g.omni_range = 6.0
	add_child(g)

func _build_boundary() -> void:
	# Invisible ring keeping the duel off the walls and the dais
	var segs := 16
	for i in segs:
		var ang := TAU * i / segs
		var pos := Vector3(cos(ang) * ARENA_R, 2.0, sin(ang) * ARENA_R)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.0 * PI * ARENA_R / segs + 1.0, 4.0, 0.4)
		cs.shape = shape
		sb.add_child(cs)
		sb.position = pos
		sb.rotation.y = -ang + PI / 2.0
		add_child(sb)

func _collision_box(pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	sb.position = pos
	add_child(sb)

# ------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/film_post.gdshader")
	post.material = _post_mat
	layer.add_child(post)
	layer.add_child(UiKit.vignette())
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_msg = UiKit.label("", 60, UiKit.SW_YELLOW, true)
	_msg.visible = false
	_hud.add_child(_msg)
	_subtitle = UiKit.label("", 24, Color(0.95, 0.95, 1.0), true)
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.position.y = -86
	_subtitle.visible = false
	_hud.add_child(_subtitle)
	var n1 := UiKit.label(player.cfg["name"], 17, Color(0.85, 0.88, 1.0))
	n1.position = Vector2(36, 24)
	_hud.add_child(n1)
	var ename: String = enemy.cfg["name"] + (" ×%d" % enemies.size() if enemies.size() > 1 else "")
	var n2 := UiKit.label(ename, 17, Color(1, 0.5, 0.45))
	n2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	n2.position = Vector2(-300, 24)
	_hud.add_child(n2)
	var help := UiKit.label(
		("Clic : attaque (enchaîne !)  •  Clic droit : parade  •  Maj : esquive  •  E : poussée" if player.cfg["melee"]
		else "Clic : rafale de blaster  •  Maj : esquive"),
		14, Color(0.6, 0.64, 0.74))
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position.y = -28
	_hud.add_child(help)

func _show_msg(t: String) -> void:
	_msg.text = t
	_msg.visible = true
	_msg.reset_size()
	_msg.position = (_hud.get_viewport_rect().size - _msg.size) / 2.0 - Vector2(0, 120)
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(_msg):
			_msg.visible = false)

func _draw_hud() -> void:
	if player == null or enemy == null:
		return
	var vp := _hud.get_viewport_rect().size
	_bar(Vector2(36, 52), 300, player.hp / player.cfg["hp"], Color(0.3, 0.9, 0.45))
	for i in enemies.size():
		var e := enemies[i]
		_bar(Vector2(vp.x - 36 - 300, 52 + i * 22), 300, e.hp / e.cfg["hp"], Color(1, 0.32, 0.27))
	# Dash + Force push cooldown pips
	_bar(Vector2(36, 74), 120, 1.0 - player.dash_cooldown / 1.1, Color(0.4, 0.7, 1.0))
	if player.has_force():
		_bar(Vector2(36, 90), 120, 1.0 - player.push_cooldown / 6.0, Color(0.65, 0.55, 1.0))
	# Hitmarker: brief X at screen center when your strike lands
	if _hitmark_t > 0.0:
		_hitmark_t -= get_process_delta_time()
		var c2 := vp / 2.0
		var a := clampf(_hitmark_t / 0.22, 0.0, 1.0)
		var col2 := Color(1, 1, 1, a)
		for sgn in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_hud.draw_line(c2 + sgn * 7.0, c2 + sgn * 16.0, col2, 2.2, true)
	# Crosshair for the shooter
	if not player.cfg["melee"]:
		var c := vp / 2.0
		var col := Color(1, 1, 1, 0.8)
		_hud.draw_arc(c, 3.0, 0, TAU, 12, col, 1.4, true)
		for ang in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:
			var v := Vector2(cos(ang), sin(ang))
			_hud.draw_line(c + v * 8.0, c + v * 14.0, col, 1.4, true)

func _bar(pos: Vector2, w: float, ratio: float, col: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_hud.draw_rect(Rect2(pos, Vector2(w, 14)), Color(0, 0, 0, 0.55), true)
	if ratio > 0.0:
		_hud.draw_rect(Rect2(pos + Vector2(1.5, 1.5), Vector2((w - 3.0) * ratio, 11)), col, true)
	_hud.draw_rect(Rect2(pos, Vector2(w, 14)), Color(1, 1, 1, 0.28), false, 1.0)

# ------------------------------------------------------------ input & camera

func _unhandled_input(event: InputEvent) -> void:
	if not _intro_done and event.is_action_pressed("fire"):
		_end_intro()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameSettings.sensitivity
		var inv := -1.0 if GameSettings.invert_y else 1.0
		_cam_yaw -= event.relative.x * 0.0032 * sens
		_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.0026 * sens * inv, -0.95, 0.55)
		if absf(event.relative.x) + absf(event.relative.y) > 0.5:
			_mouse_idle = 0.0
	if event.is_action_pressed("pause") and not _ended:
		request_menu.emit()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if player.alive and player.controls_enabled:
		var mv := Vector2.ZERO
		if Input.is_action_pressed("throttle_up"):
			mv.y += 1.0
		if Input.is_action_pressed("throttle_down"):
			mv.y -= 1.0
		if Input.is_action_pressed("roll_right"):
			mv.x += 1.0
		if Input.is_action_pressed("roll_left"):
			mv.x -= 1.0
		# Duel lock-on: whenever the foe is within reach the hero squares up to
		# it and moves target-relative (W toward, S away, A/D orbit). Out of
		# range, free camera-relative running.
		var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
		var right := Vector3(-fwd.z, 0, fwd.x)
		var wdir := fwd * mv.y + right * mv.x
		var to_e := enemy.global_position - player.global_position
		to_e.y = 0
		var dist := to_e.length()
		_lock_active = enemy.alive and (dist < 7.5 or player.attacking or player.blocking)
		if _lock_active:
			player.face_yaw = atan2(-to_e.x, -to_e.z)
			player.move_input = mv.limit_length(1.0)
		elif wdir.length() > 0.1:
			player.face_yaw = atan2(-wdir.x, -wdir.z)
			player.move_input = Vector2(0, wdir.length())
		else:
			player.move_input = Vector2.ZERO
		if Input.is_action_just_pressed("fire"):
			player.try_attack()
		player.set_blocking(Input.is_action_pressed("block"))
		if Input.is_action_just_pressed("boost"):
			player.try_dash()
		if Input.is_action_just_pressed("force_push"):
			player.try_force_push()

	# the player always squares up against the nearest living opponent
	var best: GroundFighter = null
	var best_d := INF
	for e in enemies:
		if not e.alive:
			continue
		var d := e.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		enemy = best
		player.enemy = best

	_update_bolts(delta)
	_update_trails()
	_update_camera(delta)
	_hud.queue_redraw()

func _update_camera(delta: float) -> void:
	var target := player
	if not target.alive and enemy.alive:
		target = enemy
	_cam_pivot.position = _cam_pivot.position.lerp(target.global_position + Vector3(0, 1.55, 0), clampf(16.0 * delta, 0, 1))
	# Camera assist: when locked on and the player isn't steering the camera,
	# gently swing behind the hero so the foe stays framed over the shoulder.
	_mouse_idle += delta
	if _lock_active and _mouse_idle > 0.55 and target.alive and enemy != null and enemy.alive:
		var to_e := enemy.global_position - target.global_position
		var want_yaw := atan2(-to_e.x, -to_e.z)
		_cam_yaw = lerp_angle(_cam_yaw, want_yaw, clampf(3.0 * delta, 0, 1))
		_cam_pitch = lerpf(_cam_pitch, -0.12, clampf(1.5 * delta, 0, 1))
	_cam_pivot.rotation.y = _cam_yaw
	_cam_pitch_node.rotation.x = _cam_pitch
	var hv := Vector2(target.velocity.x, target.velocity.z).length()
	camera.fov = lerpf(camera.fov, GameSettings.fov + hv * 0.35, 5.0 * delta)
	# impact shake: smooth decaying oscillation (reads as a thud, not static)
	_shake = maxf(0.0, _shake - 3.2 * delta)
	_shake_t += delta
	var sh := _shake * _shake
	camera.h_offset = sin(_shake_t * 41.0) * 0.085 * sh
	camera.v_offset = sin(_shake_t * 53.0 + 1.7) * 0.075 * sh
	camera.rotation.z = sin(_shake_t * 33.0 + 0.6) * 0.012 * sh
	if _post_mat != null:
		_post_mat.set_shader_parameter("shake", sh)
	# victory cinematic: slow orbit around the winner
	if _cine_pivot != null and is_instance_valid(_cine_target):
		_cine_pivot.position = _cine_pivot.position.lerp(
			_cine_target.global_position + Vector3(0, 1.3, 0), clampf(6.0 * delta, 0, 1))
		_cine_pivot.rotation.y += 0.45 * delta

# ------------------------------------------------------------ combat services

# Brief global freeze on impact: the blow "lands" (classic fighting-game trick).
func hit_stop(duration := 0.09, scale := 0.07) -> void:
	if _ended or Engine.time_scale < 0.9:
		return
	Engine.time_scale = scale
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func() -> void:
		if not _ended:
			Engine.time_scale = 1.0)

func _rumble(weak: float, strong: float, dur: float) -> void:
	if GameSettings.rumble:
		Input.start_joy_vibration(0, weak, strong, dur)

func melee_hit(attacker: GroundFighter) -> bool:
	var connected := false
	var targets: Array = [player] if attacker != player else enemies.duplicate()
	for target: GroundFighter in targets:
		if target == null or not target.alive:
			continue
		var to_t: Vector3 = target.global_position - attacker.global_position
		to_t.y = 0
		var facing := (-attacker.global_transform.basis.z).dot(to_t.normalized())
		if to_t.length() <= attacker.saber_reach() and facing > 0.35:
			connected = true
			target.take_hit(attacker.cfg["dmg"], attacker)
			_hit_flash(target.global_position + Vector3(0, 1.2, 0), attacker.cfg["saber_color"])
			_shake = maxf(_shake, 0.55 if target == player else 0.35)
			if attacker == player:
				_hitmark_t = 0.22
			hit_stop(0.09, 0.07)
			_rumble(0.7 if target == player else 0.35, 0.9 if target == player else 0.5, 0.22)
			if music != null:
				music.combat_event()
	return connected

# Telekinetic shove: knocks back every opponent caught in the front cone.
func force_push(caster: GroundFighter) -> void:
	var targets: Array = [player] if caster != player else enemies.duplicate()
	var origin := caster.global_position
	var fwd := -caster.global_transform.basis.z
	for target: GroundFighter in targets:
		if target == null or not target.alive:
			continue
		var to_t: Vector3 = target.global_position - origin
		to_t.y = 0
		if to_t.length() > 6.5 or fwd.dot(to_t.normalized()) < 0.3:
			continue
		target.take_push(to_t.normalized())
		_hit_flash(target.global_position + Vector3(0, 1.1, 0), Color(0.55, 0.75, 1.0))
		_shake = maxf(_shake, 0.45 if target == player else 0.3)
	_shockwave(origin + Vector3(0, 1.1, 0) + fwd * 0.6)
	_rumble(0.4, 0.6, 0.2)
	if music != null:
		music.combat_event()

func _shockwave(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.8)
	tm.material = mat
	ring.mesh = tm
	ring.position = at
	ring.rotation.x = PI / 2.0
	ring.scale = Vector3.ONE * 0.4
	add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.8, 1.0)
	light.light_energy = 3.0
	light.omni_range = 5.0
	ring.add_child(light)
	var tw := create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(11, 4, 11), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.chain().tween_callback(ring.queue_free)

func spawn_bolt(from: GroundFighter) -> void:
	var origin := from.global_position + Vector3(0, 1.25, 0) - from.global_transform.basis.z * 0.5
	var target := from.enemy if from == player else player
	var dir := -from.global_transform.basis.z
	if from.is_player:
		# Shoot where the camera looks
		dir = -camera.global_transform.basis.z
	elif target != null:
		dir = (target.global_position + Vector3(0, 1.1, 0) - origin).normalized()
		dir = (dir + Vector3(randf_range(-0.04, 0.04), randf_range(-0.02, 0.02), randf_range(-0.04, 0.04))).normalized()
	var bolt := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.035
	bm.height = 0.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.3, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.25, 0.15)
	mat.emission_energy_multiplier = 6.0
	bm.material = mat
	bolt.mesh = bm
	bolt.position = origin
	add_child(bolt)
	bolt.look_at(origin + dir)
	bolt.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.3, 0.2)
	light.light_energy = 1.2
	light.omni_range = 3.0
	bolt.add_child(light)
	_bolts.append({"node": bolt, "dir": dir, "life": 1.6, "from": from})

func _update_bolts(delta: float) -> void:
	var keep: Array = []
	for b in _bolts:
		var node: MeshInstance3D = b["node"]
		b["life"] -= delta
		var prev: Vector3 = node.position
		node.position += b["dir"] * 32.0 * delta
		var dead: bool = b["life"] <= 0.0
		# Hit fighters — a saber held in guard DEFLECTS the bolt back
		for f: GroundFighter in [player] + enemies:
			if f == b["from"] or not f.alive or dead:
				continue
			var center: Vector3 = f.global_position + Vector3(0, 1.0, 0)
			if _seg_point_dist(prev, node.position, center) < 0.55:
				var facing: float = (-f.global_transform.basis.z).dot((-b["dir"] as Vector3).normalized())
				if f.blocking and f.cfg["melee"] and facing > 0.2:
					var shooter: GroundFighter = b["from"]
					var back: Vector3 = -b["dir"]
					if shooter != null and shooter.alive:
						back = (shooter.global_position + Vector3(0, 1.1, 0) - node.position).normalized()
						back = (back + Vector3(randf_range(-0.05, 0.05), randf_range(-0.03, 0.03), randf_range(-0.05, 0.05))).normalized()
					b["dir"] = back
					b["from"] = f
					b["life"] = 1.6
					node.position += back * 0.7
					_deflect_fx(center + Vector3(0, 0.3, 0))
					if f == player:
						_hitmark_t = 0.22
				else:
					f.take_hit(b["from"].cfg["dmg"], b["from"])
					_hit_flash(center, Color(1, 0.4, 0.2))
					dead = true
		# Hit the ground or fly out of the arena
		if node.position.y < 0.05:
			_hit_flash(node.position, Color(1, 0.5, 0.2))
			dead = true
		elif Vector2(node.position.x, node.position.z).length() > ARENA_R + 14.0 or node.position.y > 25.0:
			dead = true
		if dead:
			node.queue_free()
		else:
			keep.append(b)
	_bolts = keep

func _seg_point_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.000001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (a + ab * t).distance_to(p)

func _deflect_fx(at: Vector3) -> void:
	_sparks(at, Color(1.0, 0.85, 0.45), 18, 3.5)
	_shake = maxf(_shake, 0.18)
	var sp := AudioStreamPlayer3D.new()
	sp.stream = load("res://assets/audio/saber_clash.wav")
	sp.position = at
	sp.unit_size = 12.0
	sp.bus = "SFX"
	sp.volume_db = -9.0
	sp.pitch_scale = randf_range(1.25, 1.45)
	add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)
	if music != null:
		music.combat_event(0.5)

func saber_clash(at: Vector3) -> void:
	_sparks(at, Color(1.0, 0.9, 0.5), 80, 6.5)
	_shake = maxf(_shake, 0.5)
	hit_stop(0.07, 0.1)
	_rumble(0.5, 0.7, 0.18)
	if music != null:
		music.combat_event()
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.8)
	flash.light_energy = 4.5
	flash.omni_range = 4.0
	flash.position = at
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	var sp := AudioStreamPlayer3D.new()
	sp.stream = load("res://assets/audio/saber_clash.wav")
	sp.position = at
	sp.unit_size = 14.0
	sp.bus = "SFX"
	sp.pitch_scale = randf_range(0.92, 1.1)
	add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)

func _hit_flash(at: Vector3, color: Color) -> void:
	_sparks(at, color, 14, 3.0)

func _sparks(at: Vector3, color: Color, count: int, vel: float) -> void:
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = vel * 0.4
	mat.initial_velocity_max = vel
	mat.gravity = Vector3(0, -9.0, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.7
	mat.color = color
	mat.damping_min = 1.2
	mat.damping_max = 3.0
	mat.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	mat.collision_bounce = 0.5
	mat.collision_friction = 0.3
	var dm := SphereMesh.new()
	dm.radius = 0.022
	dm.height = 0.044
	dm.radial_segments = 4
	dm.rings = 2
	var dmm := StandardMaterial3D.new()
	dmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmm.albedo_color = color
	dmm.emission_enabled = true
	dmm.emission = color
	dmm.emission_energy_multiplier = 5.0
	dm.material = dmm
	p.draw_pass_1 = dm
	p.process_material = mat
	p.amount = count
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = true
	p.position = at
	add_child(p)
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

# Ribbon trail behind each saber while swinging.
func _update_trails() -> void:
	for f: GroundFighter in _trails:
		var t: Dictionary = _trails[f]
		var pts: Array = t["points"]
		if f.alive and f.attacking:
			pts.append([f.trail_base, f.trail_tip])
		if pts.size() > 16 or (not f.attacking and pts.size() > 0):
			pts.pop_front()
		if not f.attacking and pts.size() > 0:
			pts.pop_front()
		var im: ImmediateMesh = (t["mesh"] as MeshInstance3D).mesh
		im.clear_surfaces()
		if pts.size() < 2:
			continue
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		var col: Color = f.cfg["saber_color"]
		for i in pts.size():
			var alpha := pow(float(i) / pts.size(), 1.4) * 0.42
			im.surface_set_color(Color(col.r, col.g, col.b, alpha))
			im.surface_add_vertex(pts[i][0])
			im.surface_add_vertex(pts[i][1])
		im.surface_end()

# ------------------------------------------------------------ match flow

func _on_died(f: GroundFighter) -> void:
	if _ended:
		return
	var foes_left := false
	for e in enemies:
		if e.alive:
			foes_left = true
	if f != player and foes_left:
		_show_msg("ENCORE UN !")
		hit_stop(0.12, 0.1)
		return
	if not _intro_done:
		_end_intro()
	_ended = true
	Engine.time_scale = 0.32
	var won := f != player
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_start_cinematic(player if won else f))
	get_tree().create_timer(3.4).timeout.connect(func() -> void: _show_end(won))

func _start_cinematic(winner: GroundFighter) -> void:
	# slow orbit around the victor while the end panel fades in
	_cine_target = winner
	_cine_pivot = Node3D.new()
	_cine_pivot.position = winner.global_position + Vector3(0, 1.3, 0)
	_cine_pivot.rotation.y = _cam_yaw + 0.6
	add_child(_cine_pivot)
	var ccam := Camera3D.new()
	ccam.position = Vector3(0, 0.35, 3.4)
	ccam.fov = 55.0
	_cine_pivot.add_child(ccam)
	ccam.look_at_from_position(_cine_pivot.position + _cine_pivot.basis * ccam.position, _cine_pivot.position, Vector3.UP)
	ccam.make_current()

func _show_end(won: bool) -> void:
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var layer := CanvasLayer.new()
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.42)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	layer.add_child(box)
	var title := UiKit.label("VICTOIRE !" if won else "DÉFAITE…", 76, UiKit.SW_YELLOW if won else Color(0.95, 0.3, 0.22), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub_txt := "La Force est puissante en toi." if won else "« %s »" % enemy.cfg["quote"]
	if won and campaign_mode and not campaign_next:
		sub_txt = "La campagne est terminée. La galaxie se souviendra de toi."
	var sub := UiKit.label(sub_txt, 22, Color(0.85, 0.85, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	if won and campaign_mode and campaign_next:
		var bn := UiKit.button("CHAPITRE SUIVANT", 22)
		bn.custom_minimum_size = Vector2(440, 58)
		bn.pressed.connect(func() -> void: request_next.emit())
		box.add_child(bn)
	var b1 := UiKit.button("RECOMMENCER CE DUEL" if campaign_mode else "REJOUER", 22)
	b1.custom_minimum_size = Vector2(440, 58)
	b1.pressed.connect(func() -> void: request_restart.emit())
	box.add_child(b1)
	var b2 := UiKit.button("CHANGER DE PILOTE", 22)
	b2.custom_minimum_size = Vector2(440, 58)
	b2.pressed.connect(func() -> void: request_menu.emit())
	box.add_child(b2)
