"""Build the reference archery equipment in Blender, including portable PBR maps.

Run: blender --background --python tools/build_archery_assets.py
Geometry helper coordinates are Godot (+Y up, -Z forward). The export conversion
is applied only at mesh creation. Bow pivot is the grip; arrow pivot is the TIP.
Assets are standalone and do not modify the hero model or game scripts.
"""
from pathlib import Path
import bpy
import json
import math
import struct
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "weapons"
TEX = OUT / "textures"
CAP = ROOT / "captures"
for directory in (OUT, TEX, CAP):
    directory.mkdir(parents=True, exist_ok=True)


def gv(p):
    return Vector((p[0], -p[2], p[1]))


def linear(rgb):
    v = np.asarray(rgb, dtype=np.float64) / 255.0
    return tuple(np.where(v <= .04045, v / 12.92, ((v + .055) / 1.055) ** 2.4))


def png(name, values, color=True):
    height, width = values.shape[:2]
    if values.ndim == 2:
        values = np.repeat(values[:, :, None], 3, axis=2)
    rgba = np.concatenate((np.clip(values, 0, 1), np.ones((height, width, 1))), axis=2)
    im = bpy.data.images.new(name, width, height, alpha=True)
    im.colorspace_settings.name = "sRGB" if color else "Non-Color"
    im.pixels.foreach_set(rgba.astype(np.float32).ravel())
    im.filepath_raw = str(TEX / (name + ".png"))
    im.file_format = "PNG"
    im.save()
    im.pack()
    return im


