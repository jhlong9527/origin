"""Blender character reconstruction from the user supplied turnaround images.
Keeps the gameplay pivot names; replaces all geometry, palette and equipment.
Coordinates in helpers are Godot (+Y up, -Z forward); conversion occurs at mesh creation.
"""
import bpy, math, json, random
from mathutils import Vector
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'characters'
lib = {'__file__': str(ROOT/'tools'/'build_characters.py')}
exec((ROOT/'tools'/'build_characters.py').read_text(encoding='utf8').split('\nresults=dict(')[0], lib)
mesh, sphere, box, tube, loft, arc, solid, smooth, gv = [lib[k] for k in ['mesh','sphere','box','tube','loft','arc','solid','smooth','gv']]
M = {}

def material(name, color, family, metal=0, rough=.8, emission=0):
    m = bpy.data.materials.new('Ref '+family+' | '+name)
    m.diffuse_color=(*lib['linear'](color),1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    if emission:
        p.inputs['Emission Color'].default_value=m.diffuse_color
        p.inputs['Emission Strength'].default_value=emission
    M[name]=m
    return m

def orb(name,p,size,m,parent,segments=24,rings=14):
    return smooth(sphere(name,p,size,m,parent,segments,rings))

def line(name,points,radius,m,parent,sides=8):
    return tube(name,points,[radius]*len(points),m,parent,sides)

def ribbon(name,a,b,width,depth,m,parent):
    a,b=Vector(a),Vector(b); side=Vector((b.y-a.y,a.x-b.x,0)).normalized()*width*.5
    return solid(mesh(name,[tuple(a-side),tuple(a+side),tuple(b+side),tuple(b-side)],[(0,1,2,3)],m,parent),depth)

def gem(name,center,width,height,depth,m,parent):
    x,y,z=center
    verts=[(x,y+height/2,z),(x+width/2,y,z),(x,y-height/2,z),(x-width/2,y,z),(x,y,z-depth)]
    ob=mesh(name,verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],m,parent)
    return ob

def drape(name,parent,cloth,shadow,edge,width,length,tattered=False):
    cols,rows=32,22; pts=[]
    for j in range(rows+1):
        v=j/rows
        for i in range(cols+1):
            u=i/cols
            x=(u-.5)*2*width*(.54+.46*v)
            tear=(.10*(.5+.5*math.sin(i*1.81)) + .055*math.sin(i*.7)) if tattered else .026*math.cos(i*.7)
            y=-length*v+tear*v**9
            z=.07+.23*v+math.cos(u*math.pi*8)*(.014+.039*v)
            pts.append((x,y,z))
    faces=[]
    for j in range(rows):
        for i in range(cols):
            a=j*(cols+1)+i; faces.append((a,a+1,a+cols+2,a+cols+1))
    ob=smooth(mesh(name,pts,faces,cloth,parent)); ob.data.materials.append(shadow)
    for p in ob.data.polygons:
        p.material_index=1 if (p.index%cols)%8 in [4,5] else 0
    solid(ob,.018)
    for k in [0,cols]: line(name+' sewn side',[pts[j*(cols+1)+k] for j in range(rows+1)],.005,edge,parent,6)
    line(name+' hem',[pts[rows*(cols+1)+i] for i in range(cols+1)],.006,edge,parent,6)

def hair_lock(name,points,radii,m,parent):
    # Broad overlapping tapered hair clumps, with a raised ridge along the strand.
    ob=tube(name,points,radii,m,parent,7)
    for face in ob.data.polygons: face.use_smooth=False
    return ob

def setup(boss):
    lib['legacy']['build'](boss)
    nodes={o.name:o for o in bpy.context.scene.objects if o.type=='EMPTY'}
    for ob in list(bpy.context.scene.objects):
        if ob.type=='MESH': bpy.data.objects.remove(ob,do_unlink=True)
    for m in list(bpy.data.materials):
        if m.users==0: bpy.data.materials.remove(m)
    return nodes

