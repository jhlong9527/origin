"""Blender 5.2: build a separately skinned hero; original assets are never overwritten."""
import bpy, bmesh, math, json, sys, numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Euler
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'assets/characters'; CAP=ROOT/'captures/rigging'
CAP.mkdir(parents=True,exist_ok=True)
SOURCE=OUT/'source_high_detail'; SOURCE.mkdir(exist_ok=True)
(SOURCE/'.gdignore').touch()
C=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
def gv(v): return C@Vector(v)
def sm(a,b,x):
 t=np.clip((x-a)/(b-a),0,1); return t*t*(3-2*t)
def rot(x=0,y=0,z=0): return Euler(tuple(math.radians(a) for a in (x,y,z)),'XYZ').to_matrix()
def mat4(pos,r=None):
 m=(r if r is not None else Matrix.Identity(3)).to_4x4(); m.translation=Vector(pos); return m
S={
'Hips':((0,.56,.015),None),'Torso':((0,.77,0),'Hips'),'Head':((0,1.23,0),'Torso'),
'UpperArmR':((.255,1.045,-.005),'Torso'),'ForearmR':((.37,.84,-.065),'UpperArmR'),'HandR':((.455,.65,-.235),'ForearmR'),
'UpperArmL':((-.255,1.045,-.005),'Torso'),'ForearmL':((-.39,.855,-.035),'UpperArmL'),'HandL':((-.415,.80,-.25),'ForearmL'),
'ThighR':((.15,.53,.005),'Hips'),'ShinR':((.185,.265,.005),'ThighR'),'FootR':((.185,.095,-.005),'ShinR'),
'ThighL':((-.145,.53,.005),'Hips'),'ShinL':((-.175,.265,.005),'ThighL'),'FootL':((-.18,.095,-.005),'ShinL'),
'Cape':((0,1.11,.16),'Torso'),'Tabard':((0,.57,-.1),'Hips'),
'Sword':((.49,.615,-.29),'HandR'),'Shield':((-.44,.82,-.31),'HandL')}
N=list(S)
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.obj_import(filepath=str(next((ROOT/'_incoming_model').glob('*.obj'))),forward_axis='NEGATIVE_Z',up_axis='Y')
source=bpy.context.object
p=np.asarray([v.co[:] for v in source.data.vertices])*[-2.,2.,-2.]
f=np.asarray([face.vertices[:] for face in source.data.polygons],dtype=np.int32)
source_vertex_count=len(p); source_triangle_count=len(f)
uv=np.asarray([u.uv[:] for u in source.data.uv_layers.active.data],dtype=np.float32).reshape(-1,3,2)
cent=p[f].mean(axis=1); x,y,z=cent.T
axis=np.array([.57,-.40,-.64]); axis/=np.linalg.norm(axis)
along=(cent-[.46,.66,-.26])@axis
radial=np.linalg.norm(cent-[.46,.66,-.26]-along[:,None]*axis,axis=1)
sword=(((along>-.045)&(z<-.22))|((along>-.07)&(radial<.18)&(y>.48)&(z<-.16))|((along>-.26)&(radial<.044)))&(x>.29)&(y<.85)&(z<-.10)
# The shield is angled around Y: a Z-only cut leaves its outside rim in the body.
shield=(x<-.20)&(y>.43)&(y<.955-.245*x)&(x+z<-.54)
material=bpy.data.materials.new('Reference PBR'); material.use_nodes=True
nodes=material.node_tree.nodes; links=material.node_tree.links; bsdf=nodes.get('Principled BSDF')
for suffix,slot in [('', 'Base Color'),('_roughness','Roughness'),('_metallic','Metallic'),('_normal','Normal')]:
 im=bpy.data.images.load(str(ROOT/'_incoming_model'/('texture_pbr_20250901'+suffix+'.png')),check_existing=True)
 if suffix: im.colorspace_settings.name='Non-Color'
 im.pack(); tex=nodes.new('ShaderNodeTexImage'); tex.image=im
 if slot=='Normal':
  norm=nodes.new('ShaderNodeNormalMap'); norm.inputs['Strength'].default_value=.55
  links.new(tex.outputs['Color'],norm.inputs['Color']); links.new(norm.outputs['Normal'],bsdf.inputs['Normal'])
 else: links.new(tex.outputs['Color'],bsdf.inputs[slot])
