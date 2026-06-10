class_name GroundArena
extends Node3D

# Battlefront-style 1v1 character duel inside an Imperial corridor.
# Real animated character models (see CREDITS.md), over-shoulder camera,
# saber combos, blocking, clashes and blaster fire.

signal request_restart
signal request_menu

const ROSTER := {
	"luke": {
		"name": "Luke Skywalker", "type": "jedi", "melee": true,
		"model": "res://assets/models/characters/jedi.glb",
		"model_yaw": 0.0, "model_scale": 1.0,
		"saber_color": Color(0.3, 1.0, 0.4),
		"hp": 120.0, "speed": 5.6, "dmg": 16.0, "reach": 2.4, "lunge": 5.5,
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
		"name": "Dark Vador", "type": "vader", "melee": true,
		"model": "res://assets/models/vader/scene.gltf",
		"normalize_len": 2.25, "model_yaw": PI, "model_offset_y": 1.14,
		"saber_color": Color(1.0, 0.12, 0.08),
		"hp": 170.0, "speed": 3.4, "dmg": 26.0, "reach": 2.8, "lunge": 4.5,
		"attack_time": 0.85, "attack_move_factor": 0.5,
		"ai_skill": 0.5, "ai_block_chance": 0.3,
		"quote": "Je trouve votre manque de foi déplorable.",
		"anims": {},
	},
	"trooper": {
		"name": "Stormtrooper", "type": "shooter", "melee": false,
		"model": "res://assets/models/characters/trooper.glb",
		"model_yaw": PI, "model_scale": 1.0,
		"saber_color": Color(1.0, 0.3, 0.2),
		"hp": 90.0, "speed": 6.2, "dmg": 8.0,
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

const HALL_W := 10.0
const HALL_L := 42.0
const HALL_H := 4.4

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
	player = _spawn(player_id, true, Vector3(0, 0.1, 12), PI)
	enemy = _spawn(enemy_id, false, Vector3(0, 0.1, -12), 0.0)
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

# ------------------------------------------------------------ corridor

func _build_corridor() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.013, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.68)
	env.ambient_light_energy = 0.42
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_hdr_threshold = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.12
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.sdfgi_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.07, 0.1)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.9, 0.4, 0)
	key.light_energy = 0.35
	key.light_color = Color(0.85, 0.9, 1.0)
	key.shadow_enabled = true
	add_child(key)

	# Materials
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.62, 0.64, 0.68)
	wall_mat.metallic = 0.15
	wall_mat.roughness = 0.55
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.18, 0.19, 0.23)
	dark_mat.metallic = 0.4
	dark_mat.roughness = 0.5
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.38, 0.40, 0.45)
	floor_mat.metallic = 0.62
	floor_mat.roughness = 0.22
	var red_mat := StandardMaterial3D.new()
	red_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red_mat.albedo_color = Color(1.0, 0.12, 0.1)
	red_mat.emission_enabled = true
	red_mat.emission = Color(1.0, 0.12, 0.1)
	red_mat.emission_energy_multiplier = 2.2
	var neon_mat := StandardMaterial3D.new()
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon_mat.albedo_color = Color(1.0, 1.0, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(0.95, 0.97, 1.0)
	neon_mat.emission_energy_multiplier = 4.0
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.04, 0.05, 0.08)
	window_mat.metallic = 0.8
	window_mat.roughness = 0.1
	window_mat.emission_enabled = true
	window_mat.emission = Color(0.15, 0.3, 0.45)
	window_mat.emission_energy_multiplier = 0.5

	# Floor: real textured deck tiles from the Jedi Outcast remake (2x2 m,
	# 5 variants), over an invisible collision slab. Ceiling stays flat.
	_collision_box(Vector3(0, -0.1, 0), Vector3(HALL_W, 0.2, HALL_L))
	var tiles: Array = _collect_floor_tiles()
	if tiles.is_empty():
		_box(Vector3(0, -0.1, 0), Vector3(HALL_W, 0.2, HALL_L), floor_mat)
	else:
		var trng := RandomNumberGenerator.new()
		trng.seed = 42
		var nx := int(HALL_W / 2.0)
		var nz := int(HALL_L / 2.0)
		for ix in nx:
			for iz in nz:
				var mi := MeshInstance3D.new()
				mi.mesh = tiles[trng.randi_range(0, tiles.size() - 1)]
				mi.position = Vector3(-HALL_W / 2.0 + 1.0 + ix * 2.0, -0.161, -HALL_L / 2.0 + 1.0 + iz * 2.0)
				mi.rotation.y = (PI / 2.0) * trng.randi_range(0, 3)
				add_child(mi)
	_box(Vector3(0, HALL_H + 0.1, 0), Vector3(HALL_W, 0.2, HALL_L), wall_mat)

	# Walls with panel details
	for side: float in [-1.0, 1.0]:
		var x := side * HALL_W / 2.0
		_box(Vector3(x, HALL_H / 2.0, 0), Vector3(0.2, HALL_H, HALL_L), wall_mat)
		# Red accent stripe (like the BF2 corridors)
		_box(Vector3(x - side * 0.12, 0.55, 0), Vector3(0.05, 0.1, HALL_L), red_mat, false)
		# Dark baseboard
		_box(Vector3(x - side * 0.1, 0.15, 0), Vector3(0.08, 0.3, HALL_L), dark_mat, false)
		var n := int(HALL_L / 4.0)
		for i in n:
			var z := -HALL_L / 2.0 + 2.0 + i * 4.0
			# Vertical pillars between panels
			_box(Vector3(x - side * 0.18, HALL_H / 2.0, z + 2.0), Vector3(0.18, HALL_H, 0.35), dark_mat, false)
			# Inset window band on alternating panels
			if i % 2 == 0:
				_box(Vector3(x - side * 0.08, 2.3, z), Vector3(0.06, 0.9, 2.6), window_mat, false)
			else:
				# Tech greeble panel
				_box(Vector3(x - side * 0.07, 1.5, z), Vector3(0.05, 1.4, 2.2), dark_mat, false)

	# Conduits/pipes running along the top of each wall + floor light strips
	var pipe_mat := StandardMaterial3D.new()
	pipe_mat.albedo_color = Color(0.28, 0.29, 0.33)
	pipe_mat.metallic = 0.75
	pipe_mat.roughness = 0.35
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(0.6, 0.8, 1.0)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.55, 0.75, 1.0)
	strip_mat.emission_energy_multiplier = 1.4
	for side: float in [-1.0, 1.0]:
		var x2 := side * (HALL_W / 2.0 - 0.22)
		for pi in 2:
			var pipe := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.07 - pi * 0.025
			cm.bottom_radius = cm.top_radius
			cm.height = HALL_L
			cm.material = pipe_mat
			pipe.mesh = cm
			pipe.rotation.x = PI / 2.0
			pipe.position = Vector3(x2, HALL_H - 0.45 - pi * 0.22, 0)
			add_child(pipe)
		# Soft blue-white light strip at floor level
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.03, 0.04, HALL_L)
		sm.material = strip_mat
		strip.mesh = sm
		strip.position = Vector3(side * (HALL_W / 2.0 - 0.13), 0.05, 0)
		add_child(strip)

	# Dark cross beams under the ceiling
	var n_beams := int(HALL_L / 6.0)
	for i in n_beams:
		var z3 := -HALL_L / 2.0 + 6.0 + i * 6.0
		_box(Vector3(0, HALL_H - 0.12, z3), Vector3(HALL_W, 0.22, 0.4), dark_mat, false)

	# Ceiling light fixtures + lights
	var n_lights := int(HALL_L / 6.0)
	for i in n_lights + 1:
		var z := -HALL_L / 2.0 + 3.0 + i * 6.0
		_box(Vector3(0, HALL_H - 0.03, z), Vector3(1.8, 0.06, 0.5), neon_mat, false)
		_box(Vector3(0, HALL_H - 0.08, z), Vector3(2.1, 0.1, 0.8), dark_mat, false)
		var l := OmniLight3D.new()
		l.position = Vector3(0, HALL_H - 0.6, z)
		l.light_color = Color(0.92, 0.95, 1.0)
		l.light_energy = 1.5
		l.omni_range = 8.5
		l.shadow_enabled = i % 2 == 0
		add_child(l)

	# Blast doors at both ends
	for endz: float in [-1.0, 1.0]:
		var z2 := endz * HALL_L / 2.0
		_box(Vector3(0, HALL_H / 2.0, z2), Vector3(HALL_W, HALL_H, 0.3), dark_mat)
		_box(Vector3(0, HALL_H / 2.0, z2 - endz * 0.18), Vector3(3.6, 3.4, 0.1), wall_mat, false)
		_box(Vector3(0, HALL_H / 2.0, z2 - endz * 0.26), Vector3(0.08, 3.4, 0.06), red_mat, false)

	_place_props()

