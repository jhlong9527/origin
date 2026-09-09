shader_type spatial;
render_mode diffuse_burley, cull_disabled;
#include "res://shaders/canopy.gdshaderinc"
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_map : filter_linear_mipmap, repeat_enable;
uniform int material_kind = 0;
varying vec3 world_p;
varying vec3 world_n;
varying vec3 color;
void vertex(){
 world_p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_n=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 color=COLOR.rgb;
}
void fragment(){
 vec3 w=pow(abs(world_n),vec3(6.0)); w/=max(dot(w,vec3(1.0)),.001);
 vec3 p=world_p*(material_kind==1?1.0:1.3);
 vec2 uv_x=p.zy; vec2 uv_y=p.xz; vec2 uv_z=p.xy;
 if(material_kind==1){ uv_x*=vec2(1.8,.35); uv_y*=vec2(1.8,.35); uv_z*=vec2(1.8,.35); }
 vec3 detail=texture(albedo_map,uv_x).rgb*w.x+texture(albedo_map,uv_y).rgb*w.y+texture(albedo_map,uv_z).rgb*w.z;
 vec3 nx=texture(normal_map,uv_x).rgb*2.0-1.0;
 vec3 ny=texture(normal_map,uv_y).rgb*2.0-1.0;
 vec3 nz=texture(normal_map,uv_z).rgb*2.0-1.0;
 vec3 perturb=vec3(0.0,nx.y,nx.x)*w.x+vec3(ny.x,0.0,ny.y)*w.y+vec3(nz.x,nz.y,0.0)*w.z;
 vec3 bumped=normalize(world_n+perturb*(material_kind==2?.22:.42));
 NORMAL=normalize((VIEW_MATRIX*vec4(bumped,0.0)).xyz);
 float r=texture(rough_map,uv_x).r*w.x+texture(rough_map,uv_y).r*w.y+texture(rough_map,uv_z).r*w.z;
 float shade=canopy_light(world_p,TIME);
 vec3 base=color;
 if(material_kind==0){base*=.86;}
 if(material_kind==1){base=mix(base,vec3(dot(base,vec3(.299,.587,.114))),.31)*.90;}
 if(material_kind==2){base=mix(base,vec3(.70,.83,.74),.26);}
 ALBEDO=base*detail*shade;
 ROUGHNESS=clamp(r,.28,.99);
 METALLIC=material_kind==2?.68:0.0;
 SPECULAR=material_kind==2?.55:.26;
 if(material_kind==3){
  float patch=canopy_noise(world_p.xz*37.0+world_p.y*vec2(19.0,31.0));
  if(patch<.34){ discard; }
  BACKLIGHT=color*.08;
 }
}
