import bpy
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "characters"
OUT.mkdir(parents=True, exist_ok=True)


def gv(point):
    return Vector((point[0], -point[2], point[1]))


def material(name, color, metallic=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = .69
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = gv(location)
    return obj


def finish(obj, name, mat, parent, location):
    obj.name = name
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.parent = parent
    obj.location = gv(location)
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, center, size, mat, parent, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    finish(obj, name, mat, parent, center)
    if bevel:
        mod = obj.modifiers.new("Hand forged edges", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def sphere(name, center, size, mat, parent, segments=10, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings)
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    return finish(obj, name, mat, parent, center)


def cone(name, a, b, r1, r2, mat, parent, vertices=8):
    v = gv(b) - gv(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=v.length)
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(v.normalized())
    mid = tuple((a[i] + b[i]) / 2 for i in range(3))
    return finish(obj, name, mat, parent, mid)


def mesh(name, vertices, faces, mat, parent):
    data = bpy.data.meshes.new(name)
    data.from_pydata([gv(v) for v in vertices], [], faces)
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    return obj


def shield_layer(name, factor, depth, mat, parent):
    outline = [(-.32, .28), (-.21, .36), (.21, .36), (.32, .28), (.28, -.13), (0, -.43), (-.28, -.13)]
    vertices = [(x * factor, y * factor, depth) for x, y in outline]
    vertices += [(x * factor, y * factor, depth + .055) for x, y in outline]
    faces = [tuple(range(6, -1, -1)), tuple(range(7, 14))]
    faces += [(i, (i + 1) % 7, (i + 1) % 7 + 7, i + 7) for i in range(7)]
    return mesh(name, vertices, faces, mat, parent)


def build(boss=False):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    steel = material("Armor | storm silver" if not boss else "Armor | iron plum", (.43, .59, .60) if not boss else (.27, .24, .30), .45)
    light = material("Armor | edge highlights", (.78, .83, .75) if not boss else (.59, .50, .45), .55)
    dark = material("Leather | ink", (.045, .070, .074) if not boss else (.055, .038, .050))
    leather = material("Leather | oxblood", (.23, .10, .10))
    gold = material("Inlay | antique brass", (.72, .49, .19), .65)
    cloth = material("Cloth | deep teal" if not boss else "Cloth | madder red", (.035, .32, .28) if not boss else (.38, .065, .115))
    cloth_light = material("Cloth | worn folds", (.09, .45, .35) if not boss else (.57, .12, .16))
    blade = material("Blade | moonsteel", (.81, .91, .91), .68)
    fuller = material("Blade | blue temper", (.23, .44, .49), .5)
    eye = material("Eyes | lantern", (.9, .54, .12) if boss else (.27, .91, .76), .0, 2)

    rig = empty("Rig", (0, 0, 0))
    hips = empty("Hips", (0, .87, 0), rig)
    torso = empty("Torso", (0, .15, 0), hips)
    head = empty("Head", (0, .53, -.01), torso)
    box("Padded waist", (0, 0, 0), (.40, .23, .28), dark, hips, .06)
    box("Leather belt", (0, .035, -.005), (.48, .075, .32), leather, hips)
    box("Belt buckle", (0, .035, -.19), (.13, .10, .045), gold, hips, .012)
    for side in [-1, 1]:
        for j in range(3):
            obj = box("Overlapping hip lames", (side * (.22 + j * .007), -.12 - j * .085, .005), (.16, .12, .35), steel, hips, .02)
            obj.rotation_euler.y = side * -.13
    # Breastplate facets make the armor readable at an elevated game camera.
    sphere("Forged breastplate", (0, .255, -.015), (.275, .30, .185), steel, torso)
    mesh("Breastplate center ridge", [(-.11,.04,-.18),(.11,.04,-.18),(.13,.42,-.155),(0,.47,-.215),(-.13,.42,-.155),(0,.19,-.24)], [(0,1,5),(1,2,3,5),(3,4,0,5)], light, torso)
    box("Gorget", (0,.475,-.005), (.33,.09,.29), gold, torso, .035)
    for side in [-1,1]:
        cone("Breastplate edging", (side*.23,.08,-.12),(side*.245,.39,-.115),.015,.015,gold,torso)
    # A hanging surcoat has its own cloth pivot, separate from leg collisions.
    tabard = empty("Tabard", (0,-.025,-.18), hips)
    mesh("Split teal surcoat", [(-.19,0,0),(.19,0,0),(.16,-.41,.04),(.035,-.48,.045),(0,-.31,.01),(-.055,-.47,.04),(-.17,-.40,.04)], [(0,1,4),(1,2,3,4),(4,5,6,0)], cloth, tabard)
    cone("Surcoat center braid", (0,-.03,-.01),(0,-.30,.0),.012,.012,gold,tabard,6)
    cape = empty("Cape", (0,.43,.15), torso)
    cape_verts = [(-.23,0,0),(0,.045,.045),(.23,0,0),(-.34,-.38,.18),(0,-.36,.30),(.34,-.38,.18),(-.40,-.79,.24),(-.21,-.92,.33),(-.045,-.81,.36),(.12,-.94,.36),(.32,-.83,.28),(.41,-.68,.20)]
    cape_faces = [(0,1,4,3),(1,2,5,4),(3,4,8,7,6),(4,5,11,10,9,8)]
    mesh("Tattered travel cloak",cape_verts,cape_faces,cloth,cape)
    mesh("Raised cloak folds",[(0,.04,.052),(-.07,-.33,.307),(-.045,-.81,.367),(.06,-.38,.299),(.12,-.94,.365)],[(0,1,2,3),(0,3,4)],cloth_light,cape)
    for side in [-1,1]:
        sphere("Cloak clasp",(side*.23,.41,-.105),(.052,.052,.035),gold,torso,8,4)

    # Helmet silhouette, cheek guards and inset eye opening.
    sphere("Helmet skull",(0,.13,.0),(.207,.25,.19),steel,head,12,7)
    box("Visor shadow",(0,.12,-.184),(.34,.080,.06),dark,head,.015)
    box("Visor brow",(0,.19,-.194),(.37,.055,.055),light,head,.012)
    for side in [-1,1]:
        box("Visor eye",(side*.081,.13,-.219),(.09,.022,.012),eye,head,.003)
        cheek = mesh("Angular cheekguard",[(side*.19,.10,-.12),(side*.14,-.10,-.14),(side*.04,-.075,-.23),(side*.05,.065,-.23)],[(0,1,2,3)],steel,head)
        cone("Cheek brass line",(side*.18,.08,-.15),(side*.13,-.09,-.17),.011,.011,gold,head,6)
    box("Helmet central nasal",(0,.062,-.226),(.028,.22,.037),light,head,.006)
    cone("Helmet ridge",(0,.37,.055),(0,.28,-.135),.040,.030,gold,head,6)
    if boss:
        for side in [-1,1]:
            cone("Crown lower antler",(side*.15,.26,.015),(side*.36,.47,.055),.067,.044,gold,head)
            cone("Crown upper antler",(side*.36,.47,.055),(side*.46,.73,.10),.044,.003,gold,head)
            cone("Crown tine",(side*.32,.43,.05),(side*.26,.67,-.015),.035,.004,gold,head)
            cone("Crown rear tine",(side*.40,.58,.08),(side*.57,.66,.20),.028,.003,gold,head)
        cone("Crown central spike",(0,.33,-.12),(0,.59,-.095),.060,.0,gold,head)
    else:
        plume = empty("Plume",(0,.33,.04),head)
        mesh("Swept helmet plume",[(-.055,0,0),(.055,0,0),(-.052,.16,.13),(.052,.16,.13),(-.035,.09,.38),(.035,.09,.38),(0,-.08,.47)],[(0,1,3,2),(2,3,5,4),(4,5,6)],cloth_light,plume)

    hands = {}
    for side, tag in [(1,"R"),(-1,"L")]:
        upper = empty("UpperArm"+tag,(side*.32,.38,0),torso)
        elbow = empty("Forearm"+tag,(0,-.285,0),upper)
        hand = empty("Hand"+tag,(0,-.285,0),elbow)
        hands[tag] = hand
        sphere("Shoulder leather "+tag,(0,-.055,0),(.155,.14,.15),dark,upper)
        sphere("Layered pauldron "+tag,(side*.045,-.045,0),(.20,.145,.19),steel,upper)
        box("Pauldron edge "+tag,(side*.09,-.128,-.018),(.22,.045,.33),gold,upper,.018)
        cone("Upper arm sleeve "+tag,(0,-.10,0),(0,-.25,0),.103,.094,cloth,upper)
        sphere("Elbow joint "+tag,(0,0,0),(.105,.095,.107),dark,elbow)
        sphere("Elbow cop "+tag,(side*.025,0,.045),(.12,.12,.12),steel,elbow)
        cone("Vambrace "+tag,(0,-.07,0),(0,-.245,0),.10,.075,steel,elbow)
        cone("Bracer cuff "+tag,(0,-.225,0),(0,-.265,0),.09,.09,gold,elbow)
        box("Leather fist "+tag,(0,-.025,-.01),(.135,.125,.13),leather,hand,.025)
        box("Knuckle plate "+tag,(0,-.03,-.077),(.14,.095,.035),light,hand,.012)
        thigh = empty("Thigh"+tag,(side*.145,-.07,0),hips)
        shin = empty("Shin"+tag,(0,-.39,0),thigh)
        foot = empty("Foot"+tag,(0,-.33,0),shin)
        cone("Padded thigh "+tag,(0,-.03,0),(0,-.32,0),.12,.095,dark,thigh)
        box("Thigh plate "+tag,(0,-.18,-.062),(.19,.285,.15),steel,thigh,.035)
        sphere("Kneecap "+tag,(0,-.015,-.045),(.115,.12,.11),light,shin)
        cone("Shin greave "+tag,(0,-.06,0),(0,-.29,0),.10,.073,steel,shin)
        cone("Greave ridge "+tag,(0,-.08,-.101),(0,-.28,-.071),.016,.012,gold,shin,6)
        box("Leather boot "+tag,(0,-.012,-.046),(.18,.145,.32),dark,foot,.035)
        box("Armored toe "+tag,(0,.012,-.126),(.19,.10,.19),steel,foot,.03)

    sword = empty("Sword",(0,-.06,0),hands["R"])
    # Blade points down the forearm axis at rest; articulated arms swing it into the cutting plane.
    cone("Sword leather grip",(0,.11,0),(0,-.14,0),.034,.034,leather,sword)
    for y in [.06,.015,-.03,-.075]:
        cone("Sword grip winding",(0,y+.009,0),(0,y-.009,0),.037,.037,gold,sword,8)
    sphere("Sword pommel",(0,.145,0),(.060,.070,.055),gold,sword,8,4)
    box("Sword crossguard",(0,-.16,0),(.42,.070,.09),gold,sword,.02)
    cone("Curved quillon R",(.16,-.16,0),(.24,-.205,0),.035,.014,gold,sword)
    cone("Curved quillon L",(-.16,-.16,0),(-.24,-.205,0),.035,.014,gold,sword)
    length = 1.14 if not boss else 1.23
    width = .073 if not boss else .10
    verts = [(-width,-.19,0),(width,-.19,0),(-width*.82,-length,0),(width*.82,-length,0),(0,-length-.21,0),(0,-.19,-.045),(0,-length,-.032),(0,-.19,.045),(0,-length,.032)]
    mesh("Moonsteel blade",verts,[(0,2,6,5),(5,6,3,1),(2,4,6),(6,4,3),(0,7,8,2),(7,1,3,8),(2,8,4),(8,3,4)],blade,sword)
    mesh("Blade central fuller",[(-.016,-.23,-.047),(.016,-.23,-.047),(.011,-length+.13,-.038),(-.011,-length+.13,-.038)],[(0,1,2,3)],fuller,sword)
    empty("BladeHilt",(0,-.19,0),sword)
    empty("BladeTip",(0,-length-.21,0),sword)

    shield = empty("Shield",(0,-.01,-.075),hands["L"])
    shield_layer("Shield brass silhouette",1.0,-.01,gold,shield)
    shield_layer("Shield dark bevel",.91,-.024,dark,shield)
    shield_layer("Shield enamel face",.83,-.039,cloth,shield)
    box("Shield ridge",(0,-.018,-.075),(.028,.62,.020),gold,shield,.005)
    for side in [-1,1]:
        cone("Shield heraldry branch",(0,-.05,-.082),(side*.18,.13,-.082),.016,.010,light,shield,6)
        cone("Shield heraldry leaf",(side*.10,.05,-.083),(side*.09,.21,-.083),.014,.003,light,shield,6)
    sphere("Shield boss",(0,.065,-.095),(.073,.073,.042),gold,shield,8,4)
    for x,y in [(-.24,.23),(.24,.23),(-.20,-.12),(.20,-.12),(0,-.33)]:
        sphere("Shield rivet",(x,y,-.079),(.021,.021,.015),light,shield,8,4)
    if boss:
        # The lord has a ragged iron buckler and broad silhouette, keeping parry poses readable.
        for side in [-1,1]:
            cone("Shoulder thorn",(side*.35,.41,.0),(side*.58,.69,.035),.087,.002,gold,torso)
        rig.scale = (1.47,1.47,1.47)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = rig
    stem = "thorn_lord" if boss else "wayfarer"
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(stem+".blend")))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(stem+".glb")),export_format="GLB",use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
    print("CHARACTER_READY",stem,"objects",len(bpy.data.objects))


build(False)
build(True)