def face_player(n):
    h=n['Head']; skin=M['warm skin']; hair=M['chestnut']; shade=M['hair shadow']; highlight=M['hair ridge']
    h.location += gv((0,.045,0))
    h.scale=(1.08,1.06,1.05)
    # Broad youthful cranium, tapered jaw, individually shaped ears and nose.
    loft('Face cranium and jaw',h,skin,[(-.16,.078,.112,-.018),(-.10,.157,.159,-.02),(.015,.225,.203,-.014),(.18,.247,.225,.0),(.33,.226,.204,.017),(.42,.13,.13,.026)],n=40)
    for s in [-1,1]:
        orb('Ear helix',(s*.243,.07,.007),(.057,.088,.033),skin,h)
        orb('Ear inner',(s*.268,.07,-.011),(.025,.049,.016),M['skin shade'],h)
        # Eye whites inset beneath an upper lid and brow. Dark lashes anchor expression.
        orb('Eye socket',(s*.112,.137,-.208),(.075,.051,.019),M['skin shade'],h)
        orb('Eye white',(s*.112,.145,-.226),(.063,.038,.014),M['eye white'],h)
        orb('Iris',(s*.113,.144,-.239),(.025,.032,.007),M['iris'],h)
        orb('Pupil',(s*.113,.147,-.246),(.014,.024,.005),M['hair shadow'],h)
        orb('Eye catchlight',(s*.113-.008,.159,-.251),(.006,.008,.003),M['eye white'],h,12,8)
        line('Upper eyelid',[(s*.047,.167,-.229),(s*.095,.182,-.230),(s*.170,.175,-.209)],.010,shade,h)
        line('Determined eyebrow',[(s*.055,.205,-.216),(s*.119,.233,-.218),(s*.184,.216,-.190)],.020,shade,h)
    mesh('Small angular nose',[(-.025,.088,-.218),(.025,.088,-.218),(0,.031,-.280),(-.029,.016,-.224),(.029,.016,-.224)],[(0,2,1),(0,3,2),(2,4,1),(3,4,2)],skin,h)
    line('Mouth relaxed',[(-.039,-.035,-.216),(0,-.042,-.228),(.039,-.033,-.216)],.006,M['skin shade'],h)
    # Sculpted hair cap, broken into overlapping coarse spikes with smaller strand ridges.
    orb('Hair underlayer',(0,.295,.022),(.274,.253,.240),shade,h,32,18)
    rng=random.Random(53)
    for i in range(13):
        a=-1.5+i*3.0/12
        hair_lock('Nape and back hair',[(math.sin(a)*.22,.27,math.cos(a)*.205),
            (math.sin(a)*.247,.115,math.cos(a)*.217),
            (math.sin(a)*.227,-.04+(.025 if i%2 else 0),math.cos(a)*.186)],
            [.085,.079,.001],hair if i%3 else shade,h)
    for i in range(18):
        a=i*math.tau/18
        p0=(math.sin(a)*.08,.44,math.cos(a)*.08)
        p1=(math.sin(a)*.23,.40,math.cos(a)*.21)
        p2=(math.sin(a)*.278,.23+rng.uniform(-.06,.06),math.cos(a)*.247)
        p3=(math.sin(a)*.287,.16+rng.uniform(-.07,.04),math.cos(a)*.253)
        hair_lock('Layered hair locks',[p0,p1,p2,p3],[.06,.080,.049,.001],hair if i%3 else highlight,h)
    bangs=[(-.24,.27,-.22),(-.18,.18,-.244),(-.09,.235,-.266),(.005,.245,-.26),(.105,.27,-.23),(.218,.19,-.215)]
    for i,tip in enumerate(bangs):
        root=(tip[0]*.5+.065,.47,-.07); mid=(tip[0]*.83+.028,.36,-.205)
        hair_lock('Swept fringe',[root,mid,tip],[.074,.085,.001],hair if i%2 else highlight,h)
        line('Hair strand ridge',[root,(mid[0],mid[1]+.025,mid[2]-.025),(tip[0]*.98,tip[1]+.05,tip[2]-.008)],.005,highlight,h,5)
    for i in range(7):
        a=i*.91
        hair_lock('Tousled crown spike',[(math.sin(a)*.09,.46,math.cos(a)*.08),(math.sin(a)*.17+.045,.54,math.cos(a)*.12), (math.sin(a)*.26+.07,.56+(.04 if i%2 else 0),math.cos(a)*.15)],[.081,.062,.001],hair if i%2 else highlight,h)

