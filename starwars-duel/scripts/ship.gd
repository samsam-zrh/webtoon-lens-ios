class_name Ship
extends Node3D

# Arcade space fighter shared by the player and the AI.
# Forward is -Z. Steering uses pitch/yaw/roll rates smoothed over time.

signal died(ship: Ship)
signal damaged(ship: Ship)
signal fired_laser(laser: Laser)

var cfg: Dictionary
var is_player := false
var arena: Node3D
var enemy: Ship

var hp := 100.0
var alive := true
var controls_enabled := false

var speed := 40.0
var throttle := 0.6
var boost_energy := 1.0
var boosting := false

var pitch_input := 0.0
var yaw_input := 0.0
var roll_input := 0.0
var fire_held := false

var _fire_cooldown := 0.0
var _muzzle_flip := 1.0
var _visual_bank := 0.0

# AI state
var _ai_state := "pursue"
var _ai_timer := 0.0
var _ai_evade_dir := Vector2.ZERO
var _ai_aim_jitter := Vector3.ZERO

var model: Node3D
var collision_radius := 6.0
var _engine_particles: Array = []
var _sfx_engine: AudioStreamPlayer3D
var _sfx_laser: AudioStreamPlayer3D
var _sfx_hit: AudioStreamPlayer3D
var _sfx_boost: AudioStreamPlayer3D

const LASER_SPEED := 320.0

func setup(p_cfg: Dictionary, p_is_player: bool, p_arena: Node3D) -> void:
	cfg = p_cfg
	is_player = p_is_player
	arena = p_arena
	hp = cfg["hp"]
	collision_radius = cfg["target_len"] * 0.42

	model = ModelUtil.load_model(cfg["model"], cfg["target_len"], cfg["model_rot"])
	add_child(model)

	_build_engine_glow()
	_build_audio()

func _build_engine_glow() -> void:
	var col: Color = cfg["engine_color"]
	for x in [-1.0, 1.0]:
		var p := GPUParticles3D.new()
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 0, 1)
		mat.spread = 4.0
		mat.initial_velocity_min = 18.0
		mat.initial_velocity_max = 26.0
		mat.gravity = Vector3.ZERO
		mat.scale_min = 0.5
		mat.scale_max = 0.9
		mat.color = col
		var ramp := Gradient.new()
		ramp.set_color(0, Color(col.r, col.g, col.b, 0.9))
		ramp.set_color(1, Color(col.r * 0.4, col.g * 0.4, col.b * 0.6, 0.0))
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = ramp
		mat.color_ramp = ramp_tex
		p.process_material = mat
		p.amount = 48
		p.lifetime = 0.35
		p.local_coords = true
		var dm := SphereMesh.new()
		dm.radius = 0.18
		dm.height = 0.36
		var dmm := StandardMaterial3D.new()
		dmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmm.albedo_color = col
		dmm.emission_enabled = true
		dmm.emission = col
		dmm.emission_energy_multiplier = 3.0
		dmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmm.vertex_color_use_as_albedo = true
		dm.material = dmm
		p.draw_pass_1 = dm
		p.position = Vector3(x * cfg["target_len"] * 0.16, 0.0, cfg["target_len"] * 0.45)
		add_child(p)
		_engine_particles.append(p)
	var glow := OmniLight3D.new()
	glow.light_color = col
	glow.light_energy = 1.4
	glow.omni_range = 9.0
	glow.position = Vector3(0, 0, cfg["target_len"] * 0.45)
	add_child(glow)

func _build_audio() -> void:
	_sfx_engine = AudioStreamPlayer3D.new()
	var eng: AudioStreamWAV = load("res://assets/audio/engine.wav").duplicate()
	eng.loop_mode = AudioStreamWAV.LOOP_FORWARD
	eng.loop_end = eng.data.size() / 2
	_sfx_engine.stream = eng
	_sfx_engine.unit_size = 14.0
	_sfx_engine.volume_db = -8.0
	add_child(_sfx_engine)

	_sfx_laser = AudioStreamPlayer3D.new()
	_sfx_laser.stream = load("res://assets/audio/laser_green.wav" if cfg["laser_color"].g > 0.6 else "res://assets/audio/laser_red.wav")
	_sfx_laser.unit_size = 30.0
	_sfx_laser.max_polyphony = 4
	add_child(_sfx_laser)

	_sfx_hit = AudioStreamPlayer3D.new()
	_sfx_hit.stream = load("res://assets/audio/hit.wav")
	_sfx_hit.unit_size = 25.0
	_sfx_hit.max_polyphony = 3
	add_child(_sfx_hit)

	_sfx_boost = AudioStreamPlayer3D.new()
	_sfx_boost.stream = load("res://assets/audio/boost.wav")
	_sfx_boost.unit_size = 20.0
	add_child(_sfx_boost)

