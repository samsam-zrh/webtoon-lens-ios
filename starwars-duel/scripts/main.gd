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
var _campaign_hero := ""    # "" = not in campaign
var _campaign_stage := -1
var _campaign_picking := false
var _arena_row: HBoxContainer
var _fps_label: Label

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ground" in args:
		_mode = "ground"
		start_game("luke", "vader")
	elif "--ground2" in args:
		_mode = "ground"
		start_game("luke", "trooper")
	elif "--groundv" in args:
		_mode = "ground"
		start_game("vader", "luke")
	elif "--groundh" in args:
		_mode = "ground"
		start_game("luke", "vader", {"theme": "hangar"})
	elif "--groundk" in args:
		_mode = "ground"
		start_game("kenobi", "sith", {"theme": "hangar"})
	elif "--groundb" in args:
		_mode = "ground"
		start_game("luke", "vader", {"theme": "bespin"})
	elif "--groundc" in args:
		_mode = "ground"
		start_game("luke", "vader", {"theme": "control"})
	elif "--groundi" in args:
		_mode = "ground"
		start_game("luke", "vader", {"theme": "imperial"})
	elif "--campaign2" in args:
		_mode = "ground"
		_campaign_hero = "luke"
		_start_campaign_stage(1)
	elif "--campaign" in args:
		_mode = "ground"
		_campaign_hero = "luke"
		_start_campaign_stage(0)
	elif "--groundmenu" in args:
		_mode = "ground"
		show_menu()
	elif "--duel" in args:
		start_game("anakin", "vader")
	else:
		show_menu()
	if "--options" in args:
		get_tree().create_timer(2.0).timeout.connect(_show_options)
	if "--photoholo" in args:
		get_tree().create_timer(7.0).timeout.connect(func() -> void:
			var ga: GroundArena = get_node_or_null("GroundArena")
			if ga != null:
				ga.player.global_position = Vector3(11.5, 0.1, -1.0)
				ga._cam_yaw = -0.85
				ga._cam_pitch = -0.05)
	if "--winfast" in args:
		# Headless testing: end the duel in victory shortly after it starts
		get_tree().create_timer(22.0).timeout.connect(func() -> void:
			var ga: GroundArena = get_node_or_null("GroundArena")
			if ga != null and ga.enemy != null and ga.enemy.alive:
				ga.enemy.take_hit(99999.0, ga.player))
	if "--botatk" in args:
		# Headless testing: attack regularly and push once in a while
		var atk := func() -> void:
			Input.action_press("fire")
			get_tree().create_timer(0.1).timeout.connect(func() -> void: Input.action_release("fire"))
		var t := Timer.new()
		t.wait_time = 1.4
		t.autostart = true
		add_child(t)
		t.timeout.connect(atk)
		var t2 := Timer.new()
		t2.wait_time = 7.0
		t2.autostart = true
		add_child(t2)
		t2.timeout.connect(func() -> void:
			Input.action_press("force_push")
			get_tree().create_timer(0.1).timeout.connect(func() -> void: Input.action_release("force_push")))
	if "--botblock" in args:
		# Headless testing: hold the saber in guard once the duel starts
		get_tree().create_timer(6.0).timeout.connect(func() -> void:
			Input.action_press("block"))
	if "--botfwd" in args:
		# Headless testing: hold "forward" once the duel starts
		get_tree().create_timer(5.0).timeout.connect(func() -> void:
			Input.action_press("throttle_up"))
	var fps_layer := CanvasLayer.new()
	fps_layer.layer = 10
	add_child(fps_layer)
	_fps_label = UiKit.label("", 14, Color(0.6, 1.0, 0.6))
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.position = Vector2(-90, 8)
	fps_layer.add_child(_fps_label)
	for a in args:
		if a.begins_with("--shots"):
			_capture_screenshots(int(a.trim_prefix("--shots")) if a.length() > 7 else 8)
		if a.begins_with("--film"):
			_capture_film(int(a.trim_prefix("--film")) if a.length() > 6 else 90)

# Debug helper: saves periodic screenshots so the game can be checked headless.
func _capture_screenshots(count := 8) -> void:
	for i in count:
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/shots/shot_%02d.png" % i)
	get_tree().quit()

