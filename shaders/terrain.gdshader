shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/canopy.gdshaderinc"
uniform sampler2D soil_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float coarse = noise(p * 0.57) * 0.72 + noise(p * 1.9) * 0.28;
	float speckle = noise(p * 18.0);
	float grass_mask = smoothstep(0.45, 0.7, coarse + smoothstep(4.7, 10.0, length(p)) * 0.2 + smoothstep(-1.0, 3.0, p.y) * 0.055);
	vec3 earth = mix(vec3(0.27, 0.19, 0.23), vec3(0.39, 0.29, 0.31), floor(coarse * 5.0) / 4.0);
	vec3 grass = mix(vec3(0.185, 0.285, 0.225), vec3(0.31, 0.37, 0.235), floor(coarse * 5.0) / 4.0);
	float border = max(abs(p.x) / 10.5, abs(p.y) / 7.6);
	vec3 painted = mix(earth, grass, grass_mask);
	painted = mix(painted, vec3(0.18, 0.275, 0.22) * (0.85 + coarse * 0.35), smoothstep(1.03, 1.4, border));
	vec3 soil=texture(soil_map,p*.72).rgb;
	float fine_moss=noise(p*5.3);
	float moss_edge=smoothstep(.30,.59,grass_mask)*smoothstep(.8,.45,grass_mask);
	painted=mix(painted,vec3(.27,.33,.15),moss_edge*fine_moss*.30);
	ALBEDO = painted * .96 * (.91 + speckle * .12) * mix(vec3(1),soil,.62) * canopy_light(world_position,TIME);
	NORMAL_MAP=texture(soil_normal,p*.72).rgb;
	NORMAL_MAP_DEPTH=.16;
	ROUGHNESS = mix(.79,1.0,grass_mask);
	SPECULAR=.2;
}
