extends SceneTree

var scene: Node3D
var actor: Node3D
var camera: Camera3D
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1400,1000)
	scene = Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("29333e")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("97b5dc")
	env.environment.ambient_light_energy = .55
	scene.add_child(env)
	for spec in [[Vector3(-44,-33,0),Color("ffe1b8"),2.0],[Vector3(-20,140,0),Color("91b8df"),1.0]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_color = spec[1]
		light.light_energy = spec[2]
		light.shadow_enabled = true
		scene.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16,16)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("414b58")
	mat.roughness = .9
	floor_mesh.material_override = mat
	scene.add_child(floor_mesh)
	actor = Node3D.new()
	actor.set_script(load("res://scripts/actor_visual.gd"))
	scene.add_child(actor)
	actor.setup(true)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.3
	scene.add_child(camera)
	camera.current = true
	await process_frame
	var poses := [
		["slash_forward","attack",.46,0], ["slash_reverse","attack",.46,1],
		["overhead_recovery","boss_overhead",.62,2],
		["thrust_charge","boss_thrust",.95/1.77,0], ["thrust_active","boss_thrust",1.20/1.77,0],
		["slam_charge","boss_slam",.32,0], ["slam_impact","boss_slam",.56,0], ["slam_rising","boss_slam",.91,0]]
	for pose in poses:
		actor.update_pose("idle",0,Vector3.FORWARD,0,0,1.0)
		actor.update_pose(pose[1],pose[2],Vector3.FORWARD,0,pose[3],1.0)
		var blade: PackedVector3Array = actor.get_blade_points()
		var right: Vector3 = actor.joints.HandR.global_position
		var left: Vector3 = actor.joints.HandL.global_position
		print("POSE ",pose[0], " hilt=",blade[0]," tip=",blade[1]," handR=",right," handL=",left," hands_distance=",right.distance_to(left))
		if pose[0] == "slam_impact":
			if absf(blade[1].y-.045) > .06 or right.distance_to(left) > .19: failures += 1
		if pose[0] == "overhead_recovery" and absf(blade[1].y-.055) > .06: failures += 1
		if OS.get_cmdline_user_args().has("--measure-only"): continue
		for side in [false,true]:
			camera.position = Vector3(7,2.7,.15) if side else Vector3(5,3.7,-7)
			camera.look_at(Vector3(0,1.5,-.15))
			await process_frame
			await RenderingServer.frame_post_draw
			var path: String = "res://captures/v5_boss_" + str(pose[0]) + ("_side" if side else "_three_quarter") + ".png"
			var error := root.get_texture().get_image().save_png(path)
			if error != OK: failures += 1
	print("BOSS_POSE_REVIEW_COMPLETED failures=",failures)
	quit(failures)
