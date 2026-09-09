extends SceneTree

var stage: Node3D
var camera: Camera3D
var hero: Node3D
var boss: Node3D
var failure := 0

func _initialize() -> void: call_deferred("run")

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://captures/v5_"+label+".png")
	print("CHARACTER_CAPTURE ",label," result=",result)
	if result != OK: failure += 1

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	stage=Node3D.new()
	root.add_child(stage)
	var env_node:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("303842")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("ccd8e8")
	env.ambient_light_energy=.47
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env_node.environment=env
	stage.add_child(env_node)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-42,-32,0)
	sun.light_energy=1.0
	sun.shadow_enabled=true
	stage.add_child(sun)
	var rim:=DirectionalLight3D.new()
	rim.rotation_degrees=Vector3(-20,145,0)
	rim.light_energy=.28
	rim.light_color=Color("7b9ddb")
	stage.add_child(rim)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4.3
	stage.add_child(camera)
	camera.current=true
	hero=Node3D.new()
	hero.set_script(load("res://scripts/actor_visual.gd"))
	stage.add_child(hero)
	hero.setup(false)
	boss=Node3D.new()
	boss.set_script(load("res://scripts/actor_visual.gd"))
	stage.add_child(boss)
	boss.setup(true)
	await create_timer(.8).timeout
	for subject in [hero,boss]:
		hero.visible=subject==hero
		boss.visible=subject==boss
		camera.size=3.35 if subject==hero else 4.6
		var target:=Vector3(0,1.05 if subject==hero else 1.58,0)
		var prefix: String="hero" if subject==hero else "boss"
		for view in ["front","right","back","left"]:
			var a:float={"front":PI,"right":PI*.5,"back":0.0,"left":-PI*.5}[view]
			camera.position=target+Vector3(sin(a)*7,1.2,cos(a)*7)
			camera.look_at(target)
			subject.update_pose("idle",0,Vector3.FORWARD,0,0,1)
			await shot(prefix+"_"+view)
	print("V5_CHARACTER_REVIEW ","PASS" if failure==0 else "FAIL")
	stage.free()
	quit(failure)