albedo=bpy.data.images.get('texture_pbr_20250901.png')
pixels=np.empty(albedo.size[0]*albedo.size[1]*4,dtype=np.float32); albedo.pixels.foreach_get(pixels)
pixels=pixels.reshape(albedo.size[1],albedo.size[0],4)
uv_samples=uv.mean(axis=1)%1
face_color=pixels[(uv_samples[:,1]*(albedo.size[1]-1)).astype(int),(uv_samples[:,0]*(albedo.size[0]-1)).astype(int),:3]
metal_image=bpy.data.images.get('texture_pbr_20250901_metallic.png')
metal_pixels=np.empty(metal_image.size[0]*metal_image.size[1]*4,dtype=np.float32); metal_image.pixels.foreach_get(metal_pixels)
metal_pixels=metal_pixels.reshape(metal_image.size[1],metal_image.size[0],4)
metal=metal_pixels[(uv_samples[:,1]*(metal_image.size[1]-1)).astype(int),(uv_samples[:,0]*(metal_image.size[0]-1)).astype(int),0]
# Gold quillons curl back past the blade's separating plane.
sword |= (metal>.30)&(x>.36)&(y>.46)&(y<.82)&(z<-.08)
hilt_a=np.array([.285,.755,-.055]); hilt_b=np.array([.47,.63,-.25]); hilt_axis=hilt_b-hilt_a
hilt_t=np.clip((cent-hilt_a)@hilt_axis/(hilt_axis@hilt_axis),0,1)
sword |= np.linalg.norm(cent-hilt_a-hilt_t[:,None]*hilt_axis,axis=1)<.038
# Retain cloth and leather near the two contact seams; include the full metal rim.
shield &= (x+z<-.605)|(metal>.25)|(y<.99)
labels=np.zeros(len(f),dtype=np.int32); labels[sword]=1; labels[shield]=2
vertex_color=np.zeros((len(p),3)); counts=np.bincount(f.ravel(),minlength=len(p))
for channel in range(3): vertex_color[:,channel]=np.bincount(f.ravel(),weights=np.repeat(face_color[:,channel],3),minlength=len(p))/np.maximum(1,counts)
# The scan welds the shield into the left glove. Reconstruct that occluded
# forearm from the intact right one, retaining its detailed leather/skin UVs.
# Blend the mirrored elbow into the original sleeve; reposition the wrist
# along the shield-side rest bone rather than stretching the contact cap.
face_red=(face_color[:,0]>face_color[:,1]*1.9)&(face_color[:,2]>face_color[:,1]*.85)
face_blue=(face_color[:,2]>face_color[:,0]*1.10)&(face_color[:,1]>face_color[:,0]*1.12)
replace_left=(labels==0)&(x<-.285)&(y>.44)&(y<.968)&(z<.18)&(~face_red)&(~face_blue)
labels[replace_left]=3
donor=(labels==0)&(x>.30)&(y>.44)&(y<.965)&(z<.15)&(~face_red)&(~face_blue)
donor_faces=np.flatnonzero(donor)
donor_ids,donor_inv=np.unique(f[donor_faces].ravel(),return_inverse=True)
mirrored=p[donor_ids]*[-1,1,1]
old_elbow=Vector((-.37,.84,-.065)); old_wrist=Vector((-.455,.65,-.235))
new_elbow=Vector(S['ForearmL'][0]); new_wrist=Vector(S['HandL'][0])
arm_rotation=(old_wrist-old_elbow).rotation_difference(new_wrist-new_elbow).to_matrix()
reposed=(mirrored-np.array(old_elbow))@np.array(arm_rotation).T+np.array(new_elbow)
reposed+=(np.array(new_wrist)-((np.array(old_wrist)-np.array(old_elbow))@np.array(arm_rotation).T+np.array(new_elbow)))*sm(.96,.60,mirrored[:,1])[:,None]
blend=(1-sm(.82,.96,mirrored[:,1]))[:,None]
reconstructed=mirrored*(1-blend)+reposed*blend
offset=len(p)
p=np.concatenate([p,reconstructed]); vertex_color=np.concatenate([vertex_color,vertex_color[donor_ids]])
f=np.concatenate([f,donor_inv.reshape(-1,3)[:,::-1]+offset])
uv=np.concatenate([uv,uv[donor_faces,::-1]])
labels=np.concatenate([labels,np.zeros(len(donor_faces),dtype=np.int32)])
objects=[]; coords_list=[]; colors_list=[]
for i,name in enumerate(['HeroBody','HeroSword','HeroShield']):
 fi=np.flatnonzero(labels==i); ids,inv=np.unique(f[fi].ravel(),return_inverse=True); coords=p[ids]
 data=bpy.data.meshes.new(name); data.from_pydata([gv(v) for v in coords],[],inv.reshape(-1,3).tolist())
 data.materials.append(material); layer=data.uv_layers.new(name='UVMap'); layer.data.foreach_set('uv',uv[fi].ravel())
 for face in data.polygons: face.use_smooth=True
 # Close the contact cuts left by the original fused weapon/hand surfaces.
 # Existing vertices and source UVs remain intact; only the hidden cut caps
 # receive a sampled solid material instead of stretching unrelated UV islands.
 bm=bmesh.new(); bm.from_mesh(data); bm.verts.ensure_lookup_table()
 caps=bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0).get('faces',[])
 cap_slots={}
 for face in caps:
  color=vertex_color[ids[[v.index for v in face.verts]]].mean(axis=0)
  key=tuple(np.round(color*8).astype(int))
  if key not in cap_slots:
   cap_mat=bpy.data.materials.new(name+' contact '+str(len(cap_slots))); cap_mat.use_nodes=True
   cap_node=cap_mat.node_tree.nodes.get('Principled BSDF')
   linear=np.where(color<=.04045,color/12.92,((color+.055)/1.055)**2.4)
   cap_node.inputs['Base Color'].default_value=(*linear,1); cap_node.inputs['Roughness'].default_value=.65
   data.materials.append(cap_mat); cap_slots[key]=len(data.materials)-1
  face.material_index=cap_slots[key]; face.smooth=False
 bm.to_mesh(data); bm.free()
 assert len(data.vertices)==len(coords)
 ob=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(ob); objects.append(ob); coords_list.append(coords); colors_list.append(vertex_color[ids])
