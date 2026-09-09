extends Node3D

# Decorative geometry is baked into a few meshes; only solid bases block movement.
var _rng := RandomNumberGenerator.new()
var _solid := SurfaceTool.new()
var _foliage := SurfaceTool.new()
var _gold := SurfaceTool.new()
var _flames: Array[MeshInstance3D] = []
var _fire_base: Array[Vector3] = []
var _wind_leaves: MultiMeshInstance3D
var _wind_leaf_base: Array[Vector3] = []
var _wind_leaf_phase: Array[float] = []
var _wind_leaf_speed: Array[float] = []
var _maple_surface := SurfaceTool.new()
var _petal_surface := SurfaceTool.new()
var _maple_mesh: ArrayMesh
var _wind_leaf_size: Array[float] = []
var _cut_stone := SurfaceTool.new()
var _timber := SurfaceTool.new()
var _copper := SurfaceTool.new()
var _moss := SurfaceTool.new()
var _glass := SurfaceTool.new()
var _time := 0.0

const SOIL := Color("43353a")
const STONE := Color("898578")
const DARK_STONE := Color("4b5550")
const MOSS := Color("667544")
const WOOD := Color("645042")
const BARK := Color("3e3338")
const GOLD := Color("b39250")

func _ready() -> void:
	_rng.seed = 420817
	_solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	_foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	_foliage.set_uv(Vector2.ZERO)
	_gold.begin(Mesh.PRIMITIVE_TRIANGLES)
	_maple_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_petal_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in [_cut_stone,_timber,_copper,_moss,_glass]:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_floor()
	_reference_paving()
	_borders()
	_obstacles()
	_ground_detail()
	_forest()
	_setup_wind_leaves()
	_mushrooms()
	_environment_v5()
	_finish_batch(_solid, "WorldGeometry", false)
	_finish_batch(_foliage, "Undergrowth", true)
	_finish_batch(_gold, "MetalTrim", false)
	_finish_maple_batch(_maple_surface, "RedMapleCrowns", false)
	_finish_maple_batch(_petal_surface, "GoldenPetals", true)
	_finish_environment(_cut_stone,"CarvedStone","carved_stone",0)
	_finish_environment(_timber,"WeatheredTimber","weathered_wood",1)
	_finish_environment(_copper,"PatinatedCopper","aged_copper",2)
	_finish_environment(_moss,"VelvetMoss","moss",3)
	_finish_glass()

func _finish_environment(st: SurfaceTool, label: String, prefix: String, kind: int) -> void:
	st.generate_normals()
	var mesh := st.commit()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/environment_prop.gdshader")
	material.set_shader_parameter("albedo_map",load("res://assets/environment/"+prefix+"_albedo.png"))
	material.set_shader_parameter("normal_map",load("res://assets/environment/"+prefix+"_normal.png"))
	material.set_shader_parameter("rough_map",load("res://assets/environment/"+prefix+"_roughness.png"))
	material.set_shader_parameter("material_kind",kind)
	mesh.surface_set_material(0,material)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	add_child(instance)

func _finish_glass() -> void:
	_glass.generate_normals()
	var mesh := _glass.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color(1,1,1,.24)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = .21
	mat.metallic = .06
	mat.emission_enabled = true
	mat.emission = Color(.65,.31,.08)
	mat.emission_energy_multiplier = .24
	mesh.surface_set_material(0,mat)
	var instance := MeshInstance3D.new()
	instance.name = "AmberLanternGlass"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _process(delta: float) -> void:
	_time += delta
	for i in _flames.size():
		var f := _flames[i]
		var flutter := sin(_time * 8.1 + i * 2.3) * 0.035 + sin(_time * 13.0 + i) * 0.018
		f.scale = Vector3(1.0 - flutter, 1.0 + flutter * 1.7, 1.0 + flutter)
		f.position = _fire_base[i] + Vector3(flutter * 0.22, 0.0, flutter * 0.18)
	if is_instance_valid(_wind_leaves) and _wind_leaves.multimesh:
		var mm := _wind_leaves.multimesh
		for i in _wind_leaf_base.size():
			var base := _wind_leaf_base[i]
			var phase := _wind_leaf_phase[i]
			var speed := _wind_leaf_speed[i]
			var t := _time * speed + phase
			var cycle := fposmod(t, 12.0) / 12.0
			var gust := sin(_time * .43 + phase) * .28
			var pos := base + Vector3(cycle * 1.5 + sin(t * 1.21) * .48 + gust, 3.2 - cycle * 3.1 + sin(t * 2.1) * .10, cos(t * .86 + phase) * .47)
			# The whole horizontal trajectory remains outside the central four metres.
			var horizontal := Vector2(pos.x,pos.z)
			if horizontal.length() < 4.5:
				horizontal = horizontal.normalized() * 4.5
				pos.x = horizontal.x
				pos.z = horizontal.y
			var visibility_scale := smoothstep(0.0,.055,cycle) * (1.0-smoothstep(.91,1.0,cycle))
			var basis := Basis.from_euler(Vector3(sin(t * 1.4) * .78,t * .92 + phase,cos(t * 1.1) * .66))
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * _wind_leaf_size[i] * maxf(.001,visibility_scale)), pos))

func _material(vertex_color: bool = true, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = vertex_color
	mat.vertex_color_is_srgb = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.92
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _finish_batch(st: SurfaceTool, label: String, double_sided: bool) -> void:
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count()==0:
		return
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/world_surface.gdshader")
	material.set_shader_parameter("stone_map",load("res://assets/surfaces/leaf_albedo.png" if double_sided else "res://assets/surfaces/stone_albedo.png"))
	material.set_shader_parameter("bark_map",load("res://assets/surfaces/bark_albedo.png"))
	material.set_shader_parameter("foliage",double_sided)
	material.set_shader_parameter("metal_trim",label == "MetalTrim")
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	add_child(instance)

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color.darkened(0.18))
	st.add_vertex(a)
	st.set_color(color.darkened(0.18))
	st.add_vertex(b)
	st.set_color(color.darkened(0.18))
	st.add_vertex(c)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_triangle(st, a, b, c, color)
	_triangle(st, a, c, d, color)

func _box(center: Vector3, size: Vector3, color: Color, angle: float = 0.0, st: SurfaceTool = null) -> void:
	if st == null:
		st = _solid
	var basis := Basis(Vector3.UP, angle)
	var pts: Array[Vector3] = []
	for p in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]:
		pts.append(center + basis * (p * size * 0.5))
	_quad(st, pts[0], pts[1], pts[2], pts[3], color.darkened(0.1))
	_quad(st, pts[5], pts[4], pts[7], pts[6], color.darkened(0.16))
	_quad(st, pts[4], pts[0], pts[3], pts[7], color.darkened(0.23))
	_quad(st, pts[1], pts[5], pts[6], pts[2], color.darkened(0.12))
	_quad(st, pts[3], pts[2], pts[6], pts[7], color.lightened(0.08))
	_quad(st, pts[4], pts[5], pts[1], pts[0], color.darkened(0.3))

func _beam(a: Vector3, b: Vector3, radius: float, color: Color, sides: int = 6, st: SurfaceTool = null) -> void:
	if st == null:
		st = _solid
	var axis := (b - a).normalized()
	var tangent := axis.cross(Vector3.FORWARD).normalized()
	if tangent.length() < 0.2:
		tangent = axis.cross(Vector3.RIGHT).normalized()
	var bitangent := axis.cross(tangent).normalized()
	for j in sides:
		var t0 := float(j) / sides * TAU
		var t1 := float(j + 1) / sides * TAU
		var r0 := (tangent * cos(t0) + bitangent * sin(t0)) * radius
		var r1 := (tangent * cos(t1) + bitangent * sin(t1)) * radius
		var shade := color.lightened(maxf(0.0, sin(t0)) * 0.07).darkened(maxf(0.0, -sin(t0)) * 0.12)
		_quad(st, a+r0, b+r0, b+r1, a+r1, shade)
		_triangle(st, b, b+r1, b+r0, color.lightened(0.1))
		_triangle(st, a, a+r0, a+r1, color.darkened(0.2))

