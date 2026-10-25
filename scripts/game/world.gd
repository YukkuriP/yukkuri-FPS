extends Node3D
## Deterministic procedural battlefield: 1.28 km island terrain with LOD chunks,
## towns of destructible buildings, forests, rocks, grass, ocean and lighting.
## Every client builds the identical map from the same seed.
## Yukkuri Strike - created by ゆっくりP

const Mats := preload("res://scripts/game/textures.gd")
const Building := preload("res://scripts/game/building.gd")
const Fx := preload("res://scripts/game/fx.gd")

const SIZE := 1280.0
const STEP := 2.5
const N := 513 # SIZE / STEP + 1
const CHUNKS := 8
const SEA := 0.0
const HALF := SIZE * 0.5

var seed_value := 0
var dirty := false
var heights := PackedFloat32Array()
var town_centers: Array[Vector3] = []
var towns: Array[Vector4] = [] # x, y, z, radius
var buildings: Array = []
var spawns := {0: [], 1: []}
var vehicle_spawns: Array = [] # [team, kind, Transform3D]
var env: WorldEnvironment
var sun: DirectionalLight3D
var q: Dictionary

var _n_base := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_warp := FastNoiseLite.new()

func build(seed_val: int) -> void:
	seed_value = seed_val
	q = Settings.q()
	var t0 := Time.get_ticks_msec()
	_n_base.seed = seed_val
	_n_base.frequency = 0.0024
	_n_base.fractal_octaves = 5
	_n_ridge.seed = seed_val + 1
	_n_ridge.frequency = 0.0055
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 4
	_n_warp.seed = seed_val + 2
	_n_warp.frequency = 0.03
	_layout_towns()
	_generate_heights()
	_build_environment()
	_build_terrain()
	_build_water_and_bounds()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	_build_towns(rng)
	_build_bases(rng)
	_build_trees(rng)
	_build_rocks(rng)
	_build_grass(rng)
	print("[world] built in %d ms (quality=%d)" % [Time.get_ticks_msec() - t0, Settings.quality])

# ------------------------------------------------------------------ heights
func _raw_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length() / (HALF - 40.0)
	var h := 7.0 + _n_base.get_noise_2d(x, z) * 30.0
	var ridge := _n_ridge.get_noise_2d(x, z)
	h += maxf(0.0, ridge) * 26.0 * smoothstep(0.25, 0.7, d)
	h += smoothstep(0.55, 0.82, d) * 34.0 * (0.6 + 0.4 * _n_base.get_noise_2d(x * 2.1, z * 2.1))
	h = lerpf(h, -14.0, smoothstep(0.86, 1.0, d))
	return h

func _layout_towns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 99
	var defs := [Vector3(0, 0, 0), Vector3(rng.randf_range(-40, 60), 0, -240), Vector3(rng.randf_range(-60, 40), 0, 235), Vector3(-310, 0, 0), Vector3(310, 0, 0)]
	var radii := [78.0, 52.0, 52.0, 34.0, 34.0]
	towns.clear()
	town_centers.clear()
	for i in defs.size():
		var c: Vector3 = defs[i]
		var y := maxf(_raw_height(c.x, c.z), 4.0)
		towns.append(Vector4(c.x, y, c.z, radii[i]))
		town_centers.append(Vector3(c.x, y, c.z))

