extends CharacterBody3D
## Drivable vehicles (jeep with mounted MG, main battle tank with turret
## cannon). Tanks crush through destructible walls. Terrain-following
## arcade physics keeps it light enough for mobile and easy to sync.
## Yukkuri Strike - created by ゆっくりP

const Mats := preload("res://scripts/game/textures.gd")
const Fx := preload("res://scripts/game/fx.gd")
const Weapons := preload("res://scripts/game/weapons.gd")

var kind := "jeep"
var team := 0
var net_id := 0
var hp := 400.0
var max_hp := 400.0
var alive := true
var driver: Node = null
var match_node: Node
var spawn_xform: Transform3D
var heading := 0.0
var speed := 0.0
var turret_yaw := 0.0
var gun_pitch := 0.0
var fire_cd := 0.0
var reload_left := 0.0
var respawn_t := 0.0
var model: Node3D
var turret: Node3D
var gun: Node3D
var wheels: Array[Node3D] = []
var engine: AudioStreamPlayer3D
var _in := {"throttle": 0.0, "steer": 0.0, "brake": false, "fire": false}
var _remote_target := {}
var _crush_cd := 0.0
var _smoke: CPUParticles3D

func setup(kind_: String, team_: int, xf: Transform3D) -> void:
	kind = kind_
	team = team_
	spawn_xform = xf
	max_hp = 1400.0 if kind == "tank" else 420.0
	hp = max_hp
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	set_meta("vehicle", self)
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 1.0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.6, 2.1, 7.2) if kind == "tank" else Vector3(2.0, 1.5, 4.2)
	cs.shape = bs
	cs.position.y = bs.size.y * 0.5 + 0.2
	add_child(cs)
	model = Node3D.new()
	add_child(model)
	if kind == "tank":
		_build_tank()
	else:
		_build_jeep()
	engine = AudioStreamPlayer3D.new()
	engine.stream = Sfx.streams.get("engine")
	engine.max_distance = 180.0
	engine.unit_size = 8.0
	engine.volume_db = -12.0
	add_child(engine)
	_smoke = CPUParticles3D.new()
	_smoke.emitting = false
	_smoke.amount = 40
	_smoke.lifetime = 3.0
	_smoke.local_coords = false
	var qm := QuadMesh.new()
	qm.material = Mats.soft_particle(Color(0.15, 0.14, 0.13, 0.8))
	_smoke.mesh = qm
	_smoke.gravity = Vector3(0, 2.0, 0)
	_smoke.scale_amount_min = 1.5
	_smoke.scale_amount_max = 3.5
	_smoke.position.y = 2.0
	add_child(_smoke)
	respawn()

func respawn() -> void:
	global_transform = Transform3D(Basis.IDENTITY, spawn_xform.origin)
	heading = spawn_xform.basis.get_euler().y
	rotation = Vector3(0, heading, 0)
	hp = max_hp
	alive = true
	speed = 0.0
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 8
	_smoke.emitting = false
	_set_wreck(false)

