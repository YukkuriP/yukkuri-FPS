extends Node3D
## Match manager: conquest-style objectives + tickets, damage/kill rules,
## explosions & destruction, vehicles, offline bots and online replication.
## Online model: clients detect their own hits (lag-compensated feel),
## the Render server owns HP, kills, tickets and relays world events.
## Yukkuri Strike - created by ゆっくりP

const Player := preload("res://scripts/game/player.gd")
const Bot := preload("res://scripts/game/bot.gd")
const Soldier := preload("res://scripts/game/soldier.gd")
const Vehicle := preload("res://scripts/game/vehicle.gd")
const Ballistics := preload("res://scripts/game/ballistics.gd")
const Weapons := preload("res://scripts/game/weapons.gd")
const Fx := preload("res://scripts/game/fx.gd")
const Mats := preload("res://scripts/game/textures.gd")
const Hud := preload("res://scripts/ui/hud.gd")

const START_TICKETS := 250
const RESPAWN_TIME := 5.0
const FLAG_NAMES := ["A", "B", "C"]

var main: Node
var world: Node3D
var online := false
var local_player: Node3D
var soldiers: Array = []
var vehicles: Array = []
var flags: Array = []
var tickets := [START_TICKETS, START_TICKETS]
var hud: CanvasLayer
var ballistics: Node3D
var remotes := {}
var ended := false
var shake := 0.0
var _send_t := 0.0
var _respawn_t := 0.0
var _flag_t := 0.0
var _bleed_t := 0.0

func setup(main_: Node, world_: Node3D, online_: bool, welcome: Dictionary) -> void:
	main = main_
	world = world_
	online = online_
	Player.ensure_actions()
	ballistics = Ballistics.new()
	ballistics.match_node = self
	add_child(ballistics)
	for i in mini(3, world.towns.size()):
		var t: Vector4 = world.towns[i]
		flags.append({"name": FLAG_NAMES[i], "pos": Vector3(t.x, t.y, t.z), "radius": maxf(18.0, t.w * 0.45), "owner": -1, "progress": 0.0})
	_build_flag_markers()
	for i in world.vehicle_spawns.size():
		var vs: Array = world.vehicle_spawns[i]
		var v := Vehicle.new()
		v.match_node = self
		v.net_id = i
		add_child(v)
		v.setup(vs[1], vs[0], vs[2])
		vehicles.append(v)
	local_player = Player.new()
	local_player.team = int(welcome.get("team", 0))
	local_player.display_name = Settings.player_name if Settings.player_name != "" else "Player"
	local_player.match_node = self
	local_player.net_id = int(welcome.get("id", -1))
	add_child(local_player)
	soldiers.append(local_player)
	_spawn(local_player)
	local_player.make_current()
	world.apply_viewport_quality(get_viewport())
	if online:
		var tk: Array = welcome.get("tk", [START_TICKETS, START_TICKETS])
		tickets = [int(tk[0]), int(tk[1])]
		Net.message.connect(_on_net)
		Net.disconnected.connect(_on_disconnected)
	else:
		var per_team := 4 if Settings.is_mobile else 7
		for team in [0, 1]:
			for k in per_team - (1 if team == local_player.team else 0):
				var b := Bot.new()
				b.team = team
				b.skill = randf_range(0.3, 0.75)
				b.display_name = "%s-%02d" % ["BLUE" if team == 0 else "RED", k + 1]
				b.match_node = self
				add_child(b)
				soldiers.append(b)
				_spawn(b)
	hud = Hud.new()
	hud.match_node = self
	add_child(hud)
	if not Settings.use_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_flag_markers() -> void:
	for f in flags:
		var pole := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.06
		c.bottom_radius = 0.08
		c.height = 9.0
		pole.mesh = c
		pole.material_override = Mats.metal_dark()
		add_child(pole)
		var y: float = world.height_at(f.pos.x, f.pos.z)
		pole.global_position = Vector3(f.pos.x, y + 4.5, f.pos.z)
		var cloth := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 1.1, 1.8)
		cloth.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.85, 0.85)
		m.emission_enabled = true
		m.emission_energy_multiplier = 0.4
		cloth.material_override = m
		add_child(cloth)
		cloth.global_position = Vector3(f.pos.x, y + 8.3, f.pos.z + 0.9)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = f.radius - 0.25
		tm.outer_radius = f.radius
		tm.rings = 64
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(1, 1, 1, 0.25)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = Vector3(f.pos.x, y + 0.3, f.pos.z)
		f["cloth"] = m
		f["ring"] = rm
		f["cloth_node"] = cloth
		f["base_y"] = y