func _height_fn(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	for t in towns:
		var dist := Vector2(x - t.x, z - t.z).length()
		var w := 1.0 - smoothstep(t.w * 0.95, t.w * 1.9, dist)
		h = lerpf(h, t.y, w)
	return h

func _generate_heights() -> void:
	heights.resize(N * N)
	for j in N:
		var z := -HALF + j * STEP
		for i in N:
			heights[j * N + i] = _height_fn(-HALF + i * STEP, z)

func _h(i: int, j: int) -> float:
	return heights[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]

## Bilinear ground height that matches the collision heightmap.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(_h(i, j), _h(i + 1, j), tx)
	var b := lerpf(_h(i, j + 1), _h(i + 1, j + 1), tx)
	return lerpf(a, b, tz)

func normal_at(x: float, z: float) -> Vector3:
	var hl := height_at(x - STEP, z)
	var hr := height_at(x + STEP, z)
	var hd := height_at(x, z - STEP)
	var hu := height_at(x, z + STEP)
	return Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()

func in_town(x: float, z: float, margin := 0.0) -> bool:
	for t in towns:
		if Vector2(x - t.x, z - t.z).length() < t.w + margin:
			return true
	return false

# ------------------------------------------------------------- environment
func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.39, 0.62)
	sm.sky_horizon_color = Color(0.72, 0.72, 0.68)
	sm.ground_bottom_color = Color(0.16, 0.15, 0.13)
	sm.ground_horizon_color = Color(0.62, 0.6, 0.55)
	sm.sun_angle_max = 18.0
	sm.sun_curve = 0.08
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if Settings.is_mobile else Sky.RADIANCE_SIZE_256
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(0.62, 0.67, 0.74)
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_energy = 1.4
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.tonemap_white = 6.0
	e.glow_enabled = q.glow
	e.glow_intensity = 0.55
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.2
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.ssao_enabled = q.ssao
	e.ssao_radius = 1.4
	e.ssao_intensity = 2.2
	e.ssao_power = 1.6
	e.ssil_enabled = q.ssil
	e.ssr_enabled = q.ssr
	e.fog_enabled = true
	e.fog_light_color = Color(0.68, 0.71, 0.74)
	e.fog_density = 0.0011
	e.fog_aerial_perspective = 0.6
	e.fog_sky_affect = 0.25
	e.fog_height = 20.0
	e.fog_height_density = 0.004
	e.volumetric_fog_enabled = q.vol_fog
	e.volumetric_fog_density = 0.006
	e.volumetric_fog_albedo = Color(0.85, 0.85, 0.82)
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 120.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 0.92
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, -38, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = q.shadows
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = q.shadow_dist
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if Settings.is_mobile else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = not Settings.is_mobile
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)

## Apply per-viewport quality (render scale, AA) – called when a camera goes live.
func apply_viewport_quality(vp: Viewport) -> void:
	vp.scaling_3d_scale = q.scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q.fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.use_taa = q.taa and not Settings.is_mobile
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not vp.use_taa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 2.0 if Settings.is_mobile else 1.0

# ------------------------------------------------------------------ terrain
func _build_terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	body.set_meta("terrain", true)
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	var scaled := PackedFloat32Array()
	scaled.resize(N * N)
	for k in N * N:
		scaled[k] = heights[k] / STEP
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * STEP
	body.add_child(cs)

	var mat := Mats.terrain_material(towns)
	var cells := (N - 1) / CHUNKS
	var hi_step := 2 if Settings.quality == Settings.Quality.LOW else 1
	var hi_end := 320.0 if not Settings.is_mobile else 200.0
	for cz in CHUNKS:
		for cx in CHUNKS:
			var hi := MeshInstance3D.new()
			hi.mesh = _chunk_mesh(cx * cells, cz * cells, cells, hi_step)
			hi.material_override = mat
			hi.visibility_range_end = hi_end
			hi.visibility_range_end_margin = 20.0
			hi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			add_child(hi)
			var lo := MeshInstance3D.new()
			lo.mesh = _chunk_mesh(cx * cells, cz * cells, cells, 8)
			lo.material_override = mat
			lo.visibility_range_begin = hi_end
			lo.visibility_range_begin_margin = 20.0
			lo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lo)