func _environment_v5() -> void:
	# Reference-sheet pass: mossy boulders, a carved arch, cross-braced timber,
	# and the copper/glass lantern details are all batched before scene finish.
	_mossy_rocks()
	_carved_arch()
	_cross_braced_fence()
	_lantern_glass_panels()

func _mossy_rocks() -> void:
	for p in [Vector3(-8.7,0,-6.2),Vector3(8.7,0,-6.25),Vector3(-8.8,0,6.15),Vector3(8.8,0,6.25),Vector3(-6.1,0,8.2),Vector3(6.0,0,8.25)]:
		var s := _rng.randf_range(.85,1.12)
		_boulder(p,Vector3(1.46,1.30,1.1)*s,p.x*.7)
		_boulder(p+Vector3(.63*s,0,.27*s),Vector3(.61,.52,.62)*s,p.z)
		_boulder(p+Vector3(-.62*s,0,.36*s),Vector3(.49,.38,.43)*s,p.x)
		if absf(p.z)<7.5:
			_collision("MossRock",p+Vector3(0,.55*s,0),Vector3(1.30,1.10,1.02)*s)

func _rock_point(p: Vector3, size: Vector3, theta: float, phi: float, phase: float) -> Vector3:
	var body := 1.0+sin(phi*3.0+phase)*.15+cos(phi*5.0-theta*3.0+phase)*.075
	var radial := pow(maxf(0.0,sin(theta)),.68)
	var dir := Vector3(signf(cos(phi))*pow(absf(cos(phi)),.83)*radial*body,clampf(cos(theta),-.94,.92),signf(sin(phi))*pow(absf(sin(phi)),.83)*radial*body)
	var lean := (.14*sin(theta*.7+phase)+.12*dir.y)*size.x
	return p+Vector3(dir.x*size.x*.53+lean,(dir.y*.51+.48)*size.y,dir.z*size.z*.52)

func _boulder(p: Vector3, size: Vector3, phase: float) -> void:
	# Broad fractured planes, with moss occupying the same surface instead of floating cards.
	for row in 10:
		for col in 20:
			var t0 := float(row)*PI/10.0
			var t1 := float(row+1)*PI/10.0
			var a0 := float(col)*TAU/20.0
			var a1 := float(col+1)*TAU/20.0
			var v0 := _rock_point(p,size,t0,a0,phase)
			var v1 := _rock_point(p,size,t0,a1,phase)
			var v2 := _rock_point(p,size,t1,a1,phase)
			var v3 := _rock_point(p,size,t1,a0,phase)
			var hue := Color("829087").darkened(.09+sin(a0*4.0+t0*7.0+phase)*.06)
			_quad(_cut_stone,v0,v3,v2,v1,hue)
			var moss_weight := sin(a0*2.0+phase)+cos(a0*5.0+t0*3.0+phase)*.45
			if row<5 and moss_weight>.22+float(row)*.10:
				var lift := Vector3.UP*.010
				_quad(_moss,v0+lift,v3+lift,v2+lift,v1+lift,Color("6d7b40").lightened(.08*cos(a0*3.0)))
	for fissure in 5:
		var a := phase+fissure*1.27
		for part in 6:
			var theta := .48+part*.20
			var p0 := _rock_point(p,size,theta,a+sin(theta*4.0+phase)*.09,phase)
			var p1 := _rock_point(p,size,theta+.20,a+sin((theta+.20)*4.0+phase)*.09,phase)
			var away := ((p0+p1)*.5-(p+Vector3.UP*size.y*.48)).normalized()*.008
			_beam(p0+away,p1+away,.006,Color("424e49"),4,_cut_stone)
			_beam(p0+away+Vector3(.009,.009,0),p1+away+Vector3(.009,.009,0),.0025,Color("a4aa93"),4,_cut_stone)

func _carved_arch() -> void:
	var z := -7.92
	for side in [-1.0,1.0]:
		var x: float = side*2.45
		_stone(Vector3(x,0,z),1.10,1.00,.22,0,Color("717e6a"),.12)
		for y in range(4):
			_stone(Vector3(x,.24+y*.56,z),.74,.72,.52,side*.018,Color("777d75").lightened(y*.012),.10,_cut_stone)
		_stone(Vector3(x,.22,z),.90,.84,.13,0,Color("8a8f7c"),.08)
		_stone(Vector3(x,2.40,z),.91,.82,.15,0,Color("7e8c72"),.07)
		_stone(Vector3(x,2.55,z),1.02,.82,.18,0,Color("8b8c7b"),.10,_cut_stone)
		# Recessed panel with small repeating tendrils and a chisel-highlighted frame.
		_box(Vector3(x,1.43,z+.376),Vector3(.43,1.65,.025),Color("515c53"),0,_cut_stone)
		for sx in [-.255,.255]:
			_beam(Vector3(x+sx,.55,z+.402),Vector3(x+sx,2.28,z+.402),.026,Color("a3a38b"),6,_cut_stone)
		for sy in [.55,2.28]:
			_beam(Vector3(x-.25,sy,z+.402),Vector3(x+.25,sy,z+.402),.026,Color("a3a38b"),6,_cut_stone)
		for motif in 5:
			_carved_spiral(Vector3(x,.72+motif*.31,z+.425),.14,0.0,Color("a5a58c"))
		_collision("ArchColumn",Vector3(x,1.2,z),Vector3(.88,2.4,.85))
	# True vertical annular wedge segments with bevelled front faces.
	var origin := Vector3(0,2.72,z)
	for i in 13:
		var a0 := i*PI/13.0+.012
		var a1 := (i+1)*PI/13.0-.012
		_arch_wedge(origin,2.11,2.81,a0,a1,.76,Color("8b907f").darkened(.025*sin(i*1.7)))
		var a := (a0+a1)*.5
		_carved_spiral(origin+Vector3(cos(a)*2.45,sin(a)*2.45,.424),.14,a-PI*.5,Color("afb09a"))
	for edge in [2.16,2.76]:
		for k in 64:
			var a0 := k*PI/64.0
			var a1 := (k+1)*PI/64.0
			_beam(origin+Vector3(cos(a0)*edge,sin(a0)*edge,.423),origin+Vector3(cos(a1)*edge,sin(a1)*edge,.423),.023,Color("acae95"),5,_cut_stone)
	# Crossing iron ties sit high enough to leave the gate opening readable.
	_beam(Vector3(-1.55,3.90,z+.02),Vector3(1.55,2.95,z+.02),.044,Color("68716b"),7,_copper)
	_beam(Vector3(1.55,3.90,z+.05),Vector3(-1.55,2.95,z+.05),.044,Color("68716b"),7,_copper)

func _arch_wedge(origin: Vector3, inner: float, outer: float, a0: float, a1: float, depth: float, tint: Color) -> void:
	var outline: Array[Vector3] = []
	for k in 5:
		var a := lerpf(a0,a1,k/4.0)
		outline.append(Vector3(cos(a)*outer,sin(a)*outer,0))
	for k in 5:
		var a := lerpf(a1,a0,k/4.0)
		outline.append(Vector3(cos(a)*inner,sin(a)*inner,0))
	var center := Vector3(cos((a0+a1)*.5),sin((a0+a1)*.5),0)*((inner+outer)*.5)
	for i in outline.size():
		var j := (i+1)%outline.size()
		var b0 := origin+outline[i]-Vector3.FORWARD*depth*.5
		var b1 := origin+outline[j]-Vector3.FORWARD*depth*.5
		var f0 := origin+outline[i].lerp(center,.105)-Vector3.FORWARD*(depth*.5+.044)
		var f1 := origin+outline[j].lerp(center,.105)-Vector3.FORWARD*(depth*.5+.044)
		_quad(_cut_stone,b0,b1,f1,f0,tint.lightened(.065))
		_triangle(_cut_stone,origin+center-Vector3.FORWARD*(depth*.5+.044),f0,f1,tint)
		_quad(_cut_stone,b0-Vector3.BACK*depth,b1-Vector3.BACK*depth,b1,b0,tint.darkened(.15))
		_triangle(_cut_stone,origin+center-Vector3.BACK*depth*.5,b1-Vector3.BACK*depth,b0-Vector3.BACK*depth,tint.darkened(.10))

