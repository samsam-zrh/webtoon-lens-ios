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
var attack_buffer_t := 0.0   # remembers a recent attack press (input buffering)
var hit_window_done := false
var blocking := false
var hit_stun := 0.0
var dash_timer := 0.0
var dash_cooldown := 0.0
var push_cooldown := 0.0
var dash_dir := Vector3.ZERO
var fire_cooldown := 0.0
var burst_left := 0

# Movement intent (set by arena for the player, or by AI)
var move_input := Vector2.ZERO  # x = strafe right, y = forward
var face_yaw := 0.0             # world yaw the body should face

# AI state machine: approach -> pressure (attack chains) -> retreat, with
# reactive guards timed on the opponent's windup.
var _ai_state := "approach"
var _ai_state_t := 0.0
var _ai_timer := 0.0
var _ai_strafe := 0.0
var _ai_block_t := 0.0
var _ai_atk_cd := 0.0
var _ai_chain := 0

var model: Node3D
var anim: AnimationPlayer
var saber_pivot: Node3D          # (unused for model-integrated blades)
var blade_mesh: MeshInstance3D
var halo_mesh: MeshInstance3D
var blade_light: OmniLight3D
var trail_base := Vector3.ZERO   # world-space saber base/tip, updated each frame
var trail_tip := Vector3.ZERO
var _blade_local_base := Vector3.ZERO
var _blade_local_tip := Vector3.ZERO
var _base_yaw := 0.0             # model rest yaw (procedural swing pivots around it)

var attack_recoil_t := 0.0       # set when our swing gets parried
var _blade_in_hand := false
var _flash_meshes: Array = []
var _flash_energy := 0.0
var _sfx_hum: AudioStreamPlayer3D
var _tip_prev := Vector3.ZERO
var _tip_speed := 0.0
var _swing_played := false
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

	model = build_character_model(cfg)
	if cfg.has("model_offset_y"):
		model.position.y = cfg["model_offset_y"]
	add_child(model)

	_base_yaw = cfg.get("model_yaw", 0.0)
	anim = model.find_child("AnimationPlayer", true, false)
	if anim != null:
		_play(cfg["anims"]["idle"], 0.0)

	_setup_blade()
	if cfg["melee"] and not cfg.get("blade_always", false) and blade_mesh != null and anim != null:
		_reparent_blade_to_hand.call_deferred()
	_setup_audio()
	# additive white overlay on every mesh: tweened up briefly when hit
	var stack: Array = [model]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			if nd == blade_mesh or nd == halo_mesh:
				for c2 in nd.get_children():
					stack.push_back(c2)
				continue
			var fm := StandardMaterial3D.new()
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fm.albedo_color = Color(0, 0, 0)
			fm.emission_enabled = true
			fm.emission = Color(1.0, 0.45, 0.3)
			fm.emission_energy_multiplier = 0.0
			(nd as MeshInstance3D).material_overlay = fm
			_flash_meshes.append(fm)
		for c in nd.get_children():
			stack.push_back(c)

# The source rig only poses the blade bone inside combat animations; pose one
# combat frame, measure the grip transform, then ride the hand bone forever.
func _reparent_blade_to_hand() -> void:
	await get_tree().process_frame
	if not is_instance_valid(blade_mesh) or anim == null:
		return
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
	if sk == null:
		return
	var bi := sk.find_bone("mixamorig_RightHand")
	if bi == -1:
		return
	var a0: String = cfg["anims"]["attack"][0]
	if not anim.has_animation(a0):
		return
	anim.play(a0)
	anim.seek(anim.get_animation(a0).length * 0.35, true)
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(blade_mesh):
		return
	var hand_g: Transform3D = sk.global_transform * sk.get_bone_global_pose(bi)
	var rel: Transform3D = hand_g.affine_inverse() * blade_mesh.global_transform
	var att := BoneAttachment3D.new()
	sk.add_child(att)
	att.bone_name = "mixamorig_RightHand"
	blade_mesh.reparent(att, false)
	blade_mesh.transform = rel
	if is_instance_valid(halo_mesh):
		halo_mesh.reparent(att, false)
		halo_mesh.transform = rel
	_blade_in_hand = true
	blade_mesh.visible = true
	if halo_mesh != null:
		halo_mesh.visible = true
	if blade_light != null:
		blade_light.visible = true
	anim.play(cfg["anims"]["idle"])

