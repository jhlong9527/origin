extends SceneTree

var main: Node3D
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("res://captures/v4_" + label + ".png")
	check(err == OK, "Capture " + label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Foliage capture requires a real renderer; run without --headless.")
		quit(2)
		return
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.combat.set_physics_process(false)
	main.shake_enabled = false
	main.combat.player.position = Vector3(-1.65, .03, 1.25)
	main.combat.boss.position = Vector3(1.5, .03, -1.15)
	main.combat._update_visuals(1.0)
	var arena: Node3D = main.get_node("Arena")
	var leaves: MultiMeshInstance3D = arena.get_node("WindLeaves")
	check(leaves.multimesh.instance_count == 90, "Medium density stays at 90 pooled leaves")
	check(leaves.multimesh.mesh.get_faces().size() > 12, "Falling leaves use shaped geometry instead of rectangular cards")
	# Sample multiple complete fall cycles with the production update. Rendering
	# is paused only during the fast numerical sweep, then restored for captures.
	var finite_and_clear := true
	var start_pos := leaves.multimesh.get_instance_transform(12).origin
	for step in 720:
		arena._process(1.0 / 30.0)
		for i in 90:
			var xf: Transform3D = leaves.multimesh.get_instance_transform(i)
			finite_and_clear = finite_and_clear and xf.is_finite() and Vector2(xf.origin.x, xf.origin.z).length() >= 4.49
	check(finite_and_clear, "All leaf trajectories remain finite and outside the central combat space over 24 seconds")
	check(start_pos.distance_to(leaves.multimesh.get_instance_transform(12).origin) > .1, "Pooled leaves move over time")
	await create_timer(1.5).timeout
	await shot("arena")
	main.set_process(false)
	main.hud.root.visible = false
	main.reticle.visible = false
	main.forest_focus.visible = false
	main.camera.size = 5.1
	main.camera.position = Vector3(-7.3, 7.0, 14.0)
	main.camera.look_at(Vector3(-7.3, 1.4, 9.1))
	await shot("maple_close")
	await create_timer(2.0).timeout
	await shot("maple_wind_later")
	print("V4_FOLIAGE_REVIEW ", "PASS" if failures == 0 else "FAIL")
	main.free()
	quit(failures)
