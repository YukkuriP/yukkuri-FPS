// Terrain splat shader: slope/height/macro-noise blending, no tiling repetition.
// Yukkuri Strike - created by ゆっくりP
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D n_detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_macro : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 towns[6];
uniform int town_count = 0;
uniform float sea_level = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float d = texture(n_detail, wpos.xz * 0.21).r;
	float d_b = texture(n_detail, wpos.xz * 0.047 + vec2(0.37, 0.11)).r;
	float m = texture(n_macro, wpos.xz * 0.0019).r;
	float m2 = texture(n_macro, wpos.xz * 0.0061 + vec2(0.5)).r;
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);

	vec3 grass_a = vec3(0.17, 0.22, 0.085);
	vec3 grass_b = vec3(0.33, 0.33, 0.14);
	vec3 grass = mix(grass_a, grass_b, smoothstep(0.25, 0.8, m)) * (0.72 + 0.56 * d);
	vec3 dry = vec3(0.47, 0.41, 0.27) * (0.78 + 0.44 * d);
	grass = mix(grass, dry, smoothstep(0.52, 0.78, d_b * 0.55 + m2 * 0.6));

	float rk = texture(n_detail, vec2(wpos.x + wpos.z, wpos.y * 2.3) * 0.11).r;
	vec3 rock = mix(vec3(0.28, 0.27, 0.25), vec3(0.52, 0.49, 0.44), rk) * (0.8 + 0.4 * d);
	vec3 sand = vec3(0.64, 0.57, 0.42) * (0.86 + 0.28 * d);
	vec3 dirt = vec3(0.36, 0.29, 0.20) * (0.75 + 0.5 * d);

	float town_w = 0.0;
	for (int i = 0; i < town_count; i++) {
		float dist = length(wpos.xz - towns[i].xy);
		town_w = max(town_w, 1.0 - smoothstep(towns[i].z * 0.55, towns[i].z * 1.05 + d_b * 18.0, dist));
	}
	float rock_w = smoothstep(0.24, 0.42, slope + (d - 0.5) * 0.18);
	float sand_w = 1.0 - smoothstep(sea_level + 1.2, sea_level + 3.2, wpos.y + d * 1.2);

	vec3 col = mix(grass, dirt, town_w * smoothstep(0.25, 0.6, d_b + 0.25));
	col = mix(col, sand, sand_w);
	col = mix(col, rock, rock_w);
	// subtle large-scale tint to kill repetition
	col *= mix(0.88, 1.08, m2);

	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.78, rock_w) - sand_w * 0.05;
	SPECULAR = 0.35;
	vec3 nm = texture(n_normal, wpos.xz * 0.21).rgb;
	vec3 nm2 = texture(n_normal, wpos.xz * 0.053).rgb;
	NORMAL_MAP = normalize(mix(nm, nm2, 0.45));
	NORMAL_MAP_DEPTH = mix(0.8, 1.6, rock_w);
}