func _chunk_mesh(i0: int, j0: int, cells: int, step: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := cells / step + 1
	for jj in n:
		for ii in n:
			var i := i0 + ii * step
			var j := j0 + jj * step
			verts.append(Vector3(-HALF + i * STEP, _h(i, j), -HALF + j * STEP))
			norms.append(Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * STEP, _h(i, j - 1) - _h(i, j + 1)).normalized())
	for jj in n - 1:
		for ii in n - 1:
			var a := jj * n + ii
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# skirts hide cracks between LOD levels
	var edges := [[], [], [], []]
	for k in n:
		edges[0].append(k)
		edges[1].append((n - 1) * n + k)
		edges[2].append(k * n)
		edges[3].append(k * n + n - 1)
	for e in 4:
		var base := verts.size()
		for k in n:
			var v: Vector3 = verts[edges[e][k]]
			verts.append(v - Vector3(0, 3.0 * step, 0))
			norms.append(norms[edges[e][k]])
		for k in n - 1:
			var a: int = edges[e][k]
			var b: int = edges[e][k + 1]
			idx.append_array([a, base + k, b, b, base + k, base + k + 1])
			idx.append_array([a, b, base + k, b, base + k + 1, base + k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _build_water_and_bounds() -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE * 3.0, SIZE * 3.0)
	pm.subdivide_width = 48
	pm.subdivide_depth = 48
	water.mesh = pm
	water.material_override = Mats.water_material()
	water.position.y = SEA
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var b := StaticBody3D.new()
	b.collision_layer = 1
	add_child(b)
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var cs := CollisionShape3D.new()
		var ws := WorldBoundaryShape3D.new()
		ws.plane = Plane(-d, -(HALF - 30.0))
		cs.shape = ws
		b.add_child(cs)

# -------------------------------------------------------------- settlements
const TINTS := [Color(0.86, 0.8, 0.68), Color(0.93, 0.9, 0.84), Color(0.8, 0.66, 0.48), Color(0.72, 0.74, 0.74), Color(0.85, 0.74, 0.6)]

func _add_building(rng: RandomNumberGenerator, pos: Vector3, rot: float, w: int, d: int, floors: int, wall_only := false) -> void:
	var b := Building.new()
	b.world = self
	add_child(b)
	b.position = pos
	b.rotation.y = rot
	b.generate(rng, w, d, floors, TINTS[rng.randi() % TINTS.size()], wall_only)
	buildings.append(b)

func _build_towns(rng: RandomNumberGenerator) -> void:
	# main town: street grid
	var t := towns[0]
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if gx == 0 and gz == 0:
				continue
			if abs(gx) == 2 and abs(gz) == 2:
				continue
			var p := Vector3(t.x + gx * 25.0 + rng.randf_range(-2, 2), t.y, t.z + gz * 25.0 + rng.randf_range(-2, 2))
			var w := rng.randi_range(8, 14)
			var d := rng.randi_range(8, 12)
			var floors := 1 + int(rng.randf() < 0.55) + int(rng.randf() < 0.2)
			_add_building(rng, p, (PI * 0.5) * (rng.randi() % 4), w, d, floors)
	_scatter_props(rng, t, 34)
	# villages
	for k in [1, 2]:
		var v := towns[k]
		var placed: Array[Vector3] = []
		var tries := 0
		while placed.size() < 6 and tries < 80:
			tries += 1
			var ang := rng.randf() * TAU
			var r := rng.randf_range(8.0, v.w * 0.7)
			var p := Vector3(v.x + cos(ang) * r, v.y, v.z + sin(ang) * r)
			var ok := true
			for o in placed:
				if o.distance_to(p) < 17.0:
					ok = false
			if not ok:
				continue
			placed.append(p)
			_add_building(rng, p, rng.randf() * TAU, rng.randi_range(7, 11), rng.randi_range(7, 10), 1 + int(rng.randf() < 0.35))
		_add_building(rng, Vector3(v.x, v.y, v.z + v.w * 0.85), 0.0, 18, 1, 1, true)
		_scatter_props(rng, v, 14)

func _build_bases(rng: RandomNumberGenerator) -> void:
	for team in [0, 1]:
		var b := towns[3 + team]
		var face := 1.0 if team == 0 else -1.0
		for k in 10:
			var p := Vector3(b.x - face * 8.0 + rng.randf_range(-3, 3), 0, b.z + (k - 4.5) * 3.2)
			p.y = height_at(p.x, p.z) + 0.1
			spawns[team].append(p)
		vehicle_spawns.append([team, "jeep", Transform3D(Basis(Vector3.UP, -PI * 0.5 * face), Vector3(b.x + face * 10.0, b.y + 1.2, b.z - 12.0))])
		vehicle_spawns.append([team, "jeep", Transform3D(Basis(Vector3.UP, -PI * 0.5 * face), Vector3(b.x + face * 10.0, b.y + 1.2, b.z + 12.0))])
		vehicle_spawns.append([team, "tank", Transform3D(Basis(Vector3.UP, -PI * 0.5 * face), Vector3(b.x + face * 14.0, b.y + 1.4, b.z))])
		_add_building(rng, Vector3(b.x - face * 20.0, b.y, b.z - 16.0), 0.0, 10, 8, 1)
		_add_building(rng, Vector3(b.x + face * 24.0, b.y, b.z), PI * 0.5, 22, 1, 1, true)
		_scatter_props(rng, b, 8)

func _static_box(pos: Vector3, size: Vector3, rot: float, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	sb.position = pos
	sb.rotation.y = rot

func _scatter_props(rng: RandomNumberGenerator, t: Vector4, count: int) -> void:
	var sand := Mats.fabric(Color(0.55, 0.48, 0.34), "sandbag")
	for k in count:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(4.0, t.w * 0.95)
		var p := Vector3(t.x + cos(ang) * r, 0, t.z + sin(ang) * r)
		p.y = height_at(p.x, p.z)
		if _near_building(p, 2.5):
			continue
		match rng.randi() % 4:
			0: # sandbag wall
				_static_box(p + Vector3(0, 0.5, 0), Vector3(3.2, 1.0, 0.7), rng.randf() * TAU, sand)
			1: # crate stack
				var s := rng.randf_range(1.0, 1.4)
				_static_box(p + Vector3(0, s * 0.5, 0), Vector3(s, s, s), rng.randf() * TAU, Mats.wood())
				if rng.randf() < 0.5:
					_static_box(p + Vector3(0.1, s * 1.5, 0.05), Vector3(s, s, s) * 0.9, rng.randf() * TAU, Mats.wood())
			2: # concrete barrier
				_static_box(p + Vector3(0, 0.55, 0), Vector3(2.6, 1.1, 0.55), rng.randf() * TAU, Mats.concrete())
			3: # burnt car hulk
				var rot := rng.randf() * TAU
				_static_box(p + Vector3(0, 0.75, 0), Vector3(1.9, 0.9, 4.3), rot, Mats.metal_dark())
				_static_box(p + Vector3(0, 1.45, 0), Vector3(1.6, 0.6, 2.2), rot, Mats.metal_dark())

func _near_building(p: Vector3, margin: float) -> bool:
	for b in buildings:
		var lp: Vector3 = b.to_local(p)
		if b.aabb.grow(margin).has_point(Vector3(lp.x, 0.5, lp.z)):
			return true
	return false

# --------------------------------------------------------------- vegetation
func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		st.append_from(part[0], 0, part[1])
	st.generate_normals()
	return st.commit()

func _pine_meshes() -> Array:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.3
	trunk.height = 9.0
	trunk.radial_segments = 6
	var parts := []
	for k in 5:
		var c := CylinderMesh.new()
		c.top_radius = 0.05
		c.bottom_radius = 2.3 - k * 0.38
		c.height = 3.0 - k * 0.25
		c.radial_segments = 9
		c.rings = 1
		parts.append([c, Transform3D(Basis(Vector3.UP, k * 0.7), Vector3(0, 3.2 + k * 1.45, 0))])
	return [_merge([[trunk, Transform3D(Basis(), Vector3(0, 4.5, 0))]]), _merge(parts)]

func _broadleaf_meshes() -> Array:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.32
	trunk.height = 5.0
	trunk.radial_segments = 6
	var parts := []
	var offs := [Vector3(0, 5.6, 0), Vector3(1.3, 4.9, 0.4), Vector3(-1.1, 5.0, -0.6), Vector3(0.2, 6.6, -0.3), Vector3(-0.3, 4.8, 1.2)]
	for o in offs:
		var s := SphereMesh.new()
		s.radius = 1.7
		s.height = 2.9
		s.radial_segments = 8
		s.rings = 5
		parts.append([s, Transform3D(Basis(), o)])
	return [_merge([[trunk, Transform3D(Basis(), Vector3(0, 2.5, 0))]]), _merge(parts)]

func _build_trees(rng: RandomNumberGenerator) -> void:
	var pine := _pine_meshes()
	var broad := _broadleaf_meshes()
	var trunk_mat := Mats.pbr("bark", Color(0.27, 0.2, 0.14), 0.95, 0.0, 1.4, 2.0)
	var pine_mat := Mats.foliage_material(Color(0.07, 0.13, 0.06), Color(0.16, 0.25, 0.1), 12.0, 0.18)
	var broad_mat := Mats.foliage_material(Color(0.12, 0.19, 0.06), Color(0.32, 0.4, 0.14), 8.0, 0.3)
	var forest := FastNoiseLite.new()
	forest.seed = seed_value + 7
	forest.frequency = 0.006
	var cells := 4
	var cell_size := SIZE / cells
	var buckets := {}
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 7.0
	var placed := 0
	var tries := 0
	var target: int = q.trees
	while placed < target and tries < target * 12:
		tries += 1
		var x := rng.randf_range(-HALF + 60, HALF - 60)
		var z := rng.randf_range(-HALF + 60, HALF - 60)
		if forest.get_noise_2d(x, z) < -0.05 and rng.randf() > 0.08:
			continue
		var y := height_at(x, z)
		if y < SEA + 2.5 or normal_at(x, z).y < 0.82 or in_town(x, z, 8.0):
			continue
		var kind := 0 if (y > 18.0 or rng.randf() < 0.6) else 1
		var key := Vector3i(int((x + HALF) / cell_size), kind, int((z + HALF) / cell_size))
		if not buckets.has(key):
			buckets[key] = []
		var s := rng.randf_range(0.75, 1.35)
		buckets[key].append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, y - 0.2, z)), Color.from_hsv(rng.randf_range(0.0, 0.08), rng.randf_range(0.0, 0.25), rng.randf_range(0.8, 1.15))])
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(x, y + 3.3, z)
		body.add_child(cs)
		placed += 1
	for key in buckets.keys():
		var items: Array = buckets[key]
		var meshes: Array = pine if key.y == 0 else broad
		for part in 2:
			var mmi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = part == 1
			mm.mesh = meshes[part]
			mm.instance_count = items.size()
			for k in items.size():
				mm.set_instance_transform(k, items[k][0])
				if part == 1:
					mm.set_instance_color(k, items[k][1])
			mmi.multimesh = mm
			mmi.material_override = trunk_mat if part == 0 else (pine_mat if key.y == 0 else broad_mat)
			mmi.visibility_range_end = q.view
			add_child(mmi)