# Rapid frame grab for assembling a short gameplay clip (every 2nd frame).
func _capture_film(count := 90) -> void:
	await get_tree().create_timer(0.3).timeout
	for i in count:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/film/f_%03d.png" % i)
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
	if _fps_label != null:
		_fps_label.visible = GameSettings.show_fps
		if GameSettings.show_fps:
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
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

	if _mode == "ships":
		var xs := [-14.0, 0.0, 14.0]
		for i in ORDER.size():
			var cfg := ShipsDB.get_cfg(ORDER[i])
			var m := ModelUtil.load_model(cfg["model"], cfg["target_len"], cfg["model_rot"])
			m.position = Vector3(xs[i], 1.5, 0)
			_menu_root.add_child(m)
			_preview_ships.append(m)
	else:
		# Character previews on pedestals, playing their idle animation
		var pedestal_mat := StandardMaterial3D.new()
		pedestal_mat.albedo_color = Color(0.12, 0.13, 0.18)
		pedestal_mat.metallic = 0.7
		pedestal_mat.roughness = 0.3
		var specs := [
			["luke", Vector3(-5.4, 0.7, 19.8), PI, "01_IdleArmed"],
			["kenobi", Vector3(-2.7, 0.7, 19.4), PI, "01_IdleArmed"],
			["vader", Vector3(0.0, 0.7, 19.0), PI, "01_IdleArmed"],
			["trooper", Vector3(2.7, 0.7, 19.4), PI, "01_Idle"],
			["sith", Vector3(5.4, 0.7, 19.8), PI, "01_Idle"],
		]
		for spec in specs:
			var gcfg: Dictionary = GroundArena.ROSTER[spec[0]]
			var holder := Node3D.new()
			holder.position = spec[1]
			holder.rotation.y = spec[2]
			_menu_root.add_child(holder)
			var m2: Node3D = GroundFighter.build_character_model(gcfg)
			holder.add_child(m2)
			var ap: AnimationPlayer = m2.find_child("AnimationPlayer", true, false)
			if ap != null and spec[3] != "" and ap.has_animation(spec[3]):
				ap.play(spec[3])
			# Spotlight over each pedestal so the characters read clearly
			var spot := SpotLight3D.new()
			spot.position = Vector3(0, 4.2, 1.6)
			spot.rotation.x = -1.18
			spot.spot_range = 6.5
			spot.spot_angle = 24.0
			spot.light_energy = 5.0
			spot.light_color = Color(0.9, 0.93, 1.0)
			spot.shadow_enabled = true
			holder.add_child(spot)
			var rim := OmniLight3D.new()
			rim.position = Vector3(0, 1.6, -1.4)
			rim.omni_range = 3.5
			rim.light_energy = 1.2
			rim.light_color = Color(0.45, 0.55, 1.0)
			holder.add_child(rim)
			var ped := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 1.0
			pm.bottom_radius = 1.1
			pm.height = 0.1
			pm.material = pedestal_mat
			ped.mesh = pm
			ped.position.y = -0.05
			holder.add_child(ped)
			_preview_ships.append(holder)

	var amb := AudioStreamPlayer.new()
	var custom := MusicDirector.external_stream("menu")
	if custom != null:
		amb.stream = custom
		amb.volume_db = -8.0
	else:
		var stream: AudioStreamWAV = load("res://assets/audio/ambient.wav").duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = stream.data.size() / 2
		amb.stream = stream
		amb.volume_db = -10.0
	amb.bus = "Music"
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
	var bo := UiKit.button("OPTIONS", 16)
	bo.custom_minimum_size = Vector2(160, 40)
	bo.pressed.connect(_show_options)
	modes.add_child(bo)
	if _mode == "ships":
		bs.disabled = true
	else:
		bg.disabled = true
		var bc := UiKit.button("CAMPAGNE", 16)
		bc.custom_minimum_size = Vector2(220, 40)
		bc.pressed.connect(func() -> void:
			_campaign_picking = true
			_phase = 0
			_header.text = "CAMPAGNE : CHOISIS TON HÉROS")
		modes.add_child(bc)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.position.y = -64
	root.add_child(row)

	for id in (ORDER if _mode == "ships" else ["luke", "kenobi", "vader", "trooper", "sith"]):
		row.add_child(_make_card(id))

	# arena selection row (phase 2), hidden until the opponent is picked
	_arena_row = HBoxContainer.new()
	_arena_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_arena_row.add_theme_constant_override("separation", 36)
	_arena_row.set_anchors_preset(Control.PRESET_CENTER)
	_arena_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_arena_row.grow_vertical = Control.GROW_DIRECTION_BOTH
	_arena_row.visible = false
	root.add_child(_arena_row)
	for spec in [["SALLE DU TRÔNE", "throne"], ["HANGAR IMPÉRIAL", "hangar"], ["CITÉ DES NUAGES", "bespin"], ["CENTRE DE CONTRÔLE", "control"], ["COULOIR IMPÉRIAL", "imperial"]]:
		var ab := UiKit.button(spec[0], 19)
		ab.custom_minimum_size = Vector2(240, 115)
		ab.pressed.connect(func() -> void:
			start_game(_player_pick, _enemy_pick, {"theme": spec[1]}))
		_arena_row.add_child(ab)

	var help_text: String
	if _mode == "ships":
		help_text = "Souris : piloter   •   Clic / Espace : tirer   •   Maj : boost   •   Z/S : gaz   •   Q/D : tonneau   •   Échap : pause"
	else:
		help_text = "ZQSD : se déplacer   •   Clic : attaque   •   Clic droit : parade (renvoie les tirs !)   •   Maj : esquive   •   E : poussée de Force   •   Échap : menu"
	var n_music := MusicDirector.detected_count()
	var music_l := UiKit.label(
		"♪ Musique personnalisée : %d piste(s) détectée(s)" % n_music if n_music > 0
		else "♪ Dossier « music » non détecté (musique libre incluse)",
		13, Color(0.45, 0.85, 0.5) if n_music > 0 else Color(0.5, 0.53, 0.6))
	music_l.position = Vector2(18, 14)
	root.add_child(music_l)

	var help := UiKit.label(help_text, 15, Color(0.62, 0.65, 0.75))
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position.y = -30
	root.add_child(help)

