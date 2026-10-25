extends Node
## Application root: splash -> main menu (live 3D backdrop) -> match.
## Yukkuri Strike - created by ゆっくりP

const World := preload("res://scripts/game/world.gd")
const Match := preload("res://scripts/game/match.gd")
const MainMenu := preload("res://scripts/ui/main_menu.gd")

var world: Node3D
var menu: Control
var match_node: Node
var menu_cam: Camera3D
var _cam_t := 0.0
var _ui: CanvasLayer

func _ready() -> void:
	get_window().title = "%s - by %s" % [Settings.GAME_TITLE, Settings.CREATOR]
	get_tree().root.theme = UITheme.get_theme()
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	_build_world()
	if "--screenshot" in OS.get_cmdline_user_args():
		var shot := preload("res://scripts/game/screenshot_tour.gd").new()
		add_child(shot)
		shot.start(self)
		return
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_test()
		return
	_show_splash()

func _build_world() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(20260125)
	menu_cam = Camera3D.new()
	menu_cam.fov = 60.0
	menu_cam.far = 3000.0
	add_child(menu_cam)
	menu_cam.current = true

func _process(delta: float) -> void:
	if menu_cam and menu_cam.current:
		_cam_t += delta * 0.025
		var c: Vector3 = world.town_centers[0] if world.town_centers.size() > 0 else Vector3.ZERO
		var p := c + Vector3(cos(_cam_t) * 95.0, 0.0, sin(_cam_t) * 95.0)
		p.y = world.height_at(p.x, p.z) + 24.0
		menu_cam.global_position = p
		menu_cam.look_at(c + Vector3(0, 6, 0))

func _show_splash() -> void:
	var splash := Control.new()
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(splash)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	splash.add_child(box)
	var by := UITheme.label(tr("PRESENTS"), 40, UITheme.TEXT)
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(by)
	var title := UITheme.label(Settings.GAME_TITLE, 120, UITheme.ACCENT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var creator := UITheme.label("%s: %s" % [tr("CREDITS_CREATOR"), Settings.CREATOR], 26, UITheme.TEXT_DIM)
	creator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(creator)
	splash.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(splash, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.6)
	tw.tween_property(bg, "color:a", 0.0, 0.9)
	tw.parallel().tween_property(box, "modulate:a", 0.0, 0.9)
	tw.tween_callback(func(): splash.queue_free(); show_menu())

func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu:
		menu.queue_free()
	menu = MainMenu.new()
	menu.main = self
	_ui.add_child(menu)
	menu_cam.current = true

func start_offline() -> void:
	_start_match(false, {})

func start_online(welcome: Dictionary) -> void:
	_start_match(true, welcome)

func _start_match(online: bool, welcome: Dictionary) -> void:
	if menu:
		menu.queue_free()
		menu = null
	var seed_val := int(welcome.get("seed", 20260125))
	if world.seed_value != seed_val or world.dirty:
		world.queue_free()
		world = World.new()
		world.name = "World"
		add_child(world)
		world.build(seed_val)
	match_node = Match.new()
	match_node.name = "Match"
	add_child(match_node)
	match_node.setup(self, world, online, welcome)

func end_match() -> void:
	if match_node:
		match_node.queue_free()
		match_node = null
	Net.close()
	get_tree().paused = false
	show_menu()

func _smoke_test() -> void:
	print("[smoke] world built: towns=%d blocks=%d" % [world.town_centers.size(), world.block_count()])
	start_offline()
	await get_tree().create_timer(3.0).timeout
	match_node.debug_explode_near_player()
	await get_tree().create_timer(2.0).timeout
	print("[smoke] players=%d vehicles=%d" % [match_node.soldiers.size(), match_node.vehicles.size()])
	print("[smoke] OK")
	get_tree().quit(0)
