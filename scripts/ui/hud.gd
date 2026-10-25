extends CanvasLayer
## In-game HUD: tickets/objectives, compass, radar, ammo, health, hit
## markers, damage direction, killfeed, scoreboard, scope, death/end screens
## and the pause menu (with live language switching).
## Yukkuri Strike - created by ゆっくりP

const Weapons := preload("res://scripts/game/weapons.gd")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const TouchControls := preload("res://scripts/ui/touch_controls.gd")

const VIGNETTE := """
shader_type canvas_item;
uniform float hurt = 0.0;
uniform float dark = 0.0;
void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d * vec2(1.6, 1.0));
	float v = smoothstep(0.35, 0.95, r);
	COLOR = vec4(mix(vec3(0.0), vec3(0.55, 0.0, 0.0), clamp(hurt * 1.4, 0.0, 1.0)), v * clamp(hurt + dark * 0.7, 0.0, 0.95));
}
"""

var match_node: Node
var canvas: Control
var vignette: ColorRect
var ammo_lbl: Label
var reserve_lbl: Label
var weapon_lbl: Label
var mode_lbl: Label
var hp_lbl: Label
var prompt_lbl: Label
var notify_box: VBoxContainer
var feed_box: VBoxContainer
var info_lbl: Label
var death_panel: Control
var death_lbl: Label
var respawn_lbl: Label
var score_panel: PanelContainer
var score_grid: GridContainer
var pause_panel: Control
var end_panel: Control
var touch: Control
var _root: Control
var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _dmg_marks: Array = []
var _hurt := 0.0
var _fps_t := 0.0

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE
	sm.shader = sh
	vignette.material = sm
	root.add_child(vignette)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_hud)
	root.add_child(canvas)
	# bottom-right weapon block
	var wb := VBoxContainer.new()
	wb.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wb.position = Vector2(-380, -190)
	wb.size = Vector2(340, 160)
	wb.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wb.alignment = BoxContainer.ALIGNMENT_END
	wb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wb)
	weapon_lbl = _lbl(wb, 22, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	var ah := HBoxContainer.new()
	ah.alignment = BoxContainer.ALIGNMENT_END
	wb.add_child(ah)
	ammo_lbl = _lbl(ah, 64, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, true)
	reserve_lbl = _lbl(ah, 30, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	mode_lbl = _lbl(wb, 18, UITheme.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	hp_lbl = Label.new()
	hp_lbl.add_theme_font_size_override("font_size", 34)
	hp_lbl.add_theme_font_override("font", UITheme.head_font)
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp_lbl)
	prompt_lbl = Label.new()
	prompt_lbl.add_theme_font_size_override("font_size", 24)
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.set_anchors_preset(Control.PRESET_CENTER)
	prompt_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_lbl.position.y = 120
	prompt_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_lbl.add_theme_constant_override("outline_size", 6)
	root.add_child(prompt_lbl)
	notify_box = VBoxContainer.new()
	notify_box.set_anchors_preset(Control.PRESET_CENTER)
	notify_box.position = Vector2(-300, 40)
	notify_box.size = Vector2(600, 100)
	notify_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notify_box)
	feed_box = VBoxContainer.new()
	feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed_box.position = Vector2(-560, 110)
	feed_box.size = Vector2(540, 200)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)
	info_lbl = Label.new()
	info_lbl.position = Vector2(16, 10)
	info_lbl.add_theme_font_size_override("font_size", 16)
	info_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	root.add_child(info_lbl)
	_build_death(root)
	_build_score(root)
	_root = root
	if Settings.use_touch():
		enable_touch()

func enable_touch() -> void:
	if touch:
		return
	touch = TouchControls.new()
	touch.hud = self
	_root.add_child(touch)

