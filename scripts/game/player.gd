extends "res://scripts/game/soldier.gd"
## Local player: fast CoD-style movement (sprint, slide, lean), simulated
## ballistics with zeroing, ADS, recoil, grenades and vehicle use.
## Works with keyboard/mouse and the on-screen virtual pad.
## Yukkuri Strike - created by ゆっくりP

const Weapons := preload("res://scripts/game/weapons.gd")
const ViewModel := preload("res://scripts/game/viewmodel.gd")

const WALK := 4.8
const SPRINT := 7.8
const CROUCH := 2.7
const JUMP := 4.9
const GRAVITY := 16.0
const ZEROS := [100, 200, 300, 400, 600, 800]

var head: Node3D
var camera: Camera3D
var vm: Node3D
var ammo := {}
var grenades := 3
var zero_idx := 0
var yaw := 0.0
var pitch := 0.0
var ads := 0.0
var sprint_blend := 0.0
var lean := 0.0
var bloom := 0.0
var recoil := Vector2.ZERO
var fire_cd := 0.0
var reload_t := 0.0
var reload_total := 0.0
var swap_t := 0.0
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var shots := 0
var suppression := 0.0
var input_enabled := true
var touch_move := Vector2.ZERO
var touch_look := Vector2.ZERO
var touch_hold := {"fire": false, "ads": false, "sprint": false}
var _look_frame := Vector2.ZERO
var _fire_latch := false
var _last_vy := 0.0
var _step_t := 0.0
var _ads_toggle := false
var base_fov := 80.0

