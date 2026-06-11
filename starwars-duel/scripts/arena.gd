class_name Arena
extends Node3D

# The space battlefield: environment, scenery, both ships, camera, HUD, flow.

signal request_restart
signal request_menu

const ARENA_RADIUS := 1600.0

var player: Ship
var enemy: Ship
var camera: Camera3D
var hud: Hud
var asteroids: Array = []

var _mouse_offset := Vector2.ZERO
var _trauma := 0.0
var _ended := false
var _pause_layer: CanvasLayer
var _end_layer: CanvasLayer

func start(player_id: String, enemy_id: String) -> void:
	_build_environment()
	_build_scenery()
	_build_ships(player_id, enemy_id)
	_build_camera()
	hud = Hud.new()
	hud.player = player
	hud.enemy = enemy
	hud.camera = camera
	add_child(hud)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_countdown()

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/milky_way.jpg")
	sky_mat.energy_multiplier = 1.7
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.21, 0.34)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.rotation = Vector3(-0.4, 0.6, 0.0)
	add_child(sun)

	# Cool fill light from the opposite side so ships read against the dark
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.rotation = Vector3(0.5, -2.4, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

func _build_scenery() -> void:
	# Distant sun disc aligned with the directional light
	var sun_ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 90.0
	sm.height = 180.0
	var smm := StandardMaterial3D.new()
	smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smm.albedo_color = Color(1.0, 0.95, 0.8)
	smm.emission_enabled = true
	smm.emission = Color(1.0, 0.9, 0.7)
	smm.emission_energy_multiplier = 8.0
	sm.material = smm
	sun_ball.mesh = sm
	sun_ball.position = Vector3(-2600, 1700, -3200)
	add_child(sun_ball)

	# Jupiter: real NASA-derived surface map (Solar System Scope, CC-BY 4.0)
	var jupiter := _make_textured_planet("res://assets/textures/jupiter.jpg", 1100.0, Vector3(2300, -500, -2900))
	add_child(jupiter)
	_add_atmosphere(Vector3(2300, -500, -2900), 1100.0, Color(0.95, 0.7, 0.45, 0.045))

	# Saturn with its real ring system, far on the other side
	var saturn := _make_textured_planet("res://assets/textures/saturn.jpg", 620.0, Vector3(-3100, 900, -2400))
	add_child(saturn)
	var ring := MeshInstance3D.new()
	ring.mesh = _make_ring_mesh(1.24, 2.27, load("res://assets/textures/saturn_ring.png"))
	ring.scale = Vector3.ONE * 620.0
	ring.position = Vector3(-3100, 900, -2400)
	ring.rotation = Vector3(0.42, 0.0, 0.22)
	add_child(ring)

	# The Moon, with its real surface map, behind the spawn area
	var moon := _make_textured_planet("res://assets/textures/moon.jpg", 200.0, Vector3(-700, 450, 2600))
	add_child(moon)

	# Imperial Star Destroyer looming below the battlefield
	var destroyer := ModelUtil.load_model("res://assets/models/star_destroyer.glb", 800.0, 0.0)
	destroyer.position = Vector3(-450, -380, -700)
	destroyer.rotation.y = 0.5
	ModelUtil.tint(destroyer, Color(0.52, 0.55, 0.62))
	add_child(destroyer)

	# Asteroid field: real community 3D rock models (see CREDITS.md), plus
	# noise-displaced procedural variants for variety
	var rng := RandomNumberGenerator.new()
	rng.seed = 1138
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.30, 0.28, 0.26)
	rock_mat.roughness = 1.0
	var proc_variants: Array = []
	for v in 3:
		proc_variants.append(_make_rock_mesh(rng.randi(), rock_mat))
	for i in 64:
		var pos := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)).normalized() * rng.randf_range(250.0, ARENA_RADIUS * 0.85)
		var base_r := rng.randf_range(6.0, 34.0)
		var node: Node3D
		if i % 2 == 0:
			# Real model, normalized so its longest side = 2 (radius 1)
			node = ModelUtil.load_model("res://assets/models/asteroids/asteroid_toastie.glb", 2.0, 0.0)
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = proc_variants[rng.randi_range(0, proc_variants.size() - 1)]
			node = mi
		node.scale = Vector3(base_r * rng.randf_range(0.8, 1.2), base_r * rng.randf_range(0.7, 1.1), base_r * rng.randf_range(0.8, 1.2))
		node.position = pos
		node.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		add_child(node)
		asteroids.append({"pos": pos, "radius": base_r * 1.05})

	# Decorative far clusters (no collision), outside the play zone
	for i in 10:
		var cluster := ModelUtil.load_model("res://assets/models/asteroids/asteroids_jarlan.glb", rng.randf_range(120.0, 280.0), 0.0)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 0.35), rng.randf_range(-1, 1)).normalized()
		cluster.position = dir * rng.randf_range(ARENA_RADIUS * 1.25, ARENA_RADIUS * 1.9)
		cluster.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		add_child(cluster)

	# Quiet ambient drone
	var amb := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = stream.data.size() / 2
	amb.stream = stream
	amb.volume_db = -16.0
	add_child(amb)
	amb.play()

	# Dogfight music (the player's own "battle" track when present)
	var bgm := AudioStreamPlayer.new()
	var custom := MusicDirector.external_stream("battle")
	if custom != null:
		bgm.stream = custom
	else:
		var mp3: AudioStream = load("res://assets/audio/music_battle.mp3").duplicate()
		mp3.loop = true
		bgm.stream = mp3
	bgm.volume_db = -13.0
	bgm.bus = "Music"
	add_child(bgm)
	bgm.play()