func _box(p: Node3D, s: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi

func _wheel(p: Node3D, r: float, w: float, pos: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = w
	c.radial_segments = 14
	mi.mesh = c
	mi.material_override = Mats.rubber()
	mi.rotation.z = PI * 0.5
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.add_child(mi)
	p.add_child(pivot)
	wheels.append(pivot)
	return pivot

func _paint() -> StandardMaterial3D:
	return Mats.olive_paint() if team == 0 else Mats.sand_paint()

func _build_jeep() -> void:
	var paint := _paint()
	_box(model, Vector3(1.9, 0.55, 4.0), Vector3(0, 0.95, 0), paint)
	_box(model, Vector3(1.8, 0.45, 1.4), Vector3(0, 1.4, -1.2), paint)            # hood
	_box(model, Vector3(1.85, 0.08, 0.05), Vector3(0, 1.95, -0.45), Mats.metal_dark()) # windshield frame
	_box(model, Vector3(1.7, 0.5, 0.04), Vector3(0, 1.7, -0.45), Mats.pbr("glass", Color(0.5, 0.6, 0.65, 0.35), 0.05, 0.3), Vector3(-0.25, 0, 0))
	_box(model, Vector3(0.6, 0.6, 0.6), Vector3(-0.45, 1.4, 0.3), Mats.fabric(Color(0.1, 0.1, 0.09), "seat"))
	_box(model, Vector3(0.6, 0.6, 0.6), Vector3(0.45, 1.4, 0.3), Mats.fabric(Color(0.1, 0.1, 0.09), "seat"))
	_box(model, Vector3(2.0, 0.2, 0.3), Vector3(0, 0.75, -2.05), Mats.metal_dark())  # bumper
	for x in [-0.95, 0.95]:
		for z in [-1.35, 1.35]:
			_wheel(model, 0.42, 0.35, Vector3(x, 0.45, z))
	for x in [-0.55, 0.55]:
		_box(model, Vector3(0.25, 0.12, 0.05), Vector3(x, 1.1, -2.01), Mats.emissive(Color(1, 0.95, 0.8), 2.0))
	turret = Node3D.new()
	turret.position = Vector3(0, 2.15, 0.9)
	model.add_child(turret)
	_box(turret, Vector3(0.15, 0.5, 0.15), Vector3(0, -0.2, 0), Mats.metal_dark())
	gun = Node3D.new()
	turret.add_child(gun)
	_box(gun, Vector3(0.14, 0.18, 1.1), Vector3(0, 0.05, -0.4), Mats.metal_dark())
	_box(gun, Vector3(0.6, 0.45, 0.04), Vector3(0, 0.2, -0.2), Mats.metal_dark())

func _build_tank() -> void:
	var paint := _paint()
	_box(model, Vector3(3.4, 1.0, 7.0), Vector3(0, 1.15, 0), paint)
	_box(model, Vector3(3.3, 0.5, 1.2), Vector3(0, 1.05, -3.6), paint, Vector3(0.6, 0, 0))
	for x in [-1.55, 1.55]:
		_box(model, Vector3(0.75, 0.95, 7.2), Vector3(x, 0.55, 0), Mats.rubber())
		_box(model, Vector3(0.85, 0.1, 7.1), Vector3(x, 1.12, 0), paint)
		for z in range(-3, 4):
			_wheel(model, 0.42, 0.6, Vector3(x, 0.45, z * 0.95))
	turret = Node3D.new()
	turret.position = Vector3(0, 1.65, 0.3)
	model.add_child(turret)
	_box(turret, Vector3(2.5, 0.8, 3.2), Vector3(0, 0.4, 0.2), paint)
	_box(turret, Vector3(2.1, 0.5, 0.9), Vector3(0, 0.35, -1.6), paint, Vector3(0.3, 0, 0))
	_box(turret, Vector3(0.7, 0.35, 0.7), Vector3(0.6, 0.95, 0.5), Mats.metal_dark())
	_box(turret, Vector3(1.4, 0.5, 0.9), Vector3(0, 0.45, 1.9), Mats.fabric(Color(0.25, 0.24, 0.18), "bustle"))
	gun = Node3D.new()
	gun.position = Vector3(0, 0.45, -1.4)
	turret.add_child(gun)
	var barrel := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.09
	c.bottom_radius = 0.12
	c.height = 4.6
	barrel.mesh = c
	barrel.material_override = paint
	barrel.rotation.x = PI * 0.5
	barrel.position.z = -2.3
	gun.add_child(barrel)
	_box(gun, Vector3(0.32, 0.32, 0.6), Vector3(0, 0, -2.6), paint)

func drive(throttle: float, steer: float, brake: bool, fire: bool, aim_yaw: float, aim_pitch: float, _dt: float) -> void:
	_in.throttle = throttle
	_in.steer = steer
	_in.brake = brake
	_in.fire = fire
	turret_yaw = aim_yaw
	gun_pitch = aim_pitch

func camera_transform(yaw: float, pitch: float) -> Transform3D:
	var pivot := global_position + Vector3(0, 3.6 if kind == "tank" else 2.6, 0)
	var dist := 11.0 if kind == "tank" else 7.5
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(pitch, -1.2, 0.5) - 0.18)
	var pos := pivot + b * Vector3(0, 0.6, dist)
	var space := get_world_3d().direct_space_state
	var qp := PhysicsRayQueryParameters3D.create(pivot, pos, 1)
	var hit := space.intersect_ray(qp)
	if not hit.is_empty():
		pos = hit.position + (pivot - pos).normalized() * 0.4
	return Transform3D(b, pos)

func _physics_process(delta: float) -> void:
	_crush_cd -= delta
	fire_cd -= delta
	if not alive:
		respawn_t -= delta
		if respawn_t <= 0.0 and match_node and match_node.is_authority():
			match_node.respawn_vehicle(self)
		return
	if not _remote_target.is_empty():
		_apply_remote(delta)
		return
	var is_tank := kind == "tank"
	var max_fwd := 15.0 if is_tank else 27.0
	var accel := 6.0 if is_tank else 11.0
	if driver == null:
		_in.throttle = 0.0
		_in.steer = 0.0
		_in.fire = false
	if _in.brake:
		speed = move_toward(speed, 0.0, 30.0 * delta)
	elif absf(_in.throttle) > 0.05:
		speed = move_toward(speed, _in.throttle * (max_fwd if _in.throttle > 0 else max_fwd * 0.45), accel * delta)
	else:
		speed = move_toward(speed, 0.0, 5.0 * delta)
	var turn_rate := (1.1 if is_tank else 1.6) * clampf(absf(speed) / 6.0, 0.25 if is_tank else 0.0, 1.0)
	heading -= _in.steer * turn_rate * delta * (signf(speed) if absf(speed) > 0.5 or not is_tank else 1.0)
	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= 18.0 * delta
	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var c := col.get_collider()
		if c and c.has_meta("building") and absf(speed) > 4.0 and _crush_cd <= 0.0:
			if is_tank and match_node:
				_crush_cd = 0.25
				match_node.request_explosion(col.get_position() + fwd * 0.5, 2.6, 0.0, driver, "crush", false)
				speed *= 0.8
			else:
				if absf(speed) > 12.0 and match_node:
					match_node.report_vehicle_hit(null, self, absf(speed) * 4.0, "fall")
				speed *= -0.25
		elif c and c.has_meta("soldier_body") and absf(speed) > 6.0 and match_node:
			match_node.report_hit(driver, c, 200.0, false, "vehicle")
	_align(delta)
	if driver and _in.fire and fire_cd <= 0.0:
		_fire()
	_update_visuals(delta)

func _align(delta: float) -> void:
	var w: Node = match_node.world if match_node else null
	var n := Vector3.UP
	if w:
		n = w.normal_at(global_position.x, global_position.z)
	var b := Basis(Vector3.UP, heading)
	var tilt_axis := Vector3.UP.cross(n)
	if tilt_axis.length() > 0.001:
		b = Basis(tilt_axis.normalized(), Vector3.UP.angle_to(n)) * b
	global_basis = global_basis.slerp(b.orthonormalized(), 1.0 - exp(-delta * 8.0)).orthonormalized()

func _update_visuals(delta: float) -> void:
	for wh in wheels:
		wh.rotation.x -= speed * delta / 0.42
	if turret:
		var local_yaw := turret_yaw - heading
		if kind == "tank":
			turret.rotation.y = lerp_angle(turret.rotation.y, local_yaw, 1.0 - exp(-delta * 2.5))
			gun.rotation.x = lerpf(gun.rotation.x, clampf(gun_pitch, -0.15, 0.35), 1.0 - exp(-delta * 4.0))
		else:
			turret.rotation.y = local_yaw
			gun.rotation.x = clampf(gun_pitch, -0.4, 0.6)
	var on := driver != null or absf(speed) > 0.5
	if on and not engine.playing:
		engine.play()
	elif not on and engine.playing:
		engine.stop()
	engine.pitch_scale = 0.6 + absf(speed) / (15.0 if kind == "tank" else 27.0) * 0.9
	_smoke.emitting = hp < max_hp * 0.35

func _fire() -> void:
	var wid := "shell" if kind == "tank" else "mg"
	var w := Weapons.get_w(wid)
	fire_cd = 60.0 / w.rpm
	var muzzle: Vector3 = gun.global_transform * (Vector3(0, 0, -5.0) if kind == "tank" else Vector3(0, 0.05, -1.0))
	var dir := -gun.global_transform.basis.z
	if driver and driver.get("camera"):
		# converge onto the camera's crosshair point
		var cam: Camera3D = driver.camera
		var space := get_world_3d().direct_space_state
		var qp := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 1500.0, 1 | 4 | 8)
		qp.exclude = [get_rid()]
		var hit := space.intersect_ray(qp)
		var target: Vector3 = hit.position if not hit.is_empty() else cam.global_position - cam.global_basis.z * 1500.0
		var d2 := (target - muzzle).normalized()
		if d2.dot(dir) > 0.8:
			dir = d2
	if kind != "tank":
		dir = dir.rotated(Vector3.UP, randf_range(-0.01, 0.01))
	match_node.fire_weapon(driver, muzzle, dir * w.vel, wid, kind != "tank" and randi() % 2 == 0, self)
	Fx.muzzle(gun, Vector3(0, 0, -5.0) if kind == "tank" else Vector3(0, 0.05, -1.0), 4.0 if kind == "tank" else 1.2)
	Sfx.play_at(w.sound, muzzle, match_node, 2.0 if kind == "tank" else -2.0)
	if kind == "tank":
		Fx.explosion(match_node, muzzle, 1.5)

