class_name GroundArena
extends Node3D

# Second game mode: 1v1 character duel on a platform.
# Vader is a real community 3D model; Luke and Han are dark silhouettes
# wielding a real lightsaber model / a blaster.

signal request_restart
signal request_menu

const ROSTER := {
	"vader": {"name": "Dark Vador", "hp": 130.0, "speed": 6.5, "melee": true,
		"saber_color": Color(1.0, 0.15, 0.1), "dmg": 14.0, "quote": "Je trouve votre manque de foi déplorable."},
	"luke": {"name": "Luke Skywalker", "hp": 100.0, "speed": 8.5, "melee": true,
		"saber_color": Color(0.3, 1.0, 0.4), "dmg": 12.0, "quote": "Je suis un Jedi, comme mon père avant moi."},
	"han": {"name": "Han Solo", "hp": 90.0, "speed": 8.0, "melee": false,
		"saber_color": Color(1.0, 0.3, 0.2), "dmg": 9.0, "quote": "Ne me dites jamais quelles sont mes chances !"},
}

var fighters: Array = []  # [{id,cfg,node,saber_blade,hp,is_player,cool,ai_t,ai_dir,swing}]
var camera: Camera3D
var _cam_yaw := 0.0
var _ended := false
var _started := false
var _hud: Control
var _msg: Label
var _bolts: Array = []

func start(player_id: String, enemy_id: String) -> void:
	_build_world()
	fighters.append(_spawn_fighter(player_id, true, Vector3(0, 0, 9)))
	fighters.append(_spawn_fighter(enemy_id, false, Vector3(0, 0, -9)))
	camera = Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.make_current()
	_build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var seq := ["3", "2", "1", "EN GARDE !"]
	for i in seq.size():
		var txt: String = seq[i]
		get_tree().create_timer(0.8 * i + 0.3).timeout.connect(func() -> void:
			_show_msg(txt)
			if txt == "EN GARDE !":
				_started = true)

func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = load("res://assets/textures/milky_way.jpg")
	sm.energy_multiplier = 1.6
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.27, 0.38)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, 0.5, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	# Duel platform floating in space
	var floor_mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 16.0
	cm.bottom_radius = 17.5
	cm.height = 1.6
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.2)
	fmat.metallic = 0.6
	fmat.roughness = 0.45
	cm.material = fmat
	floor_mesh.mesh = cm
	floor_mesh.position.y = -0.8
	add_child(floor_mesh)

	# Glowing rim ring
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 15.8
	tm.outer_radius = 16.2
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.85, 0.2)
	rmat.emission_energy_multiplier = 2.5
	rmat.albedo_color = Color(1.0, 0.85, 0.2)
	tm.material = rmat
	rim.mesh = tm
	rim.position.y = 0.02
	add_child(rim)

	# Jupiter looming overhead + Star Destroyer in the distance
	var jup := MeshInstance3D.new()
	var jm := SphereMesh.new()
	jm.radius = 1.0
	jm.height = 2.0
	jm.radial_segments = 96
	jm.rings = 48
	var jmat := StandardMaterial3D.new()
	jmat.albedo_texture = load("res://assets/textures/jupiter.jpg")
	jmat.roughness = 1.0
	jm.material = jmat
	jup.mesh = jm
	jup.scale = Vector3.ONE * 600.0
	jup.position = Vector3(900, 350, -1400)
	add_child(jup)

	var sd := ModelUtil.load_model("res://assets/models/star_destroyer.glb", 500.0, 0.0)
	sd.position = Vector3(-600, -80, -900)
	ModelUtil.tint(sd, Color(0.5, 0.53, 0.6))
	add_child(sd)

	var amb := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = stream.data.size() / 2
	amb.stream = stream
	amb.volume_db = -14.0
	add_child(amb)
	amb.play()

