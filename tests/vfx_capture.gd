extends SceneTree

var main: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://captures/") + filename)
	print("VFX_CAPTURE ", filename)

func _reset() -> void:
	main._restart()
	main.combat._boss_wait = 100.0
	main.combat.player.position = Vector3(0, .03, 1.7)
	main.combat.boss.position = Vector3(0, .03, -.7)
	await physics_frame

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await create_timer(1.0).timeout
	await _reset()
	main.combat.force_boss_action("thrust")
	await create_timer(.43).timeout
	await _shot("golden_cue.png")
	main.combat.request_player_action("parry")
	await create_timer(.24).timeout
	assert(main.combat.parries == 1, "Timed parry must succeed in actual rendered scene")
	await _shot("parry_success.png")
	await _reset()
	main.combat.request_player_action("skill")
	await create_timer(.49).timeout
	await _shot("skill_trail.png")
	await _reset()
	main.combat.player.position = Vector3(-5, .03, 3)
	main.combat.force_boss_action("slam")
	await create_timer(1.5).timeout
	await _shot("slam_wave.png")
	print("VFX_CAPTURE_CHECKS_PASS")
	main.free()
	quit()