func _make_card(id: String) -> Button:
	var ship_mode := _mode == "ships"
	var cfg: Dictionary = ShipsDB.get_cfg(id) if ship_mode else GroundArena.ROSTER[id]
	var b := UiKit.button("")
	b.custom_minimum_size = Vector2(286, 200)
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
	quote_l.custom_minimum_size = Vector2(244, 0)
	box.add_child(quote_l)

	_cards[id] = b
	return b

func _on_card_pressed(id: String) -> void:
	if _campaign_picking:
		_campaign_picking = false
		_campaign_hero = id
		_start_campaign_stage(0)
		return
	if _phase == 0:
		_player_pick = id
		_phase = 1
		_header.text = "CHOISIS TON ADVERSAIRE"
		var card: Button = _cards[id]
		card.disabled = true
		var picked := UiKit.panel_style(SW_YELLOW, Color(0.07, 0.065, 0.03, 0.92))
		card.add_theme_stylebox_override("disabled", picked)
	elif _phase == 1:
		if id == _player_pick:
			return
		_enemy_pick = id
		_phase = 2
		_header.text = "CHOISIS L'ARÈNE"
		for c in _cards.values():
			(c as Button).visible = false
		_arena_row.visible = true

# ----------------------------------------------------------------- Game

func start_game(player_id: String, enemy_id: String, opts: Dictionary = {}) -> void:
	_clear()
	if _mode == "ground":
		var ga := GroundArena.new()
		ga.name = "GroundArena"
		add_child(ga)
		ga.start(player_id, enemy_id, {}, opts)
		ga.request_restart.connect(func() -> void: start_game(player_id, enemy_id, opts))
		ga.request_menu.connect(show_menu)
		return
	_arena = Arena.new()
	_arena.name = "Arena"
	add_child(_arena)
	_arena.start(player_id, enemy_id)
	_arena.request_restart.connect(func() -> void: start_game(player_id, enemy_id))
	_arena.request_menu.connect(show_menu)

