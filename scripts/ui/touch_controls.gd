extends Control
## Mobile virtual pad: floating move stick (left), drag-to-look (right half),
## fire button that also steers aim while held, and action buttons.
## Yukkuri Strike - created by ゆっくりP

var hud: Node
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_ids := {}
var _btn_ids := {}
var _buttons := []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func _u() -> float:
	return clampf(size.y * 0.085, 44.0, 120.0)

func _layout() -> void:
	var u := _u()
	var w := size.x
	var h := size.y
	_buttons = [
		{"id": "fire", "label": "T_FIRE", "pos": Vector2(w - u * 2.3, h - u * 2.6), "r": u * 1.05, "hold": true},
		{"id": "fire", "label": "T_FIRE", "pos": Vector2(u * 1.1, h * 0.42), "r": u * 0.6, "hold": true},
		{"id": "ads", "label": "T_ADS", "pos": Vector2(w - u * 4.3, h - u * 1.4), "r": u * 0.65, "hold": false},
		{"id": "jump", "label": "T_JUMP", "pos": Vector2(w - u * 0.95, h - u * 3.4), "r": u * 0.55, "hold": false},
		{"id": "crouch", "label": "T_CROUCH", "pos": Vector2(w - u * 0.95, h - u * 1.15), "r": u * 0.55, "hold": false},
		{"id": "reload", "label": "T_RELOAD", "pos": Vector2(w - u * 3.7, h - u * 3.5), "r": u * 0.5, "hold": false},
		{"id": "swap", "label": "T_SWAP", "pos": Vector2(w - u * 2.3, h - u * 0.75), "r": u * 0.5, "hold": false},
		{"id": "grenade", "label": "T_NADE", "pos": Vector2(w - u * 2.4, h - u * 4.4), "r": u * 0.5, "hold": false},
		{"id": "use", "label": "T_USE", "pos": Vector2(w * 0.5 + u * 2.2, h - u * 1.0), "r": u * 0.5, "hold": false},
		{"id": "menu", "label": "T_MENU", "pos": Vector2(w - u * 0.7, u * 2.3), "r": u * 0.4, "hold": false},
	]

func _player() -> Node:
	return hud.match_node.local_player if hud and hud.match_node else null

func _input(event: InputEvent) -> void:
	var p := _player()
	if p == null or not is_visible_in_tree():
		return
	if hud.pause_panel or hud.match_node.ended:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			for b in _buttons:
				if e.position.distance_to(b.pos) <= b.r * 1.15:
					_btn_ids[e.index] = b.id
					_press(p, b.id, true)
					queue_redraw()
					get_viewport().set_input_as_handled()
					return
			if e.position.x < size.x * 0.45:
				_stick_id = e.index
				_stick_origin = e.position
				_stick_pos = e.position
			else:
				_look_ids[e.index] = true
		else:
			if _btn_ids.has(e.index):
				_press(p, _btn_ids[e.index], false)
				_btn_ids.erase(e.index)
			if e.index == _stick_id:
				_stick_id = -1
				p.touch_move = Vector2.ZERO
			_look_ids.erase(e.index)
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_pos = d.position
			var off := (_stick_pos - _stick_origin) / (_u() * 1.2)
			p.touch_move = off.limit_length(1.0) if off.length() > 0.08 else Vector2.ZERO
			queue_redraw()
		elif _look_ids.has(d.index) or _btn_ids.get(d.index, "") == "fire":
			p.touch_look += d.relative

func _press(p: Node, id: String, down: bool) -> void:
	if id == "fire":
		p.touch_hold.fire = down
	elif id == "menu":
		if down:
			hud.toggle_pause()
	elif down:
		p.touch_action(id)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var p := _player()
	if p == null or not p.alive:
		return
	var font: Font = UITheme.head_font
	var u := _u()
	if _stick_id >= 0:
		draw_circle(_stick_origin, u * 1.2, Color(1, 1, 1, 0.08))
		draw_arc(_stick_origin, u * 1.2, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(u * 1.2)
		draw_circle(knob, u * 0.45, Color(1, 1, 1, 0.35))
	else:
		var hint := Vector2(u * 2.4, size.y - u * 2.2)
		draw_arc(hint, u * 1.2, 0, TAU, 48, Color(1, 1, 1, 0.15), 2.0)
		draw_circle(hint, u * 0.45, Color(1, 1, 1, 0.12))
	var held := _btn_ids.values()
	for b in _buttons:
		var active: bool = b.id in held or (b.id == "ads" and p._ads_toggle) or (b.id == "crouch" and p.crouching)
		var col := Color(1.0, 0.69, 0.13, 0.55) if active else Color(0, 0, 0, 0.35)
		draw_circle(b.pos, b.r, col)
		draw_arc(b.pos, b.r, 0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
		var txt := tr(b.label)
		var fs := int(b.r * 0.5)
		draw_string(font, b.pos + Vector2(-b.r, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color(1, 1, 1, 0.9))