def player(n):
    material('warm skin','d79b69','skin'); material('skin shade','935d42','skin')
    material('chestnut','4e301e','hair'); material('hair shadow','241b1a','hair'); material('hair ridge','714726','hair')
    material('eye white','edebe0','eye'); material('iris','36556b','eye')
    material('blue tunic','315c80','cloth'); material('tunic fold','244563','cloth'); material('gold stitching','bf9658','cloth')
    material('red cape','a22e29','cloth'); material('cape shadow','63222c','cloth'); material('cape edge','bd4733','cloth')
    material('leather','60412e','leather'); material('leather edge','87613b','leather'); material('pants','36352f','cloth')
    material('steel','aec7d4','metal',.75,.29); material('steel shade','526a7b','metal',.65,.4)
    material('gold','c09a4f','metal',.7,.38); material('wood','89532d','wood'); material('wood light','a8743f','wood'); material('wood grain','4d301e','wood')
    hips,torso=n['Hips'],n['Torso']; tunic=M['blue tunic']; leather=M['leather']; red=M['red cape']; steel=M['steel']
    loft('Cloth waist',hips,M['pants'],[(-.12,.24,.153,0),(.14,.23,.154,0)],n=28)
    loft('Tailored short tunic',torso,tunic,[(-.22,.29,.186,0),(-.15,.278,.171,0),(.04,.216,.147,0),(.22,.268,.180,-.005),(.38,.286,.159,.004),(.49,.160,.114,0)],n=36)
    arc('Gold tunic hem',torso,M['gold stitching'],.29,.189,-.213,r=.016,n=36)
    for side in [-1,1]:
        line('Tunic side seam',[(side*.226,.26,.04),(side*.225,.06,.07),(side*.276,-.19,.08)],.004,M['gold stitching'],torso,5)
    loft('Waist belt',hips,leather,[(-.012,.266,.181,-.015),(.076,.258,.178,-.015)],n=32)
    box('Silver belt buckle',(0,.032,-.20),(.139,.110,.045),steel,hips,.012)
    box('Buckle open interior',(0,.032,-.226),(.086,.060,.008),leather,hips,.008)
    ribbon('Diagonal shoulder strap',(-.23,.43,-.16),(.23,.065,-.18),.087,.025,leather,torso)
    box('Strap square keeper',(.022,.243,-.216),(.099,.066,.024),M['gold'],torso,.005)
    for i in range(3):
        arc('Layered red scarf',torso,red if i%2 else M['cape shadow'],.204+i*.015,.15+i*.014,.48-i*.042,cz=-.012,r=.047,n=44)
    # Folded triangular scarf point lies on chest rather than floating at neck.
    solid(mesh('Scarf front fold',[(-.20,.43,-.142),(.20,.44,-.14),(.13,.335,-.192),(-.02,.315,-.224),(-.13,.35,-.20)],[(0,1,2,3,4)],red,torso),.025)
    drape('Red travel cloak',n['Cape'],red,M['cape shadow'],M['cape edge'],.50,1.15)
    # Detailed brown pack mounted over the cloak, with visible flap, pocket, straps.
    box('Backpack body',(0,.155,.322),(.46,.57,.24),leather,torso,.085)
    box('Rounded pack flap',(0,.386,.348),(.47,.19,.29),M['leather edge'],torso,.067)
    box('Front pack pocket',(0,-.014,.457),(.34,.22,.085),M['leather edge'],torso,.045)
    line('Pocket piping',[(-.15,-.03,.504),(-.12,-.103,.506),(.12,-.103,.506),(.15,-.025,.505)],.008,leather,torso)
    ribbon('Pack center strap',(0,.32,.505),(0,.012,.511),.061,.018,leather,torso)
    box('Pack clasp',(0,.074,.526),(.074,.060,.024),steel,torso,.009)
    for side in [-1,1]:
        box('Pack side pouch',(side*.262,.04,.337),(.09,.23,.16),leather,torso,.032)
        line('Backpack shoulder strap',[(side*.17,.42,.23),(side*.24,.27,.195),(side*.235,.04,.185)],.027,leather,torso)
    face_player(n)
    for tag,side in [('R',1),('L',-1)]:
        upper,fore,hand=n['UpperArm'+tag],n['Forearm'+tag],n['Hand'+tag]
        loft('Short blue sleeve',upper,tunic,[(.065,.068,.07,0),(.025,.133,.126,0),(-.07,.129,.122,0),(-.145,.120,.114,0)],n=28)
        arc('Sleeve gold seam',upper,M['gold stitching'],.126,.12,-.135,r=.012,n=28)
        loft('Bare upper arm',upper,M['warm skin'],[(-.13,.093,.098,0),(-.275,.079,.080,0)],n=24)
        orb('Bare elbow',(0,0,0),(.084,.090,.082),M['warm skin'],fore)
        loft('Leather bracer',fore,leather,[(-.05,.094,.094,0),(-.13,.09,.09,0),(-.255,.072,.075,0)],n=24)
        for y in [-.09,-.20]:arc('Bracer strap',fore,M['leather edge'],.093 if y>-.15 else .08,.094 if y>-.15 else .081,y,r=.014)
        box('Bracer buckle',(side*.087,-.10,0),(.027,.047,.045),M['gold'],fore,.004)
        orb('Gloved palm',(0,-.026,-.006),(.077,.074,.07),leather,hand)
        for k in range(4):orb('Gloved fingers',((k-1.5)*.035,-.040,-.054),(.022,.047,.026),leather,hand,16,10)
        orb('Gloved thumb',(side*.07,-.015,-.027),(.028,.047,.034),M['leather edge'],hand)
        thigh,shin,foot=n['Thigh'+tag],n['Shin'+tag],n['Foot'+tag]
        loft('Loose charcoal trousers',thigh,M['pants'],[(-.01,.131,.13,0),(-.17,.143,.14,.006),(-.33,.113,.106,-.02),(-.39,.107,.103,0)],n=28)
        arc('Knee fabric crease',thigh,M['tunic fold'],.116,.114,-.32,a=1.3,b=4.9,r=.015)
        loft('Tall leather boot shaft',shin,leather,[(-.04,.12,.115,0),(-.12,.114,.110,0),(-.285,.086,.089,0)],n=28)
        loft('Folded boot cuff',shin,M['leather edge'],[(.012,.122,.119,0),(-.045,.13,.13,0),(-.085,.12,.119,0)],n=28)
        arc('Boot ankle strap',shin,M['leather edge'],.092,.093,-.24,r=.018)
        box('Boot welt sole',(0,-.057,-.080),(.217,.060,.368),M['wood grain'],foot,.035)
        orb('Rounded leather boot',(0,.006,-.09),(.112,.082,.186),leather,foot)
        line('Boot toe stitching',[(-.076,.025,-.20),(0,.045,-.263),(.076,.025,-.20)],.005,M['leather edge'],foot,6)
    weapon(n,False)

