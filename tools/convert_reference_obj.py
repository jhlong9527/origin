import bpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / '_incoming_model'
OBJ = next(SRC.glob('*.obj'))
OUT = ROOT / 'assets' / 'characters' / 'wayfarer_reference.glb'

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(OBJ), forward_axis='NEGATIVE_Z', up_axis='Y')
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if not objects:
    raise RuntimeError('Reference OBJ did not import any mesh')

albedo = next(SRC.glob('*_20250901.png'))
normal = next(SRC.glob('*_normal.png'))
roughness = next(SRC.glob('*_roughness.png'))
metallic = next(SRC.glob('*_metallic.png'))

for obj in objects:
    obj.name = 'ReferenceHero'
    obj.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for material in obj.data.materials:
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        bsdf = nodes.get('Principled BSDF')
        if bsdf is None:
            continue
        def image(path, colorspace='sRGB'):
            tex = nodes.new('ShaderNodeTexImage')
            tex.image = bpy.data.images.load(str(path), check_existing=True)
            tex.image.colorspace_settings.name = colorspace
            return tex
        base = image(albedo, 'sRGB')
        norm = image(normal, 'Non-Color')
        rough = image(roughness, 'Non-Color')
        metal = image(metallic, 'Non-Color')
        links.new(base.outputs['Color'], bsdf.inputs['Base Color'])
        links.new(norm.outputs['Color'], nodes.new('ShaderNodeNormalMap').inputs['Color'])
        normal_node = next(n for n in nodes if n.bl_idname == 'ShaderNodeNormalMap')
        links.new(normal_node.outputs['Normal'], bsdf.inputs['Normal'])
        links.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
        links.new(metal.outputs['Color'], bsdf.inputs['Metallic'])
        bsdf.inputs['Roughness'].default_value = 0.72
    obj.select_set(False)

OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(OUT), export_format='GLB', export_apply=True, export_materials='EXPORT')
print(f'Wrote {OUT}')