func attack_recoil() -> void:
	# our swing was parried: the chain breaks and we are briefly exposed
	combo_queued = false
	attack_recoil_t = 0.45
	if attacking:
		attack_timer = minf(attack_timer, 0.15)

func damage_flash(strength := 1.0) -> void:
	_flash_energy = strength
	for fm: StandardMaterial3D in _flash_meshes:
		fm.emission_energy_multiplier = strength * 1.6
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		for fm: StandardMaterial3D in _flash_meshes:
			fm.emission_energy_multiplier = v,
		strength * 1.6, 0.0, 0.18)

# Builds the visual model for a roster entry. Vader is a real Battlefront-style
# model re-rigged onto the shared animated skeleton (see CREDITS.md).
static func build_character_model(cfg: Dictionary) -> Node3D:
	var m: Node3D
	if cfg.has("normalize_len"):
		m = ModelUtil.load_model(cfg["model"], cfg["normalize_len"], cfg.get("model_yaw", 0.0))
	else:
		m = load(cfg["model"]).instantiate()
		if cfg.has("model_scale"):
			m.scale = Vector3.ONE * cfg["model_scale"]
		m.rotation.y = cfg.get("model_yaw", 0.0)
	match cfg.get("variant", ""):
		"kenobi":
			# Jedi master robes: warm earth tones on the clothing only
			_tint_meshes(m, ["Shirt", "TShirt"], Color(0.78, 0.70, 0.55))
			_tint_meshes(m, ["Pants", "Boots"], Color(0.38, 0.30, 0.22))
			_tint_meshes(m, ["Pouldron", "Belt", "Belt_Holster", "Gauntlets"], Color(0.45, 0.36, 0.26))
		"sith":
			# Sith trooper: crimson armor
			ModelUtil.tint(m, Color(0.72, 0.10, 0.08))
	return m

static func _tint_meshes(root: Node3D, names: Array, color: Color) -> void:
	for n: String in names:
		var found := root.find_child(n, true, false)
		if found is MeshInstance3D:
			var mi := found as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				if src is StandardMaterial3D:
					var dup: StandardMaterial3D = src.duplicate()
					dup.albedo_color = color
					mi.set_surface_override_material(i, dup)

func _setup_blade() -> void:
	if not cfg["melee"]:
		return
	var color: Color = cfg["saber_color"]
	# Each model ships with a blade mesh skinned to the weapon hand: recolor
	# it into a glowing energy blade. The attachment node and its mesh child
	# can share the same name, so dig for the MeshInstance3D.
	var blade_name: String = cfg.get("blade_mesh", "lightblade_Cylinder_001")
	# White-hot core...
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lerp(Color.WHITE, 0.75)
	mat.emission_enabled = true
	mat.emission = color.lerp(Color.WHITE, 0.35)
	mat.emission_energy_multiplier = 7.0
	var attach := model.find_child(blade_name, true, false)
	if attach is MeshInstance3D:
		blade_mesh = attach
	elif attach != null:
		blade_mesh = attach.find_child("*", true, false) as MeshInstance3D
	if blade_mesh != null:
		for i in blade_mesh.mesh.get_surface_count():
			blade_mesh.set_surface_override_material(i, mat)
		# ...wrapped in an additive plasma halo (inflated duplicate of the mesh)
		halo_mesh = blade_mesh.duplicate(0) as MeshInstance3D
		for c in halo_mesh.get_children():
			c.queue_free()
		var halo := ShaderMaterial.new()
		halo.shader = load("res://shaders/blade_halo.gdshader")
		halo.set_shader_parameter("glow_color", color)
		halo_mesh.material_override = halo
		halo_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		blade_mesh.add_sibling.call_deferred(halo_mesh)
		blade_light = OmniLight3D.new()
		blade_light.light_color = color
		blade_light.light_energy = 2.6
		blade_light.omni_range = 3.8
		blade_mesh.add_child(blade_light)
	# Glowing hilt details (Vader's saber controls)
	for extra_name in cfg.get("blade_extra", []):
		var found := model.find_child(extra_name, true, false)
		if found is MeshInstance3D:
			var fmi := found as MeshInstance3D
			for i in fmi.mesh.get_surface_count():
				fmi.set_surface_override_material(i, mat)

	# Blade endpoints (local space) along the mesh's longest axis, for the
	# swing trail and to position the light.
	if blade_mesh != null:
		var ab := blade_mesh.mesh.get_aabb()
		var c := ab.get_center()
		if ab.size.y >= ab.size.x and ab.size.y >= ab.size.z:
			_blade_local_base = Vector3(c.x, ab.position.y, c.z)
			_blade_local_tip = Vector3(c.x, ab.end.y, c.z)
		elif ab.size.z >= ab.size.x:
			_blade_local_base = Vector3(c.x, c.y, ab.end.z if absf(ab.end.z) < absf(ab.position.z) else ab.position.z)
			_blade_local_tip = Vector3(c.x, c.y, ab.position.z if absf(ab.end.z) < absf(ab.position.z) else ab.end.z)
		else:
			_blade_local_base = Vector3(ab.position.x, c.y, c.z)
			_blade_local_tip = Vector3(ab.end.x, c.y, c.z)
		if blade_light != null:
			blade_light.position = (_blade_local_base + _blade_local_tip) / 2.0

