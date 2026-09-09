extends SceneTree

func _initialize() -> void:
	call_deferred("_build_preview")

func _build_preview() -> void:
	root.size = Vector2i(1600,900)
	var stage := Node3D.new()
	root.add_child(stage)
	var arena := load("res://scripts/arena.gd").new() as Node3D
	stage.add_child(arena)
	var atmosphere := load("res://scripts/atmosphere.gd").new() as Node3D
	stage.add_child(atmosphere)
	atmosphere.setup()
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0,23,17)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.5
	camera.current = true
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://arena_preview_v2.png")
	print("Arena preview complete: ",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," draw calls")
	quit()