func _carved_spiral(p: Vector3, radius: float, rotate: float, tint: Color) -> void:
	var b := Basis(Vector3.BACK,rotate)
	for k in 22:
		var t0 := k/22.0
		var t1 := (k+1)/22.0
		var a0 := t0*TAU*1.38
		var a1 := t1*TAU*1.38
		var v0 := p+b*Vector3(cos(a0)*radius*(1.0-t0*.83),sin(a0)*radius*(1.0-t0*.83),0)
		var v1 := p+b*Vector3(cos(a1)*radius*(1.0-t1*.83),sin(a1)*radius*(1.0-t1*.83),0)
		_beam(v0,v1,.012,tint,5,_cut_stone)

func _cross_braced_fence() -> void:
	for side in [-1.0,1.0]:
		for x in [-10.0,-8.0,-6.0,4.0,6.0,8.0]:
			_fence_panel(Vector3(x,0,side*7.35),Vector3(x+2.0,0,side*7.35))
		for z in range(-6,6,2):
			_fence_panel(Vector3(side*10.4,0,z),Vector3(side*10.4,0,z+2.0))

func _timber_plank(a: Vector3, b: Vector3, width: float, thickness: float, color: Color) -> void:
	var along := (b-a).normalized()
	var deep := along.cross(Vector3.UP).normalized()
	if deep.length()<.1: deep = Vector3.FORWARD
	var across := deep.cross(along).normalized()*width*.5
	deep *= thickness*.5
	var aa := a+across+deep
	var ab := a-across+deep
	var ac := a-across-deep
	var ad := a+across-deep
	var ba := b+across+deep
	var bb := b-across+deep
	var bc := b-across-deep
	var bd := b+across-deep
	_quad(_timber,aa,ba,bb,ab,color)
	_quad(_timber,ad,ac,bc,bd,color.darkened(.13))
	_quad(_timber,aa,ad,bd,ba,color.lightened(.08))
	_quad(_timber,ab,bb,bc,ac,color.darkened(.18))
	_quad(_timber,aa,ab,ac,ad,color.darkened(.13))
	_quad(_timber,ba,bd,bc,bb,color.lightened(.06))
	# Pale split fibres and one dark longitudinal fissure catch the low sun.
	for line in 3:
		var shift := across*(line*.53-.52)+deep*1.03
		_beam(a.lerp(b,.09)+shift,b.lerp(a,.08)+shift+across*.07,.0035,color.lightened(.21) if line!=1 else color.darkened(.35),4,_timber)

func _fence_panel(a: Vector3, b: Vector3) -> void:
	var along := (b-a).normalized()
	var normal := Vector3(-along.z,0,along.x)
	for p in [a,b]:
		_beam(p+Vector3.UP*.06,p+Vector3.UP*1.47,.125,Color("76573e"),8,_timber)
		_beam(p+Vector3.UP*1.44,p+Vector3.UP*1.49,.133,Color("98805a"),8,_timber)
	for y in [.32,1.16]:
		_timber_plank(a+Vector3.UP*y,b+Vector3.UP*y,.19,.13,Color("775239"))
	_timber_plank(a+Vector3.UP*.38+normal*.073,b+Vector3.UP*1.10+normal*.073,.135,.08,Color("695039"))
	_timber_plank(a+Vector3.UP*1.10-normal*.03,b+Vector3.UP*.38-normal*.03,.135,.08,Color("806048"))
	for p in [a,b]:
		for y in [.32,1.16]:
			var q: Vector3 = p+Vector3.UP*y
			for sign_v in [-1.0,1.0]:
				var face: Vector3 = q+normal*.147*sign_v
				_quad(_copper,face-along*.078-Vector3.UP*.128,face+along*.078-Vector3.UP*.128,face+along*.078+Vector3.UP*.128,face-along*.078+Vector3.UP*.128,Color("919982"))
				for y_offset in [-.080,.080]:
					_beam(face+Vector3.UP*y_offset,face+Vector3.UP*y_offset+normal*.016*sign_v,.024,Color("777663"),8,_copper)

func _lantern_glass_panels() -> void:
	for p in [Vector3(-9.7,0,-5.4),Vector3(9.7,0,-5.4),Vector3(-9.7,0,5.4),Vector3(9.7,0,5.4)]:
		_stone(p,.68,.68,.15,0,Color("7d8175"),.08)
		_stone(p+Vector3.UP*.15,.48,.48,.58,.02,Color("747c72"),.07)
		_stone(p+Vector3.UP*.73,.63,.63,.12,0,Color("939780"),.07)
		_beam(p+Vector3.UP*.85,p+Vector3.UP*1.90,.061,Color("91856c"),12,_copper)
		for y in [.87,.94,1.77,1.86]:
			_beam(p+Vector3.UP*y,p+Vector3.UP*(y+.041),.091,Color("a2ac94"),12,_copper)
		_lantern_head(p+Vector3.UP*1.90,1.0)
		_collision("LanternStoneBase",p+Vector3.UP*.4,Vector3(.65,.8,.65))
	for side in [-1.0,1.0]:
		var p := Vector3(side*3.08,2.74,-7.92)
		_beam(p,p+Vector3(side*.54,0,0),.055,Color("707f73"),10,_copper)
		_beam(p+Vector3(side*.54,0,0),p+Vector3(side*.54,-.34,0),.021,Color("94a28a"),8,_copper)
		_lantern_head(p+Vector3(side*.54,-1.05,0),.74)

func _lantern_head(p: Vector3, size: float) -> void:
	var copper := Color("bec7a4")
	_frustum(p,.17,.23,.075,4,PI/4.0,copper,_copper,size)
	_frustum(p+Vector3.UP*.075*size,.23,.27,.055,4,PI/4.0,copper.lightened(.06),_copper,size)
	var low_y := .13*size
	var high_y := .67*size
	for k in 4:
		var a := k*TAU/4.0+PI/4.0
		var b := (k+1)*TAU/4.0+PI/4.0
		var p0 := p+Vector3(cos(a)*.22*size,low_y,sin(a)*.22*size)
		var p1 := p+Vector3(cos(b)*.22*size,low_y,sin(b)*.22*size)
		var p2 := p+Vector3(cos(b)*.32*size,high_y,sin(b)*.32*size)
		var p3 := p+Vector3(cos(a)*.32*size,high_y,sin(a)*.32*size)
		_quad(_glass,p0,p1,p2,p3,Color("eec482"))
		_beam(p0,p3,.021*size,copper.darkened(.13),8,_copper)
		_beam(p0,p1,.020*size,copper,8,_copper)
		_beam(p3,p2,.024*size,copper,8,_copper)
		# Narrow edge highlight on rippled old glass.
		_beam(p0.lerp(p1,.15)+Vector3.UP*.04*size,p3.lerp(p2,.15)-Vector3.UP*.045*size,.005*size,Color("e9d9a0"),4,_glass)
	_frustum(p+Vector3.UP*.67*size,.38,.38,.045,4,PI/4.0,copper,_copper,size)
	_frustum(p+Vector3.UP*.715*size,.37,.13,.26,4,PI/4.0,copper.lightened(.06),_copper,size)
	_frustum(p+Vector3.UP*.975*size,.135,.085,.055,8,0,copper,_copper,size)
	_frustum(p+Vector3.UP*1.03*size,.082,.0,.14,8,0,copper.lightened(.11),_copper,size)
	_flame(p+Vector3.UP*.39*size,.67*size)

func _frustum(p: Vector3, lower: float, upper: float, height: float, sides: int, angle: float, color: Color, st: SurfaceTool, size: float = 1.0) -> void:
	for k in sides:
		var a0 := k*TAU/sides+angle
		var a1 := (k+1)*TAU/sides+angle
		var p0 := p+Vector3(cos(a0)*lower,0,sin(a0)*lower)*size
		var p1 := p+Vector3(cos(a1)*lower,0,sin(a1)*lower)*size
		var p2 := p+Vector3(cos(a1)*upper,height,sin(a1)*upper)*size
		var p3 := p+Vector3(cos(a0)*upper,height,sin(a0)*upper)*size
		_quad(st,p0,p3,p2,p1,color)
		_triangle(st,p+Vector3.UP*height*size,p2,p3,color.lightened(.07))

