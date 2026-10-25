extends Control
## Main menu with Play / Multiplayer / Settings / Controls / Credits.
## Yukkuri Strike - created by ゆっくりP

const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")

var main: Node
var _content: Control
var _left: VBoxContainer
var _status: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	I18n.language_changed.connect(_rebuild)
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.03, 0.92))
	g.set_color(1, Color(0.02, 0.025, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 512
	gt.height = 8
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.custom_minimum_size.x = 900
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64 if side != "left" else 90)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	margin.add_child(row)

	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	_left.custom_minimum_size.x = 440
	row.add_child(_left)
	var title := UITheme.label(Settings.GAME_TITLE, 104, UITheme.ACCENT, true)
	_left.add_child(title)
	var sub := UITheme.label(tr("TITLE_SUB"), 22, UITheme.TEXT_DIM)
	_left.add_child(sub)
	var by := UITheme.label("by %s" % Settings.CREATOR, 22, UITheme.TEXT)
	_left.add_child(by)
	var sp := Control.new()
	sp.custom_minimum_size.y = 36
	_left.add_child(sp)
	var first := UITheme.button(tr("MENU_PLAY_OFFLINE"), func(): main.start_offline())
	_left.add_child(first)
	_left.add_child(UITheme.button(tr("MENU_MULTIPLAYER"), _show_mp))
	_left.add_child(UITheme.button(tr("MENU_SETTINGS"), _show_settings))
	_left.add_child(UITheme.button(tr("MENU_CONTROLS"), _show_controls))
	_left.add_child(UITheme.button(tr("MENU_CREDITS"), _show_credits))
	if not OS.has_feature("ios") and not OS.has_feature("web"):
		_left.add_child(UITheme.button(tr("MENU_QUIT"), func(): get_tree().quit()))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(fill)
	var ver := UITheme.label("v%s  ·  © %s  ·  %s" % [ProjectSettings.get_setting("application/config/version"), Settings.CREATOR, tr("CREDITS_FREE")], 16, UITheme.TEXT_DIM)
	_left.add_child(ver)

	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_content)
	first.call_deferred("grab_focus")

func _panel(title: String) -> VBoxContainer:
	for c in _content.get_children():
		c.queue_free()
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(640, 0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	_content.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(UITheme.label(title, 54, UITheme.ACCENT, true))
	p.modulate.a = 0.0
	p.position.x += 30
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	return v

func _show_mp() -> void:
	var v := _panel(tr("MENU_MULTIPLAYER"))
	v.add_child(UITheme.label(tr("MP_NAME"), 18, UITheme.TEXT_DIM))
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 16
	v.add_child(name_edit)
	v.add_child(UITheme.label(tr("MP_SERVER_URL"), 18, UITheme.TEXT_DIM))
	var url := LineEdit.new()
	url.text = Settings.server_url
	v.add_child(url)
	var hint := UITheme.label(tr("MP_HINT"), 16, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	_status = UITheme.label("", 18, UITheme.ACCENT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.add_child(UITheme.button(tr("MP_CONNECT"), func():
		Settings.player_name = name_edit.text.strip_edges().left(16)
		Settings.server_url = url.text.strip_edges()
		Settings.save_settings()
		_status.text = tr("MP_CONNECTING")
		Net.connect_to(Settings.server_url, Settings.player_name)))

func _on_connected(welcome: Dictionary) -> void:
	if is_inside_tree():
		main.start_online(welcome)

func _on_failed() -> void:
	if _status and is_instance_valid(_status):
		_status.text = tr("MP_FAILED")

func _show_settings() -> void:
	var v := _panel(tr("MENU_SETTINGS"))
	var sp := SettingsPanel.new()
	v.add_child(sp)

func _show_controls() -> void:
	var v := _panel(tr("MENU_CONTROLS"))
	var pc := UITheme.label(tr("CONTROLS_PC"), 19)
	pc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(pc)
	v.add_child(HSeparator.new())
	var tc := UITheme.label(tr("CONTROLS_TOUCH"), 19)
	tc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tc)

func _show_credits() -> void:
	var v := _panel(tr("MENU_CREDITS"))
	v.add_child(UITheme.label(tr("CREDITS_CREATOR"), 20, UITheme.TEXT_DIM))
	v.add_child(UITheme.label(Settings.CREATOR, 64, UITheme.TEXT, true))
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label(Settings.GAME_TITLE + "  v" + str(ProjectSettings.get_setting("application/config/version")), 20))
	v.add_child(UITheme.label(tr("CREDITS_ENGINE"), 18, UITheme.TEXT_DIM))
	v.add_child(UITheme.label(tr("CREDITS_FONTS"), 18, UITheme.TEXT_DIM))
	v.add_child(UITheme.label(tr("CREDITS_FREE"), 18, UITheme.ACCENT))
