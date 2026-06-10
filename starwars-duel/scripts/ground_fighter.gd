class_name GroundFighter
extends CharacterBody3D

# Battlefront-style character: animated model (Mixamo rig), strafe-locked
# movement, saber combos with blocking, or blaster fire. The same class
# drives the player and the AI.

signal died(fighter: GroundFighter)
signal damaged(fighter: GroundFighter)

const GRAVITY := 26.0

var cfg: Dictionary
var is_player := false
var arena: Node3D
var enemy: GroundFighter

var hp := 100.0
var alive := true
var controls_enabled := false

# Combat state
var attacking := false
var attack_timer := 0.0
var combo_index := 0
var combo_queued := false
var hit_window_done := false
var blocking := false
var hit_stun := 0.0
var dash_timer := 0.0
var dash_cooldown := 0.0
var dash_dir := Vector3.ZERO
var fire_cooldown := 0.0
var burst_left := 0

# Movement intent (set by arena for the player, or by AI)
var move_input := Vector2.ZERO  # x = strafe right, y = forward
var face_yaw := 0.0             # world yaw the body should face

# AI state
var _ai_timer := 0.0
var _ai_strafe := 0.0
var _ai_want_block := false

var model: Node3D
var anim: AnimationPlayer
var saber_pivot: Node3D          # Vader procedural swing pivot
var blade_mesh: MeshInstance3D
var blade_light: OmniLight3D
var trail_base := Vector3.ZERO   # world-space saber base/tip, updated each frame
var trail_tip := Vector3.ZERO

var _sfx_hum: AudioStreamPlayer3D
var _sfx_step_t := 0.0
var _walk_phase := 0.0

func setup(p_cfg: Dictionary, p_is_player: bool, p_arena: Node3D) -> void:
	cfg = p_cfg
	is_player = p_is_player
	arena = p_arena
	hp = cfg["hp"]

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)

	if cfg.has("normalize_len"):
		# Sketchfab model in centimeters: normalize height and recenter
		model = ModelUtil.load_model(cfg["model"], cfg["normalize_len"], cfg.get("model_yaw", 0.0))
	else:
		model = load(cfg["model"]).instantiate()
		if cfg.has("model_scale"):
			model.scale = Vector3.ONE * cfg["model_scale"]
		model.rotation.y = cfg.get("model_yaw", 0.0)
	if cfg.has("model_offset_y"):
		model.position.y = cfg["model_offset_y"]
	add_child(model)

	anim = model.find_child("AnimationPlayer", true, false)
	if anim != null:
		_play(cfg["anims"]["idle"], 0.0)

	_setup_blade()
	_setup_audio()

func _setup_blade() -> void:
	if not cfg["melee"]:
		return
	var color: Color = cfg["saber_color"]
	if cfg["type"] == "jedi":
		# The Kyle model ships with a real blade mesh bone-attached to the hand:
		# recolor it into a glowing energy blade. The attachment node and its
		# mesh child share the same name, so dig for the MeshInstance3D.
		var attach := model.find_child("lightblade_Cylinder_001", true, false)
		if attach is MeshInstance3D:
			blade_mesh = attach
		elif attach != null:
			blade_mesh = attach.find_child("*", true, false) as MeshInstance3D
		if blade_mesh != null:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = color.lerp(Color.WHITE, 0.45)
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 4.5
			for i in blade_mesh.mesh.get_surface_count():
				blade_mesh.set_surface_override_material(i, mat)
			blade_light = OmniLight3D.new()
			blade_light.light_color = color
			blade_light.light_energy = 1.0
			blade_light.omni_range = 2.6
			blade_mesh.add_child(blade_light)
	else:
		# Vader: static Sketchfab model — attach a glowing blade on a pivot so
		# we can swing it procedurally.
		saber_pivot = Node3D.new()
		saber_pivot.position = Vector3(0.5, 1.05, -0.25)
		add_child(saber_pivot)
		blade_mesh = MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.032
		bm.height = 1.3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color.lerp(Color.WHITE, 0.45)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 4.5
		bm.material = mat
		blade_mesh.mesh = bm
		blade_mesh.position = Vector3(0, 0.75, 0)
		saber_pivot.add_child(blade_mesh)
		var hilt := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.035
		hm.bottom_radius = 0.04
		hm.height = 0.28
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.35, 0.36, 0.4)
		hmat.metallic = 0.9
		hmat.roughness = 0.3
		hm.material = hmat
		hilt.mesh = hm
		saber_pivot.add_child(hilt)
		blade_light = OmniLight3D.new()
		blade_light.light_color = color
		blade_light.light_energy = 1.0
		blade_light.omni_range = 2.6
		blade_light.position = Vector3(0, 0.7, 0)
		saber_pivot.add_child(blade_light)