func _build_rocks(rng: RandomNumberGenerator) -> void:
	var variants := []
	for v in 3:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.6
		sm.radial_segments = 12
		sm.rings = 7
		var arr := sm.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nz := FastNoiseLite.new()
		nz.seed = seed_value + 30 + v
		nz.frequency = 1.1
		for k in verts.size():
			var p: Vector3 = verts[k]
			verts[k] = p * (1.0 + nz.get_noise_3dv(p) * 0.45)
		arr[Mesh.ARRAY_VERTEX] = verts
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var st := SurfaceTool.new()
		st.create_from(m, 0)
		st.generate_normals()
		variants.append(st.commit())
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var lists := [[], [], []]
	for k in 260:
		var x := rng.randf_range(-HALF + 50, HALF - 50)
		var z := rng.randf_range(-HALF + 50, HALF - 50)
		var y := height_at(x, z)
		if y < SEA - 1.0 or in_town(x, z, 4.0):
			continue
		var s := rng.randf_range(0.6, 3.2) * (1.6 if normal_at(x, z).y < 0.85 else 1.0)
		var tr := Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.5, 0.9), s)), Vector3(x, y + s * 0.15, z))
		lists[k % 3].append(tr)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = s * 0.75
		cs.shape = sp
		cs.position = Vector3(x, y + s * 0.1, z)
		body.add_child(cs)
	for v in 3:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[v]
		mm.instance_count = lists[v].size()
		for k in lists[v].size():
			mm.set_instance_transform(k, lists[v][k])
		mmi.multimesh = mm
		mmi.material_override = Mats.rock()
		mmi.visibility_range_end = q.view
		add_child(mmi)

