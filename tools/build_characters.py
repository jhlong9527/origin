"""Original V2 character meshes, preserving V1's stable articulated pivots.

The archived source_v1 generator supplies the original joint hierarchy. This
script replaces its large surfaces with shaped plate, thick cloth and forged
equipment, then combines decoration into one vertex palette per rigid body.
"""
import bpy, math, json, struct
from collections import defaultdict
from mathutils import Vector
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'/'characters'
legacy={'__file__':str(Path(__file__).resolve())}
source=(OUT/'source_v1'/'build_characters.py').read_text(encoding='utf8')
source='\n'.join('    pass  # Export only the finished revision below.' if line.lstrip().startswith(('bpy.ops.wm.save_as_mainfile(', 'bpy.ops.export_scene.gltf(')) else line for line in source.splitlines())
exec(source.rsplit('\nbuild(False)',1)[0],legacy)
gv=legacy['gv']; mesh=legacy['mesh']; sphere=legacy['sphere']; box=legacy['box']
COLORS={}

def linear(h):
    values=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values)

def mat(name,h):
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear(h),1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Roughness'].default_value=.9
    # Compatibility lighting consumes mesh palette channels in display space.
    COLORS[m.name]=tuple(int(h[i:i+2],16)/255 for i in (0,2,4))+(1,)
    return m

def smooth(obj):
    for p in obj.data.polygons:p.use_smooth=True
    return obj

def solid(obj,thickness=.016):
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('True material thickness','SOLIDIFY');mod.thickness=thickness;mod.offset=0
    bpy.ops.object.modifier_apply(modifier=mod.name);return obj

def bevel(obj,width=.007):
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Forged curved edge','BEVEL');mod.width=width;mod.segments=2
    bpy.ops.object.modifier_apply(modifier=mod.name);return obj

def tube(name,points,radii,material,parent,sides=8):
    points=[Vector(p) for p in points];verts=[]
    for i,p in enumerate(points):
        t=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        normal=t.cross(Vector((0,0,1)))
        if normal.length<.05:normal=t.cross(Vector((1,0,0)))
        normal.normalize();binormal=t.cross(normal).normalized()
        for j in range(sides):
            q=p+(normal*math.cos(j*math.tau/sides)+binormal*math.sin(j*math.tau/sides))*radii[i]
            verts.append(tuple(q))
    faces=[]
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides;faces.append((a,b,b+sides,a+sides))
    faces+=[tuple(range(sides-1,-1,-1)),tuple((len(points)-1)*sides+j for j in range(sides))]
    return smooth(mesh(name,verts,faces,material,parent))

def arc(name,parent,material,rx,rz,y,cz=0,a=0,b=math.tau,r=.008,cx=0,n=24):
    pts=[(cx+math.sin(a+(b-a)*i/n)*rx,y,cz+math.cos(a+(b-a)*i/n)*rz) for i in range(n+1)]
    return tube(name,pts,[r]*len(pts),material,parent)

def loft(name,parent,material,rings,n=24,cx=0):
    rings=sorted(rings,key=lambda ring:ring[0])
    verts=[]
    for y,rx,rz,cz in rings:
        verts.extend((cx+math.sin(j*math.tau/n)*rx,y,cz+math.cos(j*math.tau/n)*rz) for j in range(n))
    faces=[]
    for i in range(len(rings)-1):
        for j in range(n):
            a=i*n+j;b=i*n+(j+1)%n;faces.append((a,b,b+n,a+n))
    faces+=[tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+j for j in range(n))]
    return smooth(mesh(name,verts,faces,material,parent))

def orb(name,p,size,m,parent):return smooth(sphere(name,p,size,m,parent,16,10))

def leaf(name,a,b,width,m,parent):
    v=Vector(b)-Vector(a);side=Vector((-v.y,v.x,0)).normalized()*width
    middle=Vector(a)+v*.55;ridge=middle+Vector((0,0,-.014))
    return solid(mesh(name,[a,tuple(middle+side),b,tuple(middle-side),tuple(ridge)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],m,parent),.008)

