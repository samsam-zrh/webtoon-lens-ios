class_name GroundArena
extends Node3D

# Battlefront-style 1v1 character duel inside an Imperial throne room
# (Death Star II inspired).
# Real animated character models (see CREDITS.md), over-shoulder camera,
# saber combos, blocking, clashes and blaster fire.

signal request_restart
signal request_menu

const ROSTER := {
	"luke": {
		"name": "Luke Skywalker", "type": "jedi", "melee": true,
		"model": "res://assets/models/characters/jedi.glb",
		"model_yaw": PI, "model_scale": 1.0,
		"saber_color": Color(0.3, 1.0, 0.4),
		"hp": 120.0, "speed": 5.6, "dmg": 16.0, "reach": 2.4, "lunge": 5.5, "turn_speed": 13.0,
		"attack_time": 0.7, "attack_anim_speed": 1.45, "attack_move_factor": 0.3,
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
		"attack_time": 0.7, "attack_anim_speed": 1.1, "attack_move_factor": 0.35,
		"ai_skill": 0.5, "ai_block_chance": 0.35,
		"quote": "Je trouve votre manque de foi déplorable.",
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
		"hp": 90.0, "speed": 6.2, "dmg": 8.0, "turn_speed": 11.0,
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
}

var player: GroundFighter
var enemy: GroundFighter
var camera: Camera3D
var _spring: SpringArm3D
var _cam_pivot: Node3D
var _cam_pitch_node: Node3D
var _cam_yaw := 0.0
var _cam_pitch := -0.12

var _started := false
var _ended := false
var _hud: Control
var _msg: Label
var _bolts: Array = []
var _trails: Dictionary = {}  # fighter -> {points: Array, mesh: MeshInstance3D}

func start(player_id: String, enemy_id: String) -> void:
	_build_corridor()
	player = _spawn(player_id, true, Vector3(0, 0.1, 12), 0.0)
	enemy = _spawn(enemy_id, false, Vector3(0, 0.1, -12), PI)
	player.enemy = enemy
	enemy.enemy = player
	player.died.connect(_on_died)
	enemy.died.connect(_on_died)

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
	camera.fov = 65.0
	camera.near = 0.1
	_spring.add_child(camera)
	camera.make_current()

	_build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var seq := ["3", "2", "1", "EN GARDE !"]
	for i in seq.size():
		var txt: String = seq[i]
		get_tree().create_timer(0.8 * i + 0.4).timeout.connect(func() -> void:
			if not is_instance_valid(self):
				return
			_show_msg(txt)
			if txt == "EN GARDE !":
				_started = true
				player.controls_enabled = true
				enemy.controls_enabled = true)

func _spawn(id: String, is_player: bool, pos: Vector3, yaw: float) -> GroundFighter:
	var f := GroundFighter.new()
	f.collision_layer = 2
	f.collision_mask = 3
	add_child(f)
	f.setup(ROSTER[id].duplicate(true), is_player, self)
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

const ARENA_R := 14.0       # gameplay boundary (inside the walls)
const ROOM_R := 17.0        # octagon wall radius
const ROOM_H := 10.0

func _build_corridor() -> void:
	_build_environment()
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_throne()
	_build_space_view()
	_build_boundary()

	var amb := AudioStreamPlayer.new()
	var hum: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
	hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.loop_end = hum.data.size() / 2
	amb.stream = hum
	amb.volume_db = -18.0
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
	env.ambient_light_color = Color(0.19, 0.21, 0.28)
	env.ambient_light_energy = 1.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.22
	env.glow_enabled = true
	env.glow_intensity = 0.42
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.5
	env.sdfgi_enabled = true
	env.volumetric_fog_enabled = true
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
	well.light_color = Color(0.85, 0.9, 1.0)
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
	m.albedo_color = Color(0.115, 0.12, 0.145)
	m.metallic = 0.55
	m.roughness = 0.42
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

func _build_space_view() -> void:
	# Star Destroyer on patrol, far beyond the viewport
	var sd := ModelUtil.load_model("res://assets/models/star_destroyer.glb", 260.0, 0.35)
	sd.position = Vector3(-110, 30, -420)
	add_child(sd)
	var drift := create_tween().set_loops()
	drift.tween_property(sd, "position:x", 60.0, 160.0)
	drift.tween_property(sd, "position:x", -110.0, 160.0)
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
	layer.add_child(UiKit.vignette())
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_msg = UiKit.label("", 60, UiKit.SW_YELLOW, true)
	_msg.visible = false
	_hud.add_child(_msg)
	var n1 := UiKit.label(player.cfg["name"], 17, Color(0.85, 0.88, 1.0))
	n1.position = Vector2(36, 24)
	_hud.add_child(n1)
	var n2 := UiKit.label(enemy.cfg["name"], 17, Color(1, 0.5, 0.45))
	n2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	n2.position = Vector2(-300, 24)
	_hud.add_child(n2)
	var help := UiKit.label(
		("Clic : attaque (enchaîne !)  •  Clic droit : parade  •  Maj : esquive" if player.cfg["melee"]
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
	_bar(Vector2(vp.x - 36 - 300, 52), 300, enemy.hp / enemy.cfg["hp"], Color(1, 0.32, 0.27))
	# Dash cooldown pip
	_bar(Vector2(36, 74), 120, 1.0 - player.dash_cooldown / 1.1, Color(0.4, 0.7, 1.0))
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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * 0.0032
		_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.0026, -0.95, 0.55)
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
		# Free movement: the character faces where it runs; it squares up to
		# the enemy while attacking or blocking (soft lock).
		var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
		var right := Vector3(-fwd.z, 0, fwd.x)
		var wdir := fwd * mv.y + right * mv.x
		var lock := player.attacking or player.blocking
		if lock and enemy.alive:
			var to_e := enemy.global_position - player.global_position
			player.face_yaw = atan2(-to_e.x, -to_e.z)
			var pfwd := Vector3(-sin(player.face_yaw), 0, -cos(player.face_yaw))
			var pright := Vector3(-pfwd.z, 0, pfwd.x)
			player.move_input = Vector2(wdir.dot(pright), wdir.dot(pfwd)).limit_length(1.0)
		elif wdir.length() > 0.1:
			player.face_yaw = atan2(-wdir.x, -wdir.z)
			player.move_input = Vector2(0, wdir.length())
		else:
			player.move_input = Vector2.ZERO
		if Input.is_action_just_pressed("fire"):
			if enemy.alive:
				var to_e2 := enemy.global_position - player.global_position
				player.face_yaw = atan2(-to_e2.x, -to_e2.z)
			player.try_attack()
		player.set_blocking(Input.is_action_pressed("block"))
		if Input.is_action_just_pressed("boost"):
			player.try_dash()

	_update_bolts(delta)
	_update_trails()
	_update_camera(delta)
	_hud.queue_redraw()

func _update_camera(delta: float) -> void:
	var target := player
	if not target.alive and enemy.alive:
		target = enemy
	_cam_pivot.position = _cam_pivot.position.lerp(target.global_position + Vector3(0, 1.55, 0), clampf(14.0 * delta, 0, 1))
	_cam_pivot.rotation.y = _cam_yaw
	_cam_pitch_node.rotation.x = _cam_pitch
	var hv := Vector2(target.velocity.x, target.velocity.z).length()
	camera.fov = lerpf(camera.fov, 65.0 + hv * 0.35, 5.0 * delta)

# ------------------------------------------------------------ combat services

func melee_hit(attacker: GroundFighter) -> void:
	var target := enemy if attacker == player else player
	if target == null or not target.alive:
		return
	var to_t := target.global_position - attacker.global_position
	to_t.y = 0
	var facing := (-attacker.global_transform.basis.z).dot(to_t.normalized())
	if to_t.length() <= attacker.saber_reach() and facing > 0.35:
		target.take_hit(attacker.cfg["dmg"], attacker)
		_hit_flash(target.global_position + Vector3(0, 1.2, 0), attacker.cfg["saber_color"])

func spawn_bolt(from: GroundFighter) -> void:
	var origin := from.global_position + Vector3(0, 1.25, 0) - from.global_transform.basis.z * 0.5
	var target := enemy if from == player else player
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
		# Hit fighters
		for f: GroundFighter in [player, enemy]:
			if f == b["from"] or not f.alive or dead:
				continue
			var center: Vector3 = f.global_position + Vector3(0, 1.0, 0)
			if _seg_point_dist(prev, node.position, center) < 0.55:
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

func saber_clash(at: Vector3) -> void:
	_sparks(at, Color(1.0, 0.9, 0.5), 36, 4.5)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.8)
	flash.light_energy = 3.0
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
	mat.damping_min = 2.0
	mat.damping_max = 5.0
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
	p.lifetime = 0.6
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
		if pts.size() > 8 or (not f.attacking and pts.size() > 0):
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
			var alpha := float(i) / pts.size() * 0.16
			im.surface_set_color(Color(col.r, col.g, col.b, alpha))
			im.surface_add_vertex(pts[i][0])
			im.surface_add_vertex(pts[i][1])
		im.surface_end()

# ------------------------------------------------------------ match flow

func _on_died(f: GroundFighter) -> void:
	if _ended:
		return
	_ended = true
	Engine.time_scale = 0.4
	get_tree().create_timer(0.45).timeout.connect(func() -> void: Engine.time_scale = 1.0)
	var won := f == enemy
	get_tree().create_timer(1.8).timeout.connect(func() -> void: _show_end(won))

func _show_end(won: bool) -> void:
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var layer := CanvasLayer.new()
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
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
	var sub := UiKit.label("La Force est puissante en toi." if won else "« %s »" % enemy.cfg["quote"], 22, Color(0.85, 0.85, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var b1 := UiKit.button("REJOUER", 22)
	b1.custom_minimum_size = Vector2(440, 58)
	b1.pressed.connect(func() -> void: request_restart.emit())
	box.add_child(b1)
	var b2 := UiKit.button("CHANGER DE PILOTE", 22)
	b2.custom_minimum_size = Vector2(440, 58)
	b2.pressed.connect(func() -> void: request_menu.emit())
	box.add_child(b2)
