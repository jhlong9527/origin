shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D scene_color : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest;
uniform float blur_strength : hint_range(0,1) = .85;
uniform bool debug_mask = false;
void vertex() { POSITION=vec4(VERTEX.xy,1.0,1.0); }
void fragment() {
	float depth=texture(scene_depth,SCREEN_UV).r;
	// Compatibility uses OpenGL NDC depth in [-1,1].
	vec4 view=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth*2.0-1.0,1.0);
	view/=view.w;
	vec3 world=(INV_VIEW_MATRIX*view).xyz;
	float forest=max(smoothstep(7.8,10.0,-world.z),smoothstep(10.75,13.5,abs(world.x)));
	float far_depth=smoothstep(29.0,35.0,-view.z);
	float coc=forest*mix(.36,1.0,far_depth)*blur_strength;
	if(!debug_mask && coc<.001) discard;
	// Explicit Gaussian taps also work when the Compatibility screen copy has no mip chain.
	vec2 px=vec2(1.8)/VIEWPORT_SIZE;
	float weights[5]=float[5](.0625,.25,.375,.25,.0625);
	vec3 blurred=vec3(0);
	for(int x=0;x<5;x++) for(int y=0;y<5;y++) {
		blurred+=textureLod(scene_color,SCREEN_UV+vec2(float(x-2),float(y-2))*px,0.0).rgb*weights[x]*weights[y];
	}
	ALBEDO=debug_mask?vec3(forest):blurred;
	ALPHA=debug_mask?1.0:coc;
}
