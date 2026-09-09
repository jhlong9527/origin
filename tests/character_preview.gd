extends SceneTree

var actors: Array[Node3D] = []
var ticks := 0
var ready_to_capture := false
var defence_mode := false
var heal_mode := false


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	defence_mode = "--defence" in OS.get_cmdline_user_args()
	heal_mode = "--heal" in OS.get_cmdline_user_args()
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("233d38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c3dac9")
	environment.environment.ambient_light_energy = .8
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_color = Color("ffe5b6")
	light.light_energy = 1.3
	light.shadow_enabled = true
	scene.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(30,20)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("496551")
	floor_mesh.material_override = floor_material
	scene.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.8 if heal_mode else 11.7
	camera.position = Vector3(3.7,8.5,-12)
	scene.add_child(camera)
	camera.look_at(Vector3(0,1,0))
	camera.current = true
	for i in range(6):
		var actor := Node3D.new()
		actor.set_script(load("res://scripts/actor_visual.gd"))
		scene.add_child(actor)
		actor.setup(i == 5)
		actor.position = Vector3((i % 3 - 1) * (2.5 if heal_mode else 3.6),0,(-1.4 if i < 3 else 1.8))
		var states := ["block","parry","dodge","stagger","dead","attack"] if defence_mode else ["idle","attack","attack","attack","block","idle"]
		if heal_mode:
			states = ["heal","heal","heal","heal","idle","idle"]
		var progress: float = [.16,.38,.72,.89,.0,.0][i] if heal_mode else .49
		actor.update_pose(states[i],progress,Vector3.FORWARD,0.0,maxi(0,i-1),1.0)
		actors.append(actor)
		print("POSE_REVIEW ",i," joints=",actor.joints.size()," blade=",actor.get_blade_points())
	ready_to_capture = true


func _process(_delta: float) -> bool:
	if not ready_to_capture:
		return false
	ticks += 1
	if ticks == 8:
		var path := "res://tests/character_defence.png" if defence_mode else "res://tests/character_preview.png"
		if heal_mode:
			path = "res://tests/character_heal.png"
		root.get_texture().get_image().save_png(path)
		quit()
	return false
