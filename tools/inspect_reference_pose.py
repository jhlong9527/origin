"""Render source turnaround and report world-space bounds before rigging."""
import bpy, json
from pathlib import Path
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'captures' / 'rigging'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(next((ROOT/'_incoming_model').glob('*.obj'))), forward_axis='NEGATIVE_Z', up_axis='Y')
ob = bpy.context.object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for p in ob.data.polygons: p.use_smooth = True
pts = [ob.matrix_world@Vector(p) for p in ob.bound_box]
lo = Vector(tuple(min(p[i] for p in pts) for i in range(3)))
hi = Vector(tuple(max(p[i] for p in pts) for i in range(3)))
print('SOURCE_BOUNDS',list(lo),list(hi))
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=12
scene.render.resolution_x=640; scene.render.resolution_y=800; scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Studio'); scene.world.color=(.4,.4,.4)
scene.view_settings.view_transform='Standard'
center=(lo+hi)*.5
for loc in [(2,-3,4),(-3,2,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc)
    light=bpy.context.object; light.data.energy=220; light.data.size=3
    light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(); cam=bpy.context.object; scene.camera=cam
cam.data.type='ORTHO'; cam.data.ortho_scale=1.15
for name,direction in [('front',(0,-4,0)),('back',(0,4,0)),('right',(4,0,0)),('left',(-4,0,0))]:
    cam.location=center+Vector(direction)
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
