extends CharacterBody3D
## Shared soldier body for the local player, bots and remote players:
## procedural humanoid model, head/body hitboxes, simple walk animation.
## Yukkuri Strike - created by ゆっくりP

const Mats := preload("res://scripts/game/textures.gd")

var team := 0
var display_name := "Soldier"
var hp := 100.0
var alive := true
var net_id := -1
var kills := 0
var deaths := 0
var crouching := false
var in_vehicle: Node = null
var weapon_id := "ar"
var match_node: Node
var model: Node3D
var head_box: Area3D
var body_box: Area3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm: Node3D
var _gun_model: Node3D
var _walk_t := 0.0
var _rids: Array[RID] = []

func setup_body(show_model: bool) -> void:
	collision_layer = 2
	set_meta("soldier_body", true)
	collision_mask = 1 | 8
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	cs.name = "Shape"
	add_child(cs)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(48)
	head_box = _hitbox("head", SphereShape3D.new(), Vector3(0, 1.62, 0))
	(head_box.get_child(0).shape as SphereShape3D).radius = 0.17
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.55, 1.35, 0.4)
	body_box = _hitbox("body", bb, Vector3(0, 0.78, 0))
	_rids = [get_rid(), head_box.get_rid(), body_box.get_rid()]
	if show_model:
		_build_model()

func _hitbox(part: String, shape: Shape3D, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 4
	a.collision_mask = 0
	a.monitoring = false
	a.set_meta("soldier", self)
	a.set_meta("part", part)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	add_child(a)
	return a

func get_exclude_rids() -> Array[RID]:
	return _rids

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_model() -> void:
	model = Node3D.new()
	add_child(model)
	var camo := Mats.fabric(Color(0.33, 0.36, 0.25) if team == 0 else Color(0.5, 0.42, 0.3), "camo%d" % team)
	var gear := Mats.fabric(Color(0.18, 0.19, 0.15) if team == 0 else Color(0.25, 0.2, 0.15), "gear%d" % team)
	var skin := Mats.pbr("skin", Color(0.72, 0.55, 0.42), 0.7, 0.0, 0.2)
	var band := Mats.emissive(Color(0.3, 0.6, 1.0) if team == 0 else Color(1.0, 0.3, 0.25), 1.5)
	band.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	band.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_box(model, Vector3(0.46, 0.62, 0.26), Vector3(0, 1.18, 0), camo)
	_box(model, Vector3(0.5, 0.42, 0.32), Vector3(0, 1.22, 0.0), gear) # plate carrier
	_box(model, Vector3(0.36, 0.2, 0.24), Vector3(0, 0.86, 0), gear)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.26
	head.mesh = sm
	head.material_override = skin
	head.position = Vector3(0, 1.6, 0)
	model.add_child(head)
	var helmet := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.15
	hm.height = 0.2
	hm.is_hemisphere = true
	helmet.mesh = hm
	helmet.material_override = camo
	helmet.position = Vector3(0, 1.66, 0)
	model.add_child(helmet)
	_box(model, Vector3(0.48, 0.05, 0.05), Vector3(0, 1.32, -0.15), band)
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.12, 0.82, 0)
	model.add_child(_leg_l)
	_box(_leg_l, Vector3(0.17, 0.82, 0.2), Vector3(0, -0.41, 0), camo)
	_box(_leg_l, Vector3(0.18, 0.12, 0.3), Vector3(0, -0.78, -0.05), gear)
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.12, 0.82, 0)
	model.add_child(_leg_r)
	_box(_leg_r, Vector3(0.17, 0.82, 0.2), Vector3(0, -0.41, 0), camo)
	_box(_leg_r, Vector3(0.18, 0.12, 0.3), Vector3(0, -0.78, -0.05), gear)
	_arm = Node3D.new()
	_arm.position = Vector3(0, 1.38, 0)
	model.add_child(_arm)
	_box(_arm, Vector3(0.12, 0.12, 0.5), Vector3(0.24, -0.08, -0.22), camo)
	_box(_arm, Vector3(0.12, 0.12, 0.55), Vector3(-0.12, -0.1, -0.3), camo)
	_gun_model = Node3D.new()
	_gun_model.position = Vector3(0.12, -0.08, -0.45)
	_arm.add_child(_gun_model)
	_box(_gun_model, Vector3(0.07, 0.12, 0.75), Vector3.ZERO, Mats.metal_dark())
	_box(_gun_model, Vector3(0.05, 0.16, 0.08), Vector3(0, -0.12, 0.05), Mats.polymer())

func animate_body(delta: float, speed: float, aim_pitch: float) -> void:
	if model == null:
		return
	_walk_t += delta * clampf(speed, 0.0, 9.0) * 1.6
	var swing := sin(_walk_t) * clampf(speed / 6.0, 0.0, 1.0) * 0.6
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_arm.rotation.x = aim_pitch
	model.position.y = -0.35 if crouching else 0.0
	model.visible = alive and in_vehicle == null

func set_dead(dead: bool) -> void:
	alive = not dead
	head_box.set_deferred("monitorable", not dead)
	body_box.set_deferred("monitorable", not dead)
	head_box.collision_layer = 0 if dead else 4
	body_box.collision_layer = 0 if dead else 4
	if model:
		model.visible = not dead
		if dead:
			model.rotation.x = 0.0

func suppress(_amount: float) -> void:
	pass