func team_color(team: int) -> Color:
	return Color(0.32, 0.66, 1.0) if team == 0 else (Color(1.0, 0.33, 0.28) if team == 1 else Color(0.85, 0.85, 0.85))

# ---------------------------------------------------------------- spawning
func _spawn_transform(team: int) -> Transform3D:
	var pts: Array = world.spawns[team]
	var pos: Vector3 = pts[randi() % pts.size()]
	var owned := flags.filter(func(f): return f.owner == team)
	if owned.size() > 0 and randf() < 0.5:
		var f: Dictionary = owned[randi() % owned.size()]
		var a := randf() * TAU
		pos = f.pos + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, f.radius * 0.7)
	pos.y = world.height_at(pos.x, pos.z) + 1.0
	var space := get_world_3d().direct_space_state
	var qp := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 40, 0), pos - Vector3(0, 5, 0), 1)
	var hit := space.intersect_ray(qp)
	if not hit.is_empty():
		pos.y = hit.position.y + 0.2
	var center := Vector3.ZERO
	var dir := (center - pos)
	var yaw := atan2(-dir.x, -dir.z)
	return Transform3D(Basis(Vector3.UP, yaw), pos)

func _spawn(s: Node3D) -> void:
	s.spawn_at(_spawn_transform(s.team))

func is_authority() -> bool:
	return not online

func respawn_vehicle(v: Node3D) -> void:
	v.respawn()

# ---------------------------------------------------------------- combat
func fire_weapon(shooter: Node, origin: Vector3, vel: Vector3, wid: String, tracer: bool, source: Node = null) -> void:
	var auth := shooter == local_player or (not online and shooter != null)
	ballistics.fire(origin, vel, Weapons.get_w(wid), wid, shooter, auth, tracer, source)
	if shooter:
		shooter.set_meta("fired_t", Time.get_ticks_msec())
	if online and shooter == local_player:
		Net.send({"t": "shot", "o": _v3(origin), "v": _v3(vel), "w": wid, "tr": tracer})

func report_hit(shooter: Node, victim: Node, dmg: float, head: bool, wid: String) -> void:
	if victim == null or not victim.alive:
		return
	if shooter and shooter != victim and shooter.team == victim.team:
		return
	if online:
		if victim.net_id >= 0:
			Net.send({"t": "hit", "v": victim.net_id, "d": int(round(dmg)), "h": head, "w": wid})
		if shooter == local_player and victim != local_player:
			hud.hitmarker(head, false)
		return
	apply_damage(victim, dmg, shooter, head, wid)

func apply_damage(victim: Node, dmg: float, attacker: Node, head: bool, wid: String) -> void:
	victim.hp -= dmg
	if victim.has_method("on_damaged"):
		victim.on_damaged(attacker)
	if victim == local_player:
		hud.damage(attacker.global_position if attacker and is_instance_valid(attacker) else Vector3.INF, dmg)
	if attacker == local_player and victim != local_player:
		hud.hitmarker(head, victim.hp <= 0.0)
	if victim.hp <= 0.0:
		_kill(victim, attacker, wid, head, true)