def cloth(name,parent,m,fold,border,width,length,cape=False):
    cols=16;rows=12;verts=[]
    for j in range(rows+1):
        v=j/rows
        for i in range(cols+1):
            u=i/cols;x=(u-.5)*2*width*(.52+.48*v if cape else 1-.12*v)
            hem=(.04*math.cos(i*2.11)+.025*math.sin(i*4.2))*v**8
            z=(.035+.23*v if cape else .03*v)+math.cos(u*math.pi*8)*(.016+.024*v)
            verts.append((x,-v*length+hem,z))
    faces=[]
    for j in range(rows):
        for i in range(cols):
            a=j*(cols+1)+i;faces.append((a,a+1,a+cols+2,a+cols+1))
    obj=smooth(mesh(name,verts,faces,m,parent));obj.data.materials.append(fold)
    for poly in obj.data.polygons:poly.material_index=1 if (poly.index%cols)%4==1 else 0
    solid(obj)
    for edge in [0,cols]:
        pts=[verts[j*(cols+1)+edge] for j in range(rows+1)];tube(name+' stitched edge',pts,[.006]*len(pts),border,parent,6)
    pts=[verts[rows*(cols+1)+i] for i in range(cols+1)];tube(name+' weighted hem',pts,[.007]*len(pts),border,parent,6)

def remove_meshes(parent):
    for child in list(parent.children):
        if child.type=='MESH':bpy.data.objects.remove(child,do_unlink=True)

def metrics(path):
    with open(path,'rb') as f:
        f.read(12);size,_=struct.unpack('<II',f.read(8));d=json.loads(f.read(size))
    tris=draws=nodes=0
    for node in d['nodes']:
        if 'mesh' not in node:continue
        nodes+=1
        for p in d['meshes'][node['mesh']]['primitives']:
            tris+=d['accessors'][p['indices']]['count']//3;draws+=1
    return {'triangles':tris,'mesh_nodes':nodes,'surface_draws_per_color_pass':draws}

def combine_rigid_palette():
    bpy.context.view_layer.update()
    palette=bpy.data.materials.new('Vertex Palette | painted armor');palette.use_nodes=True
    bsdf=palette.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(1,1,1,1)
    bsdf.inputs['Roughness'].default_value=.9
    attr=palette.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='Col'
    palette.node_tree.links.new(attr.outputs['Color'],bsdf.inputs['Base Color'])
    groups=defaultdict(list)
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH':continue
        special=obj.name=='Moonsteel blade' or (obj.data.materials and 'Eyes |' in obj.data.materials[0].name)
        if not special:groups[obj.parent].append(obj)
    for parent,objects in groups.items():
        verts=[];faces=[];colors=[];smooth_flags=[]
        for obj in objects:
            start=len(verts);verts.extend(tuple(obj.matrix_local@v.co) for v in obj.data.vertices)
            for p in obj.data.polygons:
                faces.append(tuple(start+i for i in p.vertices));m=obj.data.materials[p.material_index]
                colors.append(COLORS.get(m.name,m.diffuse_color[:]));smooth_flags.append(p.use_smooth)
        data=bpy.data.meshes.new(parent.name+' crafted surface');data.from_pydata(verts,[],faces);data.materials.append(palette)
        color_attr=data.color_attributes.new(name='Col',type='FLOAT_COLOR',domain='CORNER')
        for p,c,s in zip(data.polygons,colors,smooth_flags):
            p.use_smooth=s
            for loop in p.loop_indices:color_attr.data[loop].color=c
        o=bpy.data.objects.new(parent.name+' | crafted armor',data);bpy.context.collection.objects.link(o);o.parent=parent
        for old in objects:bpy.data.objects.remove(old,do_unlink=True)