def surface_maps(family):
    """Deterministic 1K wood/leather/feather detail; never depends on a plugin."""
    n = 1024
    y, x = np.mgrid[0:n, 0:n] / float(n)
    rng = np.random.default_rng(8831 + len(family))
    if family == "wood":
        grain = np.sin(x * math.tau * 36 + np.sin(y * math.tau * 2) * 1.8 + np.sin(y * math.tau * 7) * .17)
        fine = np.sin(x * math.tau * 127 + np.sin(y * math.tau * 3) * 4)
        pores = rng.random((n, n))
        f = .93 + grain * .066 + fine * .026 + (pores - .5) * .019
        rgb = np.stack((.44 * f, .243 * f, .110 * f), axis=-1)
        height = grain * .020 + fine * .005
        rough = .53 + grain * .045 + pores * .06
    elif family == "leather":
        noise = rng.random((n, n))
        pores = np.sin(x * math.tau * 173 + np.sin(y * math.tau * 132)) * np.sin(y * math.tau * 177)
        patina = np.sin(x * math.tau * 3 + .5) * np.sin(y * math.tau * 2)
        f = .94 + patina * .09 + pores * .025 + (noise - .5) * .055
        rgb = np.stack((.49 * f, .278 * f, .138 * f), axis=-1)
        height = pores * .008 + noise * .008
        rough = .72 + pores * .06
    else:
        vane = np.sin((y + np.abs(x - .5) * .34) * math.tau * 90)
        f = .92 + vane * .07 + (rng.random((n, n)) - .5) * .026
        rgb = np.stack((.77 * f, .637 * f, .414 * f), axis=-1)
        height = vane * .016
        rough = .84 + vane * .035
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    normal = np.stack((-dx * 5, -dy * 5, np.ones_like(dx)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return (png("archery_" + family + "_albedo", rgb),
            png("archery_" + family + "_normal", normal * .5 + .5, False),
            png("archery_" + family + "_roughness", rough, False))


MAPS = {}
M = {}


def mat(name, rgb, rough=.7, metal=0, family=None):
    material = bpy.data.materials.new("Archery | " + name)
    material.diffuse_color = (*linear(rgb), 1)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = material.diffuse_color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if family:
        if family not in MAPS:
            MAPS[family] = surface_maps(family)
        albedo, normal, roughness = MAPS[family]
        for key, im in (("Base Color", albedo), ("Roughness", roughness)):
            node = nodes.new("ShaderNodeTexImage")
            node.image = im
            links.new(node.outputs["Color"], bsdf.inputs[key])
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = normal
        bump = nodes.new("ShaderNodeNormalMap")
        bump.inputs["Strength"].default_value = .34
        links.new(tex.outputs["Color"], bump.inputs["Color"])
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    M[name] = material
    return material


def mesh(name, points, faces, material, uv=None, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([gv(p) for p in points], [], faces)
    data.materials.append(material)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    layer = data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        poly.use_smooth = smooth
        for li in poly.loop_indices:
            vi = data.loops[li].vertex_index
            layer.data[li].uv = uv[vi] if uv is not None else (points[vi][0] * 2 + .5, points[vi][1] + points[vi][2])
    return obj


def tube(name, points, radius, material, sides=8):
    pts = [Vector(p) for p in points]
    vs, uvs, fs = [], [], []
    dist = [0]
    for i in range(1, len(pts)):
        dist.append(dist[-1] + (pts[i] - pts[i - 1]).length)
    for i, p in enumerate(pts):
        tangent = (pts[min(len(pts)-1, i+1)] - pts[max(0, i-1)]).normalized()
        normal = tangent.cross(Vector((0, 0, 1)))
        if normal.length < .01:
            normal = tangent.cross(Vector((1, 0, 0)))
        normal.normalize()
        bitangent = tangent.cross(normal).normalized()
        r = radius[i] if isinstance(radius, list) else radius
        for j in range(sides + 1):
            a = j * math.tau / sides
            vs.append(tuple(p + r * (math.cos(a)*normal + math.sin(a)*bitangent)))
            uvs.append((j/sides, dist[i]/max(.001, dist[-1])))
    stride = sides + 1
    for i in range(len(pts)-1):
        for j in range(sides):
            a=i*stride+j
            fs.append((a, a+1, a+1+stride, a+stride))
    fs += [tuple(range(sides-1, -1, -1)), tuple((len(pts)-1)*stride+j for j in range(sides))]
    return mesh(name, vs, fs, material, uvs, True)


def box(name, center, size, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=gv(center))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel:
        mod = obj.modifiers.new("Rounded handmade edge", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def empty(name, p=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = gv(p)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = .05
    return obj


def join(name, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = objects[0]
    obj.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return obj


def new_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def limb(sign):
    # A recurved stave with thick central riser and horn tipped slim extremity.
    points = [(0, .105, -.016), (0, .22, -.043), (0, .39, -.033),
              (0, .54, .035), (0, .69, .153), (0, .795, .188), (0, .867, .143)]
    points = [(x, y*sign, z) for x, y, z in points]
    radii = [.035, .034, .028, .025, .020, .015, .012]
    parts = [tube("Laminated yew stave", points, radii, M["Yew wood"], 12)]
    # Fine pale sapwood strip on both cheeks, following the stave silhouette.
    for side in (-1, 1):
        trail = [(side*radii[i]*.79, y, z-.011) for i, (_,y,z) in enumerate(points)]
        parts.append(tube("Sapwood lamination", trail, [.0038]*len(trail), M["Sapwood edge"], 6))
        groove = [(side*radii[i]*.74, y, z+.014) for i, (_,y,z) in enumerate(points)]
        parts.append(tube("Heartwood growth line", groove, .0017, M["Wood shadow"], 5))
    tip = Vector(points[-1])
    before = Vector(points[-2])
    parts.append(tube("Carved horn string nock", [tuple(tip+(before-tip)*.55), tuple(tip)], [.017, .014], M["Horn tip"], 12))
    for k in range(3):
        cy = sign * (.769+k*.013)
        cz = .185-k*.001
        ring = [(.017*math.cos(j*math.tau/16), cy, cz+.017*math.sin(j*math.tau/16)) for j in range(17)]
        parts.append(tube("Tip binding", ring, .0023, M["Linen stitching"], 5))
    return join("UpperLimb" if sign == 1 else "LowerLimb", parts)


def make_bow():
    new_scene()
    root=empty("Longbow")
    upper, lower = limb(1), limb(-1)
    parts=[tube("Riser", [(0,-.145,0),(0,.145,0)], [.040,.040], M["Wood shadow"], 14)]
    # Separate diagonal leather turns are real geometry, joined into one grip.
    for i in range(13):
        p=[]
        for j in range(33):
            a=j*math.tau/32
            p.append((.043*math.cos(a), -.126+i*.019+j/32*.019, .039*math.sin(a)))
        parts.append(tube("Overlapping grip wrap",p,.0063,M["Grip leather"],7))
    for sign in (-1,1):
        ring=[(.045*math.cos(j*math.tau/32),sign*.139,.041*math.sin(j*math.tau/32)) for j in range(33)]
        parts.append(tube("Grip end collar",ring,.009,M["Dull brass"],8))
    grip=join("BowGrip",parts)
    string=tube("BowString",[(0,-.867,.143),(0,0,.180),(0,.867,.143)],.0019,M["Linen string"],8)
    for obj in (upper,lower,grip,string):
        obj.parent=root
    for name,p in (("Grip",(0,0,0)),("StringTop",(0,.867,.143)),("StringBottom",(0,-.867,.143)),("StringNock",(0,0,.180))):
        empty(name,p).parent=root
    return root


def arrow_geometry(prefix="", offset=(0,0,0), scale=1):
    ox,oy,oz=offset
    def pt(x,y,z):return (ox+x*scale,oy+y*scale,oz+z*scale)
    # Point is at local origin; shaft/fletching trail along positive Z.
    parts=[tube(prefix+"Cedar shaft",[pt(0,0,.103),pt(0,0,.931)],.010*scale,M["Yew wood"],10)]
    verts=[pt(0,0,0),pt(-.041,0,.116),pt(-.016,0,.110),pt(-.011,0,.154),
           pt(.011,0,.154),pt(.016,0,.110),pt(.041,0,.116),pt(0,.011,.091),pt(0,-.011,.091)]
    outline=[0,1,2,3,4,5,6]
    fs=[]
    for i in range(len(outline)):
        a,b=outline[i],outline[(i+1)%len(outline)]
        fs.extend([(a,b,7),(b,a,8)])
    parts.append(mesh(prefix+"Ridge forged broadhead",verts,fs,M["Forged steel"]))
    parts.append(tube(prefix+"Arrowhead socket",[pt(0,0,.110),pt(0,0,.161)],[.014*scale,.011*scale],M["Forged steel"],10))
    for i in range(6):
        z=.152+i*.006
        ring=[pt(.011*math.cos(j*math.tau/16),.011*math.sin(j*math.tau/16),z) for j in range(17)]
        parts.append(tube(prefix+"Sinew head binding",ring,.0019*scale,M["Linen stitching"],5))
    # Three true feather vanes, tapered and gently cambered with incised barbs.
    for k in range(3):
        a=k*math.tau/3+.3
        radial=Vector((math.cos(a),math.sin(a),0))
        tang=Vector((-math.sin(a),math.cos(a),0))
        verts=[];uv=[];fs=[]
        for j in range(21):
            t=j/20
            z=.720+t*.184
            width=.007+.041*math.sin(math.pi*t)**.40
            for edge in (0,1):
                p=radial*(.009+edge*width)+tang*(.004*math.sin(math.pi*t)*edge)
                verts.append(pt(p.x,p.y,z));uv.append((edge,t))
        for j in range(20):
            fs.append((j*2,j*2+1,j*2+3,j*2+2))
        vane=mesh(prefix+"Turkey feather vane",verts,fs,M["Tan feathers"],uv)
        bpy.context.view_layer.objects.active=vane
        mod=vane.modifiers.new("Feather thickness","SOLIDIFY");mod.thickness=.0015*scale
        bpy.ops.object.modifier_apply(modifier=mod.name)
        parts.append(vane)
        for j in range(11):
            t=.10+j*.073
            z=.720+t*.184
            width=.041*math.sin(math.pi*t)**.4
            p0=radial*.014; p1=radial*(width+.007)
            parts.append(tube(prefix+"Feather barb",[pt(p0.x,p0.y,z-.01),pt(p1.x,p1.y,z+.005)],.0009*scale,M["Feather barb"],4))
    parts.append(tube(prefix+"Bone nock",[pt(0,0,.912),pt(0,0,.95)],.013*scale,M["Horn tip"],10))
    return parts


def make_arrow():
    new_scene()
    root=empty("Arrow")
    arrow=join("ArrowMesh",arrow_geometry())
    arrow.parent=root
    empty("ArrowTip",(0,0,0)).parent=root
    empty("ArrowNock",(0,0,.95)).parent=root
    return root


def oval(y,rx,rz,n=48,z=0):
    return [(rx*math.sin(i*math.tau/n),y,z+rz*math.cos(i*math.tau/n)) for i in range(n+1)]


def quiver_shell():
    rings=[(-.325,.077,.062),(-.312,.098,.077),(-.265,.109,.082),(.262,.119,.086),(.318,.125,.09)]
    n=48;vs=[];uv=[];fs=[]
    for y,rx,rz in rings:
        for j in range(n+1):
            a=j*math.tau/n
            vs.append((rx*math.sin(a),y,rz*math.cos(a)))
            uv.append((j/n,(y+.325)/.65))
    for i in range(len(rings)-1):
        for j in range(n):
            a=i*(n+1)+j
            fs.append((a,a+1,a+n+2,a+n+1))
    fs.append(tuple(range(n,-1,-1)))
    return mesh("Molded leather cup",vs,fs,M["Saddle leather"],uv,True)


def strap(name,points,width,material):
    # A solid flat strap with a readable colored face, not a round wire.
    vs=[];uv=[];fs=[]
    for i,p in enumerate(points):
        prev=Vector(points[max(0,i-1)]);after=Vector(points[min(len(points)-1,i+1)])
        t=(after-prev).normalized();side=t.cross(Vector((0,0,1))).normalized()*width*.5
        for s in (-1,1):
            vs.append(tuple(Vector(p)+s*side));uv.append(((s+1)*.5,i/max(1,len(points)-1)))
    for i in range(len(points)-1):fs.append((i*2,i*2+1,i*2+3,i*2+2))
    ob=mesh(name,vs,fs,material,uv)
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new("Leather strap thickness","SOLIDIFY");mod.thickness=.010;mod.offset=0
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def buckle(name,center,w,h):
    x,y,z=center
    outline=[(x-w/2,y-h/2,z),(x+w/2,y-h/2,z),(x+w/2,y+h/2,z),(x-w/2,y+h/2,z),(x-w/2,y-h/2,z)]
    return [tube(name,outline,.007,M["Forged steel"],8),tube(name+" pin",[(x,y-h/2,z-.001),(x,y+h/2,z-.001)],.004,M["Forged steel"],6)]


def make_quiver():
    new_scene()
    root=empty("Quiver")
    parts=[quiver_shell()]
    # Hollow rolled mouth, inset lining, reinforced bottom and stitched edges.
    for y in (.265,.286,.31):
        parts.append(tube("Rolled open collar",oval(y,.125,.092),.017,M["Leather edge"],8))
    inner=mesh("Dark quiver lining",[(0,.268,0)]+oval(.268,.108,.075)[:-1],[(0,1+i,1+(i+1)%48) for i in range(48)],M["Wood shadow"])
    parts.append(inner)
    for y,rx,rz in ((-.297,.098,.077),(-.273,.106,.082)):
        parts.append(tube("Reinforced foot piping",oval(y,rx,rz),.005,M["Leather edge"],7))
    # Y/X blue-edged red harness matches the supplied front/back accessory views.
    for side in (-1,1):
        path=[(side*.116,.171,-.064),(side*.058,.106,-.099),(0,.060,-.105),(side*.010,-.048,-.105),(side*.103,-.199,-.07)]
        parts.append(strap("Blue harness trim",path,.039,M["Harness blue"]))
        parts.append(strap("Crimson strap inset",[(x,y,z-.006) for x,y,z in path],.018,M["Harness red"]))
    parts.extend(buckle("Front harness keeper",(0,.046,-.116),.047,.043))
    parts.extend(buckle("Front lower keeper",(0,-.087,-.116),.041,.035))
    for y in (.171,-.167):
        parts.append(strap("Rear harness",[(-.104,y,.066),(0,y,.098),(.104,y,.066)],.039,M["Harness red"]))
        parts.extend(buckle("Rear silver buckle",(0,y,.110),.061,.047))
    # Broad red shoulder loop hangs close to the side, as in the reference.
    loop=[(-.11,.193,.02),(-.190,.16,.04),(-.245,.045,.043),(-.235,-.151,.03),(-.198,-.196,.018),(-.101,-.187,.012)]
    parts.append(strap("Red shoulder loop",loop,.040,M["Harness red"]))
    parts.append(tube("Shoulder loop dark edge",[(x-.016,y,z) for x,y,z in loop],.004,M["Wood shadow"],6))
    # Fine stitching and embossed border sit above the leather, not decals.
    for side in (-1,1):
        outline=[(side*.099,.238,-.060),(side*.09,.187,-.074),(side*.080,-.188,-.073),(side*.063,-.269,-.071),(0,-.282,-.079)]
        parts.append(tube("Embossed border",outline,.0029,M["Leather edge"],5))
        for i in range(25):
            y=-.247+i*.019
            x=side*(.080+(y+.247)*.034)
            parts.append(tube("Hand stitched side",[(x-.003,y,-.079),(x+.003,y+.005,-.080)],.0014,M["Linen stitching"],5))
    # Embossed V motif is intentionally below the bright rolled collar.
    parts.append(tube("Stamped V emblem",[(-.075,.234,-.087),(0,.187,-.096),(.075,.234,-.087)],.0038,M["Wood shadow"],6))
    # Four stored arrows, with the same broadhead and feather profile as projectile.
    for i in range(4):
        arrow=join("Stored arrow",arrow_geometry("Stored ",scale=.70))
        # Original arrow runs +Z; rotate its shaft into Godot +Y.
        arrow.rotation_euler[0]=-math.pi/2
        arrow.location=gv((-.057+i*.038,-.094+(i%2)*.032,.007+(i%2)*.014))
        bpy.context.view_layer.objects.active=arrow
        bpy.ops.object.select_all(action="DESELECT");arrow.select_set(True)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
        parts.append(arrow)
    join("QuiverMesh",parts).parent=root
    empty("QuiverMouth",(0,.319,0)).parent=root
    return root


def glb_metrics(path):
    with path.open("rb") as file:
        file.read(12)
        size,_=struct.unpack("<II",file.read(8))
        data=json.loads(file.read(size))
    return {"mesh_nodes":sum("mesh" in n for n in data["nodes"]),
            "triangles":sum(data["accessors"][p["indices"]]["count"]//3 for m in data["meshes"] for p in m["primitives"]),
            "materials":len(data.get("materials",[])),"textures":len(data.get("textures",[])),
            "nodes":[n.get("name","") for n in data["nodes"]],"bytes":path.stat().st_size}


def bounds():
    points=[obj.matrix_world@Vector(p) for obj in bpy.context.scene.objects if obj.type=="MESH" for p in obj.bound_box]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return lo,hi


def studio(name,root):
    bpy.context.view_layer.update()
    lo,hi=bounds();center=(lo+hi)*.5
    scene=bpy.context.scene
    scene.render.engine="CYCLES"
    scene.cycles.samples=32
    scene.cycles.use_denoising=True
    scene.render.resolution_x=600;scene.render.resolution_y=600
    scene.render.resolution_percentage=100
    scene.world.color=(.24,.24,.24)
    scene.view_settings.view_transform="AgX"
    floor=mat("Studio backdrop",(193,188,174),.9)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,lo.z-.02))
    bpy.context.object.data.materials.append(floor)
    helpers=[bpy.context.object]
    for loc,power,size in [((3,-4,5),650,4),((-3,-1,3),420,3),((0,4,4),750,2)]:
        bpy.ops.object.light_add(type="AREA",location=loc)
        light=bpy.context.object;light.data.energy=power;light.data.shape="DISK";light.data.size=size
        light.rotation_euler=(center-light.location).to_track_quat("-Z","Y").to_euler();helpers.append(light)
    bpy.ops.object.camera_add()
    camera=bpy.context.object;helpers.append(camera);scene.camera=camera;camera.data.type="ORTHO"
    extent=max(hi-lo)
    camera.data.ortho_scale=extent*1.24
    # For the arrow, turn it upright for larger readable panel silhouettes.
    if name=="arrow":
        root.rotation_euler[0]=math.pi/2
        bpy.context.view_layer.update()
        lo,hi=bounds_for_root(root)
        center=(lo+hi)*.5
        camera.data.ortho_scale=.95*1.28
    directions=[(4,-2.2,1.0),(4,.25,.35),(-3,2,.8)] if name=="longbow" else [(1,-4,1.0),(4,-.5,.65),(-1,4,.8)]
    for i,direction in enumerate(directions):
        camera.location=center+Vector(direction)
        camera.rotation_euler=(center-camera.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath=str(CAP/f"archery_{name}_{i+1}.png")
        bpy.ops.render.render(write_still=True)
    if name=="arrow":root.rotation_euler=(0,0,0)
    for obj in helpers:bpy.data.objects.remove(obj,do_unlink=True)


def bounds_for_root(root):
    points=[obj.matrix_world@Vector(p) for obj in root.children_recursive if obj.type=="MESH" for p in obj.bound_box]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return lo,hi


def export(name,builder):
    root=builder();bpy.context.view_layer.update()
    lo,hi=bounds()
    size=hi-lo
    # Store useful rig contract in the native asset, without coupling it to scripts.
    root["coordinate_system"]="Godot +Y up, -Z forward"
    root["reference"]="User supplied archery components and character turnaround, September 2026"
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active=root
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+".blend")),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,export_yup=True,export_apply=True,export_extras=True)
    report=glb_metrics(OUT/(name+".glb"))
    report["bounds_godot"]={"x":round(size.x,4),"y":round(size.z,4),"z":round(size.y,4)}
    studio(name,root)
    return report


def contact_sheet():
    # All views remain lossless and individually inspectable; the sheet is a quick QA overview.
    w,h=600,600
    canvas=np.ones((h*3,w*3,4),dtype=np.float32)
    for row,name in enumerate(("longbow","quiver","arrow")):
        for col in range(3):
            im=bpy.data.images.load(str(CAP/f"archery_{name}_{col+1}.png"),check_existing=False)
            values=np.asarray(im.pixels[:],dtype=np.float32).reshape(h,w,4)
            canvas[(2-row)*h:(3-row)*h,col*w:(col+1)*w]=values
    im=bpy.data.images.new("Archery reference equipment contact sheet",w*3,h*3,alpha=True)
    im.pixels.foreach_set(canvas.ravel());im.filepath_raw=str(CAP/"archery_equipment_contact_sheet.png");im.file_format="PNG";im.save()


mat("Yew wood",(121,77,37),.56,family="wood")
mat("Sapwood edge",(158,108,55),.58)
mat("Wood shadow",(44,28,23),.81)
mat("Horn tip",(59,42,31),.49)
mat("Grip leather",(67,48,33),.83)
mat("Dull brass",(145,125,87),.44,.65)
mat("Linen stitching",(175,146,99),.91)
mat("Linen string",(141,118,88),.85)
mat("Forged steel",(169,187,197),.32,.82)
mat("Saddle leather",(130,80,41),.75,family="leather")
mat("Leather edge",(156,104,56),.68)
mat("Harness red",(118,40,30),.68)
mat("Harness blue",(61,79,104),.63)
mat("Tan feathers",(195,163,113),.86,family="feather")
mat("Feather barb",(123,95,61),.88)
results={"longbow":export("longbow",make_bow),"arrow":export("arrow",make_arrow),"quiver":export("quiver",make_quiver)}
contact_sheet()
(OUT/"archery_metrics.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
print("ARCHERY_ASSETS_COMPLETE "+json.dumps(results))
