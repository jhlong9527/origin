shader_type spatial;
render_mode diffuse_burley, cull_disabled;
#include "res://shaders/canopy.gdshaderinc"
uniform sampler2D stone_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_map : source_color, filter_linear_mipmap, repeat_enable;
uniform bool foliage = false;
uniform bool metal_trim = false;
varying vec3 world_p;
varying vec3 world_n;
varying vec3 tint;
void vertex() {
	world_p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
	world_n=normalize(MODEL_NORMAL_MATRIX*NORMAL);
	if(foliage) {
		float bend=smoothstep(.12,1.2,world_p.y);
		VERTEX.x+=sin(TIME*1.1+world_p.x*.9+world_p.z*.7)*.024*bend;
		VERTEX.z+=cos(TIME*.85+world_p.z)*.014*bend;
	}
	tint=COLOR.rgb;
}
void fragment() {
	vec3 w=pow(abs(world_n),vec3(5)); w/=max(dot(w,vec3(1)),.001);
	vec3 p=world_p*1.8;
	vec3 stone=texture(stone_map,p.zy).rgb*w.x+texture(stone_map,p.xz).rgb*w.y+texture(stone_map,p.xy).rgb*w.z;
	vec3 bark=texture(bark_map,world_p.xy*vec2(1.8,.48)+world_p.z*.41).rgb;
	float wood=step(tint.b*1.2,tint.r)*step(tint.g,tint.r*.91);
	vec3 detail=mix(stone,bark,wood*.72);
	if(foliage) detail=texture(stone_map,UV).rgb;
	float shade=canopy_light(world_p,TIME);
	ALBEDO=tint*mix(vec3(1),detail,foliage?.54:.72)*shade*1.12;
	ROUGHNESS=foliage?.88:(metal_trim?.44:.86);
	METALLIC=metal_trim?.35:0.0;
	SPECULAR=foliage?.18:.33;
	if(foliage) {
		BACKLIGHT=tint*.19;
		ROUGHNESS=.90;
	}
}
