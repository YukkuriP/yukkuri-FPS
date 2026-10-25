extends Node
## Automated screenshot capture used by the critic loop / store images:
##   godot -- --screenshot --out=/path/to/dir
## Yukkuri Strike - created by ゆっくりP

var main: Node
var out := "user://shots"

func start(main_: Node) -> void:
	main = main_
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("[shot] ", name)

func _run() -> void:
	await _wait(30)
	main.show_menu()
	await _wait(40)
	await _shot("01_menu")
	main.start_offline()
	var m: Node = main.match_node
	var p: Node3D = m.local_player
	await _wait(60)
	await _shot("02_spawn")
	var t: Vector3 = m.flags[0].pos
	p.global_position = Vector3(t.x + 30, main.world.height_at(t.x + 30, t.z + 30) + 1.0, t.z + 30)
	p.yaw = atan2(-(t.x - p.global_position.x), -(t.z - p.global_position.z))
	p.pitch = -0.05
	await _wait(60)
	await _shot("03_town")
	Input.action_press("ads")
	await _wait(40)
	await _shot("04_ads")
	Input.action_release("ads")
	m.debug_explode_near_player()
	await _wait(10)
	await _shot("05_explosion")
	await _wait(90)
	await _shot("06_destruction")
	var v: Node3D = m.vehicles[2]
	p.global_position = v.global_position + Vector3(3, 0.5, 0)
	await _wait(5)
	m.toggle_vehicle(p)
	await _wait(60)
	await _shot("07_tank")
	m.toggle_vehicle(p)
	p.switch_weapon("dmr")
	Input.action_press("ads")
	await _wait(50)
	await _shot("08_scope")
	Input.action_release("ads")
	Settings.touch_controls = 1
	m.hud.touch = preload("res://scripts/ui/touch_controls.gd").new()
	m.hud.touch.hud = m.hud
	m.hud.add_child(m.hud.touch)
	await _wait(20)
	await _shot("09_touch")
	get_tree().quit(0)