func _setup_audio() -> void:
	if cfg["melee"]:
		_sfx_hum = AudioStreamPlayer3D.new()
		var hum: AudioStreamWAV = load("res://assets/audio/saber_hum.wav").duplicate()
		hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
		hum.loop_end = hum.data.size() / 2
		_sfx_hum.stream = hum
		_sfx_hum.unit_size = 6.0
		_sfx_hum.bus = "SFX"
		_sfx_hum.volume_db = -10.0
		_sfx_hum.pitch_scale = 0.82 if cfg.get("variant", "") == "vader" else 1.0
		add_child(_sfx_hum)
	if cfg.get("variant", "") == "vader":
		var breath := AudioStreamPlayer3D.new()
		var bs: AudioStreamWAV = load("res://assets/audio/vader_breath.wav").duplicate()
		bs.loop_mode = AudioStreamWAV.LOOP_FORWARD
		bs.loop_end = bs.data.size() / 2
		breath.stream = bs
		breath.unit_size = 8.0
		breath.bus = "SFX"
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
	anim.speed_scale = 1.0
	anim.play(name, blend, speed)
	return anim.get_animation(name).length / speed

func play_sound(path: String, db: float = 0.0, pitch: float = 1.0) -> void:
	var sp := AudioStreamPlayer3D.new()
	sp.stream = load(path)
	sp.volume_db = db
	sp.pitch_scale = pitch
	sp.unit_size = 12.0
	sp.bus = "SFX"
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
	push_cooldown = maxf(0.0, push_cooldown - delta)
	attack_recoil_t = maxf(0.0, attack_recoil_t - delta)
	hit_stun = maxf(0.0, hit_stun - delta)
	attack_buffer_t = maxf(0.0, attack_buffer_t - delta)

	if controls_enabled and not is_player:
		_ai_think(delta)

	# input buffering: launch/chain the swing the moment the fighter is free
	if controls_enabled:
		_consume_attack_buffer()

	# Attack progression: the blade is "live" over a window of the swing
	# (0.5 -> 0.82 of the animation), checked every tick until it connects.
	if attacking:
		attack_timer -= delta
		var elapsed: float = 1.0 - attack_timer / float(cfg["attack_time"])
		if cfg["melee"]:
			if not hit_window_done and elapsed >= 0.5 and elapsed <= 0.82:
				if arena.melee_hit(self):
					hit_window_done = true
			# motion warp: glide toward the target during the windup and stop
			# at striking range, instead of an uncontrolled lunge impulse
			if elapsed < 0.5 and enemy != null and enemy.alive:
				var to_e := enemy.global_position - global_position
				to_e.y = 0
				var d := to_e.length()
				if d > saber_reach() * 0.75 and d < 6.0:
					velocity += to_e.normalized() * 26.0 * delta
		if attack_timer <= 0.0:
			if combo_queued and combo_index < cfg["anims"]["attack"].size() - 1 and cfg["melee"]:
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
	if attack_recoil_t > 0.0:
		speed *= 0.45
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

	var k := 1.0 - exp((-11.0 if desired.length_squared() > 0.05 else -16.0) * delta)
	velocity.x = lerpf(velocity.x, desired.x, k)
	velocity.z = lerpf(velocity.z, desired.z, k)
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Turn toward face_yaw (heavier characters turn slower)
	rotation.y = lerp_angle(rotation.y, face_yaw, cfg.get("turn_speed", 12.0) * delta)

	_update_animation(delta)
	_update_saber(delta)
	_footsteps(delta)