def weapon(n,boss):
    sword=n['Sword']; steel=M['steel']; dark=M['steel shade']; leather=M['leather']; gold=M['gold']
    loft('Bound sword grip',sword,leather,[(-.15,.038,.035,0),(.13,.036,.034,0)],n=20)
    for j in range(9):arc('Grip binding',sword,dark if boss else gold,.04,.037,-.12+j*.028,r=.003,n=16)
    orb('Sword pommel',(0,.15,0),(.065,.066,.047),dark if boss else gold,sword)
    for side in [-1,1]:
        tube('Curved sword guard',[(0,-.15,0),(side*.12,-.14,0),(side*.22,-.17,0),(side*.28,-.24,0)],[.045,.04,.027,.008],dark if boss else gold,sword,14)
    length=1.44 if boss else 1.35; width=.16 if boss else .095
    verts=[]
    for y,w in [(-.19,width),(-.30,width),(-length+.20,width*.80),(-length+.065,width*.46),(-length,0)]:
        verts.extend([(-w,y,0),(-w*.73,y,-.024),(0,y,-.045),(w*.73,y,-.024),(w,y,0),(w*.73,y,.024),(0,y,.045),(-w*.73,y,.024)])
    faces=[]
    for j in range(4):
        for k in range(8):faces.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
    blade=mesh('Moonsteel blade',verts,faces,dark if boss else steel,sword)
    blade.data.materials.append(steel)
    for p in blade.data.polygons:
        if p.index%8 in [0,3,4,7]:p.material_index=1
    if boss:
        line('Violet sword fuller',[(0,-.28,-.047),(0,-.60,-.047),(0,-1.12,-.047)],.011,M['rune'],sword)
    else:
        line('Polished central ridge',[(0,-.25,-.049),(0,-1.15,-.049)],.004,M['eye white'],sword,6)
    if boss:return
    shield=n['Shield']; outline=[(-.34,.28),(-.27,.36),(0,.44),(.27,.36),(.34,.28),(.31,-.12),(.20,-.32),(0,-.46),(-.20,-.32),(-.31,-.12)]
    verts=[]; rings=[(1,.048),(1,-.014),(.93,-.052),(.83,-.067),(.49,-.11),(0,-.127)]
    for scale,z in rings:verts.extend((x*scale,y*scale,z) for x,y in outline)
    faces=[]; count=len(outline)
    for j in range(len(rings)-1):
        for k in range(count):faces.append((j*count+k,j*count+(k+1)%count,(j+1)*count+(k+1)%count,(j+1)*count+k))
    shieldmesh=mesh('Wooden heater shield',verts,faces,steel,shield)
    for m in [M['wood'],M['wood light'],dark]:shieldmesh.data.materials.append(m)
    for p in shieldmesh.data.polygons:
        p.material_index=(1+(p.index%3==0)) if p.index>=3*count else (3 if p.index>=2*count else 0)
    line('Rolled silver rim',[(x*.975,y*.975,-.040) for x,y in outline]+[(outline[0][0]*.975,outline[0][1]*.975,-.040)],.014,steel,shield)
    for x in [-.19,-.065,.067,.19]:
        bottom=-.36+abs(x)*.7; top=.33-abs(x)*.22
        line('Wood plank joint',[(x,bottom,-.12),(x,.02,-.135),(x,top,-.10)],.005,M['wood grain'],shield,5)
        for j in range(3):
            yy=bottom+.08+j*.13
            line('Wood grain',[(x+.021,yy,-.139),(x+.028,yy+.075,-.138),(x+.02,yy+.11,-.13)],.0015,M['wood grain'],shield,4)
    gem('Diamond silver shield boss',(0,.01,-.155),.205,.29,.067,steel,shield)
    for x,y in outline[::2]:orb('Shield rim rivet',(x*.938,y*.938,-.064),(.014,.014,.013),steel,shield,12,8)
    for x in [-.11,.11]:line('Shield arm straps',[(x,-.17,.066),(x,-.13,.158),(x,.13,.158),(x,.18,.066)],.023,leather,shield)

