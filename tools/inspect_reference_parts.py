import bpy, numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(next((ROOT/'_incoming_model').glob('*.obj'))),forward_axis='NEGATIVE_Z',up_axis='Y')
ob=bpy.context.object
p=np.array([v.co[:] for v in ob.data.vertices])*[-2,2,-2]
parents=list(range(len(p)))
def find(a):
    while parents[a]!=a:
        parents[a]=parents[parents[a]]; a=parents[a]
    return a
for e in ob.data.edges:
    a,b=e.vertices; parents[find(a)]=find(b)
groups={}
for i in range(len(p)): groups.setdefault(find(i),[]).append(i)
for group in sorted(groups.values(),key=len,reverse=True)[:30]:
    pts=p[group]; print('COMPONENT',len(group),'min',pts.min(axis=0),'max',pts.max(axis=0))
print('GROUPS',len(groups))