func _spawn_fighter(id: String, is_player: bool, pos: Vector3) -> Dictionary:
	var cfg: Dictionary = ROSTER[id]
	var node := Node3D.new()
	node.position = pos
	add_child(node)

	var blade: MeshInstance3D = null
	if id == "vader":
		var m := ModelUtil.load_model("res://assets/models/vader/scene.gltf", 2.2, PI)
		m.position.y = 1.1
		node.add_child(m)
	else:
		# Dark silhouette body (capsule + head) holding a real prop
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.32
		bm.height = 1.5
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.13, 0.12, 0.11) if id == "luke" else Color(0.16, 0.13, 0.1)
		bmat.roughness = 0.9
		bm.material = bmat
		body.mesh = bm
		body.position.y = 0.95
		node.add_child(body)
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.21
		hm.height = 0.42
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.85, 0.68, 0.55)
		hmat.roughness = 0.7
		hm.material = hmat
		head.mesh = hm
		head.position.y = 1.95
		node.add_child(head)
		if cfg["melee"]:
			var saber := ModelUtil.load_model("res://assets/models/lightsaber.glb", 0.42, 0.0)
			saber.position = Vector3(0.42, 1.15, -0.1)
			node.add_child(saber)
		else:
			var gun := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(0.08, 0.14, 0.55)
			var gmat := StandardMaterial3D.new()
			gmat.albedo_color = Color(0.1, 0.1, 0.12)
			gmat.metallic = 0.7
			gm.material = gmat
			gun.mesh = gm
			gun.position = Vector3(0.42, 1.2, -0.25)
			node.add_child(gun)

	# Glowing saber blade for melee fighters (Vader's model has its own prop,
	# we add a visible energy blade for both)
	if cfg["melee"]:
		blade = MeshInstance3D.new()
		var sbm := CapsuleMesh.new()
		sbm.radius = 0.035
		sbm.height = 1.25
		var sbmat := StandardMaterial3D.new()
		sbmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var c: Color = cfg["saber_color"]
		sbmat.albedo_color = c
		sbmat.emission_enabled = true
		sbmat.emission = c
		sbmat.emission_energy_multiplier = 6.0
		sbm.material = sbmat
		blade.mesh = sbm
		blade.position = Vector3(0.42, 1.85, -0.1)
		node.add_child(blade)
		var gl := OmniLight3D.new()
		gl.light_color = c
		gl.light_energy = 1.6
		gl.omni_range = 4.0
		gl.position = blade.position
		node.add_child(gl)

	var f := {"id": id, "cfg": cfg, "node": node, "blade": blade, "hp": cfg["hp"],
		"is_player": is_player, "cool": 0.0, "ai_t": 0.0, "ai_dir": Vector2.ZERO, "swing": 0.0}
	return f

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
	var n1 := UiKit.label(fighters[0]["cfg"]["name"], 17, Color(0.85, 0.88, 1.0))
	n1.position = Vector2(36, 24)
	_hud.add_child(n1)
	var n2 := UiKit.label(fighters[1]["cfg"]["name"], 17, Color(1, 0.5, 0.45))
	n2.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	n2.position = Vector2(-260, 24)
	_hud.add_child(n2)

func _show_msg(t: String) -> void:
	_msg.text = t
	_msg.visible = true
	_msg.reset_size()
	_msg.position = (_hud.get_viewport_rect().size - _msg.size) / 2.0 - Vector2(0, 110)
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(_msg):
			_msg.visible = false)

func _draw_hud() -> void:
	var vp := _hud.get_viewport_rect().size
	_bar(Vector2(36, 52), fighters[0]["hp"] / fighters[0]["cfg"]["hp"], Color(0.3, 0.9, 0.45))
	_bar(Vector2(vp.x - 36 - 260, 52), fighters[1]["hp"] / fighters[1]["cfg"]["hp"], Color(1, 0.32, 0.27))

