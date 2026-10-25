extends RefCounted
## Visual effects: muzzle flash, impacts, tracers, explosions, debris.
## Yukkuri Strike - created by ゆっくりP

const Mats := preload("res://scripts/game/textures.gd")

static var _debris_alive := 0

static func _particles(parent: Node, pos: Vector3, amount: int, life: float, color_ramp: Gradient, size_min: float, size_max: float,
		vel_min: float, vel_max: float, spread: float, gravity: Vector3, add := false, dir := Vector3.UP, damp := 0.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = Mats.soft_particle(Color.WHITE, add)
	p.mesh = q
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = gravity
	p.damping_min = damp
	p.damping_max = damp
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = c
	p.color_ramp = color_ramp
	p.angle_min = 0
	p.angle_max = 360
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p

static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(cols)
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / maxf(1, cols.size() - 1))
	g.offsets = offs
	return g

static func flash_light(parent: Node, pos: Vector3, color: Color, energy: float, range_m: float, time: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	tw.tween_callback(l.queue_free)

static func impact(parent: Node, pos: Vector3, normal: Vector3, is_flesh := false, is_dirt := true) -> void:
	if is_flesh:
		_particles(parent, pos, 10, 0.4, _ramp([Color(0.5, 0.02, 0.02, 0.9), Color(0.3, 0.0, 0.0, 0.0)]), 0.1, 0.25, 1.0, 3.0, 35, Vector3(0, -6, 0), false, normal)
		return
	var dust_col := Color(0.45, 0.39, 0.3, 0.75) if is_dirt else Color(0.7, 0.68, 0.64, 0.7)
	_particles(parent, pos, 8, 0.9, _ramp([dust_col, Color(dust_col.r, dust_col.g, dust_col.b, 0)]), 0.2, 0.6, 0.8, 3.0, 25, Vector3(0, -1.5, 0), false, normal, 2.0)
	_particles(parent, pos, 6, 0.25, _ramp([Color(1, 0.8, 0.4, 1), Color(1, 0.5, 0.1, 0)]), 0.03, 0.06, 4.0, 9.0, 40, Vector3(0, -9, 0), true, normal)
	decal(parent, pos, normal, 0.12, Color(0.05, 0.04, 0.03, 0.9))

static func decal(parent: Node, pos: Vector3, normal: Vector3, size: float, color: Color) -> void:
	if Settings.quality == Settings.Quality.LOW:
		return
	var d := Decal.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 32
	gt.height = 32
	d.texture_albedo = gt
	d.modulate = color
	d.size = Vector3(size, 0.3, size)
	parent.add_child(d)
	d.global_position = pos
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	d.global_basis = Basis(side, up, side.cross(up))
	d.cull_mask = 1
	parent.get_tree().create_timer(25.0).timeout.connect(d.queue_free)

static func muzzle(parent: Node3D, local_pos: Vector3, scale := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35) * scale
	mi.mesh = q
	mi.material_override = Mats.emissive(Color(1.0, 0.72, 0.35), 6.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = local_pos
	mi.rotation.z = randf() * TAU
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.6, 0.05)
	tw.tween_callback(mi.queue_free)

static func tracer(parent: Node, from: Vector3, to: Vector3, color := Color(1.0, 0.75, 0.4)) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, minf(len, 6.0))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = to
	mi.look_at_from_position(from.lerp(to, 0.5), to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to, 0.05)
	tw.tween_callback(mi.queue_free)

static func explosion(parent: Node, pos: Vector3, radius: float) -> void:
	var s := radius / 6.0
	_particles(parent, pos, 26, 0.7, _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 0.9), Color(0.4, 0.15, 0.05, 0.0)]), 1.8 * s, 3.5 * s, 3.0, 14.0 * s, 180, Vector3(0, 2, 0), true, Vector3.UP, 4.0)
	_particles(parent, pos + Vector3(0, 1, 0), 34, 4.5, _ramp([Color(0.22, 0.2, 0.18, 0.85), Color(0.35, 0.33, 0.3, 0.5), Color(0.5, 0.48, 0.45, 0.0)]), 3.0 * s, 6.0 * s, 2.0, 9.0 * s, 70, Vector3(0, 1.2, 0), false, Vector3.UP, 1.5)
	_particles(parent, pos, 40, 1.6, _ramp([Color(1, 0.8, 0.4, 1), Color(1, 0.4, 0.1, 0)]), 0.06, 0.14, 12.0, 30.0 * s, 80, Vector3(0, -9.8, 0), true, Vector3.UP)
	_particles(parent, pos, 30, 2.5, _ramp([Color(0.4, 0.33, 0.24, 0.9), Color(0.4, 0.33, 0.24, 0)]), 0.6, 1.6, 6.0, 16.0 * s, 50, Vector3(0, -9.8, 0), false, Vector3.UP, 0.5)
	flash_light(parent, pos + Vector3(0, 1.5, 0), Color(1.0, 0.65, 0.3), 16.0, radius * 4.0, 0.6)
	decal(parent, pos, Vector3.UP, radius * 1.4, Color(0.03, 0.03, 0.03, 0.85))

static func debris(parent: Node, positions: Array, center: Vector3, mat: Material, max_count: int) -> void:
	var n := 0
	for p in positions:
		if n >= max_count or _debris_alive > max_count * 2:
			break
		n += 1
		_debris_alive += 1
		var rb := RigidBody3D.new()
		rb.collision_layer = 16
		rb.collision_mask = 1 | 16
		rb.mass = 20.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz := Vector3(randf_range(0.3, 0.7), randf_range(0.25, 0.6), randf_range(0.25, 0.5))
		bs.size = sz
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = mat
		rb.add_child(mi)
		parent.add_child(rb)
		rb.global_position = p
		rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir: Vector3 = (p - center).normalized() + Vector3(0, 0.5, 0)
		rb.linear_velocity = dir * randf_range(4.0, 11.0)
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		var t := parent.get_tree().create_timer(randf_range(7.0, 11.0))
		t.timeout.connect(func():
			_debris_alive -= 1
			if is_instance_valid(rb):
				var tw := rb.create_tween()
				tw.tween_property(rb, "scale", Vector3.ONE * 0.01, 0.6)
				tw.tween_callback(rb.queue_free))
	if positions.size() > 0:
		_particles(parent, center, 22, 5.0, _ramp([Color(0.62, 0.57, 0.49, 0.8), Color(0.62, 0.57, 0.49, 0.0)]), 2.5, 5.0, 1.0, 5.0, 90, Vector3(0, -0.3, 0), false, Vector3.UP, 1.0)