func _update_animation(delta: float) -> void:
	if anim == null:
		# Vader procedural motion: heavy walk sway, breathing bob, and a
		# full-body swing while attacking (his blade is held raised, so
		# twisting the torso sweeps it through a wide arc).
		if model == null:
			return
		var hv := Vector2(velocity.x, velocity.z).length()
		var walk := clampf(hv / 3.0, 0.0, 1.0)
		_walk_phase += delta * (1.4 + hv * 1.8)
		var yaw_off := 0.0
		var pitch := 0.0
		var roll := 0.0
		if attacking:
			# Smooth windup then eased strike: no snapping
			var t: float = 1.0 - attack_timer / float(cfg["attack_time"])
			if t < 0.35:
				var w := smoothstep(0.0, 1.0, t / 0.35)
				yaw_off = 0.5 * w
				pitch = -0.08 * w
			else:
				var s := smoothstep(0.0, 1.0, (t - 0.35) / 0.65)
				yaw_off = lerpf(0.5, -1.0, s)
				pitch = 0.2 * sin(s * PI)
		elif hit_stun > 0.0:
			pitch = -0.12 * smoothstep(0.0, 1.0, hit_stun / 0.45)
		else:
			pitch = walk * 0.05
			roll = sin(_walk_phase) * 0.015 * walk
		# Idle breathing
		var breath := sin(_walk_phase * 0.6) * 0.012 * (1.0 - walk)
		model.position.y = cfg.get("model_offset_y", 0.0) + breath + sin(_walk_phase * 2.0) * 0.02 * walk
		model.rotation.y = lerp_angle(model.rotation.y, _base_yaw + yaw_off, 9.0 * delta)
		model.rotation.x = lerpf(model.rotation.x, pitch, 7.0 * delta)
		model.rotation.z = lerpf(model.rotation.z, roll, 6.0 * delta)
		return
	# dash lean: the body tips into the dodge
	if model != null:
		var lean_x := -0.22 if dash_timer > 0.0 else 0.0
		model.rotation.x = lerpf(model.rotation.x, lean_x, 9.0 * delta)
	if attacking or hit_stun > 0.3:
		if anim != null:
			anim.speed_scale = 1.0
		return
	if blocking:
		anim.speed_scale = 1.0
		_play(cfg["anims"]["block"], 0.15)
		return
	var local_v := global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z)
	var a: Dictionary = cfg["anims"]
	var hv := local_v.length()
	if hv < 0.6:
		anim.speed_scale = 1.0
		_play(a["idle"], 0.25)
	else:
		# hysteresis: keep the current direction anim unless clearly dominated
		var fwdness := absf(local_v.z) / maxf(absf(local_v.x), 0.001)
		var want: String
		if fwdness > 0.8:
			want = a["run_f"] if local_v.z < 0.0 else a["run_b"]
		else:
			want = a["run_r"] if local_v.x > 0.0 else a["run_l"]
		_play(want, 0.22)
		# feet match the ground speed: no more skating
		anim.speed_scale = clampf(hv / maxf(cfg["speed"], 0.1), 0.65, 1.35)

