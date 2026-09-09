shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying float glow;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = INSTANCE_CUSTOM.r*6.28318;
	origin.x += sin(TIME*0.21+phase)*0.29;
	origin.z += cos(TIME*0.17+phase*2.3)*0.24;
	origin.y += sin(TIME*0.34+phase)*0.16;
	vec4 local_view=VIEW_MATRIX*vec4(origin,1.0);
	float s=0.45+INSTANCE_CUSTOM.g*1.15;
	POSITION=PROJECTION_MATRIX*(local_view+vec4(VERTEX.xy*s,0.0,0.0));
	glow=0.16+0.34*pow(0.5+0.5*sin(TIME*0.61+phase),2.0);
}
void fragment() {
	float r=length(UV-vec2(0.5))*2.0;
	ALBEDO=vec3(1.0,0.76,0.40);
	ALPHA=pow(max(0.0,1.0-r),2.0)*glow;
}