func _lbl(parent: Node, size: int, col: Color, align: int, heading := false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	if heading:
		l.add_theme_font_override("font", UITheme.head_font)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_death(root: Control) -> void:
	death_panel = ColorRect.new()
	(death_panel as ColorRect).color = Color(0.05, 0.0, 0.0, 0.45)
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_panel.visible = false
	root.add_child(death_panel)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_panel.add_child(v)
	death_lbl = _lbl(v, 54, UITheme.RED, HORIZONTAL_ALIGNMENT_CENTER, true)
	respawn_lbl = _lbl(v, 26, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)

func _build_score(root: Control) -> void:
	score_panel = PanelContainer.new()
	score_panel.set_anchors_preset(Control.PRESET_CENTER)
	score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	score_panel.custom_minimum_size = Vector2(760, 0)
	score_panel.visible = false
	root.add_child(score_panel)
	score_grid = GridContainer.new()
	score_grid.columns = 4
	score_grid.add_theme_constant_override("h_separation", 40)
	score_panel.add_child(score_grid)

func _refresh_score() -> void:
	for c in score_grid.get_children():
		c.queue_free()
	for h in [tr("HUD_PLAYER"), tr("HUD_KILLS"), tr("HUD_DEATHS"), ""]:
		_lbl(score_grid, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		score_grid.get_child(score_grid.get_child_count() - 1).text = h
	var all: Array = match_node.soldiers + match_node.remotes.values()
	all.sort_custom(func(a, b): return a.team < b.team or (a.team == b.team and a.kills > b.kills))
	for s in all:
		var col: Color = match_node.team_color(s.team)
		if s == match_node.local_player:
			col = UITheme.ACCENT
		for t in [s.display_name, str(s.kills), str(s.deaths), tr("HUD_TEAM_BLUE") if s.team == 0 else tr("HUD_TEAM_RED")]:
			var l := _lbl(score_grid, 20, col, HORIZONTAL_ALIGNMENT_LEFT)
			l.text = t

# ---------------------------------------------------------------- events
func hitmarker(head: bool, kill: bool) -> void:
	_hit_t = 0.28
	_hit_kill = kill
	_hit_head = head
	Sfx.play("hit", -4.0 if not kill else 0.0, 1.4 if head else 1.0)

func damage(from: Vector3, amount: float) -> void:
	_hurt = minf(1.0, _hurt + amount / 60.0)
	if from != Vector3.INF:
		_dmg_marks.append({"pos": from, "t": 1.6})

func notify(text: String, points: int) -> void:
	var l := _lbl(notify_box, 30, UITheme.ACCENT if points > 0 else UITheme.RED, HORIZONTAL_ALIGNMENT_CENTER, true)
	l.text = ("+%d  %s" % [points, text]) if points > 0 else text
	l.pivot_offset = Vector2(300, 20)
	l.scale = Vector2(1.4, 1.4)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	while notify_box.get_child_count() > 3:
		notify_box.get_child(0).free()

func killfeed(killer: String, kteam: int, victim: String, vteam: int, wid: String, head: bool) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.custom_minimum_size = Vector2(540, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", 18)
	var wname := tr(Weapons.get_w(wid).name) if Weapons.DATA.has(wid) or Weapons.VEHICLE_WEAPONS.has(wid) else (tr("W_GRENADE") if wid == "grenade" else tr("W_FALL"))
	if wid == "vehicle":
		wname = tr("W_VEHICLE")
	var kc: Color = match_node.team_color(kteam)
	var vc: Color = match_node.team_color(vteam)
	var txt := "[right]"
	if killer != "":
		txt += "[color=#%s]%s[/color]  " % [kc.to_html(false), killer]
	txt += "[color=#bbbbbb][%s%s][/color]  [color=#%s]%s[/color][/right]" % [wname, " ✛" if head else "", vc.to_html(false), victim]
	r.text = txt
	feed_box.add_child(r)
	var tw := r.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(r, "modulate:a", 0.0, 0.6)
	tw.tween_callback(r.queue_free)
	while feed_box.get_child_count() > 5:
		feed_box.get_child(0).free()

func show_death(killer: String) -> void:
	death_panel.visible = true
	death_lbl.text = tr("HUD_KILLED_BY") % killer if killer != "" else tr("HUD_ELIMINATED")

func hide_death() -> void:
	death_panel.visible = false
	_hurt = 0.0

func show_end(victory: bool) -> void:
	death_panel.visible = false
	end_panel = ColorRect.new()
	(end_panel as ColorRect).color = Color(0, 0, 0, 0.6)
	end_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(end_panel)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_panel.add_child(v)
	var t := _lbl(v, 140, UITheme.ACCENT if victory else UITheme.RED, HORIZONTAL_ALIGNMENT_CENTER, true)
	t.text = tr("HUD_VICTORY") if victory else tr("HUD_DEFEAT")
	var c := _lbl(v, 22, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	c.text = "%s  •  by %s" % [Settings.GAME_TITLE, Settings.CREATOR]
	score_panel.visible = true
	_refresh_score()

func toggle_pause() -> void:
	if pause_panel:
		pause_panel.queue_free()
		pause_panel = null
		match_node.local_player.input_enabled = true
		if not match_node.online:
			get_tree().paused = false
		if not Settings.use_touch():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	match_node.local_player.input_enabled = false
	if not match_node.online:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_panel = ColorRect.new()
	(pause_panel as ColorRect).color = Color(0, 0, 0, 0.55)
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(pause_panel)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_panel.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	var title := UITheme.label(tr("MENU_PAUSED"), 54, UITheme.ACCENT, true)
	v.add_child(title)
	var sp := SettingsPanel.new()
	v.add_child(sp)
	Settings.changed.connect(func():
		if is_instance_valid(title):
			title.text = tr("MENU_PAUSED")
		match_node.local_player.base_fov = Settings.fov, CONNECT_ONE_SHOT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	h.add_child(UITheme.button(tr("MENU_RESUME"), toggle_pause))
	h.add_child(UITheme.button(tr("MENU_LEAVE"), func(): get_tree().paused = false; match_node.leave()))
	var credit := UITheme.label("%s  -  by %s" % [Settings.GAME_TITLE, Settings.CREATOR], 16, UITheme.TEXT_DIM)
	v.add_child(credit)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if match_node == null or match_node.local_player == null:
		return
	var p: Node = match_node.local_player
	if Input.is_action_just_pressed("pause") and not match_node.ended:
		toggle_pause()
	score_panel.visible = match_node.ended or (Input.is_action_pressed("scoreboard") and pause_panel == null)
	if score_panel.visible and Engine.get_process_frames() % 15 == 0:
		_refresh_score()
	_hit_t -= delta
	_hurt = move_toward(_hurt, 0.0 if p.hp > 35 else 0.35, delta * 0.5)
	for m in _dmg_marks:
		m.t -= delta
	_dmg_marks = _dmg_marks.filter(func(m): return m.t > 0.0)
	var sm := vignette.material as ShaderMaterial
	sm.set_shader_parameter("hurt", _hurt)
	sm.set_shader_parameter("dark", p.suppression)
	var w := Weapons.get_w(p.weapon_id)
	var a: Array = p.ammo.get(p.weapon_id, [0, 0])
	if p.in_vehicle:
		var v: Node = p.in_vehicle
		weapon_lbl.text = tr("W_VEHICLE") + "  " + ("MBT" if v.kind == "tank" else "LSV")
		ammo_lbl.text = str(int(maxf(v.hp, 0.0)))
		reserve_lbl.text = " / %d" % int(v.max_hp)
		mode_lbl.text = ""
		prompt_lbl.text = tr("HUD_EXIT_VEHICLE")
	else:
		weapon_lbl.text = tr(w.name)
		ammo_lbl.text = str(a[0])
		ammo_lbl.add_theme_color_override("font_color", UITheme.RED if a[0] <= int(w.mag * 0.25) else Color.WHITE)
		reserve_lbl.text = " / %d" % a[1]
		var parts := [tr("HUD_AUTO") if w.auto else tr("HUD_SEMI")]
		if not w.get("rocket", false):
			parts.append(tr("HUD_ZERO") % p.ZEROS[p.zero_idx])
		parts.append("%s ×%d" % [tr("W_GRENADE"), p.grenades])
		mode_lbl.text = "   ".join(parts)
		var prompt := ""
		if p.reload_t > 0.0:
			prompt = tr("HUD_RELOADING")
		elif a[0] <= int(w.mag * 0.25) and a[1] > 0:
			prompt = tr("HUD_RELOAD")
		elif p.alive and match_node.nearest_vehicle(p):
			prompt = tr("HUD_ENTER_VEHICLE")
		else:
			for f in match_node.flags:
				if Vector2(p.global_position.x - f.pos.x, p.global_position.z - f.pos.z).length() < f.radius and f.owner != p.team:
					prompt = tr("HUD_CAPTURING") % f.name
		prompt_lbl.text = prompt
	var vs := canvas.size
	hp_lbl.position = Vector2(40 + 200, vs.y - 64)
	hp_lbl.text = str(int(maxf(p.hp, 0.0)))
	if death_panel.visible:
		respawn_lbl.text = tr("HUD_RESPAWN_IN") % int(ceil(maxf(match_node._respawn_t, 0.0)))
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.5
		var parts2 := ["%s  by %s" % [Settings.GAME_TITLE, Settings.CREATOR]]
		parts2.append(tr("HUD_ONLINE") + "  %s %dms" % [tr("HUD_PING"), Net.ping_ms] if match_node.online else tr("HUD_OFFLINE"))
		if Settings.show_fps:
			parts2.append("%d FPS" % Engine.get_frames_per_second())
		info_lbl.text = "   |   ".join(parts2)
	canvas.queue_redraw()

func _draw_hud() -> void:
	var p: Node = match_node.local_player
	var vs := canvas.size
	var c := vs * 0.5
	var font := UITheme.head_font
	var body := UITheme.body_font
	# ----- tickets + objectives
	var tw := 150.0
	var top := 18.0
	var mine: int = p.team
	var my_t: int = match_node.tickets[mine]
	var en_t: int = match_node.tickets[1 - mine]
	canvas.draw_rect(Rect2(c.x - 300, top, 600, 52), Color(0, 0, 0, 0.45))
	canvas.draw_string(font, Vector2(c.x - 290, top + 42), str(my_t), HORIZONTAL_ALIGNMENT_LEFT, 90, 44, UITheme.BLUE)
	canvas.draw_string(font, Vector2(c.x + 200, top + 42), str(en_t), HORIZONTAL_ALIGNMENT_RIGHT, 90, 44, UITheme.RED)
	canvas.draw_rect(Rect2(c.x - 300, top + 52, 600 * 0.5 * my_t / float(match_node.START_TICKETS), 4), UITheme.BLUE)
	canvas.draw_rect(Rect2(c.x + 300 - 600 * 0.5 * en_t / float(match_node.START_TICKETS), top + 52, 600 * 0.5 * en_t / float(match_node.START_TICKETS), 4), UITheme.RED)
	var nf: int = match_node.flags.size()
	for i in nf:
		var f: Dictionary = match_node.flags[i]
		var fx := c.x + (i - (nf - 1) * 0.5) * 70.0
		var owner_col: Color = UITheme.TEXT_DIM
		if f.owner == mine:
			owner_col = UITheme.BLUE
		elif f.owner == 1 - mine:
			owner_col = UITheme.RED
		canvas.draw_circle(Vector2(fx, top + 26), 21, Color(0, 0, 0, 0.6))
		var prog: float = f.progress if mine == 0 else -f.progress
		if absf(prog) > 0.01:
			canvas.draw_arc(Vector2(fx, top + 26), 21, -PI * 0.5, -PI * 0.5 + TAU * absf(prog), 32, UITheme.BLUE if prog > 0 else UITheme.RED, 4.0)
		canvas.draw_string(font, Vector2(fx - 20, top + 39), f.name, HORIZONTAL_ALIGNMENT_CENTER, 40, 34, owner_col)
	# ----- compass
	var yaw: float = p.yaw if not p.in_vehicle else p.yaw
	var cw := 520.0
	var cy := top + 78
	canvas.draw_rect(Rect2(c.x - cw * 0.5, cy, cw, 26), Color(0, 0, 0, 0.3))
	var heading_deg := fposmod(-rad_to_deg(yaw), 360.0)
	for d in range(0, 360, 15):
		var off := angle_difference(deg_to_rad(heading_deg), deg_to_rad(d))
		var x := c.x + rad_to_deg(off) * 3.2
		if absf(x - c.x) > cw * 0.5 - 8:
			continue
		var lab: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(d, "")
		if lab != "":
			canvas.draw_string(font, Vector2(x - 15, cy + 23), lab, HORIZONTAL_ALIGNMENT_CENTER, 30, 26, UITheme.ACCENT)
		elif d % 45 == 0:
			canvas.draw_string(body, Vector2(x - 20, cy + 19), str(d), HORIZONTAL_ALIGNMENT_CENTER, 40, 13, UITheme.TEXT)
		else:
			canvas.draw_line(Vector2(x, cy + 6), Vector2(x, cy + 14), UITheme.TEXT_DIM, 2.0)
	for f in match_node.flags:
		var to: Vector3 = f.pos - p.global_position
		var ang := atan2(to.x, -to.z)
		var off2 := angle_difference(deg_to_rad(heading_deg), ang)
		var x2 := c.x + rad_to_deg(off2) * 3.2
		if absf(x2 - c.x) < cw * 0.5:
			canvas.draw_string(font, Vector2(x2 - 10, cy + 46), f.name, HORIZONTAL_ALIGNMENT_CENTER, 20, 20, match_node.team_color(f.owner))
	canvas.draw_line(Vector2(c.x, cy - 2), Vector2(c.x, cy + 6), Color.WHITE, 2.0)
	# ----- radar
	var rc := Vector2(130, vs.y - 170)
	var rr := 100.0
	var scale := rr / 120.0
	canvas.draw_circle(rc, rr + 4, Color(0, 0, 0, 0.5))
	canvas.draw_arc(rc, rr + 4, 0, TAU, 64, Color(1, 1, 1, 0.25), 2.0)
	canvas.draw_arc(rc, rr * 0.5, 0, TAU, 48, Color(1, 1, 1, 0.08), 1.0)
	var rot := Transform2D(yaw, Vector2.ZERO)
	for f in match_node.flags:
		var rel := Vector2(f.pos.x - p.global_position.x, f.pos.z - p.global_position.z)
		var pt := rot.basis_xform(rel) * scale
		if pt.length() > rr:
			pt = pt.normalized() * rr
		canvas.draw_string(font, rc + pt + Vector2(-8, 9), f.name, HORIZONTAL_ALIGNMENT_CENTER, 16, 22, match_node.team_color(f.owner))
	var now := Time.get_ticks_msec()
	for s in match_node.soldiers + match_node.remotes.values():
		if s == p or not s.alive:
			continue
		var enemy: bool = s.team != p.team
		if enemy and now - int(s.get_meta("fired_t", -99999)) > 2500:
			continue
		var rel2 := Vector2(s.global_position.x - p.global_position.x, s.global_position.z - p.global_position.z)
		var pt2 := rot.basis_xform(rel2) * scale
		if pt2.length() <= rr:
			canvas.draw_circle(rc + pt2, 4.0, UITheme.RED if enemy else UITheme.BLUE)
	for v in match_node.vehicles:
		if not v.alive:
			continue
		var rel3 := Vector2(v.global_position.x - p.global_position.x, v.global_position.z - p.global_position.z)
		var pt3 := rot.basis_xform(rel3) * scale
		if pt3.length() <= rr:
			canvas.draw_rect(Rect2(rc + pt3 - Vector2(4, 4), Vector2(8, 8)), match_node.team_color(v.team) if v.team == p.team else Color(1, 1, 1, 0.5))
	canvas.draw_colored_polygon(PackedVector2Array([rc + Vector2(0, -9), rc + Vector2(6, 6), rc + Vector2(-6, 6)]), UITheme.ACCENT)
	# ----- health bar
	var hb := Rect2(30, vs.y - 50, 200, 10)
	canvas.draw_rect(hb, Color(0, 0, 0, 0.5))
	var hpf := clampf(p.hp / 100.0, 0.0, 1.0)
	canvas.draw_rect(Rect2(hb.position, Vector2(hb.size.x * hpf, hb.size.y)), UITheme.RED if hpf < 0.35 else Color(0.9, 0.95, 0.9))
	if not p.alive:
		return
	# ----- scope / crosshair
	var w := Weapons.get_w(p.weapon_id)
	if p.in_vehicle:
		_draw_cross(c, 10.0, Color(1, 1, 1, 0.9))
		canvas.draw_arc(c, 26, 0, TAU, 48, Color(1, 1, 1, 0.5), 1.5)
	elif w.scope and p.ads > 0.85:
		var r := vs.y * 0.46
		var black := Color(0, 0, 0, 1)
		canvas.draw_rect(Rect2(0, 0, c.x - r, vs.y), black)
		canvas.draw_rect(Rect2(c.x + r, 0, vs.x - c.x - r, vs.y), black)
		var pts := PackedVector2Array()
		for i in 65:
			var ang2 := PI + PI * i / 64.0
			pts.append(c + Vector2(cos(ang2), sin(ang2)) * r)
		pts.append(Vector2(c.x + r, 0))
		pts.append(Vector2(c.x - r, 0))
		canvas.draw_colored_polygon(pts, black)
		var pts2 := PackedVector2Array()
		for i in 65:
			var ang3 := PI * i / 64.0
			pts2.append(c + Vector2(cos(ang3), sin(ang3)) * r)
		pts2.append(Vector2(c.x - r, vs.y))
		pts2.append(Vector2(c.x + r, vs.y))
		canvas.draw_colored_polygon(pts2, black)
		canvas.draw_arc(c, r, 0, TAU, 128, Color(0.05, 0.05, 0.05), 8.0)
		canvas.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.9), 1.5)
		canvas.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.9), 1.5)
		for k in range(1, 6):
			var mil := r * 0.07 * k
			canvas.draw_line(Vector2(c.x - 5, c.y + mil), Vector2(c.x + 5, c.y + mil), Color(0, 0, 0, 0.9), 2.0)
			canvas.draw_line(Vector2(c.x + mil, c.y - 4), Vector2(c.x + mil, c.y + 4), Color(0, 0, 0, 0.9), 2.0)
			canvas.draw_line(Vector2(c.x - mil, c.y - 4), Vector2(c.x - mil, c.y + 4), Color(0, 0, 0, 0.9), 2.0)
		canvas.draw_circle(c, 1.8, Color(1, 0.15, 0.1))
		canvas.draw_string(body, Vector2(c.x + 20, c.y + r * 0.5), tr("HUD_ZERO") % p.ZEROS[p.zero_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.85, 0.85))
	elif p.ads < 0.5 and p.sprint_blend < 0.5:
		var spread_deg: float = lerpf(w.spread_hip, w.spread_ads, p.ads) + p.bloom
		var gap: float = 6.0 + spread_deg * vs.y / p.camera.fov * 0.5
		var col := Color(1, 1, 1, 0.9 * (1.0 - p.ads * 2.0))
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			canvas.draw_line(c + dir * gap + dir.orthogonal() * 0.0, c + dir * (gap + 10.0), Color(0, 0, 0, col.a * 0.6), 4.0)
			canvas.draw_line(c + dir * gap, c + dir * (gap + 10.0), col, 2.0)
		canvas.draw_circle(c, 1.5, col)
	# ----- hit marker
	if _hit_t > 0.0:
		var hc := UITheme.RED if _hit_kill else (UITheme.ACCENT if _hit_head else Color.WHITE)
		hc.a = clampf(_hit_t / 0.28, 0.0, 1.0)
		var s := 14.0 if _hit_kill else 10.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			canvas.draw_line(c + d * 6.0, c + d * (6.0 + s), hc, 3.0)
	# ----- damage direction
	for m in _dmg_marks:
		var to: Vector3 = m.pos - p.global_position
		var ang := atan2(to.x, -to.z) + yaw
		var a := clampf(m.t / 1.6, 0.0, 1.0)
		canvas.draw_arc(c, 140, ang - PI * 0.5 - 0.22, ang - PI * 0.5 + 0.22, 16, Color(1, 0.15, 0.1, 0.85 * a), 10.0)

func _draw_cross(c: Vector2, s: float, col: Color) -> void:
	canvas.draw_line(c - Vector2(s, 0), c + Vector2(s, 0), col, 2.0)
	canvas.draw_line(c - Vector2(0, s), c + Vector2(0, s), col, 2.0)