func _kill(victim: Node, attacker: Node, wid: String, head: bool, count_ticket: bool) -> void:
	if not victim.alive:
		return
	if victim.in_vehicle:
		_exit_vehicle(victim)
	victim.set_dead(true)
	victim.deaths += 1
	if count_ticket:
		tickets[victim.team] = maxi(0, tickets[victim.team] - 1)
	if attacker and attacker != victim:
		attacker.kills += 1
	var aname: String = attacker.display_name if attacker and is_instance_valid(attacker) else ""
	hud.killfeed(aname, attacker.team if attacker else -1, victim.display_name, victim.team, wid, head)
	if attacker == local_player and victim != local_player:
		hud.notify(tr("HUD_HEADSHOT") if head else tr("HUD_ELIMINATED"), 100)
		Sfx.play("kill", -2.0)
	if victim.model:
		var tw := victim.create_tween()
		tw.tween_property(victim.model, "rotation:x", -PI * 0.5 * (1 if randf() < 0.5 else -1), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(victim.model, "position:y", -0.75, 0.45)
		tw.tween_interval(3.5)
		tw.tween_callback(func(): if not victim.alive: victim.model.visible = false)
	if victim == local_player:
		_respawn_t = RESPAWN_TIME
		hud.show_death(aname)
	elif not online:
		get_tree().create_timer(RESPAWN_TIME).timeout.connect(func(): if is_instance_valid(victim) and not ended: _spawn(victim))

func report_vehicle_hit(shooter: Node, v: Node, dmg: float, wid: String) -> void:
	if not v.alive:
		return
	if online:
		Net.send({"t": "vhit", "id": v.net_id, "d": int(round(dmg)), "k": v.kind, "w": wid})
		if shooter == local_player:
			hud.hitmarker(false, false)
		return
	damage_vehicle(v, dmg, shooter)

func damage_vehicle(v: Node, dmg: float, attacker: Node) -> void:
	v.hp -= dmg
	if attacker == local_player:
		hud.hitmarker(false, v.hp <= 0.0)
	if v.hp <= 0.0:
		var d: Node = v.driver
		v.destroy()
		if attacker == local_player:
			hud.notify(tr("HUD_VEHICLE_DESTROYED"), 200)
		if d:
			apply_damage(d, 999.0, attacker, false, "rpg")

func request_explosion(pos: Vector3, radius: float, dmg: float, shooter: Node, wid: String, fx := true) -> void:
	_do_explosion(pos, radius, wid, fx, shooter == local_player)
	if online:
		Net.send({"t": "boom", "p": _v3(pos), "r": radius, "w": wid, "fx": fx})
	if dmg > 0.0:
		_splash(pos, radius, dmg, shooter, wid)

func _do_explosion(pos: Vector3, radius: float, wid: String, fx: bool, mine: bool) -> void:
	if fx:
		Fx.explosion(self, pos, radius)
		Sfx.play_at("explosion", pos, self, 8.0, 1200.0)
		if local_player:
			var d := local_player.global_position.distance_to(pos)
			shake = maxf(shake, clampf(1.0 - d / (radius * 6.0), 0.0, 1.0))
	var n: int = world.explode(pos, radius * (1.0 if wid == "crush" else 0.6))
	if n > 0 and mine and fx:
		hud.notify(tr("HUD_STRUCTURE_DESTROYED"), 25)

func _splash(pos: Vector3, radius: float, dmg: float, shooter: Node, wid: String) -> void:
	var space := get_world_3d().direct_space_state
	for s in soldiers + remotes.values():
		if not s.alive or s.in_vehicle:
			continue
		var c: Vector3 = s.global_position + Vector3(0, 0.9, 0)
		var d := c.distance_to(pos)
		if d >= radius:
			continue
		var qp := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), c, 1)
		var cover := 0.35 if not space.intersect_ray(qp).is_empty() else 1.0
		var amount := dmg * pow(1.0 - d / radius, 1.3) * cover
		if s == shooter:
			amount *= 0.5
		elif shooter and s.team == shooter.team:
			continue
		report_hit(null if s == shooter else shooter, s, amount, false, wid)
	var mult := 1.0 if wid in ["rpg", "shell"] else 0.35
	for v in vehicles:
		var d: float = v.global_position.distance_to(pos)
		if v.alive and d < radius + 2.5:
			report_vehicle_hit(shooter, v, dmg * mult * (1.0 - d / (radius + 2.5)) * 2.2, wid)

