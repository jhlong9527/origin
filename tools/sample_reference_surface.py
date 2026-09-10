import bpy,numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(next((ROOT/'_incoming_model').glob('*.obj'))),forward_axis='NEGATIVE_Z',up_axis='Y')
ob=bpy.context.object
for v in ob.data.vertices: v.co=Vector(v.co)*2
# Original local raw OBJ: x=-game.x, y=game.y, z=-game.z.
for y in [.5,.65,.8,.95,1.05]:
 for x in [-.65,-.55,-.45,-.35,-.25]:
  hit,pos,normal,index=ob.ray_cast(Vector((-x,y,3)),Vector((0,0,-1)))
  if hit: print('SHIELD',x,y,'z',round(-pos.z,3),'normal',tuple(round(v,3) for v in normal),flush=True)
p=np.array([v.co[:] for v in ob.data.vertices])*[-1,1,-1]
f=np.array([v.vertices[:] for v in ob.data.polygons]); uv=np.array([u.uv[:] for u in ob.data.uv_layers.active.data]).reshape(-1,3,2)
np.savez_compressed(ROOT/'captures/rigging/source.npz',p=p,f=f,uv=uv)