# ----------------------------------------------------------------- Campagne
# Quatre chapitres contre des adversaires de plus en plus dangereux, reliés
# par un texte déroulant. Récits originaux (hommage, pas de texte des films).

func _campaign_stages() -> Array:
	var rival := "vader" if _campaign_hero != "vader" else "luke"
	var rival_name: String = GroundArena.ROSTER[rival]["name"]
	return [
		{"id": "trooper", "mods": {}, "theme": "hangar",
			"title": "CHAPITRE I — L'AVANT-POSTE",
			"text": "La guerre civile embrase la galaxie.\nInfiltré dans le hangar d'une station impériale, tu es\nrepéré par une sentinelle. Il faudra passer par la force."},
		{"id": "trooper", "mods": {}, "count": 2, "theme": "hangar",
			"title": "CHAPITRE II — LA PATROUILLE",
			"text": "L'alarme résonne sous les voûtes du hangar.\nUne patrouille de deux soldats converge vers toi.\nReste mobile — et renvoie-leur leurs tirs."},
		{"id": "sith", "mods": {}, "theme": "throne",
			"title": "CHAPITRE III — L'ÉCARLATE",
			"text": "Dans la salle du trône, un soldat à l'armure rouge\nsang barre le passage. L'élite de l'Ordre Final ne\nrecule jamais. Toi non plus."},
		{"id": rival, "mods": {}, "theme": "bespin",
			"title": "CHAPITRE IV — LA CITÉ DES NUAGES",
			"text": "Loin au-dessus de la planète gazeuse, la vapeur monte\nde la chambre de congélation. %s t'attend\nau bord du gouffre. Le premier duel commence." % rival_name},
		{"id": "sith", "mods": {"name": "Garde prétorien", "mul": {"hp": 1.4, "dmg": 1.2, "speed": 1.2}, "set": {"ai_skill": 0.8}}, "count": 2, "theme": "throne",
			"title": "CHAPITRE V — LES GARDES PRÉTORIENS",
			"text": "Deux gardes d'élite surgissent pour protéger leur\nmaître. Encerclé dans la salle du trône, tu devras\nrester en mouvement pour survivre."},
		{"id": rival, "mods": {"name": rival_name + " (maître)", "mul": {"hp": 1.5, "dmg": 1.3}, "set": {"ai_skill": 0.85, "ai_block_chance": 0.6}}, "theme": "bespin",
			"title": "CHAPITRE VI — LE DERNIER DUEL",
			"text": "Blessé mais debout, ton adversaire canalise toute\nsa puissance. Ce duel sera le dernier.\nQue la Force soit avec toi."},
	]