bpy.data.objects.remove(source,do_unlink=True)
bpy.ops.object.armature_add(enter_editmode=True); arm=bpy.context.object; arm.name='HeroSkeleton'; arm.data.name='HeroSkeleton'
for b in list(arm.data.edit_bones): arm.data.edit_bones.remove(b)
for name,(head,parent) in S.items():
 b=arm.data.edit_bones.new(name); b.head=gv(head)
 child=next((s[0] for n,s in S.items() if s[1]==name and n not in ['Sword','Shield','Cape','Tabard']),None)
 b.tail=gv(child or (Vector(head)+Vector((0,.1,0))))
 if parent: b.parent=arm.data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT'); arm.show_in_front=True
motion=bpy.data.objects.new('Motion',None); bpy.context.collection.objects.link(motion); arm.parent=motion
weights=[]
for ob,coords,colors in zip(objects,coords_list,colors_list):
 w=np.zeros((len(coords),len(N)),dtype=np.float32)
 if ob.name in ['HeroSword','HeroShield']: w[:,N.index('Sword' if ob.name=='HeroSword' else 'Shield')]=1
 else:
  x,y,z=coords.T; h=sm(1.19,1.27,y); w[:,N.index('Head')]=h; body=1-h
  # Crimson contains more blue than brown leather. A red/green ratio alone
  # incorrectly binds gloves, skin and boot cuffs to the cloak bone.
  red=(colors[:,0]>colors[:,1]*1.9)&(colors[:,0]>colors[:,2]*1.5)&(colors[:,2]>colors[:,1]*.85)
  blue=(colors[:,2]>colors[:,0]*1.10)&(colors[:,1]>colors[:,0]*1.12)
  cape=red&(y<1.12)&(y>.13)
  w[cape,N.index('Cape')]=(1-sm(.84,1.08,y[cape]))*.9; body-=w[:,N.index('Cape')]
  arm_region=(np.abs(x)>.235)&(y>.43)&(y<1.14)&(z<.18)&(~cape)&((~blue)|(y>.88))
  legs=(y<.57)&(~cape)&(~blue)&(~arm_region)
  for side,sign in [('R',1),('L',-1)]:
   mask=legs&(x*sign>=0); hip=sm(.46,.58,y[mask]); knee=sm(.21,.32,y[mask]); ankle=sm(.07,.15,y[mask])
   w[mask,N.index('Hips')]=hip; w[mask,N.index('Thigh'+side)]=(1-hip)*knee
   w[mask,N.index('Shin'+side)]=(1-hip)*(1-knee)*ankle; w[mask,N.index('Foot'+side)]=(1-hip)*(1-knee)*(1-ankle); body[mask]=0
  for side,sign in [('R',1),('L',-1)]:
   mask=arm_region&(x*sign>0); chain=['UpperArm'+side,'Forearm'+side,'Hand'+side]; pts=coords[mask]; scores=[]
   for j,name in enumerate(chain):
    a=np.asarray(S[name][0]); b=np.asarray(S[chain[j+1]][0]) if j<2 else a+[sign*.015,-.045,-.03]
    ab=b-a; t=np.clip((pts-a)@ab/(ab@ab),0,1); d=np.linalg.norm(pts-a-t[:,None]*ab,axis=1)
    scores.append(np.exp(-d*d/.008))
   score=np.stack(scores,axis=1); score/=score.sum(axis=1,keepdims=True)
   amount=body[mask]*sm(.235,.32,np.abs(x[mask]))
   for j,name in enumerate(chain): w[mask,N.index(name)]=score[:,j]*amount
   body[mask]-=amount
  torso=sm(.55,.80,y); w[:,N.index('Torso')]+=body*torso; w[:,N.index('Hips')]+=body*(1-torso)
  # Diffuse weights along actual mesh edges, never between nearby disconnected surfaces.
  # This removes the former one-triangle jumps at cuffs, cloak seams and the tunic hem.
  edges=np.asarray([edge.vertices[:] for edge in ob.data.edges],dtype=np.int32)
  row=np.concatenate([edges[:,0],edges[:,1]]); col=np.concatenate([edges[:,1],edges[:,0]])
  conductance=1/np.maximum(.003,np.linalg.norm(coords[row]-coords[col],axis=1))
  degree=np.bincount(row,weights=conductance,minlength=len(coords))
  for iteration in range(48):
   smooth=np.stack([np.bincount(row,weights=conductance*w[col,k],minlength=len(coords)) for k in range(len(N))],axis=1)/np.maximum(degree[:,None],1e-8)
   w=.35*w+.65*smooth
 order=np.argsort(w,axis=1)[:,-4:]; filtered=np.zeros_like(w); np.put_along_axis(filtered,order,np.take_along_axis(w,order,axis=1),axis=1)
 w=filtered/filtered.sum(axis=1,keepdims=True); assert np.isfinite(w).all() and np.max(abs(w.sum(axis=1)-1))<1e-5
 weights.append(w)
 for k,name in enumerate(N):
  group=ob.vertex_groups.new(name=name)
  for vi in np.flatnonzero(w[:,k]>.00001): group.add([int(vi)],float(w[vi,k]),'REPLACE')
 mod=ob.modifiers.new('Bound skin','ARMATURE'); mod.object=arm; ob.parent=arm