func _setup_audio() -> void:
	if cfg["melee"]:
		_sfx_hum = AudioStreamPlayer3D.new()
		var hum: AudioStreamWAV = load("res://assets/audio/saber_hum.wav").duplicate()
		hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hum.loop_end = hum.data.size() / 2
		_sfx_hum.stream = hum
		_sfx_hum.unit_size = 6.0
		_sfx_hum.volume_db = -10.0
		_sfx_hum.pitch_scale = 1.0 if cfg["type"] == "jedi" else 0.82
		add_child(_sfx_hum)
	if cfg["type"] == "vader":
		var breath := AudioStreamPlayer3D.new()
		var bs: AudioStreamWAV = load("res://assets/audio/vader_breath.wav").duplicate()
		bs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		bs.loop_end = bs.data.size() / 2
		breath.stream = bs
		breath.unit_size = 8.0
		breath.volume_db = -6.0
		add_child(breath)
		breath.play()

func _ready() -> void:
	if _sfx_hum != null:
		_sfx_hum.play()

# ------------------------------------------------------------------ helpers

func _play(name: String, blend: float = 0.2, speed: float = 1.0) -> void:
	if anim == null:
		return
	if anim.has_animation(name) and anim.current_animation != name:
		anim.play(name, blend, speed)

func _play_oneshot(name: String, blend: float = 0.15, speed: float = 1.0) -> float:
	if anim == null or not anim.has_animation(name):
		return 0.8
	anim.play(name, blend, speed)
	return anim.get_animation(name).length / speed

func play_sound(path: String, db: float = 0.0, pitch: float = 1.0) -> void:
	var sp := AudioStreamPlayer3D.new()
	sp.stream = load(path)
	sp.volume_db = db
	sp.pitch_scale = pitch
	sp.unit_size = 12.0
	add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)

func saber_reach() -> float:
	return cfg.get("reach", 2.4)

# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = 0
		velocity.z = 0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	hit_stun = maxf(0.0, hit_stun - delta)

	if controls_enabled and not is_player:
		_ai_think(delta)

	# Attack progression
	if attacking:
		attack_timer -= delta
		if not hit_window_done and attack_timer < cfg["attack_time"] * 0.55:
			hit_window_done = true
			if cfg["melee"]:
				arena.melee_hit(self)
		if attack_timer <= 0.0:
			if combo_queued and combo_index < 2 and cfg["melee"]:
				combo_queued = false
				_start_attack(combo_index + 1)
			else:
				attacking = false
				combo_index = 0

	# Burst fire (trooper)
	if burst_left > 0 and fire_cooldown <= 0.0 and not attacking:
		burst_left -= 1
		fire_cooldown = 0.16
		arena.spawn_bolt(self)
		_play_oneshot(cfg["anims"]["attack"][0], 0.1, 1.4)

	# Movement
	var speed: float = cfg["speed"]
	if blocking:
		speed *= 0.4
	if attacking:
		speed *= cfg.get("attack_move_factor", 0.25)
	if hit_stun > 0.0:
		speed *= 0.2

	var desired := Vector3.ZERO
	if dash_timer > 0.0:
		dash_timer -= delta
		desired = dash_dir * cfg["speed"] * 2.6
	elif controls_enabled:
		var fwd := Vector3(-sin(face_yaw), 0, -cos(face_yaw))
		var right := Vector3(-fwd.z, 0, fwd.x)
		desired = (fwd * move_input.y + right * move_input.x)
		if desired.length() > 1.0:
			desired = desired.normalized()
		desired *= speed

	velocity.x = lerpf(velocity.x, desired.x, 10.0 * delta)
	velocity.z = lerpf(velocity.z, desired.z, 10.0 * delta)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Face direction (strafe-lock toward face_yaw)
	rotation.y = lerp_angle(rotation.y, face_yaw, 12.0 * delta)

	_update_animation(delta)
	_update_saber(delta)
	_footsteps(delta)