func _update_saber(_delta: float) -> void:
	if not cfg["melee"]:
		return
	# Kyle's blade bone is only posed in combat animations; elsewhere it sits
	# in bind pose inside the torso, so only show it while it is being swung.
	# Vader's blade is skinned to his hand and stays drawn ("blade_always").
	if cfg["type"] == "jedi" and blade_mesh != null and not cfg.get("blade_always", false) and not _blade_in_hand:
		var show := attacking or blocking
		blade_mesh.visible = show
		if halo_mesh != null:
			halo_mesh.visible = show
		if blade_light != null:
			blade_light.visible = show
	# Track world-space blade endpoints for the trail
	if blade_mesh != null:
		var xf := blade_mesh.global_transform
		trail_base = xf * _blade_local_base
		trail_tip = xf * _blade_local_tip
		var dt := get_physics_process_delta_time()
		if dt > 0.0:
			var raw := (trail_tip - _tip_prev).length() / dt
			_tip_speed = lerpf(_tip_speed, raw, 0.5)
		_tip_prev = trail_tip
		# the whoosh triggers on real blade motion, scaled by how hard it moves
		if attacking and not _swing_played and _tip_speed > 7.0:
			_swing_played = true
			var idx := 1 + randi() % 3
			play_sound("res://assets/audio/saber_swing%d.wav" % idx,
				clampf(-12.0 + _tip_speed * 0.35, -12.0, -3.0),
				randf_range(0.92, 1.12))
		# hum doppler: pitch and volume ride the blade speed
		if _sfx_hum != null and _sfx_hum.playing:
			var base_pitch := 0.82 if cfg.get("variant", "") == "vader" else 1.0
			var k := clampf(_tip_speed / 22.0, 0.0, 1.0)
			_sfx_hum.pitch_scale = lerpf(_sfx_hum.pitch_scale, base_pitch * (1.0 + k * 0.35), 0.3)
			_sfx_hum.volume_db = lerpf(_sfx_hum.volume_db, -10.0 + k * 7.0, 0.25)