func _radial_moss_grout() -> void:
	# Thin green joints follow the existing rounded radial paving without adding collision.
	for ring in [1.86,2.60,3.36]:
		for i in 32:
			var a := float(i)/32.0*TAU
			var p0 := Vector3(sin(a)*ring,0.057,cos(a)*ring)
			var p1 := Vector3(sin(a+.055)*ring,0.057,cos(a+.055)*ring)
			_beam(p0,p1,.010,Color("68764b"),4,_moss)

func _reference_paving() -> void:
	# The reference's circular medallion uses fitted radial courses, worn bevels
	# and moss between stones. Heights stay visual-only so the arena stays smooth.
	for ring in 5:
		var inner := .66+ring*.65
		var outer := inner+.59
		var count := 14+ring*6
		for i in count:
			var a0 := (i+ring*.48)*TAU/count+.013
			var a1 := (i+1+ring*.48)*TAU/count-.013
			var outline: Array[Vector2] = []
			for k in 4:
				var a := lerpf(a0,a1,k/3.0)
				outline.append(Vector2(sin(a),cos(a))*outer)
			for k in 4:
				var a := lerpf(a1,a0,k/3.0)
				outline.append(Vector2(sin(a),cos(a))*inner)
			var tint := Color("9b9a80").lerp(Color("748379"),_rng.randf()*.62)
			_worn_tile(outline,.045+_rng.randf()*.009,tint)
	var center_outline: Array[Vector2] = []
	for k in 16:
		center_outline.append(Vector2(sin(k*TAU/16.0),cos(k*TAU/16.0))*.59)
	_worn_tile(center_outline,.048,Color("7f8971"))
	# Four arms form a cross outside the ring; joints carry restrained moss.
	for side in [-1.0,1.0]:
		for row in 5:
			for column in 3:
				var across := (column-1)*.62
				var along: float = side*(4.14+row*.60)
				_stone(Vector3(across,.007,along),.56,.53,.038,_rng.randf_range(-.02,.02),Color("92947d"),.06)
				_stone(Vector3(along,.007,across),.53,.56,.038,_rng.randf_range(-.02,.02),Color("87917c"),.06)

func _worn_tile(outline: Array[Vector2], height: float, tint: Color) -> void:
	var center := Vector2.ZERO
	for p in outline: center+=p
	center/=outline.size()
	for i in outline.size():
		var j := (i+1)%outline.size()
		var pa := outline[i]
		var pb := outline[j]
		var shrink_a := pa.lerp(center,.07)
		var shrink_b := pb.lerp(center,.07)
		var v0 := Vector3(pa.x,.009,pa.y)
		var v1 := Vector3(pb.x,.009,pb.y)
		var v2 := Vector3(shrink_b.x,height,shrink_b.y)
		var v3 := Vector3(shrink_a.x,height,shrink_a.y)
		_quad(_cut_stone,v0,v3,v2,v1,tint.lightened(.09))
		_triangle(_cut_stone,Vector3(center.x,height,center.y),v2,v3,tint)
		# Moss grows in the joint at ground height and only occasionally climbs an edge.
		if _rng.randf()<.55:
			var mid := pa.lerp(pb,.47)
			var end := pa.lerp(pb,.90)
			_beam(Vector3(mid.x,.012,mid.y),Vector3(end.x,.012,end.y),.012,Color("687842"),4,_moss)
	# Fine fissures meet the top stone surface without z-fighting.
	if _rng.randf()<.29:
		var edge := outline[_rng.randi()%outline.size()]
		var crack := center.lerp(edge,.35)
		_beam(Vector3(crack.x,height+.0015,crack.y),Vector3(edge.x,height+.0015,edge.y),.0038,tint.darkened(.34),4,_cut_stone)

func _stone(center: Vector3, width: float, depth: float, height: float, angle: float, color: Color, bevel: float = 0.12, target: SurfaceTool = null) -> void:
	if target == null:
		target = _cut_stone
	var outline := [Vector2(-0.38,-0.5), Vector2(0.38,-0.5), Vector2(0.5,-0.36), Vector2(0.5,0.34), Vector2(0.36,0.5), Vector2(-0.34,0.5), Vector2(-0.5,0.36), Vector2(-0.5,-0.34)]
	var bottom: Array[Vector3] = []
	var rim: Array[Vector3] = []
	var top: Array[Vector3] = []
	var basis := Basis(Vector3.UP, angle)
	for p: Vector2 in outline:
		p *= _rng.randf_range(0.91,1.035)
		bottom.append(center + basis * Vector3(p.x * width, 0.0, p.y * depth))
		rim.append(center + basis * Vector3(p.x * width, maxf(0.02, height - bevel), p.y * depth))
		top.append(center + basis * Vector3(p.x * (width - bevel), height, p.y * (depth - bevel)))
	var tc := center + Vector3.UP * height
	for i in 8:
		var j := (i + 1) % 8
		_quad(target, bottom[i], bottom[j], rim[j], rim[i], color.darkened(0.22))
		_quad(target, rim[i], rim[j], top[j], top[i], color.lightened(0.06))
		_triangle(target, tc, top[i], top[j], color.darkened(_rng.randf_range(0.0,0.052)))
	if width > 0.45 and depth > 0.35:
		# Hairline fissures and stone inclusions share the static batch.
		var top_y := center.y+height+0.0015
		var p0 := center+basis*Vector3(-width*0.28,0,-depth*0.13)
		var p1 := center+basis*Vector3(-width*0.06,0,depth*0.01)
		var p2 := center+basis*Vector3(width*0.04,0,depth*0.27)
		p0.y=top_y; p1.y=top_y; p2.y=top_y
		var shift := basis*Vector3(0.01,0,0)
		_quad(target,p0-shift,p1-shift,p1+shift,p0+shift,color.darkened(0.34))
		_quad(target,p1-shift,p2-shift,p2+shift,p1+shift,color.darkened(0.27))
		for fleck in 4:
			var at := center+basis*Vector3(_rng.randf_range(-width*0.31,width*0.31),height+0.002,_rng.randf_range(-depth*0.31,depth*0.31))
			var s := _rng.randf_range(0.009,0.025)
			_triangle(target,at+Vector3(-s,0,-s),at+Vector3(s,0,-s),at+Vector3(0,0,s),color.lightened(0.12))

