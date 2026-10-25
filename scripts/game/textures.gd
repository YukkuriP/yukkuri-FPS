extends RefCounted
## Procedural texture + material factory. Resolution scales with the quality
## preset so mobile builds use small textures (and ETC2/ASTC VRAM import).
## Yukkuri Strike - created by ゆっくりP

static var _cache := {}

static func noise_tex(key: String, freq: float, size: int, normal := false, octaves := 5, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, bump := 6.0) -> NoiseTexture2D:
	var ck := "%s_%d_%s" % [key, size, normal]
	if _cache.has(ck):
		return _cache[ck]
	var n := FastNoiseLite.new()
	n.seed = hash(key) & 0xffff
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	_cache[ck] = t
	return t

static func tex_size() -> int:
	return Settings.q()["tex"]

static func terrain_material(towns: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	var s := tex_size()
	m.set_shader_parameter("n_detail", noise_tex("terrain_detail", 0.02, s))
	m.set_shader_parameter("n_macro", noise_tex("terrain_macro", 0.006, 256, false, 4))
	m.set_shader_parameter("n_normal", noise_tex("terrain_normal", 0.03, s, true, 6, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 9.0))
	var arr := PackedVector4Array()
	for t in towns:
		arr.append(Vector4(t.x, t.z, t.w if t is Vector4 else 60.0, 0))
	while arr.size() < 6:
		arr.append(Vector4.ZERO)
	m.set_shader_parameter("towns", arr)
	m.set_shader_parameter("town_count", towns.size())
	return m

static func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("n_normal", noise_tex("water_normal", 0.04, mini(tex_size(), 512), true, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4.0))
	return m

static func foliage_material(base: Color, tip: Color, height: float, sway: float, fade_start := 0.0, fade_end := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("height", height)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("fade_start", fade_start)
	m.set_shader_parameter("fade_end", fade_end)
	m.set_shader_parameter("n_detail", noise_tex("foliage", 0.08, 256))
	return m

## Generic PBR surface with noise-driven albedo variation and normal map.
static func pbr(key: String, color: Color, rough: float, metal := 0.0, normal_strength := 1.0, scale := 1.0, vertex_color := false) -> StandardMaterial3D:
	var ck := "mat_" + key
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	var s := mini(tex_size(), 512)
	var g := Gradient.new()
	g.set_color(0, Color(0.84, 0.84, 0.84))
	g.set_color(1, Color(1.0, 1.0, 1.0))
	var nt := noise_tex(key + "_alb", 0.09, s, false, 5)
	var alb := NoiseTexture2D.new()
	alb.width = s
	alb.height = s
	alb.seamless = true
	alb.noise = nt.noise
	alb.color_ramp = g
	m.albedo_texture = alb
	m.normal_enabled = normal_strength > 0.0
	if m.normal_enabled:
		m.normal_texture = noise_tex(key + "_nrm", 0.05, s, true, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 5.0)
		m.normal_scale = normal_strength * 0.45
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.35 * scale
	m.vertex_color_use_as_albedo = vertex_color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[ck] = m
	return m

static func plaster() -> StandardMaterial3D:
	return pbr("plaster", Color(0.78, 0.72, 0.62), 0.92, 0.0, 1.2, 1.0, true)

static func concrete() -> StandardMaterial3D:
	return pbr("concrete", Color(0.55, 0.55, 0.53), 0.88, 0.0, 1.0, 1.4, true)

static func metal_dark() -> StandardMaterial3D:
	return pbr("gunmetal", Color(0.11, 0.115, 0.12), 0.38, 0.85, 0.4, 3.0)

static func polymer() -> StandardMaterial3D:
	return pbr("polymer", Color(0.16, 0.15, 0.13), 0.62, 0.0, 0.3, 4.0)

static func tan_polymer() -> StandardMaterial3D:
	return pbr("tan_polymer", Color(0.55, 0.47, 0.34), 0.66, 0.0, 0.3, 4.0)

static func olive_paint() -> StandardMaterial3D:
	return pbr("olive", Color(0.29, 0.32, 0.2), 0.58, 0.25, 0.6, 1.0)

static func sand_paint() -> StandardMaterial3D:
	return pbr("sandpaint", Color(0.58, 0.5, 0.36), 0.6, 0.25, 0.6, 1.0)

static func rubber() -> StandardMaterial3D:
	return pbr("rubber", Color(0.06, 0.06, 0.06), 0.9, 0.0, 0.5, 2.0)

static func fabric(color: Color, key: String) -> StandardMaterial3D:
	return pbr("fabric_" + key, color, 0.95, 0.0, 0.8, 3.0)

static func wood() -> StandardMaterial3D:
	return pbr("wood", Color(0.36, 0.25, 0.15), 0.8, 0.0, 0.8, 1.0)

static func rock() -> StandardMaterial3D:
	return pbr("rock", Color(0.45, 0.43, 0.4), 0.9, 0.0, 1.6, 0.8)

static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	return m

static func soft_particle(color: Color, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	m.proximity_fade_enabled = not Settings.is_mobile
	m.proximity_fade_distance = 1.5
	return m
