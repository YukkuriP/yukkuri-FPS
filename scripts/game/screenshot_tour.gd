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
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("[shot] ", name)

func _run() -> void:
	print("[shot] tour start")
	await _wait(30)
	print("[shot] waited")
	main.show_menu()
	await _wait(40)
	await _shot("01_menu")
	main.start_offline()
	var m: Node = main.match_node
	var p: Node3D = m.local_player
	await _wait(60)
	await _shot("02_spawn")
	var t: Vector3 = m.flags[0].pos
	var tgt: Node3D = main.world.buildings[0]
	var bc := tgt.global_position
	var off := Vector3(42, 0, 30)
	p.global_position = Vector3(bc.x + off.x, main.world.height_at(bc.x + off.x, bc.z + off.z) + 0.5, bc.z + off.z)
	p.yaw = atan2(-(bc.x - p.global_position.x), -(bc.z - p.global_position.z))
	p.pitch = 0.02
	await _wait(60)
	await _shot("03_town")
	Input.action_press("ads")
	await _wait(40)
	await _shot("04_ads")
	Input.action_release("ads")
	var eye := p.global_position + Vector3(0, 1.6, 0)
	var qp := PhysicsRayQueryParameters3D.create(eye, bc + Vector3(0, 2.0, 0), 1)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(qp)
	var boom: Vector3 = hit.position if not hit.is_empty() else bc
	m.request_explosion(boom, 7.0, 0.0, p, "rpg")
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
	m.hud.enable_touch()
	await _wait(20)
	await _shot("09_touch")
	get_tree().quit(0)