func throw_grenade(shooter: Node, pos: Vector3, vel: Vector3, auth := true) -> void:
	var g := RigidBody3D.new()
	g.collision_layer = 16
	g.collision_mask = 1 | 8 | 16
	g.mass = 0.4
	g.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.8
	g.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.06
	cs.shape = sh
	g.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.14
	mi.mesh = sm
	mi.material_override = Mats.olive_paint()
	g.add_child(mi)
	add_child(g)
	g.global_position = pos
	g.linear_velocity = vel
	g.angular_velocity = Vector3(randf(), randf(), randf()) * 8.0
	if online and shooter == local_player:
		Net.send({"t": "nade", "p": _v3(pos), "v": _v3(vel)})
	var is_auth := auth and (shooter == local_player or not online)
	get_tree().create_timer(Weapons.GRENADE.fuse).timeout.connect(func():
		if not is_instance_valid(g):
			return
		if is_auth and not ended:
			request_explosion(g.global_position + Vector3(0, 0.2, 0), Weapons.GRENADE.radius, Weapons.GRENADE.dmg, shooter if is_instance_valid(shooter) else null, "grenade")
		g.queue_free())

# ---------------------------------------------------------------- vehicles
func nearest_vehicle(p: Node3D) -> Node3D:
	var best: Node3D = null
	var bd := 5.5
	for v in vehicles:
		if not v.alive or v.driver != null or v.has_meta("remote_driver"):
			continue
		var d: float = v.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = v
	return best

func toggle_vehicle(p: Node3D) -> void:
	if p.in_vehicle:
		_exit_vehicle(p)
		return
	var v := nearest_vehicle(p)
	if v == null:
		return
	v.driver = p
	v.clear_remote()
	p.set_in_vehicle(v)
	p.yaw = v.heading
	Sfx.play("click", -4.0, 0.7)

func _exit_vehicle(p: Node3D) -> void:
	var v: Node3D = p.in_vehicle
	if v == null:
		return
	v.driver = null
	p.set_in_vehicle(null)
	var out: Vector3 = v.global_position + v.global_basis.x * (2.6 if v.kind == "jeep" else 3.4)
	out.y = maxf(world.height_at(out.x, out.z), v.global_position.y) + 0.5
	p.global_position = out
	p.velocity = Vector3.ZERO
	if p == local_player:
		p.camera.transform = Transform3D.IDENTITY

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if local_player and local_player.camera:
		shake = move_toward(shake, 0.0, delta * 1.6)
		var t := Time.get_ticks_msec() * 0.05
		local_player.camera.h_offset = sin(t * 1.3) * shake * 0.12
		local_player.camera.v_offset = cos(t * 1.7) * shake * 0.12
	if ended:
		return
	if not local_player.alive:
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_spawn(local_player)
			local_player.make_current()
			hud.hide_death()
			if online:
				Net.send({"t": "spawn"})
	if online:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / Net.SEND_RATE
			var st: Dictionary = local_player.get_net_state()
			st["t"] = "st"
			st["a"] = local_player.alive
			if local_player.in_vehicle:
				st["vs"] = local_player.in_vehicle.get_net_state()
			Net.send(st)
		_interpolate_remotes(delta)
	_flag_t -= delta
	if _flag_t <= 0.0:
		_flag_t = 0.25
		_update_flags(0.25)
	if not online:
		_bleed_t -= delta
		if _bleed_t <= 0.0:
			_bleed_t = 4.0
			var owned := [0, 0]
			for f in flags:
				if f.owner >= 0:
					owned[f.owner] += 1
			if owned[0] > owned[1]:
				tickets[1] = maxi(0, tickets[1] - (owned[0] - owned[1]))
			elif owned[1] > owned[0]:
				tickets[0] = maxi(0, tickets[0] - (owned[1] - owned[0]))
		if tickets[0] <= 0 or tickets[1] <= 0:
			_end(0 if tickets[1] <= 0 else 1)

