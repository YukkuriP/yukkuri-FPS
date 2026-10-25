// Foliage: per-instance tint + wind sway weighted by vertex height.
// Yukkuri Strike - created by ゆっくりP
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 base_color : source_color = vec3(0.13, 0.2, 0.08);
uniform vec3 tip_color : source_color = vec3(0.3, 0.38, 0.14);
uniform float sway = 0.25;
uniform float height = 8.0;
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;
uniform sampler2D n_detail : hint_default_white, filter_linear_mipmap, repeat_enable;

varying float h;
varying vec3 tint;
varying vec3 wp;

void vertex() {
	h = clamp(VERTEX.y / height, 0.0, 1.0);
	tint = COLOR.rgb;
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = world.x * 0.13 + world.z * 0.11;
	VERTEX.x += sin(TIME * 1.3 + ph) * sway * h * h;
	VERTEX.z += cos(TIME * 1.1 + ph * 1.3) * sway * 0.6 * h * h;
	if (fade_end > 0.0) {
		float dist = length(world - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
		VERTEX *= 1.0 - smoothstep(fade_start, fade_end, dist);
	}
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(n_detail, wp.xy * 0.7 + wp.zy * 0.5).r;
	vec3 c = mix(base_color, tip_color, h) * tint * (0.75 + 0.5 * n);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.25, 0.3, 0.1) * h;
	AO = mix(0.45, 1.0, h);
}