if '--rest-only' in sys.argv:
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'wayfarer_rigged.blend'),check_existing=False,compress=True)
 print('REST_READY',flush=True); sys.exit(0)
REST={n:mat4(S[n][0]) for n in N}
def global_pose(angles):
 g={}
 for n,(pos,parent) in S.items():
  r=rot(*angles.get(n,(0,0,0)))
  g[n]=(g[parent]@mat4(Vector(pos)-Vector(S[parent][0]),r)) if parent else mat4(pos,r)
 return g
def solve_arm(g,side,target,pole):
 upper,fore,hand=['UpperArm'+side,'Forearm'+side,'Hand'+side]; a=g[upper].translation; b=g[fore].translation; c=g[hand].translation
 la=(b-a).length; lb=(c-b).length; t=Vector(target); d=t-a; distance=min(d.length,la+lb-.002); axis=d.normalized()
 t=a+axis*distance; along=(la*la-lb*lb+distance*distance)/(2*distance)
 up=Vector(pole)-axis*Vector(pole).dot(axis); up.normalize(); elbow=a+axis*along+up*math.sqrt(max(0,la*la-along*along))
 ru=(b-a).normalized().rotation_difference((elbow-a).normalized()).to_matrix()@g[upper].to_3x3()
 rf=(c-b).normalized().rotation_difference((t-elbow).normalized()).to_matrix()@g[fore].to_3x3()
 g[upper]=mat4(a,ru); g[fore]=mat4(elbow,rf); g[hand]=mat4(t,rf)
 for n in ['Sword','Shield']:
  if S[n][1]==hand: g[n]=g[hand]@mat4(Vector(S[n][0])-Vector(S[hand][0]))
