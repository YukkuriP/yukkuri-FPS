class_name UITheme
extends RefCounted
## Shared UI look (dark tactical panels, amber accent).
## Yukkuri Strike - created by ゆっくりP

const ACCENT := Color(1.0, 0.69, 0.13)
const ACCENT_DIM := Color(1.0, 0.69, 0.13, 0.35)
const TEXT := Color(0.93, 0.94, 0.95)
const TEXT_DIM := Color(0.62, 0.66, 0.70)
const PANEL := Color(0.04, 0.05, 0.06, 0.82)
const BLUE := Color(0.32, 0.66, 1.0)
const RED := Color(1.0, 0.33, 0.28)

static var _theme: Theme
static var body_font: Font
static var head_font: Font

static func get_theme() -> Theme:
	if _theme:
		return _theme
	body_font = load("res://assets/fonts/body_font.tres")
	var head_base: FontFile = load("res://assets/fonts/Teko.ttf")
	var hv := FontVariation.new()
	hv.base_font = head_base
	hv.variation_opentype = {"wght": 600}
	hv.fallbacks = [body_font]
	head_font = hv
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 20
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.06, 0.07, 0.08, 0.55)
	btn.content_margin_left = 22
	btn.content_margin_right = 22
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	btn.border_width_left = 3
	btn.border_color = Color(1, 1, 1, 0.08)
	var hover := btn.duplicate()
	hover.bg_color = Color(1.0, 0.69, 0.13, 0.16)
	hover.border_color = ACCENT
	hover.border_width_left = 6
	var pressed := hover.duplicate()
	pressed.bg_color = Color(1.0, 0.69, 0.13, 0.32)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, btn)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, hover)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
	t.set_font_size("font_size", "Button", 24)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_width_top = 2
	panel.border_color = ACCENT
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	t.set_stylebox("panel", "PanelContainer", panel)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0.5)
	line.border_width_bottom = 2
	line.border_color = ACCENT_DIM
	line.content_margin_left = 10
	line.content_margin_right = 10
	line.content_margin_top = 6
	line.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", line)
	t.set_color("font_color", "LineEdit", TEXT)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(1, 1, 1, 0.12)
	slider_bg.content_margin_top = 3
	slider_bg.content_margin_bottom = 3
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = ACCENT
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.06, 0.07, 0.08, 0.97)
	popup.border_width_left = 2
	popup.border_color = ACCENT
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_color("font_color", "Label", TEXT)
	_theme = t
	return t

static func label(text: String, size := 20, color := TEXT, heading := false) -> Label:
	get_theme()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if heading:
		l.add_theme_font_override("font", head_font)
	return l

static func button(text: String, cb: Callable, size := 26) -> Button:
	get_theme()
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(380, 54)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): Sfx.play("click", -8.0); cb.call())
	b.mouse_entered.connect(func(): Sfx.play("click", -22.0, 1.6))
	return b
