"""Render rest-pose region masks for the scanned single-shell character."""
import bpy, numpy as np
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1]
CAP=ROOT/'captures/rigging'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'assets/characters/source_high_detail/wayfarer_rigged.blend'))
for ob in bpy.data.objects:
    ob.animation_data_clear()
arm=bpy.data.objects['HeroSkeleton']
for pb in arm.pose.bones: pb.matrix_basis=Matrix.Identity(4)
motion=bpy.data.objects['Motion']; motion.matrix_basis=Matrix.Identity(4)
for name,color in [('HeroBody',(.1,.65,.25,1)),('HeroSword',(.9,.04,.02,1)),('HeroShield',(.02,.18,1,1))]:
    ob=bpy.data.objects[name]
    mat=bpy.data.materials.new(name+' diagnostic'); mat.diffuse_color=color; mat.use_nodes=True
    node=mat.node_tree.nodes.get('Principled BSDF'); node.inputs['Base Color'].default_value=color
    ob.data.materials.clear(); ob.data.materials.append(mat)
    pts=np.array([v.co[:] for v in ob.data.vertices]); print(name,pts.min(axis=0),pts.max(axis=0),flush=True)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=12
scene.render.resolution_x=900; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Mask studio'); scene.world.color=(.5,.5,.5)
scene.view_settings.view_transform='Standard'
target=Vector((0,0,.93))
for loc in [(3,4,5),(-3,-3,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc); light=bpy.context.object; light.data.energy=450; light.data.size=4
    light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(); cam=bpy.context.object; scene.camera=cam; cam.data.type='ORTHO'; cam.data.ortho_scale=2.15
for name,loc in [('front',(0,6,.93)),('side',(6,0,.93)),('back',(0,-6,.93))]:
    cam.location=loc; cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(CAP/(name+'_regions.png')); bpy.ops.render.render(write_still=True)