func _build_grass(rng: RandomNumberGenerator) -> void:
	var per_cell := int(q.grass / 150.0)
	if per_cell <= 0:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 14:
		var a := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var dir := Vector3(cos(a), 0, sin(a)) * 0.05
		var hgt := rng.randf_range(0.35, 0.75)
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		st.set_normal(Vector3.UP)
		st.add_vertex(off - dir)
		st.add_vertex(off + dir)
		st.add_vertex(off + lean + Vector3(0, hgt, 0))
	var mesh := st.commit()
	var mat := Mats.foliage_material(Color(0.12, 0.17, 0.06), Color(0.42, 0.45, 0.2), 0.7, 0.08, 45.0, 60.0)
	var cell := 32.0
	var extent := 340.0
	var x := -extent
	while x < extent:
		var z := -extent
		while z < extent:
			var items := []
			for k in per_cell:
				var px := x + rng.randf() * cell
				var pz := z + rng.randf() * cell
				var py := height_at(px, pz)
				if py < SEA + 2.0 or normal_at(px, pz).y < 0.85 or _in_town_core(px, pz):
					continue
				var s := rng.randf_range(0.7, 1.4)
				items.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(px, py - 0.05, pz)), Color.from_hsv(rng.randf_range(0.0, 0.1), rng.randf_range(0.0, 0.3), rng.randf_range(0.75, 1.2))])
			if items.size() > 0:
				var mmi := MultiMeshInstance3D.new()
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_colors = true
				mm.mesh = mesh
				mm.instance_count = items.size()
				for k in items.size():
					mm.set_instance_transform(k, items[k][0])
					mm.set_instance_color(k, items[k][1])
				mmi.multimesh = mm
				mmi.material_override = mat
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.visibility_range_end = 70.0
				add_child(mmi)
			z += cell
		x += cell

func _in_town_core(x: float, z: float) -> bool:
	for t in towns:
		if Vector2(x - t.x, z - t.z).length() < t.w * 0.75:
			return true
	return false

# ------------------------------------------------------------- destruction
func block_count() -> int:
	var n := 0
	for b in buildings:
		n += b.blocks.size()
	return n

## Deterministic explosion against all destructible structures.
func explode(pos: Vector3, radius: float) -> int:
	var destroyed := []
	for b in buildings:
		destroyed.append_array(b.explode(pos, radius))
	if destroyed.size() > 0:
		dirty = true
		Fx.debris(self, destroyed, pos, Mats.plaster(), q.debris)
		Sfx.play_at("debris", pos, self, 4.0)
	return destroyed.size()