def boss(n):
    # The reference knight reads as polished black-violet plate under warm sunset
    # lighting.  Lift the mid values and lower roughness slightly so the armor
    # catches a readable rim highlight in the game scene instead of collapsing
    # into a single black silhouette.
    material('steel','827c9b','metal',.78,.30); material('steel shade','38334e','metal',.70,.42)
    material('armor','514a68','metal',.76,.32); material('armor edge','aaa4bf','metal',.78,.25)
    material('leather','30283d','leather'); material('gold','665a80','metal',.70,.36)
    material('dark cloak','2b2344','cloth'); material('cloak folds','4a3d60','cloth'); material('cloak edge','6a6284','cloth')
    material('tabard','5a3047','cloth'); material('rune','a94be0','gem',.42,.24,.8); material('red eyes','ef3d4f','eye',0,.24,2.2)
    armor=M['armor']; edge=M['armor edge']; dark=M['steel shade']; hips,torso,h=n['Hips'],n['Torso'],n['Head']
    loft('Armored waist',hips,dark,[(-.15,.237,.164,0),(.12,.24,.17,0)],n=32)
    loft('Black leather belt',hips,M['leather'],[(0,.269,.188,0),(.065,.263,.18,0)],n=32)
    gem('Angular belt clasp',(0,.025,-.21),.18,.11,.028,edge,hips)
    for side in [-1,1]:
        for j in range(3):
            ob=orb('Overlapping tassets',(side*(.23+j*.009),-.10-j*.080,-.04),(.12,.088,.175),armor,hips)
            line('Tasset rolled edge',[(side*.16,-.12-j*.08,-.19),(side*.245,-.15-j*.08,-.21),(side*.315,-.11-j*.08,-.155)],.008,edge,hips)
    loft('Black cuirass',torso,armor,[(.01,.208,.15,0),(.12,.26,.186,-.02),(.26,.32,.229,-.026),(.40,.305,.203,0),(.485,.174,.133,.012)],n=40)
    tube('Breastplate medial ridge',[(0,.03,-.17),(0,.19,-.264),(0,.35,-.236),(0,.44,-.16)],[.012,.020,.014,.007],edge,torso,10)
    for side in [-1,1]:
        line('Cuirass sweeping contour',[(side*.025,.10,-.218),(side*.17,.16,-.233),(side*.264,.27,-.177),(side*.255,.37,-.151)],.012,dark,torso)
        gem('Chest violet inset',(side*.164,.335,-.211),.072,.085,.014,M['rune'],torso)
    gem('Central violet seal',(0,.145,-.269),.08,.13,.014,M['rune'],torso)
    for j in range(3):arc('Neck gorget',torso,armor if j%2 else edge,.174+j*.009,.13+j*.007,.46-j*.037,r=.026,n=32)
    drape('Torn black mantle',n['Cape'],M['dark cloak'],M['cloak folds'],M['cloak edge'],.55,1.17,True)
    for j in range(4):
        pts=[]
        for k in range(25):
            t=k/24; x=(t-.5)*(.47+j*.032)
            pts.append((x,-.055-j*.058-math.sin(t*math.pi)*(.065+j*.016),.09+math.sin(t*math.pi)*.014+j*.009))
        line('Gathered back mantle collar',pts,.020,M['cloak folds'],n['Cape'],10)
    drape('Oxblood waist pennant',n['Tabard'],M['tabard'],M['leather'],M['tabard'],.18,.57,True)
    # Closed angular visor, pointed cheek plates and two clean backward-curved horns.
    loft('Horned helmet shell',h,armor,[(-.14,.11,.13,-.016),(-.04,.189,.162,0),(.10,.218,.19,.013),(.27,.198,.177,.024),(.40,.103,.105,.03),(.43,.005,.006,.03)],n=40)
    box('Eye slit black recess',(0,.10,-.182),(.35,.077,.041),M['leather'],h,.013)
    for side in [-1,1]:
        line('Slanted red eye',[(side*.034,.098,-.213),(side*.09,.12,-.213),(side*.151,.151,-.190)],.013,M['red eyes'],h,8)
        solid(mesh('Pointed visor cheek',[(side*.20,.11,-.154),(side*.15,-.105,-.17),(side*.035,-.17,-.229),(side*.037,.074,-.224)],[(0,1,2,3)],armor,h),.025)
        line('Visor cheek bright bevel',[(side*.15,-.103,-.173),(side*.036,-.169,-.233),(side*.037,.07,-.23)],.008,edge,h)
        tube('Curving black horn',[(side*.175,.29,.025),(side*.29,.35,.035),(side*.365,.48,.055),(side*.34,.62,.053),(side*.302,.71,.02)],[.091,.083,.062,.035,.001],armor,h,18)
        line('Horn edge glint',[(side*.232,.34,-.038),(side*.316,.45,-.002),(side*.312,.58,.012)],.008,edge,h)
    line('Helmet crown ridge',[(0,.428,.025),(0,.357,-.096),(0,.23,-.174) ],.012,edge,h)
    box('Visor nasal',(0,-.035,-.229),(.026,.25,.028),edge,h,.006)
    for tag,side in [('R',1),('L',-1)]:
        upper,fore,hand=n['UpperArm'+tag],n['Forearm'+tag],n['Hand'+tag]
        orb('Domed spiked pauldron',(side*.012,.006,0),(.211,.155,.202),armor,upper,32,18)
        arc('Pauldron rim',upper,edge,.206,.20,-.064,r=.018,n=36)
        for k in range(3):
            tube('Pauldron spike',[(side*(.028+k*.063),.09,(-.10+k*.09)),(side*(.06+k*.075),.22+k*.004,-.12+k*.09),(side*(.075+k*.091),.34-k*.034,-.11+k*.09)],[.060,.035,.001],armor,upper,14)
        for j in range(4):loft('Articulated upper arm lames',upper,edge if j%2 else armor,[(-.09-j*.044,.121-j*.009,.127-j*.009,0),(-.133-j*.044,.122-j*.009,.127-j*.009,0)],n=28)
        orb('Elbow cop',(side*.013,0,-.03),(.11,.103,.105),armor,fore)
        loft('Faceted armored vambrace',fore,armor,[(-.04,.105,.105,0),(-.11,.114,.114,-.01),(-.23,.078,.089,0),(-.267,.074,.084,0)],n=24)
        line('Vambrace ridge',[(0,-.065,-.106),(0,-.14,-.134),(0,-.24,-.090)],.012,edge,fore)
        for y in [-.10,-.245]:arc('Vambrace cuff',fore,edge,.1 if y>-.2 else .078,.109 if y>-.2 else .086,y,r=.011,n=24)
        orb('Black gauntlet palm',(0,-.026,-.009),(.086,.072,.080),M['leather'],hand)
        for k in range(4):
            for j in range(2):box('Gauntlet finger plate',((k-1.5)*.038,-.015-j*.033,-.065),(.032,.037,.030),armor if j else edge,hand,.009)
        orb('Gauntlet thumb',(side*.075,-.02,-.018),(.027,.053,.043),armor,hand)
        thigh,shin,foot=n['Thigh'+tag],n['Shin'+tag],n['Foot'+tag]
        loft('Padded trouser',thigh,M['leather'],[(-.02,.127,.127,0),(-.36,.099,.100,0)],n=28)
        loft('Cuisse plates',thigh,armor,[(-.07,.12,.129,-.01),(-.21,.116,.12,-.018),(-.335,.097,.106,0)],n=28)
        orb('Angular knee plate',(0,-.016,-.065),(.12,.131,.10),armor,shin)
        gem('Kneecap bevel',(0,-.012,-.16),.13,.15,.022,edge,shin)
        loft('Black greave',shin,armor,[(-.08,.103,.106,0),(-.14,.101,.11,-.012),(-.285,.073,.084,0)],n=28)
        line('Greave silver ridge',[(0,-.085,-.109),(0,-.19,-.126),(0,-.289,-.089)],.012,edge,shin)
        box('Dark armored sole',(0,-.05,-.075),(.214,.069,.373),M['leather'],foot,.022)
        orb('Armored boot',(0,.012,-.085),(.108,.082,.177),armor,foot)
        for j in range(4):arc('Sabatons overlapping lip',foot,edge,.103-j*.006,.052,.034-j*.012,cz=-.043-j*.05,a=1.1,b=5.18,r=.009,n=20)
    weapon(n,True)