func _bar(pos: Vector2, ratio: float, col: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_hud.draw_rect(Rect2(pos, Vector2(260, 14)), Color(0, 0, 0, 0.5), true)
	_hud.draw_rect(Rect2(pos + Vector2(1.5, 1.5), Vector2(257.0 * ratio, 11)), col, true)
	_hud.draw_rect(Rect2(pos, Vector2(260, 14)), Color(1, 1, 1, 0.28), false, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * 0.004
	if event.is_action_pressed("pause") and not _ended:
		request_menu.emit()

func _physics_process(delta: float) -> void:
	if fighters.size() < 2:
		return
	var p: Dictionary = fighters[0]
	var e: Dictionary = fighters[1]
	for f in fighters:
		f["cool"] = maxf(0.0, f["cool"] - delta)
		# Saber swing animation: rotate the blade forward then back
		if f["blade"] != null:
			f["swing"] = maxf(0.0, f["swing"] - delta * 3.0)
			(f["blade"] as MeshInstance3D).rotation.x = -f["swing"] * 1.9

	if _started and not _ended:
		_player_control(p, e, delta)
		_ai_control(e, p, delta)
	_update_bolts(delta)
	_update_camera(p, delta)
	_hud.queue_redraw()

func _player_control(p: Dictionary, e: Dictionary, delta: float) -> void:
	var node: Node3D = p["node"]
	var fwd := Vector3(-sin(_cam_yaw), 0, -cos(_cam_yaw))
	var right := Vector3(-fwd.z, 0, fwd.x)
	var mv := Vector3.ZERO
	if Input.is_action_pressed("throttle_up"):
		mv += fwd
	if Input.is_action_pressed("throttle_down"):
		mv -= fwd
	if Input.is_action_pressed("roll_right"):
		mv += right
	if Input.is_action_pressed("roll_left"):
		mv -= right
	var spd: float = p["cfg"]["speed"]
	if Input.is_action_pressed("boost"):
		spd *= 1.7
	node.position += mv.normalized() * spd * delta if mv.length() > 0.1 else Vector3.ZERO
	node.position = Vector3(node.position.x, 0, node.position.z)
	if node.position.length() > 15.0:
		node.position = node.position.normalized() * 15.0
	# Face the enemy
	var look := (e["node"] as Node3D).position - node.position
	if look.length() > 0.5:
		node.rotation.y = atan2(-look.x, -look.z)
	if Input.is_action_pressed("fire") and p["cool"] <= 0.0:
		_attack(p, e)

func _ai_control(e: Dictionary, p: Dictionary, delta: float) -> void:
	var node: Node3D = e["node"]
	var pnode: Node3D = p["node"]
	e["ai_t"] -= delta
	if e["ai_t"] <= 0.0:
		e["ai_t"] = randf_range(0.7, 1.6)
		e["ai_dir"] = Vector2(randf_range(-1, 1), randf_range(0.2, 1.0)).normalized()
	var to_p := pnode.position - node.position
	var dist := to_p.length()
	var fwd := to_p.normalized()
	var strafe: Vector3 = Vector3(-fwd.z, 0, fwd.x) * float(e["ai_dir"].x)
	var want_dist: float = 2.6 if e["cfg"]["melee"] else 8.5
	var approach: float = clampf((dist - want_dist) * 0.6, -1.0, 1.0)
	var mv: Vector3 = (fwd * approach + strafe * 0.7).normalized()
	node.position += mv * e["cfg"]["speed"] * 0.8 * delta
	node.position = Vector3(node.position.x, 0, node.position.z)
	if node.position.length() > 15.0:
		node.position = node.position.normalized() * 15.0
	node.rotation.y = atan2(-fwd.x, -fwd.z)
	var in_range := dist < 3.2 if e["cfg"]["melee"] else dist < 13.0
	if in_range and e["cool"] <= 0.0 and randf() < 0.65:
		_attack(e, p)

func _attack(a: Dictionary, b: Dictionary) -> void:
	var melee: bool = a["cfg"]["melee"]
	a["cool"] = 0.65 if melee else 0.5
	var anode: Node3D = a["node"]
	var bnode: Node3D = b["node"]
	if melee:
		a["swing"] = 1.0
		_play3d("res://assets/audio/laser_red.wav", anode.position, -4.0)
		# Lunge forward
		var dir := (bnode.position - anode.position)
		var dist := dir.length()
		if dist < 6.0:
			anode.position += dir.normalized() * minf(2.2, maxf(0.0, dist - 1.2))
		if dist < 3.6:
			_damage(b, a["cfg"]["dmg"])
	else:
		_play3d("res://assets/audio/laser_green.wav", anode.position, -4.0)
		var bolt := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.05
		bm.height = 0.7
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0.25, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.25, 0.2)
		mat.emission_energy_multiplier = 6.0
		bm.material = mat
		bolt.mesh = bm
		bolt.rotation.x = PI / 2.0
		var origin: Vector3 = anode.position + Vector3(0, 1.2, 0)
		var target: Vector3 = bnode.position + Vector3(0, 1.1, 0)
		var dir2 := (target - origin).normalized()
		# Slight aim error so it is dodgeable
		dir2 = (dir2 + Vector3(randf_range(-0.05, 0.05), randf_range(-0.03, 0.03), randf_range(-0.05, 0.05))).normalized()
		bolt.position = origin
		add_child(bolt)
		_bolts.append({"node": bolt, "dir": dir2, "life": 2.0, "from": a})

func _update_bolts(delta: float) -> void:
	var keep: Array = []
	for b in _bolts:
		var node: MeshInstance3D = b["node"]
		b["life"] -= delta
		node.position += b["dir"] * 26.0 * delta
		node.look_at(node.position + b["dir"])
		var hit := false
		for f in fighters:
			if f == b["from"]:
				continue
			if node.position.distance_to((f["node"] as Node3D).position + Vector3(0, 1.1, 0)) < 0.8:
				_damage(f, b["from"]["cfg"]["dmg"])
				hit = true
		if b["life"] <= 0.0 or hit:
			node.queue_free()
		else:
			keep.append(b)
	_bolts = keep

func _damage(f: Dictionary, dmg: float) -> void:
	if _ended:
		return
	f["hp"] -= dmg
	_play3d("res://assets/audio/hit.wav", (f["node"] as Node3D).position, -2.0)
	if f["hp"] <= 0.0:
		f["hp"] = 0.0
		_ended = true
		(f["node"] as Node3D).rotation.x = PI / 2.0 * (1 if f["id"] != "vader" else -1)
		_play3d("res://assets/audio/explosion.wav", (f["node"] as Node3D).position, -2.0)
		var won: bool = not f["is_player"]
		get_tree().create_timer(1.2).timeout.connect(func() -> void: _show_end(won))

func _play3d(path: String, at: Vector3, db: float) -> void:
	var sp := AudioStreamPlayer3D.new()
	sp.stream = load(path)
	sp.position = at
	sp.volume_db = db
	sp.unit_size = 20.0
	add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)

func _update_camera(p: Dictionary, delta: float) -> void:
	var node: Node3D = p["node"]
	var back := Vector3(sin(_cam_yaw), 0, cos(_cam_yaw))
	var desired := node.position + back * 7.5 + Vector3(0, 3.4, 0)
	camera.position = camera.position.lerp(desired, clampf(9.0 * delta, 0, 1))
	camera.look_at(node.position + Vector3(0, 1.6, 0) - back * 3.0)

func _show_end(won: bool) -> void:
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
	var sub := UiKit.label("« %s »" % fighters[1]["cfg"]["quote"] if not won else "La Force est puissante en toi.", 22, Color(0.85, 0.85, 0.92))
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