def clip_pose(name,t,duration):
 p=t/duration; a={}; lift=0.; roll=0.; gait=math.sin(t*math.tau*1.7)
 if name in ['idle','bow_idle']: a.update(Torso=(math.sin(t*math.pi)*1.2,0,0),Cape=(math.sin(t*math.pi)*2,0,0))
 if name in ['move','bow_move','bow_draw_move']:
  for side,s in [('R',1),('L',-1)]:
   a['Thigh'+side]=(s*gait*23,0,0); a['Shin'+side]=(-max(0,-s*gait)*34,0,0)
  a.update(Torso=(-4,0,0),Cape=(9+gait*3,0,0))
 if name.startswith('attack') or name=='skill':
  cut=int(name[-1]) if name.startswith('attack') else 0
  wind=float(sm(0,.27,p)); slash=float(sm(.29,.54,p)); recovery=1-float(sm(.65,1,p))
  starts=[(35,-55,-20),(80,55,-5),(130,5,-12)]; ends=[(70,65,0),(75,-60,-22),(60,0,-6)]
  a['UpperArmR']=tuple(((1-slash)*starts[cut][i]+slash*ends[cut][i])*wind*recovery for i in range(3))
  a.update(ForearmR=((20 if cut<2 else -25)*wind*recovery,0,0),Torso=(-9*wind*recovery,(-28+56*slash)*(1 if cut!=1 else -1)*wind*recovery,0),ThighL=(12*wind*recovery,0,0),ShinL=(-18*wind*recovery,0,0),Cape=(15*math.sin(p*math.pi),0,0))
 if name=='block': a.update(Torso=(-8,0,0),UpperArmL=(38,-20,0),ForearmL=(30,0,0))
 if name=='parry':
  w=math.sin(p*math.pi); a.update(Torso=(-8*w,-22*w,0),UpperArmL=(45*w,55*w,8*w),ForearmL=(18*w,0,0))
 if name in ['dodge','bow_skill']:
  u=float(np.clip((t-.12)/.58,0,1)) if name=='bow_skill' else float(sm(.06,.47,t))
  tuck=math.sin(u*math.pi); roll=(1 if name=='bow_skill' else -1)*math.tau*u; lift=(.50 if name=='bow_skill' else 0)*4*u*(1-u)
  for side in ['R','L']: a['Thigh'+side]=(75*tuck,0,0); a['Shin'+side]=(-112*tuck,0,0)
  a.update(Torso=(-25*tuck,0,0),Cape=(15*tuck,0,0))
  if name=='bow_skill' and t>=.70:
   settle=1-float(sm(.70,.86,t)); a['Torso']=(-12*settle,0,0)
   for side in ['R','L']: a['Thigh'+side]=(28*settle,0,0); a['Shin'+side]=(-40*settle,0,0)
 if name in ['hurt','stagger','dead']:
  w=math.sin(p*math.pi) if name=='hurt' else float(sm(0,.35,p)); a['Torso']=((20 if name=='hurt' else -35)*w,4*w,0)
  if name=='dead': roll=-math.pi*.48*w
 if name=='weapon_switch':
  w=math.sin(p*math.pi); a.update(UpperArmR=(-15*w,0,10*w),UpperArmL=(-15*w,0,-10*w))
 g=global_pose(a)
 if name.startswith('bow'):
  draw=0.; ready=1.
  if name.startswith('bow_draw'): draw=float(sm(.18,.70,t))*(1-float(sm(.72,.80,t))); ready=float(sm(0,.15,t))
  elif name=='bow_skill':
   ready=float(sm(.70,.85,t))
   for release in [.92,1.14,1.36]: draw=max(draw,float(sm(release-.16,release-.015,t))*(1-float(sm(release,release+.055,t))))
  elif name in ['bow_idle','bow_move']: ready=.65
  pitch,_,bank=a.get('Torso',(0,0,0))
  a['Torso']=(pitch,-32*ready,bank); a['Head']=(0,24*ready,0)
  g=global_pose(a)
  # Side-on shoulders give both arms room; the drawing hand remains outside
  # the chest instead of pulling the string through the torso.
  solve_arm(g,'L',g['HandL'].translation.lerp(Vector((.06,1.10,-.48)),ready),(-1,-.25,0))
  solve_arm(g,'R',g['HandR'].translation.lerp(Vector((-.01+.07*draw,1.10,-.36+.19*draw)),ready),(1,.12,.05))
 if name=='heal':
  w=float(sm(.12,.4,p))*(1-float(sm(.8,1,p))); solve_arm(g,'L',g['HandL'].translation.lerp(Vector((-.05,1.21,-.23)),w),(-1,-.2,0))
 return g,roll,lift
