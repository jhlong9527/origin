extends Node3D

# Call setup() once after add_child. All atmospheric effects work in GL Compatibility.
var _configured := false
var sun_light: DirectionalLight3D
var light_clock := 0.0
var animate_light := true

func setup() -> void:
	if _configured:
		return
	_configured = true
	name = "SunsetAtmosphere"
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("252c39")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9594ba")
	env.ambient_light_energy = 0.43
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun_light = sun
	sun.name = "LowAmberSun"
	sun.rotation_degrees = Vector3(-27, -135, 0)
	sun.light_color = Color("ffbd7b")
	sun.light_energy = 1.60
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 1.1
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "CoolSkyBounce"
	fill.rotation_degrees = Vector3(-62, 38, 0)
	fill.light_color = Color("80acbd")
	fill.light_energy = 0.22
	add_child(fill)
	_shafts()
	_dust()

func _process(delta: float) -> void:
	if not _configured or not animate_light: return
	light_clock += delta
	# Slow cloud transmission changes avoid flashes during combat.
	sun_light.light_energy = 1.58 + sin(light_clock*.21)*.09 + sin(light_clock*.083)*.06

func _shafts() -> void:
	# Thin planes follow the physical sun direction; no full-screen tint/post-process.
	var shader := load("res://shaders/sunset_shaft.gdshader") as Shader
	var slots := [Vector3(-8.4, 5.7, -7.2), Vector3(-5.1, 5.7, -9.2), Vector3(-11.0, 5.7, -4.0)]
	for i in slots.size():
		var start: Vector3 = slots[i]
		var finish := start + Vector3(9.0, -5.62, 9.0)
		var width := 0.54 if i == 1 else 0.85
		var side := Vector3(0.707, 0, -0.707)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners := [start-side*width*0.32,start+side*width*0.32,finish+side*width,finish-side*width]
		var uv := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
		for j in [0,1,2,0,2,3]:
			st.set_uv(uv[j])
			st.add_vertex(corners[j])
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("phase",i*2.19)
		material.set_shader_parameter("strength",0.095 if i==1 else 0.068)
		var instance := MeshInstance3D.new()
		instance.name = "CanopySunShaft%d" % i
		instance.mesh = st.commit()
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)

func _dust() -> void:
	var shader := load("res://shaders/sunset_dust.gdshader") as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045,0.045)
	quad.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = 82
	var rng := RandomNumberGenerator.new()
	rng.seed = 12071
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-9.8,9.8),rng.randf_range(0.4,4.4),rng.randf_range(-7.0,6.5))
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,p))
		mm.set_instance_custom_data(i,Color(rng.randf(),rng.randf(),rng.randf(),1))
	var instance := MultiMeshInstance3D.new()
	instance.name = "DriftingSunMotes"
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-12,-1,-10),Vector3(24,8,20))
	add_child(instance)