func _ready() -> void:
	_sfx_engine.play()

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if controls_enabled and not is_player:
		_ai_think(delta)

	# Throttle and boost
	var max_speed: float = cfg["max_speed"]
	var target_speed: float = lerpf(18.0, max_speed, throttle)
	if boosting and boost_energy > 0.0 and controls_enabled:
		target_speed = cfg["boost_speed"]
		boost_energy = maxf(0.0, boost_energy - delta * 0.45)
	else:
		boost_energy = minf(1.0, boost_energy + delta * 0.18)
	speed = lerpf(speed, target_speed, 2.4 * delta)

	# Rotation
	var tr: float = cfg["turn_rate"]
	if not controls_enabled:
		pitch_input = 0.0
		yaw_input = 0.0
		roll_input = 0.0
	rotate_object_local(Vector3.RIGHT, pitch_input * tr * delta)
	rotate_object_local(Vector3.UP, yaw_input * tr * delta)
	rotate_object_local(Vector3.FORWARD, roll_input * tr * 1.8 * delta)

	# Visual banking on the model when yawing
	_visual_bank = lerpf(_visual_bank, -yaw_input * 0.55, 4.0 * delta)
	if model:
		model.rotation.z = _visual_bank

	position += -global_transform.basis.z * speed * delta

	# Engine sound follows speed
	_sfx_engine.pitch_scale = 0.8 + speed / cfg["boost_speed"] * 0.7

	# Firing
	_fire_cooldown -= delta
	if controls_enabled and fire_held and _fire_cooldown <= 0.0:
		_fire()

	# Soft arena boundary: steer back toward the center
	var dist := position.length()
	if dist > Arena.ARENA_RADIUS:
		var to_center := (-position).normalized()
		var fwd := -global_transform.basis.z
		var corrected := fwd.slerp(to_center, delta * 0.9).normalized()
		look_at(global_position + corrected, global_transform.basis.y)

func _fire() -> void:
	_fire_cooldown = cfg["fire_interval"]
	if not is_player:
		# The AI shoots in slower bursts than a human spamming the trigger
		_fire_cooldown *= 1.7
	_muzzle_flip = -_muzzle_flip
	var muzzle_local := Vector3(_muzzle_flip * cfg["target_len"] * 0.3, 0.0, -cfg["target_len"] * 0.5)
	var origin := global_transform * muzzle_local
	var dir := -global_transform.basis.z
	if not is_player and enemy != null and enemy.alive:
		# AI aims at the predicted enemy position, with skill-based error
		var to_target: Vector3 = enemy.global_position + enemy.linear_velocity() * (global_position.distance_to(enemy.global_position) / LASER_SPEED) - origin
		var err: float = (1.0 - float(cfg["ai_skill"])) * 0.22
		dir = (to_target.normalized() + _ai_aim_jitter * err).normalized()
	var laser := Laser.new()
	laser.setup(self, origin, dir, cfg["laser_color"], cfg["laser_damage"], LASER_SPEED)
	arena.add_child(laser)
	_sfx_laser.play()
	fired_laser.emit(laser)

func linear_velocity() -> Vector3:
	return -global_transform.basis.z * speed

func take_damage(amount: float, _from: Ship) -> void:
	if not alive:
		return
	hp -= amount
	_sfx_hit.play()
	damaged.emit(self)
	if hp <= 0.0:
		hp = 0.0
		_die()

func _die() -> void:
	alive = false
	controls_enabled = false
	died.emit(self)

func start_boost_sfx() -> void:
	if not _sfx_boost.playing:
		_sfx_boost.play()

# ------------------------------------------------------------------ AI

func _ai_think(delta: float) -> void:
	if enemy == null or not enemy.alive:
		fire_held = false
		return
	_ai_timer -= delta
	var skill: float = cfg["ai_skill"]
	var to_enemy: Vector3 = enemy.global_position - global_position
	var dist: float = to_enemy.length()
	var fwd: Vector3 = -global_transform.basis.z
	var facing: float = fwd.dot(to_enemy.normalized())
	var enemy_facing_me: float = (-enemy.global_transform.basis.z).dot(-to_enemy.normalized())

	if _ai_timer <= 0.0:
		_ai_timer = randf_range(0.8, 1.8)
		_ai_aim_jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		# Choose state: evade when the enemy is on our tail, otherwise pursue
		if enemy_facing_me > 0.85 and facing < 0.0 and dist < 350.0 and randf() < 0.7:
			_ai_state = "evade"
			_ai_evade_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		elif dist < 80.0 and facing > 0.5:
			_ai_state = "extend"
		else:
			_ai_state = "pursue"

	match _ai_state:
		"pursue":
			var predicted: Vector3 = enemy.global_position + enemy.linear_velocity() * minf(dist / LASER_SPEED, 1.2)
			_ai_steer_towards(predicted, delta, skill)
			throttle = clampf(dist / 250.0, 0.45, 1.0)
			boosting = dist > 500.0 and boost_energy > 0.4
		"evade":
			pitch_input = _ai_evade_dir.y * 1.0
			yaw_input = _ai_evade_dir.x * 0.8
			roll_input = signf(_ai_evade_dir.x) * 0.7
			throttle = 1.0
			boosting = boost_energy > 0.25
		"extend":
			_ai_steer_towards(global_position + fwd * 100.0 + global_transform.basis.y * 60.0, delta, skill)
			throttle = 1.0
			boosting = false

	fire_held = _ai_state == "pursue" and facing > 0.978 and dist < 520.0

func _ai_steer_towards(target: Vector3, _delta: float, skill: float) -> void:
	var local: Vector3 = global_transform.affine_inverse() * target
	var dir: Vector3 = local.normalized()
	pitch_input = clampf(dir.y * 3.0 * skill, -1.0, 1.0)
	yaw_input = clampf(-dir.x * 3.0 * skill, -1.0, 1.0)
	roll_input = clampf(-dir.x * 0.5, -0.6, 0.6)
