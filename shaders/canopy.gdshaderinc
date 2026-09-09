float canopy_hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float canopy_noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(canopy_hash(i),canopy_hash(i+vec2(1,0)),f.x),mix(canopy_hash(i+vec2(0,1)),canopy_hash(i+vec2(1,1)),f.x),f.y);
}
float canopy_light(vec3 p, float time) {
	vec2 q=p.xz+p.y*vec2(.75,.75)+vec2(time*.045,sin(time*.11)*.13);
	float patches=canopy_noise(q*.48)*.70+canopy_noise(q*1.3)*.30;
	return mix(.68,1.08,smoothstep(.31,.69,patches));
}