func get_exclude_rids() -> Array[RID]:
	return [get_rid()]

func destroy() -> void:
	if not alive:
		return
	alive = false
	respawn_t = 30.0
	speed = 0.0
	Fx.explosion(match_node, global_position + Vector3(0, 1.5, 0), 8.0)
	Sfx.play_at("explosion", global_position, match_node, 6.0)
	_smoke.emitting = true
	engine.stop()
	_set_wreck(true)

func _set_wreck(w: bool) -> void:
	var dark := Mats.pbr("wreck", Color(0.06, 0.055, 0.05), 0.95)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if w:
			mi.set_meta("orig_mat", mi.material_override)
			mi.material_override = dark
		elif mi.has_meta("orig_mat"):
			mi.material_override = mi.get_meta("orig_mat")

func get_net_state() -> Dictionary:
	return {"id": net_id, "p": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"h": snappedf(heading, 0.001), "s": snappedf(speed, 0.01), "ty": snappedf(turret_yaw, 0.001), "gp": snappedf(gun_pitch, 0.001)}

func set_remote_state(st: Dictionary) -> void:
	_remote_target = st

func clear_remote() -> void:
	_remote_target = {}

func _apply_remote(delta: float) -> void:
	var p: Array = _remote_target.p
	var target := Vector3(p[0], p[1], p[2])
	global_position = global_position.lerp(target, 1.0 - exp(-delta * 12.0))
	heading = lerp_angle(heading, float(_remote_target.h), 1.0 - exp(-delta * 12.0))
	speed = float(_remote_target.s)
	turret_yaw = float(_remote_target.ty)
	gun_pitch = float(_remote_target.gp)
	_align(delta)
	_update_visuals(delta)