static func ensure_actions() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "crouch": [KEY_CTRL, KEY_C], "sprint": [KEY_SHIFT], "reload": [KEY_R], "use": [KEY_F],
		"grenade": [KEY_G], "lean_left": [KEY_Q], "lean_right": [KEY_E], "zero_up": [KEY_PAGEUP], "zero_down": [KEY_PAGEDOWN],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4], "scoreboard": [KEY_TAB], "pause": [KEY_ESCAPE, KEY_P],
	}
	for a in map:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in map[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["ads", MOUSE_BUTTON_RIGHT], ["next_weapon", MOUSE_BUTTON_WHEEL_DOWN], ["prev_weapon", MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var m := InputEventMouseButton.new()
			m.button_index = pair[1]
			InputMap.action_add_event(pair[0], m)
	# gamepad support
	var pad := {"jump": JOY_BUTTON_A, "crouch": JOY_BUTTON_B, "reload": JOY_BUTTON_X, "next_weapon": JOY_BUTTON_Y,
		"sprint": JOY_BUTTON_LEFT_STICK, "use": JOY_BUTTON_DPAD_UP, "grenade": JOY_BUTTON_RIGHT_SHOULDER, "pause": JOY_BUTTON_START}
	for a in pad:
		var j := InputEventJoypadButton.new()
		j.button_index = pad[a]
		InputMap.action_add_event(a, j)
	for pair in [["fire", JOY_AXIS_TRIGGER_RIGHT], ["ads", JOY_AXIS_TRIGGER_LEFT]]:
		var j := InputEventJoypadMotion.new()
		j.axis = pair[1]
		j.axis_value = 1.0
		InputMap.action_add_event(pair[0], j)

func _ready() -> void:
	setup_body(false)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 2400.0
	head.add_child(camera)
	vm = ViewModel.new()
	camera.add_child(vm)
	base_fov = Settings.fov
	reset_loadout()

func reset_loadout() -> void:
	ammo.clear()
	for id in Weapons.ORDER:
		var w := Weapons.get_w(id)
		ammo[id] = [w.mag, w.reserve]
	grenades = Weapons.GRENADE.count
	weapon_id = "ar"
	zero_idx = 0
	hp = 100.0
	if vm.is_node_ready():
		vm.set_weapon(weapon_id)
	else:
		vm.ready.connect(func(): vm.set_weapon(weapon_id), CONNECT_ONE_SHOT)

func spawn_at(t: Transform3D) -> void:
	global_position = t.origin
	yaw = t.basis.get_euler().y
	pitch = 0.0
	velocity = Vector3.ZERO
	set_dead(false)
	base_fov = Settings.fov
	reset_loadout()
	reload_t = 0.0

func make_current() -> void:
	camera.current = true

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := deg_to_rad(Settings.mouse_sens) * lerpf(1.0, 0.55, ads)
		if weapon_id == "dmr" and ads > 0.8:
			s *= 0.4
		_look(event.relative * s)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Settings.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _look(rel: Vector2) -> void:
	_look_frame += rel * 400.0
	yaw -= rel.x
	pitch -= rel.y * (-1.0 if Settings.invert_y else 1.0)
	pitch = clampf(pitch, deg_to_rad(-88), deg_to_rad(88))

func touch_action(name: String) -> void:
	match name:
		"jump": _jump()
		"crouch": crouching = not crouching
		"reload": start_reload()
		"swap": cycle_weapon(1)
		"grenade": throw_grenade()
		"use": use()
		"ads": _ads_toggle = not _ads_toggle

func _process(delta: float) -> void:
	if not alive:
		return
	var w := Weapons.get_w(weapon_id)
	if touch_look != Vector2.ZERO:
		_look(touch_look * deg_to_rad(Settings.touch_sens) * lerpf(1.0, 0.5, ads))
		touch_look = Vector2.ZERO
	var pad_look := Vector2.ZERO
	var jx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var jy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(jx) > 0.15 or absf(jy) > 0.15:
		pad_look = Vector2(jx, jy) * 2.6 * delta * Settings.mouse_sens / 0.12
		_look(pad_look)
	# recoil recovery
	var rec := recoil * minf(1.0, delta * 9.0)
	recoil -= rec
	pitch = clampf(pitch + rec.y, deg_to_rad(-88), deg_to_rad(88))
	yaw += rec.x
	rotation.y = yaw
	head.rotation.x = pitch
	var want_lean := 0.0
	if input_enabled and in_vehicle == null:
		want_lean = Input.get_action_strength("lean_right") - Input.get_action_strength("lean_left")
	lean = lerpf(lean, want_lean, 1.0 - exp(-delta * 10.0))
	head.rotation.z = -lean * 0.22
	head.position = Vector3(lean * 0.45, lerpf(head.position.y, 1.05 if crouching else 1.62, 1.0 - exp(-delta * 12.0)), 0)
	if in_vehicle:
		vm.visible = false
		return
	vm.visible = true
	# ADS / sprint blending
	var want_ads: bool = input_enabled and (_act("ads") or touch_hold.ads or _ads_toggle) and reload_t <= 0.0 and swap_t <= 0.0
	var speed := Vector2(velocity.x, velocity.z).length()
	var sprinting := _is_sprinting() and speed > 5.0
	ads = move_toward(ads, 1.0 if want_ads else 0.0, delta * 5.5)
	sprint_blend = move_toward(sprint_blend, 1.0 if sprinting and ads < 0.1 else 0.0, delta * 6.0)
	var zoom: float = lerpf(1.0, w.ads_fov, ads)
	camera.fov = lerpf(camera.fov, base_fov * zoom * (1.06 if sprinting else 1.0), 1.0 - exp(-delta * 14.0))
	vm.visible = not (w.scope and ads > 0.85)
	# timers
	fire_cd -= delta
	bloom = move_toward(bloom, 0.0, delta * 3.0)
	suppression = move_toward(suppression, 0.0, delta * 0.6)
	if swap_t > 0.0:
		swap_t -= delta
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()
	# shooting
	var trig: bool = input_enabled and (_act("fire") or touch_hold.fire)
	if trig and fire_cd <= 0.0 and reload_t <= 0.0 and swap_t <= 0.0 and sprint_blend < 0.4:
		if w.auto or not _fire_latch:
			_fire(w)
	if not trig:
		_fire_latch = false
	if input_enabled:
		if Input.is_action_just_pressed("reload"): start_reload()
		if Input.is_action_just_pressed("next_weapon"): cycle_weapon(1)
		if Input.is_action_just_pressed("prev_weapon"): cycle_weapon(-1)
		for i in 4:
			if Input.is_action_just_pressed("weapon_%d" % (i + 1)): switch_weapon(Weapons.ORDER[i])
		if Input.is_action_just_pressed("grenade"): throw_grenade()
		if Input.is_action_just_pressed("use"): use()
		if Input.is_action_just_pressed("zero_up"): zero_idx = mini(zero_idx + 1, ZEROS.size() - 1); Sfx.play("click", -10)
		if Input.is_action_just_pressed("zero_down"): zero_idx = maxi(zero_idx - 1, 0); Sfx.play("click", -10)
	var rl := 0.0
	if reload_t > 0.0 and reload_total > 0.0:
		rl = 1.0 - reload_t / reload_total
	vm.update(delta, _look_frame, speed, ads, sprint_blend, rl if reload_t > 0.0 else -1.0, is_on_floor())
	_look_frame = Vector2.ZERO

func _act(a: String) -> bool:
	# touch screens emulate the mouse; never treat those taps as trigger pulls
	return not Settings.use_touch() and Input.is_action_pressed(a)

func _is_sprinting() -> bool:
	if not input_enabled:
		return false
	var mv := _move_input()
	return (Input.is_action_pressed("sprint") or touch_hold.sprint or touch_move.length() > 0.95) and mv.y < -0.3 and not crouching

func _move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var jl := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if jl.length() > 0.2:
		v = jl
	if touch_move.length() > 0.05:
		v = touch_move
	return v.limit_length(1.0)

func _jump() -> void:
	if is_on_floor() and alive and in_vehicle == null:
		if crouching:
			crouching = false
			return
		velocity.y = JUMP
		slide_t = 0.0

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if in_vehicle:
		var mv := _move_input()
		var fire: bool = input_enabled and (_act("fire") or touch_hold.fire)
		in_vehicle.drive(-mv.y, mv.x, input_enabled and Input.is_action_pressed("jump"), fire, yaw, pitch, delta)
		global_position = in_vehicle.global_position + Vector3(0, 1.0, 0)
		camera.global_transform = in_vehicle.camera_transform(yaw, pitch)
		return
	if input_enabled:
		if Input.is_action_just_pressed("jump"):
			_jump()
		if Input.is_action_just_pressed("crouch"):
			if _is_sprinting() and is_on_floor() and Vector2(velocity.x, velocity.z).length() > 6.0:
				slide_t = 0.75
				slide_dir = Vector3(velocity.x, 0, velocity.z).normalized()
				crouching = true
				Sfx.play("footstep", -2.0, 0.6)
			else:
				crouching = not crouching
	var mv := _move_input()
	var dir := (transform.basis * Vector3(mv.x, 0, mv.y))
	dir.y = 0
	var target_speed := WALK
	if crouching:
		target_speed = CROUCH
	elif _is_sprinting():
		target_speed = SPRINT
	target_speed *= lerpf(1.0, 0.55, ads)
	var hv := Vector3(velocity.x, 0, velocity.z)
	if slide_t > 0.0:
		slide_t -= delta
		hv = slide_dir * lerpf(4.0, 11.0, slide_t / 0.75)
	elif is_on_floor():
		hv = hv.lerp(dir * target_speed, 1.0 - exp(-delta * (14.0 if dir.length() > 0.1 else 10.0)))
	else:
		hv += dir * 6.0 * delta
		hv = hv.limit_length(maxf(SPRINT, hv.length()))
	velocity.x = hv.x
	velocity.z = hv.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_last_vy = velocity.y
	var was_air := not is_on_floor()
	move_and_slide()
	if was_air and is_on_floor() and _last_vy < -13.0:
		match_node.report_hit(null, self, (absf(_last_vy) - 13.0) * 9.0, false, "fall")
	if is_on_floor() and hv.length() > 1.0:
		_step_t -= delta * hv.length()
		if _step_t <= 0.0:
			_step_t = 2.6
			Sfx.play("footstep", -12.0 if crouching else -6.0, randf_range(0.85, 1.15))
	if global_position.y < -30.0:
		match_node.report_hit(null, self, 999.0, false, "fall")

func _fire(w: Dictionary) -> void:
	var mag: int = ammo[weapon_id][0]
	if mag <= 0:
		Sfx.play("empty", -6.0)
		_fire_latch = true
		fire_cd = 0.25
		if ammo[weapon_id][1] > 0:
			start_reload()
		return
	ammo[weapon_id][0] = mag - 1
	fire_cd = 60.0 / w.rpm
	_fire_latch = true
	shots += 1
	var spread := deg_to_rad(lerpf(w.spread_hip, w.spread_ads, ads) + bloom * (1.0 - ads * 0.7))
	if not is_on_floor():
		spread += deg_to_rad(2.0)
	var basis := camera.global_transform.basis
	var dir := -basis.z
	var zero: float = ZEROS[zero_idx]
	var vel: float = w.vel
	if not w.get("rocket", false):
		var t := zero / vel
		var drop := 0.5 * 9.81 * t * t
		dir = dir.rotated(basis.x, atan2(drop, zero))
	var a := randf() * TAU
	var r := sqrt(randf()) * spread
	dir = dir.rotated(basis.x, sin(a) * r).rotated(basis.y, cos(a) * r).normalized()
	var origin := camera.global_position + dir * 0.3
	var tracer: bool = w.tracer_every > 0 and shots % w.tracer_every == 0
	match_node.fire_weapon(self, origin, dir * vel, weapon_id, tracer)
	Sfx.play(w.sound, -2.0, randf_range(0.95, 1.05))
	vm.kick(1.0)
	var rc: Vector2 = w.recoil
	var k := lerpf(1.0, 0.6, ads) * (0.7 if crouching else 1.0)
	recoil.y += deg_to_rad(rc.x) * k * randf_range(0.8, 1.1)
	recoil.x += deg_to_rad(rc.y) * k * randf_range(-1.0, 1.0)
	bloom = minf(bloom + 0.45, 4.0)
	if ammo[weapon_id][0] == 0 and ammo[weapon_id][1] > 0:
		get_tree().create_timer(0.25).timeout.connect(start_reload)

func start_reload() -> void:
	if reload_t > 0.0 or not alive or in_vehicle:
		return
	var w := Weapons.get_w(weapon_id)
	if ammo[weapon_id][0] >= w.mag or ammo[weapon_id][1] <= 0:
		return
	reload_total = w.reload
	reload_t = w.reload
	Sfx.play("reload", -4.0)

func _finish_reload() -> void:
	var w := Weapons.get_w(weapon_id)
	var need: int = w.mag - ammo[weapon_id][0]
	var take := mini(need, ammo[weapon_id][1])
	ammo[weapon_id][0] += take
	ammo[weapon_id][1] -= take
	Sfx.play("click", -6.0, 1.3)

func switch_weapon(id: String) -> void:
	if id == weapon_id or not alive:
		return
	weapon_id = id
	reload_t = 0.0
	swap_t = 0.45
	vm.set_weapon(id)
	zero_idx = 0
	Sfx.play("click", -8.0, 0.8)

func cycle_weapon(dirn: int) -> void:
	var i := (Weapons.index_of(weapon_id) + dirn + Weapons.ORDER.size()) % Weapons.ORDER.size()
	switch_weapon(Weapons.ORDER[i])

func throw_grenade() -> void:
	if grenades <= 0 or not alive or in_vehicle:
		return
	grenades -= 1
	var dir := -camera.global_transform.basis.z
	match_node.throw_grenade(self, camera.global_position + dir * 0.6, dir * 19.0 + Vector3.UP * 3.5 + velocity * 0.5)

func use() -> void:
	match_node.toggle_vehicle(self)

func suppress(amount: float) -> void:
	suppression = minf(1.0, suppression + amount * 0.6)
	recoil += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 0.004 * amount

func set_dead(dead: bool) -> void:
	super.set_dead(dead)
	if vm:
		vm.visible = not dead

func get_net_state() -> Dictionary:
	return {"p": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"r": [snappedf(yaw, 0.001), snappedf(pitch, 0.001)], "c": crouching, "w": weapon_id,
		"v": in_vehicle.net_id if in_vehicle else -1}