CLIPS={'idle':2.,'move':.588235,'bow_idle':2.,'bow_move':.588235,'attack0':.5904,'attack1':.6396,'attack2':.82,'skill':.902,'block':1.,'parry':.5412,'dodge':.5248,'hurt':.4018,'stagger':1.23,'dead':1.,'heal':1.189,'weapon_switch':.62,'bow_draw':1.05,'bow_draw_move':1.05,'bow_skill':1.70}
scene=bpy.context.scene; scene.render.fps=60
arm.animation_data_create(); motion.animation_data_create()
bone_rest={n:arm.data.bones[n].matrix_local.copy() for n in N}; metrics={}; samples={}
# Skin floor tests use all source vertices, including the cloak and weapons.
def deform(g,idx):
 coords=coords_list[idx]; result=np.zeros_like(coords)
 for k,n in enumerate(N):
  mask=weights[idx][:,k]>0
  if not np.any(mask): continue
  m=g[n]@REST[n].inverted()
  result[mask]+=(coords[mask]@np.array(m.to_3x3()).T+np.array(m.translation))*weights[idx][mask,k,None]
 return result
for name,duration in CLIPS.items():
 act=bpy.data.actions.new(name); act.use_fake_user=True; arm.animation_data.action=act
 root_act=bpy.data.actions.new(name+'_root'); root_act.use_fake_user=True; motion.animation_data.action=root_act
 frames=round(duration*60); minima=[]; samples[name]=[]
 for frame in range(frames+1):
  t=duration*frame/frames; g,roll,lift=clip_pose(name,t,duration)
  points=np.concatenate([deform(g,i) for i in range(1 if name.startswith('bow') else 3)])
  rotation=rot(math.degrees(roll)); pivot=np.array([0,.78,0]); rotated=(points-pivot)@np.array(rotation).T+pivot
  ground=.018-float(rotated[:,1].min()); height=ground+lift
  motion.rotation_mode='QUATERNION'; motion.rotation_quaternion=(C@rotation@C.inverted()).to_quaternion()
  motion.location=gv(Vector((0,.78+height,0))-rotation@Vector((0,.78,0)))
  motion.keyframe_insert('location',frame=frame+1); motion.keyframe_insert('rotation_quaternion',frame=frame+1)
  targets={n:mat4(gv(g[n].translation),C@g[n].to_3x3()@C.inverted())@mat4((0,0,0),bone_rest[n].to_3x3()) for n in N}
  for n in N:
   parent=S[n][1]
   basis=bone_rest[n].inverted()@bone_rest[parent]@targets[parent].inverted()@targets[n] if parent else bone_rest[n].inverted()@targets[n]
   pb=arm.pose.bones[n]; pb.rotation_mode='QUATERNION'; pb.matrix_basis=basis
   for channel in ['location','rotation_quaternion','scale']: pb.keyframe_insert(channel,frame=frame+1,group=n)
  minima.append(float(rotated[:,1].min()+height)); samples[name].append({'t':t,'min_y':minima[-1],'lift':lift,'roll':roll})
 for ob,action in [(arm,act),(motion,root_act)]:
  track=ob.animation_data.nla_tracks.new(); track.name=name; track.strips.new(name,1,action)
  ob.animation_data.action=None; track.mute=True
 metrics[name]={'min_y':min(minima),'frames':frames+1}
 print('BAKED',name,metrics[name],flush=True)