def build(boss):
    legacy['build'](boss)
    nodes={o.name:o for o in bpy.context.scene.objects if o.type=='EMPTY'}
    steel=mat('V2 storm silver' if not boss else 'V2 iron plum','688793' if not boss else '503c55')
    light=mat('V2 edge highlights','a6bdc4' if not boss else '937986')
    dark=mat('V2 padding','243836' if not boss else '221e2b');leather=mat('V2 oxblood','573331')
    gold=mat('V2 brass','b39151' if not boss else 'b98b44');glint=mat('V2 polished brass','e2b96c')
    fabric=mat('V2 cloth','1d7264' if not boss else '70263d');fold=mat('V2 cloth folds','369c80' if not boss else '983750')
    blade=mat('Blade | moonsteel','aac7ce');fuller=mat('V2 blue temper','3a6377')
    eye=mat('Eyes | lantern','7be1c6' if not boss else 'ffd068')
    p=eye.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=eye.diffuse_color;p.inputs['Emission Strength'].default_value=1.5
    hips=nodes['Hips'];torso=nodes['Torso'];head=nodes['Head']
    for name in ['Hips','Torso','Head','Cape','Tabard','Sword','Shield']+[t+s for t in ['UpperArm','Forearm','Hand','Thigh','Shin','Foot'] for s in ['R','L']]:remove_meshes(nodes[name])
    loft('Quilted waist',hips,dark,[(-.13,.21,.145,0),(.04,.22,.15,0),(.12,.185,.13,0)])
    loft('Wrapped leather belt',hips,leather,[(-.005,.24,.173,0),(.064,.23,.164,0)])
    box('Belt clasp',(0,.03,-.179),(.105,.082,.029),gold,hips,.009);box('Buckle inset',(0,.03,-.199),(.057,.040,.008),dark,hips,.006)
    for j in range(3):
        loft('Flaring overlapping fauld',hips,steel,[(-.045-j*.078,.218+j*.012,.158+j*.008,0),(-.112-j*.078,.236+j*.014,.17+j*.008,0)])
        arc('Fauld rolled lip',hips,gold,.237+j*.014,.171+j*.008,-.112-j*.078,r=.006)
    loft('Anatomical cuirass',torso,steel,[(0,.187,.13,0),(.09,.205,.151,-.015),(.27,.285,.196,-.023),(.39,.275,.17,-.005),(.47,.182,.125,0)])
    tube('Breastplate medial keel',[(0,.025,-.145),(0,.18,-.219),(0,.29,-.231),(0,.40,-.178)],[.011,.018,.014,.007],light,torso)
    for side in [-1,1]:
        tube('Sweeping chest inlay',[(side*.035,.13,-.198),(side*.13,.20,-.205),(side*.21,.31,-.16),(side*.21,.38,-.135)],[.005]*4,gold,torso,6)
        tube('Rolled armhole',[(side*.18,.44,-.064),(side*.255,.365,-.08),(side*.27,.27,-.09),(side*.225,.11,-.089)],[.010]*4,light,torso)
        orb('Cloak rosette',(side*.20,.42,-.115),(.048,.048,.021),gold,torso);orb('Rosette enamel',(side*.20,.42,-.139),(.022,.022,.009),fabric,torso)
    loft('Shaped gorget',torso,light,[(.455,.155,.119,0),(.49,.17,.128,0),(.513,.148,.112,0)])
    arc('Collar gold cord',torso,gold,.17,.128,.49,r=.007)
    cloth('Heavy surcoat',nodes['Tabard'],fabric,fold,gold,.17,.50)
    cloth('Heavy travel mantle',nodes['Cape'],fabric,fold,leather,.46 if boss else .40,1.06 if boss else .92,True)
    for j in range(3):arc('Gathered mantle folds',torso,fabric if j%2 else fold,.225+j*.016,.17+j*.015,.40-j*.028,cz=.04,a=-1.7,b=1.7,r=.023)
    loft('Shaped bascinet shell',head,steel,[(-.08,.128,.132,-.028),(.04,.195,.179,-.006),(.18,.207,.177,0),(.29,.16,.138,.014),(.38,.063,.059,.025),(.394,.006,.012,.024)])
    box('Inset visor opening',(0,.123,-.182),(.354,.061,.054),dark,head,.016)
    tube('Swept visor brow',[(-.18,.165,-.156),(-.11,.185,-.199),(0,.19,-.214),(.11,.185,-.199),(.18,.165,-.156)],[.024]*5,light,head)
    for side in [-1,1]:
        box('Lantern eye',(side*.076,.128,-.218),(.072,.018,.010),eye,head,.004)
        verts=[(side*.18,.10,-.151),(side*.18,-.033,-.124),(side*.105,-.11,-.165),(side*.025,-.09,-.223),(side*.025,.077,-.222),(side*.10,.11,-.200)]
        bevel(solid(mesh('Raised cheek plate',verts,[(0,1,2,3,4,5)],steel,head),.026))
        for j in range(3):box('Inset breathing vent',(side*(.054+j*.034),-.008-j*.005,-.230+j*.009),(.012,.059,.008),dark,head,.004)
        tube('Cheek rolled border',[(side*.18,.084,-.171),(side*.17,-.04,-.16),(side*.11,-.10,-.189),(side*.038,-.082,-.231)],[.007]*4,gold,head,6)
        orb('Visor hinge',(side*.195,.12,-.027),(.023,.025,.028),gold,head)
    bevel(solid(mesh('Diamond nasal',[(0,.186,-.228),(-.023,.089,-.239),(-.015,-.10,-.24),(0,-.117,-.252),(.015,-.10,-.24),(.023,.089,-.239),(0,.083,-.26)],[(0,1,6),(1,2,3,6),(3,4,5,6),(5,0,6)],light,head),.013),.004)
    tube('Helmet comb',[(0,.27,-.141),(0,.382,-.039),(0,.405,.04),(0,.33,.129)],[.010,.019,.018,.012],gold,head)
    if boss:
        arc('Crown circlet',head,gold,.204,.178,.22,r=.018)
        for side in [-1,1]:
            tube('Swept crown antler',[(side*.16,.245,.02),(side*.28,.34,.014),(side*.37,.46,.033),(side*.39,.60,.08),(side*.47,.74,.12)],[.060,.053,.038,.022,.001],gold,head,10)
            tube('Crown inner tine',[(side*.325,.39,.022),(side*.285,.49,-.01),(side*.26,.635,-.04)],[.034,.023,.001],glint,head)
            tube('Crown outer tine',[(side*.392,.59,.077),(side*.50,.63,.16),(side*.56,.735,.19)],[.025,.016,.001],glint,head)
        leaf('Central crown leaf',(0,.235,-.179),(0,.48,-.114),.056,gold,head)
    else:
        plume=nodes['Plume'];remove_meshes(plume)
        tube('Swept horsehair plume',[(0,0,0),(0,.15,.08),(0,.12,.23),(0,.045,.38),(0,-.055,.45)],[.038,.048,.04,.024,.002],fold,plume,10)
        for x in [-.018,.018]:tube('Plume engraved lock',[(x,.01,.01),(x,.145,.1),(x,.108,.25),(x,.025,.39)],[.005]*4,fabric,plume,6)
    for side,tag in [(1,'R'),(-1,'L')]:
        upper=nodes['UpperArm'+tag];elbow=nodes['Forearm'+tag];hand=nodes['Hand'+tag]
        orb('Padded shoulder',(0,-.045,0),(.14,.13,.14),dark,upper)
        s=1.13 if boss else 1
        loft('Domed pauldron',upper,steel,[(.105,.022,.026,0),(.09,.115*s,.143,0),(.03,.202*s,.207,0),(-.065,.225*s,.213,0),(-.104,.216*s,.196,0)],cx=side*.035)
        arc('Pauldron rolled lip',upper,gold,.216*s,.197,-.105,cx=side*.035,r=.013)
        for j in range(2):loft('Pauldron overlapping lame',upper,light if j==0 else steel,[(-.09-j*.05,.19-j*.016,.171-j*.009,0),(-.15-j*.05,.16-j*.011,.161-j*.009,0)],cx=side*.024)
        tube('Pauldron chased ridge',[(side*.034,.107,-.012),(side*.044,.071,-.125),(side*.061,-.024,-.209),(side*.062,-.100,-.201)],[.006]*4,gold,upper,6)
        for z in [-.14,.12]:orb('Pauldron rivet',(side*.177,-.07,z),(.013,.013,.013),glint,upper)
        loft('Quilted arm sleeve',upper,fabric,[(-.12,.088,.09,0),(-.26,.077,.079,0)],n=16)
        for j in range(3):arc('Sleeve stitch',upper,leather,.088,.09,-.14-j*.038,r=.004,n=12)
        orb('Elbow hinge',(0,0,0),(.079,.076,.075),dark,elbow);orb('Curved elbow cop',(side*.02,-.015,.025),(.113,.095,.11),steel,elbow)
        leaf('Elbow wing',(side*.03,.03,.052),(side*.18,-.025,.035),.055,light,elbow)
        loft('Sculpted vambrace',elbow,steel,[(-.055,.086,.09,0),(-.09,.102,.097,-.005),(-.19,.081,.079,-.01),(-.255,.064,.067,0)],n=20)
        for j in range(3):arc('Vambrace lames',elbow,light,.089-j*.007,.089-j*.007,-.115-j*.046,cz=-.009,a=1.18,b=5.10,r=.007,n=14)
        arc('Brass bracer cuff',elbow,gold,.073,.073,-.25,r=.009)
        orb('Leather palm',(0,-.028,-.010),(.073,.07,.068),leather,hand)
        for j in range(4):orb('Articulated knuckle',((j-1.5)*.032,-.014,-.065),(.021,.030,.023),light,hand)
        orb('Thumb plate',(side*.065,-.006,-.034),(.028,.044,.032),steel,hand)
        thigh=nodes['Thigh'+tag];shin=nodes['Shin'+tag];foot=nodes['Foot'+tag]
        loft('Padded thigh',thigh,dark,[(-.03,.106,.114,0),(-.34,.079,.082,0)],n=16)
        loft('Tapered cuisse',thigh,steel,[(-.07,.108,.12,-.008),(-.17,.104,.114,-.016),(-.32,.079,.093,-.01)],n=20)
        for j in range(2):arc('Cuisse chased line',thigh,light,.101-j*.011,.111-j*.012,-.15-j*.09,cz=-.01,a=1.25,b=5.03,r=.006)
        orb('Shaped kneecap',(0,-.003,-.042),(.106,.118,.108),steel,shin)
        leaf('Poleyn wing',(side*.049,.026,-.037),(side*.16,-.036,-.036),.053,light,shin)
        tube('Knee crest',[(0,.08,-.103),(0,-.005,-.156),(0,-.08,-.105)],[.007,.010,.006],gold,shin)
        loft('Anatomical greave',shin,steel,[(-.085,.089,.088,0),(-.12,.094,.10,-.01),(-.23,.074,.083,-.008),(-.295,.063,.073,0)],n=20)
        tube('Greave medial ridge',[(0,-.08,-.094),(0,-.15,-.112),(0,-.28,-.078)],[.008,.012,.006],light,shin)
        for y in [-.12,-.27]:arc('Greave strap',shin,leather,.095 if y>-.2 else .078,.098 if y>-.2 else .081,y,a=-1.8,b=1.8,r=.013)
        box('Boot sole',(0,-.041,-.046),(.176,.065,.316),dark,foot,.025);orb('Leather boot upper',(0,.013,-.048),(.092,.074,.151),leather,foot)
        for j in range(4):loft('Overlapping sabaton',foot,steel if j%2 else light,[(-.009,.093-j*.004,.049,-.04-j*.044),(.045-j*.009,.078-j*.004,.043,-.04-j*.044)],n=16)
        if boss:tube('Swept shoulder thorn',[(side*.10,.06,.02),(side*.18,.14,.05),(side*.30,.26,.10),(side*.34,.36,.12)],[.062,.058,.028,.001],gold,upper,10)
    sword=nodes['Sword']
    loft('Sword leather grip',sword,leather,[(-.145,.032,.029,0),(.10,.035,.031,0)],n=16)
    spiral=[(.037*math.cos(i*math.tau/12),.10-i*.25/96,.033*math.sin(i*math.tau/12)) for i in range(97)]
    tube('Spiral grip winding',spiral,[.004]*97,gold,sword,5)
    orb('Pommel housing',(0,.146,0),(.066,.067,.046),gold,sword);orb('Pommel enamel',(0,.15,-.04),(.031,.036,.012),fabric,sword)
    for side in [-1,1]:
        tube('Forged curved crossguard',[(0,-.16,0),(side*.08,-.15,0),(side*.16,-.17,-.005),(side*.23,-.21,-.012),(side*.25,-.255,-.013)],[.045,.041,.033,.025,.014],gold,sword,12)
        tube('Quillon chased line',[(side*.035,-.135,-.035),(side*.13,-.153,-.031),(side*.205,-.195,-.032)],[.005]*3,glint,sword,6)
    length=1.23 if boss else 1.14;width=.10 if boss else .073;verts=[]
    for y,w,t in [(-.19,width,.038),(-.30,width,.041),(-.43,width*.82,.033),(-length,width*.62,.020),(-length-.21,0,.001)]:
        verts += [(-w,y,0),(-w*.79,y,-t*.43),(0,y,-t),(w*.79,y,-t*.43),(w,y,0),(w*.79,y,t*.43),(0,y,t),(-w*.79,y,t*.43)]
    faces=[]
    for i in range(4):
        for j in range(8):faces.append((i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j))
    mesh('Moonsteel blade',verts,faces,blade,sword)
    tube('Inlaid fuller',[(0,-.29,-.043),(0,-.43,-.036),(0,-length+.12,-.024)],[.008,.008,.003],fuller,sword,5)
    shield=nodes['Shield']
    outline=[(-.32,.25),(-.29,.33),(-.18,.365),(0,.38),(.18,.365),(.29,.33),(.32,.25),(.30,.02),(.25,-.19),(.12,-.35),(0,-.435),(-.12,-.35),(-.25,-.19),(-.30,.02)]
    n=len(outline);verts=[]
    for factor,z in [(1,.035),(1,-.012),(.94,-.050),(.86,-.073),(.52,-.112),(0,-.131)]:verts.extend((x*factor,y*factor,z) for x,y in outline)
    faces=[]
    for ring in range(5):
        for j in range(n):faces.append((ring*n+j,ring*n+(j+1)%n,(ring+1)*n+(j+1)%n,(ring+1)*n+j))
    face=smooth(mesh('Domed heater shield',verts,faces,gold,shield));face.data.materials.append(fabric);face.data.materials.append(dark)
    for p in face.data.polygons:p.material_index=1 if p.index>=n*3 else (2 if n*2<=p.index<n*3 else 0)
    border=[(x*.973,y*.973,-.040) for x,y in outline];border.append(border[0]);tube('Shield rolled rim',border,[.012]*len(border),glint,shield)
    for x,y in outline[::2]:orb('Perimeter rivet',(x*.925,y*.925,-.061),(.015,.015,.011),light,shield)
    for i in range(4):box('Rear shield timber',((i-1.5)*.125,-.02,.05),(.11,.56-abs(i-1.5)*.08,.025),leather,shield,.018)
    for x in [-.12,.12]:tube('Shield leather arm strap',[(x,-.16,.066),(x,-.14,.15),(x,.13,.15),(x,.16,.066)],[.024]*4,dark,shield)
    tube('Heraldic tree trunk',[(0,-.30,-.116),(0,-.15,-.146),(0,.04,-.149),(0,.245,-.129)],[.017,.015,.013,.007],glint,shield)
    for side in [-1,1]:
        for j in range(2):
            y=-.10+j*.16;tube('Raised tree branch',[(0,y,-.147),(side*.08,y+.055,-.151),(side*.17,y+.13,-.129)],[.010,.008,.003],light,shield)
            leaf('Raised heraldic leaf',(side*.105,y+.07,-.157),(side*.13,y+.205,-.146),.029,glint,shield)
    orb('Heraldic heart mount',(0,-.025,-.159),(.052,.065,.026),gold,shield);orb('Heraldic enamel heart',(0,-.02,-.184),(.031,.043,.014),fabric,shield)
    combine_rigid_palette()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=nodes['Rig']
    stem='thorn_lord' if boss else 'wayfarer'
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(stem+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(stem+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
    result={'before':metrics(OUT/'source_v1'/(stem+'.glb')),'after':metrics(OUT/(stem+'.glb'))}
    print('MODEL_METRICS',stem,json.dumps(result));return stem,result

results=dict([build(False),build(True)])
(OUT/'model_metrics.json').write_text(json.dumps(results,indent=2),encoding='utf8')