func _collision(label: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _floor() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "PaintedEarth"
	var plane := PlaneMesh.new()
	plane.size = Vector2(45, 36)
	ground.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("soil_map",load("res://assets/surfaces/soil_albedo.png"))
	mat.set_shader_parameter("soil_normal",load("res://assets/surfaces/soil_normal.png"))
	ground.material_override = mat
	add_child(ground)
	_collision("ArenaFloor", Vector3(0,-0.4,0), Vector3(46,0.8,36))

func _paving() -> void:
	# Flat visual stones do not create movement snags in the combat space.
	for ring in 3:
		var radius := 2.45 + ring * 0.76
		var count := 24 + ring * 8
		for i in count:
			if _rng.randf() < 0.12 + ring * 0.025:
				continue
			var a := float(i) / count * TAU
			var pos := Vector3(sin(a) * radius, 0.008, cos(a) * radius)
			var tint := STONE.lerp(Color("a89c7c"), _rng.randf() * 0.6).darkened(_rng.randf() * 0.12)
			_stone(pos, TAU * radius / count * 0.9, 0.64, 0.046, a, tint, 0.07)
			if _rng.randf() < 0.24:
				_stone(pos + Vector3(0.09,0.05,-0.07), 0.3, 0.33, 0.008, a+0.3, MOSS.darkened(0.1), 0.035)
	# A restrained center medallion keeps silhouettes legible.
	for i in 14:
		var a := float(i) / 14.0 * TAU
		var pos := Vector3(sin(a) * 1.87, 0.009, cos(a) * 1.87)
		_stone(pos, 0.76, 0.55, 0.041, a, DARK_STONE.lightened(0.18), 0.08)
	for x in range(-2,3):
		for z in range(-2,3):
			var pos := Vector3(x*0.61, 0.008, z*0.61)
			if pos.length() > 1.42 or _rng.randf()<0.2:
				continue
			_stone(pos, 0.56, 0.56, 0.032, _rng.randf_range(-0.03,0.03), DARK_STONE.lightened(_rng.randf_range(0.02,0.14)), 0.045)
	for k in 8:
		var a := k * TAU/8.0
		var a0 := Vector3(sin(a)*1.25,0.047,cos(a)*1.25)
		var a1 := Vector3(sin(a)*1.58,0.047,cos(a)*1.58)
		_beam(a0,a1,0.017,GOLD.darkened(0.18),4,_gold)
	# Irregular paving trails lead into the arena gates.
	for side in [-1,1]:
		for row in range(5):
			for col in range(-1,2):
				if _rng.randf()<0.15:
					continue
				var pos := Vector3(col * 0.64 + _rng.randf_range(-0.06,0.06),0.008,side*(4.65 + row*0.61))
				_stone(pos,0.53,0.5,0.035,_rng.randf_range(-0.09,0.09),STONE.darkened(_rng.randf_range(0.0,0.17)),0.065)

func _borders() -> void:
	_collision("WestBoundary", Vector3(-10.9,1.2,0), Vector3(0.5,3,15.8))
	_collision("EastBoundary", Vector3(10.9,1.2,0), Vector3(0.5,3,15.8))
	_collision("NorthBoundary", Vector3(0,1.2,-7.7), Vector3(22.3,3,0.5))
	_collision("SouthBoundary", Vector3(0,1.2,7.7), Vector3(22.3,3,0.5))

func _post(p: Vector3) -> void:
	_box(p + Vector3(0,0.66,0),Vector3(0.24,1.3,0.25),WOOD)
	_box(p + Vector3(0,1.26,0),Vector3(0.31,0.12,0.32),GOLD.darkened(0.24))
	_stone(p+Vector3(0,1.33,0),0.24,0.24,0.07,0,GOLD,0.08)
	for h in [0.34,0.89]:
		_box(p+Vector3(0,h,0),Vector3(0.29,0.065,0.29),BARK)
	for zoff in [-0.075,0.074]:
		_beam(p+Vector3(zoff,0.1,0.13),p+Vector3(zoff+0.019,1.15,0.13),0.008,WOOD.lightened(0.2),4)

func _fence() -> void:
	for side in [-1,1]:
		for x in range(-10,11,2):
			if side==-1 and abs(x)<3:
				continue
			if side==1 and abs(x)<3:
				continue
			var p := Vector3(x,0,side * 7.35)
			_post(p)
			if x < 10 and (x < -2 or x >= 2):
				for y in [0.39,0.94]:
					_box(p+Vector3(1,y,0),Vector3(1.85,0.15,0.15),WOOD.darkened(0.14))
					_beam(p+Vector3(0.14,y+0.037,-0.086),p+Vector3(1.86,y+0.028,-0.086),0.008,WOOD.lightened(0.21),4)
		for z in range(-6,7,2):
			var p := Vector3(side * 10.4,0,z)
			_post(p)
			if z < 6:
				for y in [0.39,0.94]:
					_box(p+Vector3(0,y,1),Vector3(0.15,0.15,1.85),WOOD.darkened(0.1))
					_beam(p+Vector3(-0.08,y+0.03,0.12),p+Vector3(-0.08,y+0.02,1.85),0.008,WOOD.lightened(0.2),4)

func _gate() -> void:
	for side in [-1,1]:
		var x: float = side * 2.45
		_stone(Vector3(x,0,-7.8),1.13,1.07,0.23,0,DARK_STONE,0.14)
		for y in range(5):
			_stone(Vector3(x,0.23+y*0.44,-7.8),0.74,0.75,0.42,_rng.randf_range(-0.027,0.027),STONE.darkened(0.15+y*0.02),0.1)
		_stone(Vector3(x,2.44,-7.8),1.0,0.92,0.18,0,STONE,0.12)
		_stone(Vector3(x,2.62,-7.8),0.7,0.66,0.16,0,MOSS.darkened(0.1),0.1)
		# Engraved diamond with a small inset golden crest.
		_box(Vector3(x,1.63,-7.411),Vector3(0.33,0.33,0.028),DARK_STONE,0)
		var c := Vector3(x,1.63,-7.388)
		_triangle(_gold,c+Vector3(0,0.16,0),c+Vector3(-0.115,0,0),c+Vector3(0,-0.16,0),GOLD.darkened(0.1))
		_triangle(_gold,c+Vector3(0,0.16,0),c+Vector3(0,-0.16,0),c+Vector3(0.115,0,0),GOLD)
		var root := Vector3(x+side*0.35,0.1,-7.45)
		_beam(root,root+Vector3(-side*0.35,1.15,0.08),0.047,Color("435642"),6)
		_beam(root+Vector3(-side*0.35,1.15,0.08),root+Vector3(side*0.11,2.47,-0.02),0.036,Color("435642"),6)
		for k in 7:
			_leaf(root+Vector3(_rng.randf_range(-0.24,0.15),k*0.32+0.18,0.1),_rng.randf()*TAU,0.31,Color("677c43"))
	# Broken central lintel, deliberately above and behind the playable boundary.
	_stone(Vector3(-1.57,2.51,-7.8),1.05,0.68,0.36,-0.025,STONE.darkened(0.08),0.13)
	_stone(Vector3(1.72,2.52,-7.8),0.77,0.68,0.35,0.055,STONE.darkened(0.08),0.13)
	for side in [-1,1]:
		for i in 3:
			_stone(Vector3(side*(3.2+i*0.78),0,-7.52),0.68,0.72,_rng.randf_range(0.42,0.85),_rng.randf_range(-0.1,0.1),DARK_STONE.lightened(0.14),0.15)

func _obstacles() -> void:
	for p in [Vector3(-7.4,0,-4.3),Vector3(7.4,0,-4.3),Vector3(-7.9,0,4.35),Vector3(7.9,0,4.35)]:
		var tower: bool = p.z < 0.0
		_stone(p,1.24,1.04,0.26,_rng.randf_range(-0.1,0.1),DARK_STONE,0.15)
		_stone(p+Vector3(0,0.26,0),0.99,0.81,0.6 if tower else 0.42,0.05,STONE.darkened(0.15),0.15)
		_stone(p+Vector3(0.12,0.86 if tower else 0.67,-0.04),1.04,0.79,0.21,-0.07,STONE,0.13)
		_stone(p+Vector3(-0.08,1.07 if tower else 0.88,-0.02),0.51,0.53,0.05,0.1,MOSS,0.06)
		_collision("RuinBase",p+Vector3(0,0.55,0),Vector3(1.28,1.2,1.05))
		for j in 5:
			var offset := Vector3(_rng.randf_range(-1.0,1.0),0.016,_rng.randf_range(-0.75,0.75))
			_stone(p+offset,0.2+_rng.randf()*0.25,0.24+_rng.randf()*0.18,0.06+_rng.randf()*0.1,_rng.randf()*TAU,STONE.darkened(0.12),0.07)
		for j in 4:
			_fern(p+Vector3(_rng.randf_range(-0.83,0.83),0.0,_rng.randf_range(-0.73,0.73)),_rng.randf_range(0.45,0.7))

func _ground_detail() -> void:
	for i in 1150:
		var p := Vector3(_rng.randf_range(-13.8,13.8),0.028,_rng.randf_range(-10.4,10.4))
		var dist := Vector2(p.x,p.z).length()
		if dist < 4.1:
			continue
		if absf(p.x)<1.15 and absf(p.z)>4.0:
			continue
		if absf(p.x)<8.5 and absf(p.z)<5.6 and _rng.randf()<0.48:
			continue
		var h := _rng.randf_range(0.12,0.4) * (1.25 if dist>10 else 1.0)
		var color := Color("6a7747").lerp(Color("9e9d55"),_rng.randf()*0.7).darkened(_rng.randf()*0.23)
		for j in range(3):
			var theta := _rng.randf()*TAU
			var d := Vector3(cos(theta),0,sin(theta))
			var side := Vector3(-d.z,0,d.x)*0.025
			var base := p + d * _rng.randf_range(-0.08,0.08)
			_triangle(_foliage,base-side,base+Vector3.UP*h+d*h*0.31,base+side,color)
	for i in 470:
		var p := Vector3(_rng.randf_range(-11.2,11.2),0.005,_rng.randf_range(-8.5,8.5))
		if p.length()<2.2 or (p.length()<4.25 and p.length()>2.15):
			continue
		var s := _rng.randf_range(0.045,0.13)
		_stone(p,s*1.4,s,_rng.randf_range(0.022,0.065),_rng.randf()*TAU,STONE.darkened(_rng.randf_range(0.16,0.43)),0.025)
	for i in 85:
		var p := Vector3(_rng.randf_range(-12,12),0,_rng.randf_range(-9,9))
		if absf(p.x)<6.4 and absf(p.z)<5.2:
			continue
		_fern(p,_rng.randf_range(0.28,0.72))
	for i in 110:
		var p := Vector3(_rng.randf_range(-11.3,11.3),0,_rng.randf_range(-8.7,8.7))
		if absf(p.x)<5.0 and absf(p.z)<4.5:
			continue
		var h := _rng.randf_range(0.14,0.29)
		_beam(p,p+Vector3(0,h,0),0.011,Color("667441"),4,_foliage)
		var hue := Color("c7b989") if i%3 else Color("af708d")
		for j in 5:
			var a := float(j)*TAU/5.0
			var t := p+Vector3(0,h,0)
			var a0 := t+Vector3(sin(a)*0.075,0.005,cos(a)*0.075)
			var a1 := t+Vector3(sin(a+0.65)*0.078,0.005,cos(a+0.65)*0.078)
			_triangle(_foliage,t,a0,a1,hue)
		_stone(p+Vector3(0,h+0.005,0),0.033,0.033,0.012,0,GOLD,0.005)
	# Roots and fallen twigs lie flush, outside the active center.
	for i in 24:
		var p := Vector3(_rng.randf_range(-10.1,10.1),0.04,_rng.randf_range(-6.9,6.9))
		if p.length()<5.0:
			continue
		var a := _rng.randf()*TAU
		var v := Vector3(sin(a),0,cos(a))*_rng.randf_range(0.6,1.3)
		_beam(p,p+v,0.029,WOOD.darkened(0.15),5)
		_beam(p+v*0.46,p+v*0.64+Vector3(v.z*0.28,0,-v.x*0.28),0.018,WOOD,5)

func _leaf(p: Vector3, angle: float, length: float, color: Color, up: float = 0.1) -> void:
	var along := Vector3(sin(angle),0,cos(angle))
	var across := Vector3(along.z,0,-along.x)
	var tip := p + along*length + Vector3.UP*up
	var mid := p+along*length*0.5+Vector3.UP*(up+length*0.15)
	var left := mid+across*length*0.23-Vector3.UP*length*0.045
	var right := mid-across*length*0.23-Vector3.UP*length*0.045
	_leaf_face([p,left,mid],[Vector2(.5,0),Vector2(0,.5),Vector2(.5,.5)],color.darkened(.1))
	_leaf_face([left,tip,mid],[Vector2(0,.5),Vector2(.5,1),Vector2(.5,.5)],color.darkened(.04))
	_leaf_face([p,mid,right],[Vector2(.5,0),Vector2(.5,.5),Vector2(1,.5)],color.lightened(.08))
	_leaf_face([mid,tip,right],[Vector2(.5,.5),Vector2(.5,1),Vector2(1,.5)],color.lightened(.12))

func _leaf_face(points: Array, uv: Array, tint: Color) -> void:
	for i in 3:
		_foliage.set_color(tint.darkened(.10))
		_foliage.set_uv(uv[i])
		_foliage.add_vertex(points[i])

func _fern(p: Vector3, size: float) -> void:
	for i in 7:
		var a := i*TAU/7.0+_rng.randf_range(-0.18,0.18)
		var d := Vector3(sin(a),0,cos(a))
		var col := Color("3e684f").lerp(Color("839354"),_rng.randf()*0.55)
		var length := size*_rng.randf_range(0.7,1.1)
		_beam(p,p+d*length+Vector3.UP*size*0.28,0.013,col.lightened(0.1),4,_foliage)
		for j in 4:
			var frac := (j+1)*0.19
			var base := p+d*length*frac+Vector3.UP*(size*0.28*frac+sin(frac*PI)*0.11)
			_leaf(base,a-0.86,length*(0.34-frac*0.22),col,0.015)
			_leaf(base,a+0.86,length*(0.34-frac*0.22),col,0.015)
		_leaf(p+d*length*0.69+Vector3.UP*size*0.25,a,length*0.33,col,0.04)

func _crown_mesh() -> ArrayMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 9
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var v := vertices[i]
		var angle := atan2(v.z,v.x)
		var profile := 1.0 + sin(angle*11.0+v.y*1.7)*0.055 + sin(angle*19.0-v.y)*0.025
		v.x *= profile
		v.z *= profile
		v.y += sin(angle*11.0)*0.04*(1.0-absf(v.y))
		vertices[i] = v
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var shaped := ArrayMesh.new()
	shaped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var st := SurfaceTool.new()
	st.create_from(shaped,0)
	st.generate_normals()
	var array_mesh := st.commit()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode specular_disabled;
varying vec3 local_p;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){local_p=VERTEX;}
void fragment(){
	vec2 p=local_p.xz*5.7+local_p.y*0.17;
	vec2 cell=floor(p);
	vec2 f=fract(p)-0.5;
	float angle=h(cell)*2.8;
	f=mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle)))*f;
	f.y*=1.55;
	float r=length(f);
	float leaf=1.0-smoothstep(0.23,0.35,r);
	float edge=smoothstep(0.27,0.31,r)*(1.0-smoothstep(0.33,0.39,r));
	float vein=(1.0-smoothstep(0.007,0.018,abs(f.y)))*leaf;
	float shade=0.86+floor((local_p.y+1.0)*2.0)*0.067+leaf*0.09-edge*0.08-vein*0.035;
	ALBEDO=COLOR.rgb*0.77*shade;
	ROUGHNESS=1.0;
}"""
	material.shader = shader
	array_mesh.surface_set_material(0,material)
	return array_mesh

func _branch(a: Vector3, b: Vector3, radius: float) -> void:
	var mid := a.lerp(b,0.51)+Vector3(0.09,0.04,-0.05)
	_beam(a,mid,radius,BARK.lightened(0.025),9)
	_beam(mid,b,radius*0.64,BARK.lightened(0.09),8)
	for k in 3:
		var r := radius*0.96
		var side := Vector3(cos(k*TAU/3.0)*r,0,sin(k*TAU/3.0)*r)
		_beam(a+side,mid+side*0.65,0.008,BARK.lightened(0.24),4)

func _leaf_cluster(center: Vector3, size: float, tint: Color) -> void:
	# Individually folded leaves create a broken silhouette with visible branch gaps.
	for k in 38:
		var a := k*2.399963
		var r := sqrt((k+0.4)/38.0)*size
		var y := (1.0-r/size)*size*0.38+_rng.randf_range(-0.13,0.13)
		var p := center+Vector3(cos(a)*r,y,sin(a)*r)
		var c := tint.lightened(_rng.randf_range(0.0,0.14)).darkened(_rng.randf_range(0.0,0.1))
		_leaf(p,a+_rng.randf_range(-0.45,0.45),_rng.randf_range(0.27,0.48)*size,c,_rng.randf_range(-0.04,0.11))

func _maple_petal(p: Vector3, scale: float, color: Color) -> void:
	for petal in 5:
		var angle := petal * TAU / 5.0
		var b := Basis(Vector3.UP,angle)
		var center := p+b*Vector3(0,scale*.15,scale*.48)
		for k in 10:
			var a0 := k*TAU/10.0
			var a1 := (k+1)*TAU/10.0
			var v0 := p+b*Vector3(sin(a0)*scale*.33,scale*(.16+.14*cos(a0)),scale*(.48+cos(a0)*.52))
			var v1 := p+b*Vector3(sin(a1)*scale*.33,scale*(.16+.14*cos(a1)),scale*(.48+cos(a1)*.52))
			for v in [center,v0,v1]:
				_petal_surface.set_uv(Vector2((v.x-p.x)/scale*.5+.5,(v.z-p.z)/scale*.5+.5))
				_petal_surface.set_color(color)
				_petal_surface.add_vertex(v)
	_beam(p,p+Vector3.UP*scale*.28,scale*.14,Color("bd7925"),8)
	for stamen in 5:
		var a := stamen*TAU/5.0
		var tip := p+Vector3(sin(a)*scale*.16,scale*.35,cos(a)*scale*.16)
		_beam(p,tip,scale*.025,Color("f4d36a"),4)
		_stone(tip,scale*.11,scale*.11,scale*.07,0,Color("f6de82"),scale*.02)

func _maple_material(petal: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var prefix := "petal" if petal else "maple"
	mat.albedo_texture = load("res://assets/surfaces/"+prefix+"_albedo.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/surfaces/"+prefix+"_normal.png")
	mat.normal_scale = .56
	mat.roughness_texture = load("res://assets/surfaces/"+prefix+"_roughness.png")
	mat.roughness = .92
	mat.backlight_enabled = true
	mat.backlight = Color(.18,.10,.06)
	return mat

func _finish_maple_batch(st: SurfaceTool, label: String, petal: bool) -> void:
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0,_maple_material(petal))
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	add_child(instance)

func _emit_maple(st: SurfaceTool, transform: Transform3D, tint: Color) -> void:
	# Five deep lobes, smaller edge teeth and a raised midrib. Local z maps to V.
	var outline := PackedVector2Array([Vector2(-.025,-.46),Vector2(-.11,-.29),Vector2(-.28,-.34),Vector2(-.23,-.20),Vector2(-.46,-.13),Vector2(-.34,-.03),Vector2(-.49,.04),Vector2(-.28,.12),Vector2(-.35,.23),Vector2(-.22,.22),Vector2(-.26,.38),Vector2(-.12,.28),Vector2(-.08,.40),Vector2(0,.49),Vector2(.08,.40),Vector2(.12,.28),Vector2(.26,.38),Vector2(.22,.22),Vector2(.35,.23),Vector2(.28,.12),Vector2(.49,.04),Vector2(.34,-.03),Vector2(.46,-.13),Vector2(.23,-.20),Vector2(.28,-.34),Vector2(.11,-.29),Vector2(.025,-.46)])
	var indices := Geometry2D.triangulate_polygon(outline)
	for index in indices:
		var v: Vector2 = outline[index]
		var fold := maxf(0.0,1.0-absf(v.x)*2.1)*.045 + sin(v.y*7.0)*.016
		st.set_color(tint)
		st.set_uv(v+Vector2(.5,.5))
		st.add_vertex(transform*Vector3(v.x,fold,v.y))

func _red_maple(p: Vector3, size: float) -> void:
	var top := p+Vector3(.10*size,1.25*size,.03)
	_branch(p,top,.15*size)
	for root in 5:
		var a := root*TAU/5.0
		_beam(p+Vector3.UP*.18,p+Vector3(cos(a)*.42,.035,sin(a)*.42)*size,.055*size,BARK,7)
	for level in 3:
		var radius := size * (1.12-float(level)*.18)
		var crown := top+Vector3(0,float(level)*.29*size,0)
		for j in 8:
			var a := j*TAU/8.0+level*.53
			# Keep every primary branch buried inside the leaf mass. A short
			# exposed collar still reads between lobes, while the previous full
			# radius endpoint could poke visibly beyond the red canopy silhouette.
			var branch_radius := radius * .72
			var tip := crown+Vector3(cos(a)*branch_radius,-.06*size,sin(a)*branch_radius)
			_branch(top-Vector3.UP*.22,tip,.037*size)
			for twig in 2:
				var twig_angle := a + (twig-.5)*.62
				var twig_len := size * (.11 + .035 * (1.0-float(level)/3.0))
				var target := tip+Vector3(cos(twig_angle)*twig_len,-.025*size,sin(twig_angle)*twig_len)
				_beam(tip,target,.012*size,BARK.lightened(.15),6)
		for leaf in 92:
			var a := leaf*2.399963+level*.74
			var r := sqrt((leaf+.4)/92.0)*radius
			var pos := crown+Vector3(cos(a)*r,(1.0-r/radius)*.22*size+_rng.randf_range(-.07,.10),sin(a)*r)
			var b := Basis.from_euler(Vector3(_rng.randf_range(-.38,.38),a+_rng.randf_range(-.8,.8),_rng.randf_range(-.35,.35)))
			var s := _rng.randf_range(.24,.39)*size
			var tint := Color("7c2530").lerp(Color("d8643d"),_rng.randf_range(.08,.82)).lightened(level*.025)
			_emit_maple(_maple_surface,Transform3D(b.scaled(Vector3.ONE*s),pos),tint)
	for flower in 9:
		var a := flower*2.399963
		var r := _rng.randf_range(.28,.68)*size
		# Seat the flower just above the upper leaf layer, attached by a short stem.
		var y := (.58 + (1.0-r/(size*.76))*.22 + .13)*size
		var flower_pos := top+Vector3(cos(a)*r,y,sin(a)*r)
		_beam(flower_pos-Vector3.UP*.12*size,flower_pos,.006*size,BARK.lightened(.2),5)
		_maple_petal(flower_pos,_rng.randf_range(.075,.12)*size,Color("e8bf59"))

func _maple_detail(p: Vector3, h: float, crown_scale: float) -> void:
	# Fine twigs remain visible through gaps in the red canopy.
	var crown := p + Vector3(0,h,0)
	for j in 9:
		var a := j * 2.399963 + _rng.randf_range(-0.16,0.16)
		var start := p + Vector3(0,h*0.62,0)
		var end := crown + Vector3(cos(a)*crown_scale*_rng.randf_range(.72,1.05), _rng.randf_range(-.16,.42), sin(a)*crown_scale*_rng.randf_range(.72,1.05))
		_branch(start,end,_rng.randf_range(.035,.065))
	# Small clusters of golden petals/seed pods add color breakup.
	for j in 18:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(.25, crown_scale*1.18)
		var petal := crown + Vector3(cos(a)*r,_rng.randf_range(-.28,.48),sin(a)*r)
		_maple_petal(petal,_rng.randf_range(.045,.085),Color("e7bd55"))

func _setup_wind_leaves() -> void:
	# A pooled MultiMesh keeps the medium-density (90) drifting leaves inexpensive.
	_wind_leaves = MultiMeshInstance3D.new()
	_wind_leaves.name = "WindLeaves"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 90
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_maple(st,Transform3D.IDENTITY,Color.WHITE)
	st.generate_normals()
	st.generate_tangents()
	_maple_mesh = st.commit()
	_maple_mesh.surface_set_material(0,_maple_material())
	mm.mesh = _maple_mesh
	_wind_leaves.multimesh = mm
	add_child(_wind_leaves)
	for i in mm.instance_count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side*_rng.randf_range(7.0,12.3),.06,_rng.randf_range(-9.7,9.7))
		if i % 5 == 0:
			pos = Vector3(_rng.randf_range(-10,10),.06,(-1.0 if i%2 else 1.0)*_rng.randf_range(5.7,9.7))
		_wind_leaf_base.append(pos)
		_wind_leaf_phase.append(_rng.randf()*12.0)
		_wind_leaf_speed.append(_rng.randf_range(.75,1.3))
		var s := _rng.randf_range(.17,.29)
		_wind_leaf_size.append(s)
		mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,_wind_leaf_phase[i]).scaled(Vector3.ONE*s),pos))
		mm.set_instance_color(i,Color("a43b29").lerp(Color("e1a74d"),_rng.randf()*.78))

func _forest() -> void:
	var trees := [Vector3(-13,0,-8.8),Vector3(-9.5,0,-10.1),Vector3(-5.9,0,-11.0),Vector3(5.7,0,-11.2),Vector3(9.1,0,-10.0),Vector3(12.7,0,-8.7),Vector3(-13.6,0,-3.6),Vector3(13.6,0,-3.2),Vector3(-13.8,0,1.8),Vector3(13.5,0,2.7),Vector3(-13.2,0,7.3),Vector3(13.4,0,7.5),Vector3(-9.4,0,10.8),Vector3(9.8,0,10.8)]
	for index in trees.size():
		var p: Vector3 = trees[index]
		var h := _rng.randf_range(2.7,4.1)
		var bend := Vector3(_rng.randf_range(-0.35,0.35),0,_rng.randf_range(-0.3,0.3))
		_branch(p,p+Vector3.UP*h+bend,0.31)
		for root in 6:
			var a := root*TAU/6.0
			_beam(p+Vector3.UP*0.25,p+Vector3(sin(a),0.07,cos(a))*_rng.randf_range(0.7,1.3),0.11,BARK.lightened(0.06),5)
		for j in 3:
			var a := j*TAU/3.0+index
			var fork := p+Vector3.UP*(h*0.66)+bend*0.66
			var end := p+Vector3.UP*(h+0.22)+Vector3(sin(a)*0.9,0,cos(a)*0.9)+bend
			_branch(fork,end,0.14)
		for j in 7:
			var a := j*2.39996
			var r := sqrt(float(j)/7.0)*1.41
			var loc := p+Vector3.UP*h+bend+Vector3(sin(a)*r,_rng.randf_range(-0.14,0.65),cos(a)*r)
			var tip := loc+Vector3(sin(a)*0.28,0.16,cos(a)*0.28)
			_branch(p+Vector3.UP*h*0.74+bend*0.74,tip,0.083)
			var tint := Color("315348").lerp(Color("6f8450"),_rng.randf()*0.7)
			_leaf_cluster(loc,_rng.randf_range(0.81,1.15),tint)
			_leaf_cluster(loc+Vector3(0,-0.17,0),0.72,tint.darkened(0.2))
		for j in 4:
			_fern(p+Vector3(_rng.randf_range(-1.2,1.2),0,_rng.randf_range(-1.0,1.0)),_rng.randf_range(0.7,1.1))
	# Lower shrubs knit together the frame without covering combatants.
	for i in 62:
		var side := -1.0 if i%2 else 1.0
		var p := Vector3(side*_rng.randf_range(11.0,14.8),0.35,_rng.randf_range(-10.5,10.7))
		if i%3==0:
			p = Vector3(_rng.randf_range(-13,13),0.3,-9.8-_rng.randf()*2.0)
		var s := _rng.randf_range(0.4,0.85)
		_leaf_cluster(p,s,Color("365848").lerp(Color("708456"),_rng.randf()*0.5))

func _mushrooms() -> void:
	for p in [Vector3(-10.4,0,-8.5),Vector3(9.4,0,-8.6),Vector3(-11.5,0,4.8),Vector3(11.5,0,5.8),Vector3(-7.3,0,9.1),Vector3(6.2,0,9.2),Vector3(-12,0,-0.8)]:
		_red_maple(p,1.3)
		for j in 3:
			var s := _rng.randf_range(0.4,1.15) if j else 1.3
			var center: Vector3 = p+Vector3(_rng.randf_range(-0.5,0.5),0,_rng.randf_range(-0.55,0.55))
			if j%2==0:
				continue
			_beam(center,center+Vector3(0.09*s,0.95*s,0),0.14*s,Color("ae9272"),8)
			var cap := center+Vector3(0.09*s,0.85*s,0)
			var color := Color("9e3d38") if j%2==0 else Color("977239")
			var rings := 7
			var segments := 24
			for r in rings:
				var a0 := float(r)/rings*PI*0.5
				var a1 := float(r+1)/rings*PI*0.5
				for k in segments:
					var t0 := float(k)/segments*TAU
					var t1 := float(k+1)/segments*TAU
					var v0 := cap+Vector3(cos(t0)*sin(a0)*s,cos(a0)*s*0.49,sin(t0)*sin(a0)*s)
					var v1 := cap+Vector3(cos(t1)*sin(a0)*s,cos(a0)*s*0.49,sin(t1)*sin(a0)*s)
					var v2 := cap+Vector3(cos(t1)*sin(a1)*s,cos(a1)*s*0.49,sin(t1)*sin(a1)*s)
					var v3 := cap+Vector3(cos(t0)*sin(a1)*s,cos(a1)*s*0.49,sin(t0)*sin(a1)*s)
					_quad(_solid,v0,v3,v2,v1,color.lightened((1.0-float(r)/rings)*0.16))
					if r==3:
						_triangle(_solid,cap,v2,v3,Color("c3ad83").darkened(0.25))
			for dot in 7:
				var theta := _rng.randf()*TAU
				var rr := _rng.randf_range(0.12,0.75)
				var y := sqrt(1.0-rr*rr)*s*0.49
				var pos := cap+Vector3(cos(theta)*rr*s,y+0.015,sin(theta)*rr*s)
				_stone(pos,s*0.14,s*0.13,0.026,theta,Color("d0ba88"),0.035)

func _flame(p: Vector3, scale_factor: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffc66c")
	mat.emission_enabled = true
	mat.emission = Color("ffaf46")
	mat.emission_energy_multiplier = 2.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = scale_factor * 0.15
	mesh.height = scale_factor * 0.63
	mesh.radial_segments = 7
	mesh.rings = 4
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = p
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_flames.append(instance)
	_fire_base.append(p)
	var light := OmniLight3D.new()
	light.position = p+Vector3.UP*0.18
	light.light_color = Color("ffbe6b")
	light.light_energy = 1.45
	light.omni_range = 4.6
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	add_child(light)

func _lanterns() -> void:
	for p in [Vector3(-9.7,0,-5.4),Vector3(9.7,0,-5.4),Vector3(-9.7,0,5.4),Vector3(9.7,0,5.4)]:
		_stone(p,0.58,0.54,0.16,0,DARK_STONE,0.08)
		_beam(p+Vector3.UP*0.14,p+Vector3.UP*1.62,0.067,GOLD.darkened(0.3),7)
		_stone(p+Vector3.UP*1.36,0.38,0.38,0.085,PI/4,GOLD.darkened(0.11),0.06)
		_stone(p+Vector3.UP*1.94,0.43,0.43,0.11,PI/4,GOLD,0.1)
		for k in 4:
			var a := k*TAU/4+PI/4
			var offset := Vector3(sin(a)*0.18,0,cos(a)*0.18)
			_beam(p+offset+Vector3.UP*1.43,p+offset*0.8+Vector3.UP*1.94,0.022,GOLD.darkened(0.16),5,_gold)
		_beam(p+Vector3.UP*2.05,p+Vector3.UP*2.22,0.042,GOLD,6,_gold)
		_flame(p+Vector3.UP*1.69,0.73)
	for p in [Vector3(-3.5,0,-6.9),Vector3(3.5,0,-6.9)]:
		_stone(p,0.66,0.66,0.18,0,DARK_STONE,0.07)
		_beam(p+Vector3.UP*0.17,p+Vector3.UP*0.84,0.13,GOLD.darkened(0.42),8)
		_stone(p+Vector3.UP*0.79,0.64,0.64,0.13,PI/4,GOLD.darkened(0.3),0.08)
		for k in 6:
			var a := k*TAU/6
			_beam(p+Vector3(sin(a)*0.2,0.87,cos(a)*0.2),p+Vector3(sin(a)*0.31,1.15,cos(a)*0.31),0.025,GOLD.darkened(0.18),5,_gold)
		_flame(p+Vector3.UP*1.15,1.0)

