extends SceneTree

var scene: Node3D
var camera: Camera3D
var arena: Node3D
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures+=1

func shot(label: String, position: Vector3, target: Vector3, size: float) -> void:
	camera.size=size
	camera.position=position
	camera.look_at(target)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://captures/v5_env_"+label+".png")==OK,"Capture "+label)

func run() -> void:
	scene=Node3D.new()
	root.add_child(scene)
	arena=load("res://scripts/arena.gd").new()
	scene.add_child(arena)
	check(arena.get_node("WindLeaves").multimesh.instance_count==90,"90 pooled wind leaves retained")
	for label in ["CarvedStone","WeatheredTimber","PatinatedCopper","VelvetMoss","AmberLanternGlass"]:
		check(arena.has_node(NodePath(label)),"Environment batch "+label)
	var solids:=0
	for node in arena.get_children():
		if node is StaticBody3D:
			solids+=1
			if node.name.begins_with("MossRock") or node.name.begins_with("LanternStoneBase"):
				check(Vector2(node.position.x,node.position.z).length()>7.5,"New solid base stays outside central arena")
	check(solids>=15,"Arena boundaries, rock bases and lantern bases retain collision")
	var world:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("b7afa0")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("879cab")
	env.ambient_light_energy=.60
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	world.environment=env
	scene.add_child(world)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-31,-37,0)
	sun.light_color=Color("ffd2a0")
	sun.light_energy=1.8
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=60
	scene.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	scene.add_child(camera)
	await process_frame
	if DisplayServer.get_name()=="headless":
		print("V5_ENVIRONMENT_PARSE_COMPLETE")
		scene.free()
		quit(failures)
		return
	await shot("arena",Vector3(0,19,23),Vector3(0,.2,0),26.0)
	await shot("arch",Vector3(3.5,6.2,2),Vector3(0,2.6,-7.92),8.7)
	await shot("lantern_rock_fence",Vector3(-5.5,4.6,.3),Vector3(-9.3,1.05,-5.7),5.0)
	await shot("paving",Vector3(3,8.5,6),Vector3(0,0,0),10.0)
	await shot("maple",Vector3(-7.3,6.6,14.0),Vector3(-7.3,1.4,9.1),5.1)
	var samples:Array[float]=[]
	var previous:=Time.get_ticks_usec()
	for frame in 180:
		await process_frame
		var now:=Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous=now
	samples.sort()
	print("V5_ENVIRONMENT_FRAME_MS median=",samples[90]," p95=",samples[171]," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("V5_ENVIRONMENT_REVIEW ","PASS" if failures==0 else "FAIL")
	scene.free()
	quit(failures)