for ob in [arm,motion]:
 for track in ob.animation_data.nla_tracks: track.mute=False
motion.location=(0,0,0); motion.rotation_quaternion=(1,0,0,0)
for pb in arm.pose.bones: pb.matrix_basis=Matrix.Identity(4)
for ob in bpy.context.selected_objects: ob.select_set(False)
for ob in [motion,arm]+objects: ob.select_set(True)
bpy.context.view_layer.objects.active=arm; scene.frame_start=1; scene.frame_end=103; scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'wayfarer_rigged.blend'),check_existing=False,compress=True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'wayfarer_rigged.glb'),export_format='GLB',use_selection=True,export_apply=False,export_animations=True,export_animation_mode='NLA_TRACKS',export_skins=True,export_yup=True,export_anim_slide_to_zero=True)
report={'source_vertices':source_vertex_count,'source_triangles':source_triangle_count,'bones':N,'parts':{o.name:sum(len(face.vertices)-2 for face in o.data.polygons) for o in objects},'clips':metrics,'height_m':float(p[:,1].max()),'coordinate_system':'Godot +Y up -Z forward','weights':'anatomical regions with 48 topology diffusion passes; max 4 normalized influences','repairs':'shield-side forearm reconstructed from the intact opposite arm; contact seams capped'}
(OUT/'rigged_model_metrics.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
(CAP/'animation_samples.json').write_text(json.dumps(samples),encoding='utf-8')
print('RIGGED_EXPORT_COMPLETE',json.dumps(report),flush=True)
