class_name UiKit

# Shared visual language for all UI: fonts, colors, styled controls.

const SW_YELLOW := Color(1.0, 0.91, 0.12)
const TEXT_DIM := Color(0.72, 0.75, 0.85)
const PANEL_BG := Color(0.025, 0.03, 0.06, 0.88)
const BORDER_DIM := Color(1.0, 0.91, 0.12, 0.28)

static var _display: FontFile
static var _body: FontFile

static func display_font() -> FontFile:
	if _display == null:
		_display = load("res://assets/fonts/Orbitron.ttf")
	return _display

static func body_font() -> FontFile:
	if _body == null:
		_body = load("res://assets/fonts/Exo2.ttf")
	return _body

static func label(text: String, size: int, color: Color = Color.WHITE, display := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_font() if display else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	return l

static func button(text: String, size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", display_font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.92, 0.93, 1.0))
	b.add_theme_color_override("font_hover_color", SW_YELLOW)
	b.add_theme_color_override("font_pressed_color", SW_YELLOW)
	b.add_theme_color_override("font_focus_color", Color(0.92, 0.93, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))

	var normal := StyleBoxFlat.new()
	normal.bg_color = PANEL_BG
	normal.set_border_width_all(1)
	normal.border_color = BORDER_DIM
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(14)
	b.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.border_color = SW_YELLOW
	hover.bg_color = Color(0.06, 0.065, 0.11, 0.92)
	b.add_theme_stylebox_override("hover", hover)

	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.1, 0.095, 0.05, 0.95)
	b.add_theme_stylebox_override("pressed", pressed)

	var focus := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("focus", focus)

	var disabled := normal.duplicate()
	disabled.border_color = Color(1, 1, 1, 0.08)
	disabled.bg_color = Color(0.02, 0.02, 0.04, 0.6)
	b.add_theme_stylebox_override("disabled", disabled)
	return b

static func panel_style(border: Color = BORDER_DIM, bg: Color = PANEL_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(4)
	s.set_content_margin_all(18)
	return s

# Full-screen vignette + subtle letterbox feel, drawn above the 3D view.
static func vignette() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float d = dot(uv, uv);
	float v = smoothstep(0.18, 0.62, d) * 0.55;
	COLOR = vec4(0.0, 0.0, 0.02, v);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	return r