func _update_animation(delta: float) -> void:
	if anim == null:
		# Vader procedural motion: slow bob + lean while walking
		var hv := Vector2(velocity.x, velocity.z).length()
		_walk_phase += delta * (1.0 + hv * 1.6)
		if model != null:
			model.position.y = cfg.get("model_offset_y", 0.0) + sin(_walk_phase * 2.0) * 0.02 * minf(hv, 1.0)
			model.rotation.z = sin(_walk_phase) * 0.015 * minf(hv, 1.0)
			model.rotation.x = clampf(hv * 0.015, 0.0, 0.05)
		return
	if attacking or hit_stun > 0.3:
		return
	if blocking:
		_play(cfg["anims"]["block"], 0.15)
		return
	var local_v := global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	var a: Dictionary = cfg["anims"]
	if local_v.length() < 0.6:
		_play(a["idle"], 0.25)
	elif absf(local_v.z) >= absf(local_v.x):
		_play(a["run_f"] if local_v.z < 0.0 else a["run_b"], 0.2)
	else:
		_play(a["run_r"] if local_v.x > 0.0 else a["run_l"], 0.2)

func _update_saber(_delta: float) -> void:
	if not cfg["melee"]:
		return
	# Kyle's blade bone is only posed in combat animations; elsewhere it sits
	# in bind pose inside the torso, so only show it while it is being swung.
	if cfg["type"] == "jedi" and blade_mesh != null:
		var show := attacking or blocking
		blade_mesh.visible = show
		if blade_light != null:
			blade_light.visible = show
	# Track world-space blade endpoints for the trail
	if cfg["type"] == "jedi" and blade_mesh != null:
		var xf := blade_mesh.global_transform
		trail_base = xf.origin
		trail_tip = xf * Vector3(0, 0, -1.1)
	elif saber_pivot != null:
		var xf2 := saber_pivot.global_transform
		trail_base = xf2 * Vector3(0, 0.1, 0)
		trail_tip = xf2 * Vector3(0, 1.4, 0)
	# Vader saber swing: animate the pivot during the attack
	if saber_pivot != null:
		if attacking:
			var t: float = 1.0 - attack_timer / float(cfg["attack_time"])
			var swing := sin(t * PI)
			saber_pivot.rotation = Vector3(-swing * 2.2, 0.3 - t * 1.2, swing * 0.4)
		else:
			saber_pivot.rotation = saber_pivot.rotation.lerp(Vector3(0.55, 0.0, -0.25), 0.15)