func _update_flags(dt: float) -> void:
	var all: Array = soldiers + remotes.values()
	for f in flags:
		var cnt := [0, 0]
		for s in all:
			if s.alive and Vector2(s.global_position.x - f.pos.x, s.global_position.z - f.pos.z).length() < f.radius:
				cnt[s.team] += 1
		var diff: int = cnt[0] - cnt[1]
		if diff != 0:
			var prev_owner: int = f.owner
			f.progress = clampf(f.progress + signf(diff) * minf(absf(diff), 3) * 0.1 * dt, -1.0, 1.0)
			if f.progress >= 1.0:
				f.owner = 0
			elif f.progress <= -1.0:
				f.owner = 1
			elif (f.owner == 0 and f.progress < 0.0) or (f.owner == 1 and f.progress > 0.0):
				f.owner = -1
			if f.owner != prev_owner:
				if f.owner == local_player.team:
					hud.notify(tr("HUD_FLAG_CAPTURED") % f.name, 150)
					Sfx.play("kill", -6.0, 0.7)
				elif prev_owner == local_player.team:
					hud.notify(tr("HUD_FLAG_LOST") % f.name, 0)
		var col := team_color(f.owner)
		f.cloth.albedo_color = col
		f.cloth.emission = col
		f.ring.albedo_color = Color(col.r, col.g, col.b, 0.3)
		f.cloth_node.global_position.y = f.base_y + 1.5 + absf(f.progress) * 6.8

func _end(winner: int) -> void:
	if ended:
		return
	ended = true
	hud.show_end(winner == local_player.team)
	local_player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t := get_tree().create_timer(9.0, true)
	t.timeout.connect(func(): if is_instance_valid(main): main.end_match())

func leave() -> void:
	main.end_match()

func debug_explode_near_player() -> void:
	var best: Node3D = null
	var bd := INF
	for b in world.buildings:
		var d: float = b.global_position.distance_to(local_player.global_position)
		if d < bd:
			bd = d
			best = b
	if best:
		request_explosion(best.global_position + Vector3(0, 2.0, 0), 7.0, 120.0, local_player, "rpg")

# ---------------------------------------------------------------- network
func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]

func _a3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _by_id(id: int) -> Node:
	if local_player and id == local_player.net_id:
		return local_player
	return remotes.get(id)

func _remote(pl: Dictionary) -> Node3D:
	var id := int(pl.id)
	if remotes.has(id):
		return remotes[id]
	var s := Soldier.new()
	s.team = int(pl.get("tm", 1))
	s.net_id = id
	s.display_name = str(pl.get("n", "Player"))
	s.match_node = self
	add_child(s)
	s.setup_body(true)
	s.global_position = _a3(pl.p)
	s.set_meta("tp", s.global_position)
	s.set_meta("ty", 0.0)
	s.set_meta("tpitch", 0.0)
	remotes[id] = s
	return s

