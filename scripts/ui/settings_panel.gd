extends VBoxContainer
## Settings form shared by the main menu and the in-game pause menu.
## Yukkuri Strike - created by ゆっくりP

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size.x = 560
	_build()

func _row(text: String, ctl: Control) -> void:
	var h := HBoxContainer.new()
	var l := UITheme.label(text, 19)
	l.custom_minimum_size.x = 260
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	add_child(h)

func _slider(minv: float, maxv: float, step: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.custom_minimum_size.y = 32
	s.value_changed.connect(func(x): cb.call(x); Settings.save_settings())
	return s

func _option(items: Array, selected: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(selected)
	o.item_selected.connect(func(i): cb.call(i); Settings.save_settings())
	return o

func _build() -> void:
	var langs: Dictionary = I18n.languages()
	var codes := langs.keys()
	var names := []
	for c in codes:
		names.append(langs[c])
	_row(tr("SET_LANGUAGE"), _option(names, maxi(codes.find(Settings.language), 0), func(i):
		I18n.set_language(codes[i])
		Settings.save_settings()
		for c in get_children():
			c.queue_free()
		_build.call_deferred()))
	_row(tr("SET_QUALITY"), _option([tr("Q_LOW"), tr("Q_MEDIUM"), tr("Q_HIGH"), tr("Q_ULTRA")], Settings.quality, func(i): Settings.quality = i))
	_row(tr("SET_MOUSE_SENS"), _slider(0.02, 0.5, 0.01, Settings.mouse_sens, func(x): Settings.mouse_sens = x))
	_row(tr("SET_TOUCH_SENS"), _slider(0.05, 1.0, 0.01, Settings.touch_sens, func(x): Settings.touch_sens = x))
	_row(tr("SET_FOV"), _slider(60, 110, 1, Settings.fov, func(x): Settings.fov = x))
	_row(tr("SET_VOLUME"), _slider(0, 1, 0.05, Settings.volume, func(x): Settings.volume = x))
	_row(tr("SET_INVERT_Y"), _option([tr("OPT_OFF"), tr("OPT_ON")], int(Settings.invert_y), func(i): Settings.invert_y = i == 1))
	_row(tr("SET_TOUCH_CONTROLS"), _option([tr("OPT_AUTO"), tr("OPT_OFF"), tr("OPT_ON")], Settings.touch_controls + 1, func(i): Settings.touch_controls = i - 1))
	_row(tr("SET_SHOW_FPS"), _option([tr("OPT_OFF"), tr("OPT_ON")], int(Settings.show_fps), func(i): Settings.show_fps = i == 1))
