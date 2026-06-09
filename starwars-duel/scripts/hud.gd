class_name Hud
extends CanvasLayer

# In-game HUD: crosshair, steering cursor, enemy markers, bars, messages.

const SW_YELLOW := Color(1.0, 0.91, 0.12)

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
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)

	_player_name = _mk_label(18, SW_YELLOW)
	_player_name.position = Vector2(28, -1)
	_canvas.add_child(_player_name)

	_enemy_name = _mk_label(18, Color(1, 0.45, 0.4))
	_enemy_name.position = Vector2(-1, -1)
	_canvas.add_child(_enemy_name)

	_speed_label = _mk_label(20, Color(0.7, 0.9, 1.0))
	_canvas.add_child(_speed_label)

	_dist_label = _mk_label(15, Color(1, 0.6, 0.55))
	_canvas.add_child(_dist_label)

	_msg_label = _mk_label(72, SW_YELLOW)
	_msg_label.visible = false
	_canvas.add_child(_msg_label)

	_warn_label = _mk_label(26, Color(1, 0.3, 0.2))
	_warn_label.visible = false
	_warn_label.text = "! LIMITE DE ZONE — DEMI-TOUR !"
	_canvas.add_child(_warn_label)

func _mk_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l

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
	_player_name.position = Vector2(28, vp.y - 120)

	_enemy_name.text = "%s — %s" % [enemy.cfg["pilot"], enemy.cfg["ship"]]
	_enemy_name.reset_size()
	_enemy_name.position = Vector2(vp.x - _enemy_name.size.x - 28, 24)

	_speed_label.text = "%d m/s" % int(player.speed)
	_speed_label.position = Vector2(vp.x - 150, vp.y - 60)

	var dist := player.global_position.distance_to(enemy.global_position)
	_dist_label.text = "%d m" % int(dist)

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

	# Crosshair
	var ch_col := Color(0.6, 1.0, 0.7, 0.9)
	_canvas.draw_arc(center, 14.0, 0, TAU, 32, ch_col, 1.5)
	for ang in [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]:
		var v := Vector2(cos(ang), sin(ang))
		_canvas.draw_line(center + v * 18.0, center + v * 26.0, ch_col, 1.5)

	# Steering cursor
	var cur := center + mouse_offset * (minf(vp.x, vp.y) * 0.32)
	_canvas.draw_arc(cur, 5.0, 0, TAU, 16, Color(1, 1, 1, 0.85), 1.5)

	# Enemy marker + lead reticle
	if enemy.alive:
		var epos := enemy.global_position
		if not camera.is_position_behind(epos):
			var p := camera.unproject_position(epos)
			var col := Color(1, 0.35, 0.3, 0.95)
			var r := 22.0
			_canvas.draw_rect(Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), col, false, 1.8)
			_dist_label.position = p + Vector2(r + 6, -8)
			_dist_label.visible = true
			# Lead reticle: where to shoot so the bolt meets the target
			var tof := player.global_position.distance_to(epos) / Ship.LASER_SPEED
			var lead := epos + enemy.linear_velocity() * tof
			if not camera.is_position_behind(lead):
				var lp := camera.unproject_position(lead)
				var lc := Color(1, 0.8, 0.2, 0.95)
				_canvas.draw_line(lp + Vector2(0, -10), lp + Vector2(10, 0), lc, 1.6)
				_canvas.draw_line(lp + Vector2(10, 0), lp + Vector2(0, 10), lc, 1.6)
				_canvas.draw_line(lp + Vector2(0, 10), lp + Vector2(-10, 0), lc, 1.6)
				_canvas.draw_line(lp + Vector2(-10, 0), lp + Vector2(0, -10), lc, 1.6)
		else:
			# Off-screen arrow toward the enemy
			var dir3 := (enemy.global_position - player.global_position).normalized()
			var local := camera.global_transform.basis.inverse() * dir3
			var dir2 := Vector2(local.x, -local.y).normalized()
			var edge := center + dir2 * (minf(vp.x, vp.y) * 0.42)
			var col2 := Color(1, 0.35, 0.3, 0.9)
			var perp := Vector2(-dir2.y, dir2.x)
			_canvas.draw_colored_polygon(PackedVector2Array([
				edge + dir2 * 14.0, edge - dir2 * 4.0 + perp * 9.0, edge - dir2 * 4.0 - perp * 9.0
			]), col2)
			_dist_label.visible = false

	# Player bars: hull + boost
	var bx := 28.0
	var by := vp.y - 92.0
	_draw_bar(Vector2(bx, by), Vector2(280, 16), player.hp / player.cfg["hp"], Color(0.25, 0.9, 0.4), "COQUE")
	_draw_bar(Vector2(bx, by + 28), Vector2(280, 10), player.boost_energy, Color(0.35, 0.7, 1.0), "BOOST")

	# Enemy bar (top right)
	var ex := vp.x - 28.0 - 280.0
	_draw_bar(Vector2(ex, 56.0), Vector2(280, 16), enemy.hp / enemy.cfg["hp"], Color(1.0, 0.3, 0.25), "")

func _draw_bar(pos: Vector2, size: Vector2, ratio: float, color: Color, _label: String) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_canvas.draw_rect(Rect2(pos, size), Color(0, 0, 0, 0.55), true)
	_canvas.draw_rect(Rect2(pos + Vector2(2, 2), Vector2((size.x - 4) * ratio, size.y - 4)), color, true)
	_canvas.draw_rect(Rect2(pos, size), Color(1, 1, 1, 0.35), false, 1.0)