# Adds a box mesh; with_collision also registers a static collider.
func _box(pos: Vector3, size: Vector3, mat: Material, with_collision: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	if with_collision:
		_collision_box(pos, size)

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

# One deck-tile mesh per LevelFloor variant in the remake's instanced file.
func _collect_floor_tiles() -> Array:
	var tiles: Array = []
	var ps: PackedScene = load("res://assets/models/imperial_base.glb")
	if ps == null:
		return tiles
	var inst: Node = ps.instantiate()
	var stack: Array = [inst]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and "Floor" in n.get_parent().name and not seen.has(n.get_parent().name):
			seen[n.get_parent().name] = true
			tiles.append((n as MeshInstance3D).mesh)
		for c in n.get_children():
			stack.push_back(c)
	inst.free()
	return tiles

# Real crates/barrels from the Jedi Outcast remake, placed along the walls.
func _place_props() -> void:
	var sources: Array = []
	for path in ["res://assets/models/imperial_base.glb", "res://assets/models/imperial_base_dc.glb"]:
		var ps: PackedScene = load(path)
		if ps == null:
			continue
		var inst: Node = ps.instantiate()
		var stack: Array = [inst]
		var seen: Dictionary = {}
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var base: String = mi.name.get_slice("_", 0)
				if not seen.has(base) and (base.begins_with("Create") or "Barrel" in mi.name or "barrel" in mi.name):
					seen[base] = true
					sources.append(mi.mesh)
			for c in n.get_children():
				stack.push_back(c)
		inst.free()
	if sources.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	var spots := [
		Vector3(-3.8, 0, -16), Vector3(3.7, 0, -14), Vector3(-3.6, 0, -7),
		Vector3(3.8, 0, 7), Vector3(-3.7, 0, 14), Vector3(3.6, 0, 16),
		Vector3(-3.9, 0, 2), Vector3(3.9, 0, -2),
	]
	for spot in spots:
		var mesh: Mesh = sources[rng.randi_range(0, sources.size() - 1)]
		var aabb := mesh.get_aabb()
		var target_h := rng.randf_range(0.9, 1.4)
		var s := target_h / maxf(aabb.size.y, 0.01)
		var mi2 := MeshInstance3D.new()
		mi2.mesh = mesh
		mi2.scale = Vector3.ONE * s
		mi2.position = spot - Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) * s
		mi2.rotation.y = rng.randf_range(0, TAU)
		add_child(mi2)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(aabb.size.x * s, target_h, aabb.size.z * s)
		cs.shape = shape
		cs.position = Vector3(0, target_h / 2.0, 0)
		sb.add_child(cs)
		sb.position = spot
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
		player.move_input = mv
		player.face_yaw = _cam_yaw
		if Input.is_action_just_pressed("fire"):
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
	camera.fov = lerpf(camera.fov, 65.0 + hv * 1.1, 5.0 * delta)

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
		# Hit walls
		if absf(node.position.x) > HALL_W / 2.0 - 0.2 or absf(node.position.z) > HALL_L / 2.0 - 0.2 or node.position.y < 0.05 or node.position.y > HALL_H:
			_hit_flash(node.position, Color(1, 0.5, 0.2))
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
	_sparks(at, Color(1.0, 0.9, 0.5), 90, 7.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.8)
	flash.light_energy = 6.0
	flash.omni_range = 7.0
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
	_sparks(at, color, 30, 4.0)

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
		if pts.size() > 10 or (not f.attacking and pts.size() > 0):
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
			var alpha := float(i) / pts.size() * 0.25
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