func _make_textured_planet(tex_path: String, radius: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 96
	sm.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.roughness = 1.0
	mat.metallic = 0.0
	sm.material = mat
	mi.mesh = sm
	mi.scale = Vector3.ONE * radius
	mi.position = pos
	return mi

func _add_atmosphere(pos: Vector3, radius: float, color: Color) -> void:
	var atmo := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 1.03
	am.height = 2.06
	am.radial_segments = 64
	am.rings = 32
	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	amat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	amat.albedo_color = color
	amat.cull_mode = BaseMaterial3D.CULL_FRONT
	am.material = amat
	atmo.mesh = am
	atmo.scale = Vector3.ONE * radius
	atmo.position = pos
	add_child(atmo)

# Flat annulus whose UV.x runs from the inner to the outer edge, so the
# real Saturn ring strip texture (radial scan) maps correctly.
func _make_ring_mesh(inner: float, outer: float, tex: Texture2D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 128
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var i0 := Vector3(cos(a0), 0, sin(a0)) * inner
		var i1 := Vector3(cos(a1), 0, sin(a1)) * inner
		var o0 := Vector3(cos(a0), 0, sin(a0)) * outer
		var o1 := Vector3(cos(a1), 0, sin(a1)) * outer
		st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(i0)
		st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(o0)
		st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(o1)
		st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(i0)
		st.set_uv(Vector2(1.0, 0.5)); st.add_vertex(o1)
		st.set_uv(Vector2(0.0, 0.5)); st.add_vertex(i1)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh

# Builds a rocky asteroid mesh: a sphere displaced by 3D noise, with flat
# (faceted) normals for a chunky rock look.
func _make_rock_mesh(noise_seed: int, mat: Material) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.55
	noise.fractal_octaves = 3
	# Displace along the radius; seam vertices share a direction so they stay welded
	for i in verts.size():
		var dir := verts[i].normalized()
		var n := noise.get_noise_3dv(dir * 2.2)
		verts[i] = dir * (1.0 + 0.38 * n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var j := 0
	while j < idx.size():
		# Unindexed triangles -> per-face normals from generate_normals()
		st.add_vertex(verts[idx[j]])
		st.add_vertex(verts[idx[j + 1]])
		st.add_vertex(verts[idx[j + 2]])
		j += 3
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh

func _build_ships(player_id: String, enemy_id: String) -> void:
	player = Ship.new()
	player.setup(ShipsDB.get_cfg(player_id), true, self)
	player.position = Vector3(0, 0, 420)
	add_child(player)

	enemy = Ship.new()
	enemy.setup(ShipsDB.get_cfg(enemy_id), false, self)
	enemy.position = Vector3(0, 0, -420)
	enemy.rotation.y = PI
	add_child(enemy)

	player.enemy = enemy
	enemy.enemy = player

	player.died.connect(_on_ship_died)
	enemy.died.connect(_on_ship_died)
	player.damaged.connect(func(_s: Ship) -> void: _trauma = minf(_trauma + 0.5, 1.0))

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.far = 12000.0
	camera.fov = 75.0
	add_child(camera)
	_update_camera(1.0)
	camera.make_current()

	# Space dust drifting past the cockpit: cheap but sells the speed
	var dust := GPUParticles3D.new()
	var dmat := ParticleProcessMaterial.new()
	dmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dmat.emission_box_extents = Vector3(90, 60, 90)
	dmat.gravity = Vector3.ZERO
	dmat.initial_velocity_min = 0.0
	dmat.initial_velocity_max = 0.5
	dmat.scale_min = 0.5
	dmat.scale_max = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 4
	mesh.rings = 2
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.8, 0.85, 1.0, 0.5)
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mmat
	dust.draw_pass_1 = mesh
	dust.process_material = dmat
	dust.amount = 500
	dust.lifetime = 6.0
	dust.local_coords = false
	dust.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	camera.add_child(dust)

func _countdown() -> void:
	player.controls_enabled = false
	enemy.controls_enabled = false
	var seq := ["3", "2", "1", "EN GARDE !"]
	for i in seq.size():
		var t := get_tree().create_timer(0.9 * i + 0.4)
		var txt: String = seq[i]
		t.timeout.connect(func() -> void:
			if is_instance_valid(hud):
				hud.show_center_message(txt, 0.75)
				if txt == "EN GARDE !":
					player.controls_enabled = true
					enemy.controls_enabled = true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_offset += event.relative * 0.002
		_mouse_offset = _mouse_offset.limit_length(1.0)
	if event.is_action_pressed("pause") and not _ended:
		_toggle_pause()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	# Player controls
	if player.alive and player.controls_enabled:
		player.pitch_input = -_mouse_offset.y
		player.yaw_input = -_mouse_offset.x
		var roll := 0.0
		if Input.is_action_pressed("roll_left"):
			roll += 1.0
		if Input.is_action_pressed("roll_right"):
			roll -= 1.0
		player.roll_input = roll
		if Input.is_action_pressed("throttle_up"):
			player.throttle = minf(1.0, player.throttle + delta * 0.8)
		if Input.is_action_pressed("throttle_down"):
			player.throttle = maxf(0.0, player.throttle - delta * 0.8)
		var was_boosting := player.boosting
		player.boosting = Input.is_action_pressed("boost") and player.boost_energy > 0.05
		if player.boosting and not was_boosting:
			player.start_boost_sfx()
		player.fire_held = Input.is_action_pressed("fire")
		# The cursor relaxes back to center so the ship flies straight again
		_mouse_offset = _mouse_offset.lerp(Vector2.ZERO, delta * 2.0)
	hud.mouse_offset = _mouse_offset

	_check_collisions(delta)
	_update_camera(delta)
	_trauma = maxf(0.0, _trauma - delta * 1.4)

func _check_collisions(_delta: float) -> void:
	for ship: Ship in [player, enemy]:
		if not ship.alive:
			continue
		for a in asteroids:
			var d: float = ship.global_position.distance_to(a["pos"])
			if d < a["radius"] + ship.collision_radius:
				ship.take_damage(18.0, ship)
				var push: Vector3 = (ship.global_position - a["pos"]).normalized()
				ship.global_position = a["pos"] + push * (a["radius"] + ship.collision_radius + 2.0)
				if ship == player:
					_trauma = 1.0
	# Ship vs ship ramming
	if player.alive and enemy.alive:
		var d := player.global_position.distance_to(enemy.global_position)
		var min_d := player.collision_radius + enemy.collision_radius
		if d < min_d:
			player.take_damage(25.0, enemy)
			enemy.take_damage(25.0, player)
			var axis := (player.global_position - enemy.global_position).normalized()
			player.global_position += axis * (min_d - d + 3.0)
			_trauma = 1.0

func _update_camera(delta: float) -> void:
	var target := player
	if target == null:
		return
	var xf := target.global_transform
	var back := xf.basis.z
	var up := xf.basis.y
	var desired := xf.origin + back * 16.0 + up * 4.5
	var w := clampf(7.0 * delta, 0.0, 1.0)
	camera.global_position = camera.global_position.lerp(desired, w)
	var look := xf.origin - xf.basis.z * 60.0
	camera.look_at(look, up.lerp(camera.global_transform.basis.y, 0.4))
	camera.fov = lerpf(camera.fov, 73.0 + (target.speed / target.cfg["boost_speed"]) * 16.0, 4.0 * delta)
	if _trauma > 0.0:
		var sh := _trauma * _trauma
		camera.rotation += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012 * sh

func _on_ship_died(ship: Ship) -> void:
	_spawn_explosion(ship.global_position, ship.cfg["target_len"])
	if ship.model:
		ship.model.visible = false
	Engine.time_scale = 0.35
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)
	if not _ended:
		_ended = true
		var won := ship == enemy
		var t2 := get_tree().create_timer(1.6)
		t2.timeout.connect(func() -> void: _show_end(won))

func _spawn_explosion(at: Vector3, size: float) -> void:
	for cfg in [
		{"color": Color(1.0, 0.7, 0.2), "count": 110, "vel": 46.0, "life": 1.2, "scale": 1.0},
		{"color": Color(1.0, 0.35, 0.12), "count": 60, "vel": 30.0, "life": 1.6, "scale": 1.3},
		{"color": Color(0.6, 0.6, 0.65), "count": 50, "vel": 55.0, "life": 2.0, "scale": 0.6},
	]:
		var p := GPUParticles3D.new()
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 180.0
		mat.initial_velocity_min = cfg["vel"] * 0.4
		mat.initial_velocity_max = cfg["vel"]
		mat.gravity = Vector3.ZERO
		mat.scale_min = cfg["scale"] * 0.5
		mat.scale_max = cfg["scale"]
		mat.color = cfg["color"]
		mat.damping_min = 4.0
		mat.damping_max = 9.0
		var ramp := Gradient.new()
		var c: Color = cfg["color"]
		ramp.set_color(0, Color(c.r, c.g, c.b, 1.0))
		ramp.set_color(1, Color(c.r * 0.3, c.g * 0.2, c.b * 0.15, 0.0))
		var ramp_tex := GradientTexture1D.new()
		ramp_tex.gradient = ramp
		mat.color_ramp = ramp_tex
		var dm := SphereMesh.new()
		dm.radius = 0.3 * size / 9.0
		dm.height = 0.6 * size / 9.0
		var dmm := StandardMaterial3D.new()
		dmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmm.albedo_color = c
		dmm.emission_enabled = true
		dmm.emission = c
		dmm.emission_energy_multiplier = 4.0
		dmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmm.vertex_color_use_as_albedo = true
		dm.material = dmm
		p.draw_pass_1 = dm
		p.process_material = mat
		p.amount = cfg["count"]
		p.lifetime = cfg["life"]
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = true
		p.position = at
		add_child(p)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.75, 0.4)
	flash.light_energy = 14.0
	flash.omni_range = 220.0
	flash.position = at
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.1)
	tw.tween_callback(flash.queue_free)

	var boom := AudioStreamPlayer3D.new()
	boom.stream = load("res://assets/audio/explosion.wav")
	boom.unit_size = 80.0
	boom.position = at
	add_child(boom)
	boom.play()