func _on_net(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"snap":
			var seen := {}
			for pl in msg.get("pl", []):
				var id := int(pl.id)
				if id == local_player.net_id:
					local_player.hp = float(pl.get("hp", local_player.hp))
					continue
				seen[id] = true
				var s := _remote(pl)
				s.set_meta("tp", _a3(pl.p))
				var r: Array = pl.get("r", [0, 0])
				s.set_meta("ty", float(r[0]))
				s.set_meta("tpitch", float(r[1]))
				s.crouching = bool(pl.get("c", false))
				s.kills = int(pl.get("k", 0))
				s.deaths = int(pl.get("d", 0))
				s.hp = float(pl.get("hp", 100))
				var alive_now := bool(pl.get("a", true))
				if alive_now and not s.alive:
					s.set_dead(false)
				var vid := int(pl.get("v", -1))
				for v in vehicles:
					if v.get_meta("remote_driver", -1) == id and v.net_id != vid:
						v.remove_meta("remote_driver")
				if vid >= 0 and vid < vehicles.size():
					vehicles[vid].set_meta("remote_driver", id)
					if s.in_vehicle != vehicles[vid]:
						s.set_in_vehicle(vehicles[vid])
				elif s.in_vehicle:
					s.set_in_vehicle(null)
			for id in remotes.keys():
				if not seen.has(id):
					remotes[id].queue_free()
					remotes.erase(id)
			for vs in msg.get("vs", []):
				var vid := int(vs.id)
				if vid >= 0 and vid < vehicles.size() and vehicles[vid].driver != local_player:
					vehicles[vid].set_remote_state(vs)
			var tk: Array = msg.get("tk", tickets)
			tickets = [int(tk[0]), int(tk[1])]
		"shot":
			var s: Node = remotes.get(int(msg.id))
			var src: Node = s.in_vehicle if s and s.in_vehicle else s
			var wid := str(msg.w)
			var w := Weapons.get_w(wid)
			var o := _a3(msg.o)
			ballistics.fire(o, _a3(msg.v), w, wid, s, false, bool(msg.get("tr", false)), src)
			Sfx.play_at(w.sound, o, self, 0.0)
			if s:
				s.set_meta("fired_t", Time.get_ticks_msec())
		"boom":
			_do_explosion(_a3(msg.p), float(msg.r), str(msg.w), bool(msg.get("fx", true)), false)
		"nade":
			throw_grenade(remotes.get(int(msg.id)), _a3(msg.p), _a3(msg.v), false)
		"dmg":
			var victim := _by_id(int(msg.v))
			if victim:
				victim.hp = float(msg.hp)
				var attacker := _by_id(int(msg.get("by", -1)))
				if victim == local_player:
					hud.damage(attacker.global_position if attacker else Vector3.INF, float(msg.get("d", 10)))
		"kill":
			var victim := _by_id(int(msg.v))
			var attacker := _by_id(int(msg.get("by", -1)))
			if victim:
				if attacker == local_player and victim != local_player:
					hud.hitmarker(bool(msg.get("h", false)), true)
				_kill(victim, attacker, str(msg.get("w", "ar")), bool(msg.get("h", false)), false)
		"vdmg":
			var id := int(msg.id)
			if id >= 0 and id < vehicles.size():
				vehicles[id].hp = float(msg.hp)
		"vdead":
			var id := int(msg.id)
			if id >= 0 and id < vehicles.size():
				var v: Node = vehicles[id]
				if v.driver == local_player:
					_exit_vehicle(local_player)
				v.destroy()
				if int(msg.get("by", -1)) == local_player.net_id:
					hud.notify(tr("HUD_VEHICLE_DESTROYED"), 200)
		"vspawn":
			var id := int(msg.id)
			if id >= 0 and id < vehicles.size():
				vehicles[id].respawn()
				vehicles[id].clear_remote()
		"end":
			_end(int(msg.winner))

func _interpolate_remotes(delta: float) -> void:
	var k := 1.0 - exp(-delta * 14.0)
	for s in remotes.values():
		var tp: Vector3 = s.get_meta("tp")
		var prev: Vector3 = s.global_position
		if s.in_vehicle:
			s.global_position = s.in_vehicle.global_position
		elif prev.distance_to(tp) > 8.0:
			s.global_position = tp
		else:
			s.global_position = prev.lerp(tp, k)
		s.rotation.y = lerp_angle(s.rotation.y, float(s.get_meta("ty")), k)
		s.velocity = (s.global_position - prev) / maxf(delta, 0.001)
		if s.alive:
			s.animate_body(delta, Vector2(s.velocity.x, s.velocity.z).length(), -float(s.get_meta("tpitch")))

func _on_disconnected() -> void:
	if not ended:
		hud.notify(tr("MP_DISCONNECTED"), 0)
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(main): main.end_match())
