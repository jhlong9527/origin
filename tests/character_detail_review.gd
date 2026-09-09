extends SceneTree

var scene: Node3D
var camera: Camera3D
var actors: Array[Node3D] = []
var report: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1f3034")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b0c7cd")
	environment.environment.ambient_light_energy = .55
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-53,-32,0)
	light.light_color = Color("ffe2b8")
	light.light_energy = .95
	light.shadow_enabled = true
	light.shadow_bias = .025
	light.shadow_normal_bias = .35
	scene.add_child(light)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30,30)
	floor_node.mesh = floor_mesh
	floor_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("485b5e")
	floor_node.material_override = floor_mat
	scene.add_child(floor_node)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.8
	camera.position = Vector3(2.3,4.3,-8)
	scene.add_child(camera)
	camera.look_at(Vector3(0,1.4,0))
	camera.current = true
	for legacy in [true,false]:
		for actor in actors: actor.free()
		actors.clear()
		for boss in [false,true]:
			var actor := Node3D.new()
			actor.set_script(load("res://scripts/actor_visual.gd"))
			scene.add_child(actor)
			if legacy:
				load_legacy(actor,boss)
			else:
				actor.setup(boss)
			actor.position.x = 1.35 if boss else -1.3
			actor.update_pose("idle",0,Vector3.FORWARD,0,0,1)
			actors.append(actor)
		await settle()
		var key := "v1" if legacy else "v2"
		report[key] = {"pair_render_draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"rendered_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		await shot("character_"+key+"_front.png")
	camera.position = Vector3(-2.4,4.4,8)
	camera.look_at(Vector3(0,1.4,0))
	await settle()
	await shot("character_v2_back.png")
	camera.position = Vector3(2.3,4.3,-8)
	camera.look_at(Vector3(0,1.4,0))
	actors[0].update_pose("attack",.39,Vector3.FORWARD,0,2,1)
	actors[1].update_pose("attack",.38,Vector3.FORWARD,0,2,1)
	actors[1].set_parry_glow(true)
	await settle()
	await shot("character_v2_actions.png")
	var file := FileAccess.open("res://tests/character_drawcalls.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("CHARACTER_DRAW_CALLS ",JSON.stringify(report))
	quit()

func load_legacy(actor: Node3D,boss: bool) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := "res://assets/characters/source_v1/"+("thorn_lord.glb" if boss else "wayfarer.glb")
	assert(document.append_from_file(ProjectSettings.globalize_path(path),state) == OK)
	actor.is_boss = boss
	actor.model = document.generate_scene(state)
	actor.add_child(actor.model)
	for joint_name in actor.JOINT_NAMES:
		var joint := actor.model.find_child(joint_name,true,false) as Node3D
		actor.joints[joint_name] = joint
		actor.rest_positions[joint_name] = joint.position
	actor.blade_hilt = actor.model.find_child("BladeHilt",true,false)
	actor.blade_tip = actor.model.find_child("BladeTip",true,false)
	actor.sword_node = actor.model.find_child("Sword",true,false)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded,cull_front; void vertex(){VERTEX+=NORMAL*0.008;} void fragment(){ALBEDO=vec3(0.027,0.033,0.031);}"
	var outline := ShaderMaterial.new()
	outline.shader = shader
	actor._prepare_materials(actor.model,{},outline)

func settle() -> void:
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/"+name)
