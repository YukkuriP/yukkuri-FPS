extends Node3D
## Projectile simulation: every bullet is integrated with gravity and drag
## and swept with ray casts each physics tick (bullet drop + travel time).
## Yukkuri Strike - created by ゆっくりP

const Fx := preload("res://scripts/game/fx.gd")
const Mats := preload("res://scripts/game/textures.gd")
const G := 9.81

var match_node: Node
var bullets: Array = []

func fire(origin: Vector3, velocity: Vector3, w: Dictionary, weapon_id: String, shooter: Node, authoritative: bool, tracer: bool, source: Node = null) -> void:
	if source == null:
		source = shooter
	var b := {"src": source, "p": origin, "v": velocity, "w": w, "id": weapon_id, "shooter": shooter, "auth": authoritative,
		"life": 4.0 if not w.get("rocket", false) else 8.0, "origin": origin, "mesh": null, "whizzed": false}
	if w.get("rocket", false):
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.07
		cm.height = 0.8
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = Mats.olive_paint()
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.25)
		glow.light_energy = 3.0
		glow.omni_range = 6.0
		mi.add_child(glow)
		var trail := CPUParticles3D.new()
		trail.amount = 60
		trail.lifetime = 1.6
		trail.local_coords = false
		var q := QuadMesh.new()
		q.material = Mats.soft_particle(Color.WHITE)
		trail.mesh = q
		trail.gravity = Vector3(0, 0.6, 0)
		trail.spread = 10.0
		trail.initial_velocity_min = 0.2
		trail.initial_velocity_max = 0.8
		trail.scale_amount_min = 0.5
		trail.scale_amount_max = 1.2
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.85, 0.6, 0.9))
		g.add_point(0.1, Color(0.7, 0.7, 0.68, 0.6))
		g.set_color(g.get_point_count() - 1, Color(0.8, 0.8, 0.78, 0.0))
		trail.color_ramp = g
		mi.add_child(trail)
		add_child(mi)
		mi.global_position = origin
		b.mesh = mi
	elif tracer:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.02, 1.0)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.7, 0.35)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.65, 0.3)
		m.emission_energy_multiplier = 6.0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = origin
		b.mesh = mi
	bullets.append(b)

func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		if _step(b, delta, space):
			if b.mesh:
				b.mesh.queue_free()
			bullets.remove_at(i)
		i -= 1

func _step(b: Dictionary, dt: float, space: PhysicsDirectSpaceState3D) -> bool:
	b.life -= dt
	if b.life <= 0.0:
		return true
	var w: Dictionary = b.w
	var v: Vector3 = b.v
	v.y -= G * w.get("gravity", 1.0) * dt
	v -= v * v.length() * w.drag * dt
	var from: Vector3 = b.p
	var to: Vector3 = from + v * dt
	b.v = v
	var qp := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8 | 16)
	qp.collide_with_areas = true
	qp.hit_back_faces = false
	if is_instance_valid(b.src) and b.src.has_method("get_exclude_rids"):
		qp.exclude = b.src.get_exclude_rids()
	var hit := space.intersect_ray(qp)
	_update_whiz(b, from, to)
	if hit.is_empty():
		b.p = to
		if b.mesh:
			b.mesh.global_position = to
			if v.length() > 1.0:
				b.mesh.look_at(to + v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
				if not w.get("rocket", false):
					b.mesh.scale = Vector3(1, 1, clampf(v.length() * dt * 0.9, 0.5, 14.0))
		return false
	var pos: Vector3 = hit.position
	var col: Object = hit.collider
	var dist := pos.distance_to(b.origin)
	if w.get("rocket", false):
		if b.auth:
			match_node.request_explosion(pos - v.normalized() * 0.3, w.radius, w.dmg, b.shooter if is_instance_valid(b.shooter) else null, b.id)
		return true
	var f: Array = w.falloff
	var dmg: float = w.dmg * lerpf(1.0, f[2], clampf((dist - f[0]) / maxf(1.0, f[1] - f[0]), 0.0, 1.0))
	if col is Area3D and col.has_meta("soldier"):
		var s: Node = col.get_meta("soldier")
		var head: bool = col.get_meta("part") == "head"
		Fx.impact(self, pos, hit.normal, true)
		if b.auth:
			match_node.report_hit(b.shooter if is_instance_valid(b.shooter) else null, s, dmg * (w.mult_head if head else 1.0), head, b.id)
		return true
	if col and col.has_meta("vehicle"):
		Fx.impact(self, pos, hit.normal, false, false)
		Sfx.play_at("impact", pos, self, -2.0, 80.0)
		if b.auth:
			match_node.report_vehicle_hit(b.shooter if is_instance_valid(b.shooter) else null, col.get_meta("vehicle"), dmg * (0.35 if b.id == "dmr" else 0.12), b.id)
		return true
	var dirt := col != null and col.has_meta("terrain")
	Fx.impact(self, pos, hit.normal, false, dirt)
	Sfx.play_at("impact", pos, self, -8.0, 60.0)
	return true

func _update_whiz(b: Dictionary, from: Vector3, to: Vector3) -> void:
	if b.whizzed or match_node == null or match_node.local_player == null:
		return
	var lp: Node3D = match_node.local_player
	if b.shooter == lp or not lp.alive:
		return
	var head: Vector3 = lp.global_position + Vector3(0, 1.6, 0)
	var closest := Geometry3D.get_closest_point_to_segment(head, from, to)
	if closest.distance_to(head) < 2.5 and closest != from and closest != to:
		b.whizzed = true
		Sfx.play("whiz", -4.0, randf_range(0.9, 1.2))
		lp.suppress(1.0 - closest.distance_to(head) / 2.5)
