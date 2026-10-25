extends Node3D
## First-person weapon model with procedural sway, bob, recoil, ADS, reload
## and sprint poses (CoD-style feel without skeletal animation assets).
## Yukkuri Strike - created by ゆっくりP

const Mats := preload("res://scripts/game/textures.gd")
const Fx := preload("res://scripts/game/fx.gd")

const HIP := Vector3(0.17, -0.17, -0.36)
const SPRINT_ROT := Vector3(-0.25, 0.9, 0.35)

var models := {}
var current := ""
var muzzle_pos := {}
var ads_pos := {}
var _kick := 0.0
var _kick_rot := 0.0
var _sway := Vector2.ZERO
var _bob_t := 0.0
var _root: Node3D

func _ready() -> void:
	_root = Node3D.new()
	add_child(_root)
	for id in ["ar", "smg", "dmr", "rpg"]:
		var m := _build(id)
		m.visible = false
		_root.add_child(m)
		models[id] = m

func _part(p: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)

func _bx(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _cy(r: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	return c

func _build(id: String) -> Node3D:
	var g := Node3D.new()
	var metal := Mats.metal_dark()
	var poly := Mats.polymer()
	var tan := Mats.tan_polymer()
	var rx := Vector3(PI * 0.5, 0, 0)
	var glove := Mats.fabric(Color(0.12, 0.12, 0.1), "glove")
	var sleeve := Mats.fabric(Color(0.3, 0.33, 0.23), "sleeve")
	match id:
		"ar":
			_part(g, _bx(Vector3(0.05, 0.075, 0.34)), Vector3(0, 0, -0.05), metal)          # receiver
			_part(g, _bx(Vector3(0.056, 0.07, 0.26)), Vector3(0, 0.003, -0.33), tan)       # handguard
			_part(g, _cy(0.011, 0.24), Vector3(0, 0.012, -0.58), metal, rx)                 # barrel
			_part(g, _cy(0.018, 0.06), Vector3(0, 0.012, -0.7), metal, rx)                  # muzzle brake
			_part(g, _bx(Vector3(0.035, 0.15, 0.06)), Vector3(0, -0.1, -0.12), metal, Vector3(0.25, 0, 0)) # mag
			_part(g, _bx(Vector3(0.035, 0.1, 0.04)), Vector3(0, -0.075, 0.07), poly, Vector3(-0.3, 0, 0))  # grip
			_part(g, _bx(Vector3(0.045, 0.08, 0.22)), Vector3(0, -0.01, 0.22), tan)        # stock
			_part(g, _bx(Vector3(0.02, 0.012, 0.3)), Vector3(0, 0.045, -0.15), metal)      # rail
			_part(g, _bx(Vector3(0.042, 0.045, 0.07)), Vector3(0, 0.07, -0.08), poly)      # red dot body
			_part(g, _bx(Vector3(0.03, 0.03, 0.005)), Vector3(0, 0.075, -0.115), Mats.emissive(Color(1, 0.1, 0.05), 3.0)) # dot
			muzzle_pos[id] = Vector3(0, 0.012, -0.76)
			ads_pos[id] = Vector3(0, -0.075, -0.24)
		"smg":
			_part(g, _bx(Vector3(0.05, 0.08, 0.3)), Vector3(0, 0, -0.06), poly)
			_part(g, _cy(0.014, 0.12), Vector3(0, 0.01, -0.27), metal, rx)
			_part(g, _bx(Vector3(0.03, 0.2, 0.045)), Vector3(0, -0.13, -0.08), metal)
			_part(g, _bx(Vector3(0.035, 0.1, 0.04)), Vector3(0, -0.08, 0.05), poly, Vector3(-0.3, 0, 0))
			_part(g, _bx(Vector3(0.02, 0.05, 0.2)), Vector3(0, 0.0, 0.18), metal)
			_part(g, _bx(Vector3(0.012, 0.03, 0.01)), Vector3(0, 0.055, -0.18), metal)
			muzzle_pos[id] = Vector3(0, 0.01, -0.34)
			ads_pos[id] = Vector3(0, -0.068, -0.22)
		"dmr":
			_part(g, _bx(Vector3(0.055, 0.08, 0.42)), Vector3(0, 0, -0.05), Mats.olive_paint())
			_part(g, _cy(0.013, 0.5), Vector3(0, 0.01, -0.5), metal, rx)
			_part(g, _cy(0.02, 0.08), Vector3(0, 0.01, -0.78), metal, rx)
			_part(g, _cy(0.025, 0.3), Vector3(0, 0.09, -0.07), metal, rx)               # scope
			_part(g, _cy(0.032, 0.06), Vector3(0, 0.09, -0.24), metal, rx)
			_part(g, _bx(Vector3(0.04, 0.1, 0.05)), Vector3(0, -0.08, -0.05), metal)
			_part(g, _bx(Vector3(0.05, 0.1, 0.28)), Vector3(0, -0.02, 0.25), Mats.olive_paint())
			muzzle_pos[id] = Vector3(0, 0.01, -0.83)
			ads_pos[id] = Vector3(0, -0.09, -0.2)
		"rpg":
			_part(g, _cy(0.045, 1.0), Vector3(0, 0.0, -0.15), Mats.olive_paint(), rx)
			_part(g, _cy(0.07, 0.25, 10), Vector3(0, 0.0, -0.72), Mats.olive_paint(), rx)
			_part(g, _bx(Vector3(0.03, 0.1, 0.04)), Vector3(0, -0.09, -0.1), poly)
			_part(g, _bx(Vector3(0.05, 0.06, 0.08)), Vector3(-0.05, 0.06, -0.2), metal)
			muzzle_pos[id] = Vector3(0, 0, -0.85)
			ads_pos[id] = Vector3(0.05, -0.12, -0.3)
	# arms
	_part(g, _bx(Vector3(0.07, 0.07, 0.36)), Vector3(0.05, -0.1, 0.24), sleeve, Vector3(0.2, 0.15, 0))
	_part(g, _bx(Vector3(0.06, 0.08, 0.09)), Vector3(0.0, -0.08, 0.07), glove)
	_part(g, _bx(Vector3(0.07, 0.07, 0.4)), Vector3(-0.09, -0.1, -0.12), sleeve, Vector3(0.15, -0.35, 0))
	_part(g, _bx(Vector3(0.06, 0.06, 0.09)), Vector3(-0.02, -0.05, -0.3), glove)
	return g

func set_weapon(id: String) -> void:
	for k in models:
		models[k].visible = k == id
	current = id
	_root.position.y = -0.3

func kick(amount: float) -> void:
	_kick = minf(_kick + 0.035 * amount, 0.12)
	_kick_rot = minf(_kick_rot + 0.06 * amount, 0.3)
	var s := 1.6 if current == "dmr" or current == "rpg" else 1.0
	Fx.muzzle(models[current], muzzle_pos[current], s)
	Fx.flash_light(models[current], models[current].global_transform * muzzle_pos[current], Color(1, 0.75, 0.4), 2.5, 5.0, 0.06)

func update(delta: float, look_delta: Vector2, speed: float, ads: float, sprint: float, reload_t: float, on_floor: bool) -> void:
	_sway = _sway.lerp(look_delta * 0.0018, 1.0 - exp(-delta * 10.0))
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-delta * 14.0))
	_kick_rot = lerpf(_kick_rot, 0.0, 1.0 - exp(-delta * 10.0))
	if on_floor:
		_bob_t += delta * speed * 1.7
	var bob_amt := clampf(speed / 7.0, 0.0, 1.2) * (1.0 - ads * 0.85)
	var bob := Vector3(sin(_bob_t) * 0.012, -absf(cos(_bob_t)) * 0.012, 0) * bob_amt
	var hip_to_ads: Vector3 = HIP.lerp(ads_pos.get(current, HIP), ads)
	var target := hip_to_ads + bob + Vector3(-_sway.x, _sway.y, _kick) * (1.0 - ads * 0.6)
	var rot := Vector3(_kick_rot + _sway.y * 2.0, -_sway.x * 2.0, -_sway.x * 1.5)
	rot = rot.lerp(SPRINT_ROT, sprint)
	target += Vector3(-0.05, -0.04, 0.02) * sprint
	if reload_t > 0.0:
		var k := sin(clampf(reload_t, 0.0, 1.0) * PI)
		target += Vector3(0, -0.12, 0.05) * k
		rot += Vector3(-0.5, 0.2, 0.6) * k
	_root.position = _root.position.lerp(target, 1.0 - exp(-delta * 18.0))
	_root.rotation = _root.rotation.lerp(rot, 1.0 - exp(-delta * 14.0))