def combine_by_pivot_and_material():
    # Preserve explicit PBR families. Merge details sharing a rigid joint and material.
    bpy.context.view_layer.update(); groups=defaultdict(list)
    for ob in list(bpy.context.scene.objects):
        if ob.type!='MESH':continue
        if ob.name=='Moonsteel blade':continue
        for pi in range(len(ob.data.materials)):
            groups[(ob.parent,ob.data.materials[pi])].append((ob,pi))
    old=set()
    for (parent,mat),parts in groups.items():
        verts=[];faces=[]; flags=[]
        for ob,pi in parts:
            old.add(ob); offset=len(verts)
            verts.extend(tuple(ob.matrix_local@v.co) for v in ob.data.vertices)
            for poly in ob.data.polygons:
                if poly.material_index==pi:
                    faces.append(tuple(offset+k for k in poly.vertices));flags.append(poly.use_smooth)
        data=bpy.data.meshes.new(parent.name+' '+mat.name);data.from_pydata(verts,[],faces);data.materials.append(mat)
        for p,sm in zip(data.polygons,flags):p.use_smooth=sm
        ob=bpy.data.objects.new(parent.name+' '+mat.name,data);bpy.context.collection.objects.link(ob);ob.parent=parent
    for ob in old:bpy.data.objects.remove(ob,do_unlink=True)

def build(is_boss):
    M.clear(); n=setup(is_boss)
    boss(n) if is_boss else player(n)
    combine_by_pivot_and_material()
    # Add editable reference images to the .blend without exporting them into the game.
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=n['Rig']
    stem='thorn_lord' if is_boss else 'wayfarer'
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(stem+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(stem+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
    result=lib['metrics'](OUT/(stem+'.glb'));print('REFERENCE_MODEL',stem,json.dumps(result))
    return stem,result

result=dict([build(False),build(True)])
(OUT/'reference_model_metrics.json').write_text(json.dumps(result,indent=2),encoding='utf8')