func _footsteps(delta: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 2.0 and is_on_floor():
		_sfx_step_t -= delta
		if _sfx_step_t <= 0.0:
			_sfx_step_t = clampf(2.6 / hv, 0.26, 0.5)
			play_sound("res://assets/audio/footstep.wav", -14.0, randf_range(0.9, 1.1))

# ------------------------------------------------------------------ actions

func try_attack() -> void:
	if not alive or hit_stun > 0.2:
		return
	if attacking:
		if cfg["melee"] and attack_timer < cfg["attack_time"] * 0.55:
			combo_queued = true
		return
	if cfg["melee"]:
		_start_attack(0)
	else:
		if burst_left <= 0 and fire_cooldown <= 0.0:
			burst_left = 3

func _start_attack(index: int) -> void:
	combo_index = index
	attacking = true
	hit_window_done = false
	blocking = false
	if anim != null:
		var names: Array = cfg["anims"]["attack"]
		var n: String = names[mini(index, names.size() - 1)]
		cfg["attack_time"] = _play_oneshot(n, 0.12, cfg.get("attack_anim_speed", 1.3))
	attack_timer = cfg["attack_time"]
	play_sound("res://assets/audio/saber_swing.wav" if cfg["melee"] else "res://assets/audio/laser_red.wav", -4.0, randf_range(0.92, 1.12))
	# Lunge toward the enemy
	if cfg["melee"] and enemy != null:
		var to_e := enemy.global_position - global_position
		to_e.y = 0
		if to_e.length() > 1.2 and to_e.length() < 5.5:
			velocity += to_e.normalized() * cfg.get("lunge", 5.0)

func set_blocking(want: bool) -> void:
	if not cfg["melee"] or attacking or not alive:
		blocking = false
		return
	blocking = want

func try_dash() -> void:
	if dash_cooldown > 0.0 or not alive or attacking:
		return
	var fwd := Vector3(-sin(face_yaw), 0, -cos(face_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var d := fwd * move_input.y + right * move_input.x
	if d.length() < 0.2:
		d = fwd
	dash_dir = d.normalized()
	dash_timer = 0.22
	dash_cooldown = 1.1
	play_sound("res://assets/audio/boost.wav", -10.0, 1.5)

func take_hit(dmg: float, from: GroundFighter) -> void:
	if not alive:
		return
	var to_attacker := from.global_position - global_position
	to_attacker.y = 0
	var facing := (-global_transform.basis.z).dot(to_attacker.normalized())
	if blocking and facing > 0.25 and from.cfg["melee"]:
		# Saber clash: blocked!
		arena.saber_clash((global_position + from.global_position) / 2.0 + Vector3(0, 1.3, 0))
		velocity -= to_attacker.normalized() * 3.0
		from.velocity += to_attacker.normalized() * 3.0
		hp -= dmg * 0.15
	elif blocking and facing > 0.25:
		# Blaster bolt deflected
		arena.saber_clash(global_position + Vector3(0, 1.3, 0))
		hp -= dmg * 0.25
	else:
		hp -= dmg
		hit_stun = 0.45
		velocity -= to_attacker.normalized() * 4.0
		if anim != null and not attacking:
			_play_oneshot(cfg["anims"]["hit"], 0.1, 1.2)
		play_sound("res://assets/audio/hit.wav", -6.0)
	damaged.emit(self)
	if hp <= 0.0:
		hp = 0.0
		_die()

func _die() -> void:
	alive = false
	controls_enabled = false
	blocking = false
	attacking = false
	if anim != null:
		_play_oneshot(cfg["anims"]["death"], 0.2, 1.0)
	elif model != null:
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", -PI / 2.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if blade_mesh != null:
		blade_mesh.visible = false
	if blade_light != null:
		blade_light.visible = false
	if _sfx_hum != null:
		_sfx_hum.stop()
	died.emit(self)

# ------------------------------------------------------------------ AI

func _ai_think(delta: float) -> void:
	if enemy == null or not enemy.alive:
		move_input = Vector2.ZERO
		return
	_ai_timer -= delta
	var to_e := enemy.global_position - global_position
	to_e.y = 0
	var dist := to_e.length()
	face_yaw = atan2(-to_e.x, -to_e.z)

	if _ai_timer <= 0.0:
		_ai_timer = randf_range(0.5, 1.1)
		_ai_strafe = [-1.0, 0.0, 1.0][randi() % 3] * randf_range(0.4, 1.0)
		_ai_want_block = randf() < cfg.get("ai_block_chance", 0.3)
		if randf() < 0.12 and dist < 6.0:
			try_dash()

	var skill: float = cfg.get("ai_skill", 0.6)
	if cfg["melee"]:
		var want := clampf((dist - saber_reach() * 0.75) * 0.8, -1.0, 1.0)
		move_input = Vector2(_ai_strafe, want)
		# Block reactively when the player is mid-swing
		set_blocking(_ai_want_block and enemy.attacking and dist < 4.0)
		if dist < saber_reach() + 0.4 and not blocking and randf() < skill * 2.2 * delta * 60.0 * 0.02:
			try_attack()
	else:
		var want2 := clampf((dist - 10.0) * 0.5, -1.0, 1.0)
		move_input = Vector2(_ai_strafe, want2)
		if dist < 18.0 and randf() < skill * delta * 60.0 * 0.014:
			try_attack()
