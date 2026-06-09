extends Node

# App root: main menu (pilot selection with rotating 3D previews) <-> arena.

const SW_YELLOW := Color(1.0, 0.91, 0.12)
const ORDER := ["vader", "anakin", "han"]

var _menu_root: Node
var _arena: Arena
var _preview_ships: Array = []
var _phase := 0  # 0 = pick your pilot, 1 = pick the opponent
var _mode := "ships"  # "ships" (dogfight) or "ground" (character duel)
var _player_pick := ""
var _enemy_pick := ""
var _cards: Dictionary = {}
var _header: Label

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ground" in args:
		_mode = "ground"
		start_game("luke", "vader")
	elif "--duel" in args:
		start_game("anakin", "vader")
	else:
		show_menu()
	if "--shots" in args:
		_capture_screenshots()

# Debug helper: saves periodic screenshots so the game can be checked headless.
func _capture_screenshots() -> void:
	for i in 8:
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/shots/shot_%02d.png" % i)
	get_tree().quit()

func _clear() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	for c in get_children():
		c.queue_free()
	_menu_root = null
	_arena = null
	_preview_ships = []
	_cards = {}

func _process(delta: float) -> void:
	for s in _preview_ships:
		if is_instance_valid(s):
			s.rotation.y += delta * 0.5

# ----------------------------------------------------------------- Menu

func show_menu() -> void:
	_clear()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_phase = 0
	_player_pick = ""
	_enemy_pick = ""
	_menu_root = Node.new()
	_menu_root.name = "Menu"
	add_child(_menu_root)
	_build_menu_world()
	_build_menu_ui()

func _build_menu_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/textures/milky_way.jpg")
	sky_mat.energy_multiplier = 1.5
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.32, 0.45)
	env.ambient_light_energy = 0.9
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	_menu_root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.5, 0.4, 0.0)
	sun.light_energy = 1.6
	_menu_root.add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.5, 26)
	cam.rotation.x = -0.06
	_menu_root.add_child(cam)
	cam.make_current()

	var xs := [-14.0, 0.0, 14.0]
	for i in ORDER.size():
		var cfg := ShipsDB.get_cfg(ORDER[i])
		var m := ModelUtil.load_model(cfg["model"], cfg["target_len"], cfg["model_rot"])
		m.position = Vector3(xs[i], 1.5, 0)
		_menu_root.add_child(m)
		_preview_ships.append(m)

	var amb := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = stream.data.size() / 2
	amb.stream = stream
	amb.volume_db = -10.0
	_menu_root.add_child(amb)
	amb.play()

func _build_menu_ui() -> void:
	var ui := CanvasLayer.new()
	_menu_root.add_child(ui)

	ui.add_child(UiKit.vignette())

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.position.y = 30
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var title := UiKit.label("STAR WARS", 92, SW_YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)

	var sub := UiKit.label("D U E L   S P A T I A L", 24, Color(0.82, 0.85, 0.95), true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	top.add_child(spacer)

	_header = UiKit.label("CHOISIS TON PILOTE", 28, SW_YELLOW, true)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_header)

	# Mode toggle: ship dogfight or character duel
	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 16)
	top.add_child(modes)
	var bs := UiKit.button("VAISSEAUX", 16)
	bs.custom_minimum_size = Vector2(220, 40)
	bs.pressed.connect(func() -> void:
		_mode = "ships"
		show_menu())
	modes.add_child(bs)
	var bg := UiKit.button("PERSONNAGES", 16)
	bg.custom_minimum_size = Vector2(220, 40)
	bg.pressed.connect(func() -> void:
		_mode = "ground"
		show_menu())
	modes.add_child(bg)
	if _mode == "ships":
		bs.disabled = true
	else:
		bg.disabled = true

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position.y = -64
	root.add_child(row)

	for id in (ORDER if _mode == "ships" else ["vader", "luke", "han"]):
		row.add_child(_make_card(id))

	var help := UiKit.label(
		"Souris : piloter   •   Clic / Espace : tirer   •   Maj : boost   •   Z/S : gaz   •   Q/D : tonneau   •   Échap : pause",
		15, Color(0.62, 0.65, 0.75))
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position.y = -30
	root.add_child(help)

func _make_card(id: String) -> Button:
	var ship_mode := _mode == "ships"
	var cfg: Dictionary = ShipsDB.get_cfg(id) if ship_mode else GroundArena.ROSTER[id]
	var b := UiKit.button("")
	b.custom_minimum_size = Vector2(370, 200)
	b.pressed.connect(_on_card_pressed.bind(id))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 14
	box.offset_bottom = -14
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)

	var disp_name: String = cfg["pilot"] if ship_mode else cfg["name"]
	var name_l := UiKit.label(disp_name.to_upper(), 22, SW_YELLOW, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)

	var sub_txt: String = cfg["ship"] if ship_mode else ("Sabre laser" if cfg["melee"] else "Blaster")
	var ship_l := UiKit.label(sub_txt, 16, Color(0.85, 0.88, 1.0))
	ship_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ship_l)

	var sep := ColorRect.new()
	sep.color = UiKit.BORDER_DIM
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sep)

	var stats_txt: String
	if ship_mode:
		stats_txt = "COQUE %d    VITESSE %d    AGILITÉ %.1f" % [int(cfg["hp"]), int(cfg["max_speed"]), cfg["turn_rate"]]
	else:
		stats_txt = "VIE %d    VITESSE %d    DÉGÂTS %d" % [int(cfg["hp"]), int(cfg["speed"]), int(cfg["dmg"])]
	var stats_l := UiKit.label(stats_txt, 13, Color(0.7, 0.9, 1.0), true)
	stats_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stats_l)

	var quote_l := UiKit.label("« %s »" % cfg["quote"], 14, Color(0.6, 0.63, 0.72))
	quote_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote_l.custom_minimum_size = Vector2(320, 0)
	box.add_child(quote_l)

	_cards[id] = b
	return b

func _on_card_pressed(id: String) -> void:
	if _phase == 0:
		_player_pick = id
		_phase = 1
		_header.text = "CHOISIS TON ADVERSAIRE"
		var card: Button = _cards[id]
		card.disabled = true
		var picked := UiKit.panel_style(SW_YELLOW, Color(0.07, 0.065, 0.03, 0.92))
		card.add_theme_stylebox_override("disabled", picked)
	else:
		if id == _player_pick:
			return
		_enemy_pick = id
		start_game(_player_pick, _enemy_pick)

# ----------------------------------------------------------------- Game

func start_game(player_id: String, enemy_id: String) -> void:
	_clear()
	if _mode == "ground":
		var ga := GroundArena.new()
		ga.name = "GroundArena"
		add_child(ga)
		ga.start(player_id, enemy_id)
		ga.request_restart.connect(func() -> void: start_game(player_id, enemy_id))
		ga.request_menu.connect(show_menu)
		return
	_arena = Arena.new()
	_arena.name = "Arena"
	add_child(_arena)
	_arena.start(player_id, enemy_id)
	_arena.request_restart.connect(func() -> void: start_game(player_id, enemy_id))
	_arena.request_menu.connect(show_menu)
