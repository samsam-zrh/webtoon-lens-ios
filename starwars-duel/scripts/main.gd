extends Node

# App root: main menu (pilot selection with rotating 3D previews) <-> arena.

const SW_YELLOW := Color(1.0, 0.91, 0.12)
const ORDER := ["vader", "anakin", "han"]

var _menu_root: Node
var _arena: Arena
var _preview_ships: Array = []
var _phase := 0  # 0 = pick your pilot, 1 = pick the opponent
var _player_pick := ""
var _enemy_pick := ""
var _cards: Dictionary = {}
var _header: Label

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--duel" in args:
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
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/space_sky.gdshader")
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

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var title := Label.new()
	title.text = "STAR WARS"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", SW_YELLOW)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y = 36
	root.add_child(title)

	var sub := Label.new()
	sub.text = "D U E L   S P A T I A L"
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y = 150
	root.add_child(sub)

	_header = Label.new()
	_header.text = "CHOISIS TON PILOTE"
	_header.add_theme_font_size_override("font_size", 34)
	_header.add_theme_color_override("font_color", SW_YELLOW)
	_header.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_header.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_header.position.y = 210
	root.add_child(_header)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position.y = -60
	root.add_child(row)

	for id in ORDER:
		var cfg := ShipsDB.get_cfg(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(360, 190)
		b.text = "%s\n%s\n\nCoque %d   Vitesse %d   Agilité %.1f\n\n« %s »" % [
			cfg["pilot"], cfg["ship"], int(cfg["hp"]), int(cfg["max_speed"]), cfg["turn_rate"], cfg["quote"]
		]
		b.add_theme_font_size_override("font_size", 18)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_card_pressed.bind(id))
		row.add_child(b)
		_cards[id] = b

	var help := Label.new()
	help.text = "Souris : piloter  •  Clic / Espace : tirer  •  Maj : boost  •  W/S (Z/S) : gaz  •  A/D (Q/D) : tonneau  •  Échap : pause"
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.position.y = -24
	root.add_child(help)

func _on_card_pressed(id: String) -> void:
	if _phase == 0:
		_player_pick = id
		_phase = 1
		_header.text = "CHOISIS TON ADVERSAIRE"
		var card: Button = _cards[id]
		card.disabled = true
		card.modulate = Color(1.0, 0.95, 0.4)
	else:
		if id == _player_pick:
			return
		_enemy_pick = id
		start_game(_player_pick, _enemy_pick)

# ----------------------------------------------------------------- Game

func start_game(player_id: String, enemy_id: String) -> void:
	_clear()
	_arena = Arena.new()
	_arena.name = "Arena"
	add_child(_arena)
	_arena.start(player_id, enemy_id)
	_arena.request_restart.connect(func() -> void: start_game(player_id, enemy_id))
	_arena.request_menu.connect(show_menu)
