extends "res://scripts/game/soldier.gd"
## Offline AI soldier: captures objectives, finds targets with line of sight,
## aims with human-like reaction time, error and bullet-drop compensation.
## Yukkuri Strike - created by ゆっくりP

const Weapons := preload("res://scripts/game/weapons.gd")

var skill := 0.5
var yaw := 0.0
var pitch := 0.0
var target: Node3D = null
var goal := Vector3.ZERO
var ammo := 30
var fire_cd := 0.0
var burst := 0
var reload_t := 0.0
var think_t := 0.0
var react_t := 0.0
var strafe := 1.0
var strafe_t := 0.0
var stuck_t := 0.0
var last_attacker: Node3D = null
var _aim_err := Vector3.ZERO
var _last_pos := Vector3.ZERO

func _ready() -> void:
	setup_body(true)
	var r := randf()
	weapon_id = "dmr" if r < 0.18 else ("smg" if r < 0.4 else "ar")
	ammo = Weapons.get_w(weapon_id).mag

func spawn_at(t: Transform3D) -> void:
	global_position = t.origin
	yaw = t.basis.get_euler().y
	velocity = Vector3.ZERO
	hp = 100.0
	target = null
	last_attacker = null
	ammo = Weapons.get_w(weapon_id).mag
	set_dead(false)
	_pick_goal()

func on_damaged(attacker: Node3D) -> void:
	if attacker and attacker != self:
		last_attacker = attacker
		react_t = minf(react_t, 0.25)

func _physics_process(delta: float) -> void:
	if not alive or match_node == null:
		return
	think_t -= delta
	if think_t <= 0.0:
		think_t = randf_range(0.25, 0.4)
		_think()
	var w := Weapons.get_w(weapon_id)
	var move_dir := Vector3.ZERO
	var dist_t := 9999.0
	if is_instance_valid(target) and target.alive:
		dist_t = global_position.distance_to(target.global_position)
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = randf_range(0.6, 1.8)
			strafe = [-1.0, 1.0][randi() % 2]
			crouching = weapon_id == "dmr" or randf() < 0.25
		var to_t := (target.global_position - global_position)
		to_t.y = 0
		var side := to_t.normalized().cross(Vector3.UP)
		move_dir = side * strafe
		var ideal := 160.0 if weapon_id == "dmr" else (18.0 if weapon_id == "smg" else 45.0)
		if dist_t > ideal * 1.5:
			move_dir += to_t.normalized()
		elif dist_t < ideal * 0.4:
			move_dir -= to_t.normalized() * 0.5
		_aim(delta, w, dist_t)
	else:
		crouching = false
		var to_g := goal - global_position
		to_g.y = 0
		if to_g.length() < 6.0:
			_pick_goal()
		move_dir = to_g.normalized()
		var desired := atan2(-move_dir.x, -move_dir.z)
		yaw = lerp_angle(yaw, desired, 1.0 - exp(-delta * 5.0))
		pitch = lerpf(pitch, 0.0, delta * 3.0)
	move_dir = move_dir.normalized() if move_dir.length() > 0.01 else Vector3.ZERO
	_avoid(move_dir)
	var spd := 2.6 if crouching else (4.4 if target else 6.4)
	velocity.x = lerpf(velocity.x, move_dir.x * spd, 1.0 - exp(-delta * 8.0))
	velocity.z = lerpf(velocity.z, move_dir.z * spd, 1.0 - exp(-delta * 8.0))
	if not is_on_floor():
		velocity.y -= 16.0 * delta
	move_and_slide()
	rotation.y = yaw
	stuck_t += delta
	if stuck_t > 2.0:
		if global_position.distance_to(_last_pos) < 1.0 and move_dir != Vector3.ZERO:
			goal = global_position + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
			if is_on_floor():
				velocity.y = 4.8
		_last_pos = global_position
		stuck_t = 0.0
	if global_position.y < -30.0:
		match_node.report_hit(null, self, 999.0, false, "fall")
	reload_t -= delta
	if reload_t <= 0.0 and ammo <= 0:
		ammo = w.mag
	animate_body(delta, Vector2(velocity.x, velocity.z).length(), -pitch)

