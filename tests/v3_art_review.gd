extends SceneTree

var main: Node3D

func _initialize() -> void:
	call_deferred("run")

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://captures/v3_" + label + ".png"
	var err := root.get_texture().get_image().save_png(path)
	print("ART_CAPTURE ", label, " result=",err)

func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.combat.set_physics_process(false)
	main.shake_enabled=false
	main.combat.player.position=Vector3(-1.65,.03,1.25)
	main.combat.boss.position=Vector3(1.5,.03,-1.15)
	main.combat.player_direction=Vector3(1,0,-1).normalized()
	main.combat.boss_direction=Vector3(-1,0,1).normalized()
	main.combat._update_visuals(1.0)
	await create_timer(1.0).timeout
	await shot("arena")
	main.forest_focus.visible=false
	await shot("focus_off")
	main.forest_focus.visible=true
	await shot("focus_on")
	main.forest_focus.material_override.set_shader_parameter("debug_mask",true)
	await shot("focus_mask")
	main.forest_focus.material_override.set_shader_parameter("debug_mask",false)
	await create_timer(2.5).timeout
	await shot("light_later")
	# Close-up keeps the same imported meshes and production materials.
	main.set_process(false)
	main.hud.root.visible=false
	main.reticle.visible=false
	main.forest_focus.visible=false
	main.camera.size=7.2
	main.combat.player.position=Vector3(-1.25,.03,0)
	main.combat.boss.position=Vector3(1.25,.03,0)
	main.combat.player_visual.rotation.y=0
	main.combat.boss_visual.rotation.y=0
	main.camera.position=Vector3(2.0,5,-8)
	main.camera.look_at(Vector3(0,1.3,0))
	await shot("characters_front")
	main.camera.position=Vector3(-2.0,4.5,8)
	main.camera.look_at(Vector3(0,1.3,0))
	await shot("characters_back")
	print("ART_REVIEW_COMPLETE")
	main.free()
	quit()
