// Stylised-realistic ocean: scrolling dual normal maps + fresnel.
// Yukkuri Strike - created by ゆっくりP
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

uniform sampler2D n_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.02, 0.09, 0.12);
uniform vec3 shallow : source_color = vec3(0.07, 0.24, 0.26);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.05 + TIME * 0.8) * 0.15 + cos(wpos.z * 0.04 + TIME * 0.6) * 0.15;
}

void fragment() {
	vec2 uv = wpos.xz * 0.02;
	vec3 n1 = texture(n_normal, uv + vec2(TIME * 0.01, TIME * 0.006)).rgb;
	vec3 n2 = texture(n_normal, uv * 2.3 - vec2(TIME * 0.007, -TIME * 0.011)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0);
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, fres * 0.6);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
