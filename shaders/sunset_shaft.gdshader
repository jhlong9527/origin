shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float phase = 0.0;
uniform float strength = 0.08;
void fragment() {
	float across = pow(max(0.0, 1.0-abs(UV.x*2.0-1.0)),2.2);
	float length_fade = smoothstep(0.0,0.13,UV.y)*(1.0-smoothstep(0.62,1.0,UV.y));
	float variation = 0.86+sin(UV.y*14.0+TIME*0.14+phase)*0.08;
	ALBEDO = vec3(1.0,0.66,0.30);
	ALPHA = across*length_fade*variation*strength;
}
