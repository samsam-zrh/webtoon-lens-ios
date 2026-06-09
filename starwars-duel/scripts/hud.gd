class_name Hud
extends CanvasLayer

# In-game HUD: crosshair, steering cursor, enemy markers, bars, messages.

const SW_YELLOW := UiKit.SW_YELLOW

var player: Ship
var enemy: Ship
var camera: Camera3D
var mouse_offset := Vector2.ZERO

var _canvas: Control
var _msg_label: Label
var _player_name: Label
var _enemy_name: Label
var _speed_label: Label
var _dist_label: Label
var _warn_label: Label

func _ready() -> void:
	add_child(UiKit.vignette())

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)

	_player_name = UiKit.label("", 17, Color(0.85, 0.88, 1.0))
	_canvas.add_child(_player_name)

	_enemy_name = UiKit.label("", 17, Color(1, 0.5, 0.45))
	_canvas.add_child(_enemy_name)

	_speed_label = UiKit.label("", 22, Color(0.7, 0.9, 1.0), true)
	_canvas.add_child(_speed_label)

	_dist_label = UiKit.label("", 14, Color(1, 0.6, 0.55), true)
	_canvas.add_child(_dist_label)

	_msg_label = UiKit.label("", 64, SW_YELLOW, true)
	_msg_label.visible = false
	_canvas.add_child(_msg_label)

	_warn_label = UiKit.label("!  LIMITE DE ZONE — DEMI-TOUR  !", 24, Color(1, 0.35, 0.25), true)
	_warn_label.visible = false
	_canvas.add_child(_warn_label)

func show_center_message(text: String, duration: float = 0.9) -> void:
	_msg_label.text = text
	_msg_label.visible = true
	_msg_label.reset_size()
	var vp := _canvas.get_viewport_rect().size
	_msg_label.position = (vp - _msg_label.size) / 2.0 - Vector2(0, 120)
	var t := get_tree().create_timer(duration)
	t.timeout.connect(func() -> void:
		if is_instance_valid(_msg_label):
			_msg_label.visible = false)

func _process(_delta: float) -> void:
	if player == null or enemy == null or camera == null:
		return
	var vp := _canvas.get_viewport_rect().size

	_player_name.text = "%s — %s" % [player.cfg["pilot"], player.cfg["ship"]]
	_player_name.position = Vector2(36, vp.y - 132)

	_enemy_name.text = "%s — %s" % [enemy.cfg["pilot"], enemy.cfg["ship"]]
	_enemy_name.reset_size()
	_enemy_name.position = Vector2(vp.x - _enemy_name.size.x - 36, 30)

	_speed_label.text = "%d M/S" % int(player.speed)
	_speed_label.reset_size()
	_speed_label.position = Vector2(vp.x - _speed_label.size.x - 36, vp.y - 64)

	_warn_label.visible = player.global_position.length() > Arena.ARENA_RADIUS and player.alive
	if _warn_label.visible:
		_warn_label.reset_size()
		_warn_label.position = Vector2((vp.x - _warn_label.size.x) / 2.0, vp.y * 0.24)

	_canvas.queue_redraw()

func _draw_hud() -> void:
	if player == null or enemy == null or camera == null:
		return
	var vp := _canvas.get_viewport_rect().size
	var center := vp / 2.0
	var font := UiKit.body_font()

	# Crosshair: circle + ticks
	var ch_col := Color(0.6, 1.0, 0.7, 0.85)
	_canvas.draw_arc(center, 13.0, 0, TAU, 40, ch_col, 1.2, true)
	for ang in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:
		var v := Vector2(cos(ang), sin(ang))
		_canvas.draw_line(center + v * 17.0, center + v * 24.0, ch_col, 1.2, true)

	# Steering cursor
	var cur := center + mouse_offset * (minf(vp.x, vp.y) * 0.32)
	_canvas.draw_arc(cur, 4.5, 0, TAU, 20, Color(1, 1, 1, 0.8), 1.2, true)

	# Enemy marker + lead reticle
	if enemy.alive:
		var epos := enemy.global_position
		if not camera.is_position_behind(epos):
			var p := camera.unproject_position(epos)
			var col := Color(1, 0.35, 0.3, 0.95)
			_draw_corner_box(p, 24.0, col)
			_dist_label.text = "%d m" % int(player.global_position.distance_to(epos))
			_dist_label.reset_size()
			_dist_label.position = p + Vector2(30, -10)
			_dist_label.visible = true
			# Lead reticle: where to shoot so the bolt meets the target
			var tof := player.global_position.distance_to(epos) / Ship.LASER_SPEED
			var lead := epos + enemy.linear_velocity() * tof
			if not camera.is_position_behind(lead):
				var lp := camera.unproject_position(lead)
				var lc := Color(1, 0.85, 0.2, 0.95)
				var pts := PackedVector2Array([
					lp + Vector2(0, -9), lp + Vector2(9, 0), lp + Vector2(0, 9), lp + Vector2(-9, 0), lp + Vector2(0, -9)
				])
				_canvas.draw_polyline(pts, lc, 1.4, true)
		else:
			# Off-screen arrow toward the enemy
			var dir3 := (enemy.global_position - player.global_position).normalized()
			var local := camera.global_transform.basis.inverse() * dir3
			var dir2 := Vector2(local.x, -local.y).normalized()
			var edge := center + dir2 * (minf(vp.x, vp.y) * 0.42)
			var col2 := Color(1, 0.35, 0.3, 0.9)
			var perp := Vector2(-dir2.y, dir2.x)
			_canvas.draw_colored_polygon(PackedVector2Array([
				edge + dir2 * 13.0, edge - dir2 * 4.0 + perp * 8.0, edge - dir2 * 4.0 - perp * 8.0
			]), col2)
			_dist_label.visible = false

	# Player bars: hull + boost
	var bx := 36.0
	var by := vp.y - 100.0
	_draw_bar(Vector2(bx, by), Vector2(280, 14), player.hp / player.cfg["hp"], Color(0.3, 0.9, 0.45))
	_canvas.draw_string(font, Vector2(bx + 288, by + 12), "COQUE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.75, 0.85))
	_draw_bar(Vector2(bx, by + 24), Vector2(280, 8), player.boost_energy, Color(0.4, 0.7, 1.0))
	_canvas.draw_string(font, Vector2(bx + 288, by + 32), "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.75, 0.85))

	# Enemy bar (top right)
	var ex := vp.x - 36.0 - 280.0
	_draw_bar(Vector2(ex, 62.0), Vector2(280, 14), enemy.hp / enemy.cfg["hp"], Color(1.0, 0.32, 0.27))

func _draw_corner_box(p: Vector2, r: float, col: Color) -> void:
	var l := r * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := p + Vector2(sx * r, sy * r)
			_canvas.draw_line(corner, corner + Vector2(-sx * l, 0), col, 1.6, true)
			_canvas.draw_line(corner, corner + Vector2(0, -sy * l), col, 1.6, true)

func _draw_bar(pos: Vector2, size: Vector2, ratio: float, color: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_canvas.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.5), true)
	if ratio > 0.0:
		_canvas.draw_rect(Rect2(pos + Vector2(1.5, 1.5), Vector2((size.x - 3.0) * ratio, size.y - 3.0)), color, true)
	_canvas.draw_rect(Rect2(pos, size), Color(1, 1, 1, 0.28), false, 1.0)