func _start_campaign_stage(stage: int) -> void:
	_campaign_stage = stage
	var st: Dictionary = _campaign_stages()[stage]
	_clear()
	# opening crawl
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.005, 0.005, 0.012)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var stars := TextureRect.new()
	stars.texture = load("res://assets/textures/milky_way.jpg")
	stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	stars.modulate = Color(0.45, 0.45, 0.55)
	layer.add_child(stars)
	var crawl := VBoxContainer.new()
	crawl.set_anchors_preset(Control.PRESET_CENTER)
	crawl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crawl.grow_vertical = Control.GROW_DIRECTION_BOTH
	crawl.alignment = BoxContainer.ALIGNMENT_CENTER
	crawl.add_theme_constant_override("separation", 26)
	layer.add_child(crawl)
	var title := UiKit.label(st["title"], 44, SW_YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crawl.add_child(title)
	var body := UiKit.label(st["text"], 24, Color(1.0, 0.9, 0.35))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crawl.add_child(body)
	var hint := UiKit.label("Clic pour continuer", 15, Color(0.6, 0.63, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crawl.add_child(hint)
	# slow upward drift, Star Wars style
	crawl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(crawl, "modulate:a", 1.0, 1.2)
	tw.parallel().tween_property(crawl, "position:y", -60.0, 9.0).as_relative()
	var started := [false]
	var begin := func() -> void:
		if started[0]:
			return
		started[0] = true
		_begin_campaign_duel(st)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			begin.call())
	get_tree().create_timer(9.0).timeout.connect(begin)

func _begin_campaign_duel(st: Dictionary) -> void:
	_clear()
	var ga := GroundArena.new()
	ga.name = "GroundArena"
	add_child(ga)
	ga.campaign_mode = true
	ga.campaign_next = _campaign_stage < _campaign_stages().size() - 1
	ga.start(_campaign_hero, st["id"], st["mods"], {"theme": st.get("theme", "throne"), "count": st.get("count", 1)})
	ga.request_restart.connect(func() -> void: _start_campaign_stage(_campaign_stage))
	ga.request_next.connect(func() -> void: _start_campaign_stage(_campaign_stage + 1))
	ga.request_menu.connect(func() -> void:
		_campaign_hero = ""
		_campaign_stage = -1
		show_menu())

# ----------------------------------------------------------------- Options

func _show_options() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.02, 0.95)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(640, 0)
	layer.add_child(box)
	var title := UiKit.label("OPTIONS", 44, SW_YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)

	var add_slider := func(label: String, minv: float, maxv: float, step: float, value: float, on_change: Callable) -> void:
		grid.add_child(UiKit.label(label, 18, Color(0.85, 0.88, 1.0)))
		var sl := HSlider.new()
		sl.min_value = minv
		sl.max_value = maxv
		sl.step = step
		sl.value = value
		sl.custom_minimum_size = Vector2(330, 26)
		sl.value_changed.connect(on_change)
		grid.add_child(sl)
	var add_check := func(label: String, value: bool, on_change: Callable) -> void:
		grid.add_child(UiKit.label(label, 18, Color(0.85, 0.88, 1.0)))
		var cb := CheckButton.new()
		cb.button_pressed = value
		cb.toggled.connect(on_change)
		grid.add_child(cb)

	add_slider.call("Sensibilité souris", 0.3, 2.5, 0.05, GameSettings.sensitivity,
		func(v: float) -> void: GameSettings.sensitivity = v)
	add_check.call("Inverser l'axe Y", GameSettings.invert_y,
		func(v: bool) -> void: GameSettings.invert_y = v)
	add_slider.call("Champ de vision (FOV)", 55.0, 90.0, 1.0, GameSettings.fov,
		func(v: float) -> void: GameSettings.fov = v)
	add_slider.call("Volume général", 0.0, 1.0, 0.05, GameSettings.volume_master,
		func(v: float) -> void:
			GameSettings.volume_master = v
			GameSettings.apply())
	add_slider.call("Volume musique", 0.0, 1.0, 0.05, GameSettings.volume_music,
		func(v: float) -> void:
			GameSettings.volume_music = v
			GameSettings.apply())
	add_slider.call("Volume effets", 0.0, 1.0, 0.05, GameSettings.volume_sfx,
		func(v: float) -> void:
			GameSettings.volume_sfx = v
			GameSettings.apply())
	grid.add_child(UiKit.label("Qualité graphique", 18, Color(0.85, 0.88, 1.0)))
	var q := OptionButton.new()
	for n in ["Basse", "Moyenne", "Haute"]:
		q.add_item(n)
	q.selected = GameSettings.quality
	q.item_selected.connect(func(i: int) -> void: GameSettings.quality = i)
	grid.add_child(q)
	add_check.call("Vibrations manette", GameSettings.rumble,
		func(v: bool) -> void: GameSettings.rumble = v)
	add_check.call("Plein écran", GameSettings.fullscreen,
		func(v: bool) -> void:
			GameSettings.fullscreen = v
			GameSettings.apply())
	add_check.call("Afficher les FPS", GameSettings.show_fps,
		func(v: bool) -> void: GameSettings.show_fps = v)

	var hint := UiKit.label("La qualité graphique s'applique au prochain duel.", 14, Color(0.6, 0.63, 0.72))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var back := UiKit.button("FERMER", 20)
	back.custom_minimum_size = Vector2(300, 52)
	back.pressed.connect(func() -> void:
		GameSettings.save_settings()
		GameSettings.apply()
		layer.queue_free())
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(back)
	box.add_child(center)