func _avoid(move_dir: Vector3) -> void:
	if move_dir == Vector3.ZERO or not is_on_floor():
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.5, 0)
	var qp := PhysicsRayQueryParameters3D.create(from, from + move_dir * 1.2, 1 | 8)
	qp.exclude = get_exclude_rids()
	if not space.intersect_ray(qp).is_empty():
		var qh := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.0, 0), from + Vector3(0, 1.0, 0) + move_dir * 1.2, 1 | 8)
		qh.exclude = get_exclude_rids()
		if space.intersect_ray(qh).is_empty():
			velocity.y = 4.8
		else:
			strafe = -strafe
			velocity += move_dir.cross(Vector3.UP) * strafe * 2.0

func _think() -> void:
	var best: Node3D = null
	var best_d := 260.0 if weapon_id == "dmr" else 170.0
	for s in match_node.soldiers:
		if s == self or not s.alive or s.team == team:
			continue
		var d := global_position.distance_to(s.global_position)
		if d > best_d:
			continue
		if s != last_attacker and d > 12.0:
			var to := (s.global_position - global_position).normalized()
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			if fwd.dot(to) < 0.1:
				continue
		if _can_see(s):
			best = s
			best_d = d
	for v in match_node.vehicles:
		if v.alive and v.driver and v.team != team and weapon_id != "dmr":
			var d := global_position.distance_to(v.global_position)
			if d < best_d * 0.7 and _can_see(v.driver):
				best = v.driver
				best_d = d
	if best != target:
		target = best
		react_t = lerpf(0.75, 0.25, skill) + randf() * 0.2
		_aim_err = Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * lerpf(1.6, 0.6, skill)
	if target == null and last_attacker and not last_attacker.alive:
		last_attacker = null

func _can_see(s: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3(0, 1.0 if crouching else 1.6, 0)
	var tgt: Vector3 = s.global_position + Vector3(0, 1.3, 0)
	if s.get("in_vehicle") and s.in_vehicle:
		tgt = s.in_vehicle.global_position + Vector3(0, 1.5, 0)
	var qp := PhysicsRayQueryParameters3D.create(eye, tgt, 1)
	return space.intersect_ray(qp).is_empty()

func _aim(delta: float, w: Dictionary, dist: float) -> void:
	var tp: Vector3 = target.global_position + Vector3(0, 1.25, 0)
	if target.get("in_vehicle") and target.in_vehicle:
		tp = target.in_vehicle.global_position + Vector3(0, 1.5, 0)
	var tof: float = dist / w.vel
	tp += target.velocity * tof * skill
	_aim_err = _aim_err.lerp(Vector3.ZERO, delta * 0.6)
	tp += _aim_err * clampf(dist / 30.0, 0.5, 3.0)
	var eye := global_position + Vector3(0, 1.0 if crouching else 1.55, 0)
	var d := tp - eye
	var drop := 0.5 * 9.81 * tof * tof
	d.y += drop
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var turn := lerpf(4.0, 9.0, skill)
	yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-delta * turn))
	pitch = lerpf(pitch, want_pitch, 1.0 - exp(-delta * turn))
	react_t -= delta
	fire_cd -= delta
	if react_t > 0.0 or fire_cd > 0.0 or reload_t > 0.0:
		return
	if absf(angle_difference(yaw, want_yaw)) > 0.08:
		return
	if ammo <= 0:
		reload_t = w.reload
		return
	if burst <= 0:
		burst = 1 if not w.auto else randi_range(3, 7)
	burst -= 1
	ammo -= 1
	fire_cd = 60.0 / w.rpm
	if burst <= 0:
		fire_cd += randf_range(0.25, 0.7) if w.auto else randf_range(1.2, 2.5)
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var spread := deg_to_rad(lerpf(2.2, 0.7, skill) * (0.5 if crouching else 1.0))
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread)).rotated(dir.cross(Vector3.UP).normalized(), randf_range(-spread, spread))
	match_node.fire_weapon(self, eye + dir * 0.6, dir * w.vel, weapon_id, w.tracer_every > 0 and randi() % w.tracer_every == 0)
	Sfx.play_at(w.sound, eye, match_node, 0.0)

func _pick_goal() -> void:
	if match_node == null or match_node.flags.is_empty():
		goal = global_position
		return
	var options := []
	for f in match_node.flags:
		if f.owner != team:
			options.append(f)
	if options.is_empty():
		options = match_node.flags
	var f: Dictionary = options[randi() % options.size()]
	var r: float = f.radius * 0.6
	goal = f.pos + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