func _footsteps(delta: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 2.0 and is_on_floor():
		_sfx_step_t -= delta
		if _sfx_step_t <= 0.0:
			_sfx_step_t = clampf(2.6 / hv, 0.26, 0.5)
			play_sound("res://assets/audio/footstep.wav", -14.0, randf_range(0.9, 1.1))

# ------------------------------------------------------------------ actions

func try_attack() -> void:
	if not alive:
		return
	if cfg["melee"]:
		# Buffer the press: it is consumed as soon as the character can act,
		# so attacks never feel dropped even if pressed a touch early/late.
		attack_buffer_t = 0.30
	else:
		if burst_left <= 0 and fire_cooldown <= 0.0:
			burst_left = 3

# Spend a buffered attack the instant the fighter is free to swing or chain.
func _consume_attack_buffer() -> void:
	if attack_buffer_t <= 0.0 or not cfg["melee"]:
		return
	if hit_stun > 0.2:
		return
	if attacking:
		var elapsed: float = 1.0 - attack_timer / float(cfg["attack_time"])
		if elapsed >= 0.42 and combo_index < cfg["anims"]["attack"].size() - 1:
			combo_queued = true
			attack_buffer_t = 0.0
		return
	if attack_recoil_t > 0.0:
		return
	_start_attack(0)
	attack_buffer_t = 0.0

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
	_swing_played = false
	if not cfg["melee"]:
		play_sound("res://assets/audio/laser_red.wav", -4.0, randf_range(0.92, 1.12))


func set_blocking(want: bool) -> void:
	if not cfg["melee"] or attacking or not alive:
		blocking = false
		return
	blocking = want

func has_force() -> bool:
	return cfg["melee"] and cfg["type"] == "jedi"

func try_force_push() -> void:
	if push_cooldown > 0.0 or not alive or not has_force() or hit_stun > 0.2:
		return
	if attacking:
		attacking = false
		combo_queued = false
		combo_index = 0
	push_cooldown = 6.0
	blocking = false
	_play_oneshot("19_Block3", 0.1, 1.5)
	play_sound("res://assets/audio/force_push.wav", -2.0, randf_range(0.95, 1.05))
	arena.force_push(self)

func take_push(dir: Vector3) -> void:
	if not alive:
		return
	velocity += dir * 11.0 + Vector3.UP * 4.0
	hit_stun = 1.0
	blocking = false
	if attacking:
		attacking = false
		combo_queued = false
		combo_index = 0
	hp -= 4.0
	damage_flash(0.7)
	if anim != null:
		_play_oneshot(cfg["anims"]["hit"], 0.1, 0.9)
	damaged.emit(self)
	if hp <= 0.0:
		hp = 0.0
		_die()

func try_dash() -> void:
	if dash_cooldown > 0.0 or not alive:
		return
	if attacking:
		# cancel the swing into the dodge
		attacking = false
		combo_queued = false
		combo_index = 0
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
		# Saber clash: blocked! The attacker recoils, exposed.
		arena.saber_clash((global_position + from.global_position) / 2.0 + Vector3(0, 1.3, 0))
		velocity -= to_attacker.normalized() * 1.8
		from.velocity += to_attacker.normalized() * 2.6
		from.attack_recoil()
		hp -= dmg * 0.15
	elif blocking and facing > 0.25:
		# Blaster bolt deflected
		arena.saber_clash(global_position + Vector3(0, 1.3, 0))
		hp -= dmg * 0.25
	else:
		hp -= dmg
		hit_stun = 0.45
		velocity -= to_attacker.normalized() * 2.4
		damage_flash(1.0)
		if anim != null and not attacking:
			_play_oneshot(cfg["anims"]["hit"], 0.1, 1.2)
		if from.cfg["melee"]:
			play_sound("res://assets/audio/saber_hit.wav", -1.0, randf_range(0.92, 1.1))
		else:
			play_sound("res://assets/audio/hit.wav", -4.0)
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
	if halo_mesh != null:
		halo_mesh.visible = false
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

	var skill: float = cfg.get("ai_skill", 0.6)
	if cfg["melee"]:
		_ai_state_t -= delta
		_ai_block_t -= delta
		_ai_atk_cd -= delta
		var reach := saber_reach()
		# reactive guard: read the opponent's windup and raise the blade
		if (_ai_block_t <= 0.0 and enemy.attacking and dist < reach + 1.2
				and not attacking and randf() < cfg.get("ai_block_chance", 0.3) * delta * 60.0 * 0.12):
			_ai_block_t = randf_range(0.4, 0.7)
		set_blocking(_ai_block_t > 0.0)
		# parried? back off and reset the exchange
		if attack_recoil_t > 0.2 and _ai_state != "retreat":
			_ai_state = "retreat"
			_ai_state_t = randf_range(0.7, 1.1)
		match _ai_state:
			"approach":
				move_input = Vector2(_ai_strafe * 0.4, clampf((dist - reach * 0.8) * 0.9, -0.3, 1.0))
				if dist < reach + 0.3:
					_ai_state = "pressure"
					_ai_state_t = randf_range(1.4, 2.4)
					_ai_chain = 1 + randi() % 3
			"pressure":
				move_input = Vector2(_ai_strafe * 0.6, clampf((dist - reach * 0.7) * 0.8, -0.5, 0.6))
				if not blocking and _ai_atk_cd <= 0.0 and dist < reach + 0.4 and _ai_chain > 0:
					try_attack()
					_ai_chain -= 1
					_ai_atk_cd = randf_range(0.9, 1.5) - skill * 0.5
				elif has_force() and push_cooldown <= 0.0 and dist < 4.0 and randf() < skill * delta * 2.0:
					try_force_push()
				if _ai_state_t <= 0.0 or _ai_chain <= 0:
					if randf() < 0.45:
						_ai_state = "retreat"
						_ai_state_t = randf_range(0.6, 1.2)
					else:
						_ai_state = "pressure"
						_ai_state_t = randf_range(1.2, 2.0)
						_ai_chain = 1 + randi() % 3
			"retreat":
				move_input = Vector2(_ai_strafe, -0.7)
				# punish a whiffed swing on the way out
				if enemy.attacking and dist < reach and _ai_atk_cd <= 0.0:
					try_attack()
					_ai_atk_cd = 1.0
				if _ai_state_t <= 0.0 or dist > reach * 2.2:
					_ai_state = "approach"
				if randf() < 0.5 * delta and dist < 4.0:
					try_dash()
	else:
		var want2: float
		if dist < 2.8:
			want2 = -0.35         # only a small step back at point blank
		elif dist > 9.0:
			want2 = 1.0           # close back in
		else:
			want2 = 0.2           # hold position, keep light pressure
		# never back into the arena edge
		var flat := Vector2(global_position.x, global_position.z)
		if want2 < 0.0 and flat.length() > 10.0:
			want2 = 0.4
		# a raised saber guard sends bolts back: flank instead of feeding it
		var target_guarding: bool = enemy.blocking and enemy.cfg["melee"]
		move_input = Vector2(_ai_strafe * (2.0 if target_guarding else 1.4), want2)
		var rate := 0.008 if target_guarding else 0.022
		if dist < 20.0 and randf() < skill * delta * 60.0 * rate:
			try_attack()