func _show_end(won: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_end_layer = CanvasLayer.new()
	add_child(_end_layer)
	var panel := _overlay_panel(_end_layer)

	var title := UiKit.label("VICTOIRE !" if won else "DÉFAITE…", 76, Hud.SW_YELLOW if won else Color(0.95, 0.3, 0.22), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var sub := UiKit.label("La Force est puissante en toi." if won else "« %s »" % enemy.cfg["quote"], 24, Color(0.85, 0.85, 0.92))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(sub)

	panel.add_child(_spacer(30))
	panel.add_child(_menu_button("REJOUER", func() -> void: request_restart.emit()))
	panel.add_child(_menu_button("CHANGER DE PILOTE", func() -> void: request_menu.emit()))

func _toggle_pause() -> void:
	if _pause_layer != null:
		_pause_layer.queue_free()
		_pause_layer = null
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pause_layer = CanvasLayer.new()
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var panel := _overlay_panel(_pause_layer)
	var title := UiKit.label("PAUSE", 58, Hud.SW_YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	panel.add_child(_spacer(24))
	panel.add_child(_menu_button("REPRENDRE", _toggle_pause))
	panel.add_child(_menu_button("QUITTER VERS LE MENU", func() -> void:
		get_tree().paused = false
		request_menu.emit()))

func _overlay_panel(layer: CanvasLayer) -> VBoxContainer:
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
	return box

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _menu_button(text: String, action: Callable) -> Button:
	var b := UiKit.button(text, 22)
	b.custom_minimum_size = Vector2(440, 58)
	b.pressed.connect(action)
	return b
