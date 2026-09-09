extends SceneTree

var main: Node3D
var samples: Array[float] = []
var draw_calls: Array[int] = []
var recording := false
var last_frame := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and last_frame > 0:
		samples.append((now - last_frame) / 1000.0)
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	last_frame = now
	return false

func _check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func _shot(filename: String) -> void:
	recording = false
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var error := picture.save_png(ProjectSettings.globalize_path("res://captures/v2_" + filename + ".png"))
	_check(error == OK, "Rendered capture: " + filename)

func _reset(player_at := Vector3(-2, .03, 2), boss_at := Vector3(1, .03, -1)) -> void:
	main._restart()
	main.combat._test_mode = true
	main.combat._boss_wait = 100.0
	main.combat.player.position = player_at
	main.combat.boss.position = boss_at
	await physics_frame
	await physics_frame

func _boss_progress(amount: float) -> void:
	for frame in 240:
		if main.combat.boss_time / main.combat._boss_duration >= amount: return
		await physics_frame

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.shake_enabled = false
	await create_timer(1.5).timeout
	await _reset()
	await _shot("sunset_arena")
	await _reset(Vector3(0, .03, 2.1), Vector3(0, .03, 0))
	main.combat.force_boss_action("slash")
	await _boss_progress(.19)
	_check(main.combat.visual_state().warning.is_empty(), "Ordinary slash has no ground warning")
	await _shot("slash_windup")
	await _reset(Vector3(0, .03, 2.4), Vector3(0, .03, 0))
	main.combat.force_boss_action("thrust")
	await _boss_progress(.25)
	_check(main.combat.visual_state().warning.get("kind") == "thrust", "Thrust warning comes from combat geometry")
	await _shot("thrust_warning")
	main.combat.request_player_action("parry")
	for frame in 90:
		if main.combat.parries > 0: break
		await physics_frame
	_check(main.combat.parries == 1, "Rendered scene preserves timed shield parry")
	await _shot("parry_impact")
	await _reset(Vector3(-3.5, .03, 3.6), Vector3(3.5, .03, -3.2))
	main.combat.request_player_action("skill")
	for frame in 120:
		if not main.combat.projectiles.is_empty() and main.combat.projectiles[0].age > .22: break
		await physics_frame
	_check(not main.combat.projectiles.is_empty(), "Q displays a traveling projectile after launch")
	await _shot("q_projectile")
	await _reset(Vector3(-5, .03, 3.5), Vector3(.4, .03, -1.4))
	main.combat.force_boss_action("slam")
	await _boss_progress(.31)
	await _shot("slam_warning")
	for frame in 200:
		if not main.combat._shockwaves.is_empty() and main.combat._shockwaves[0].radius > 4.1: break
		await physics_frame
	_check(not main.combat._shockwaves.is_empty(), "Slam displays the simulated expanding front")
	await _shot("slam_front")
	main.hud.toggle_pause()
	var frozen: float = main.combat.simulation_time
	await create_timer(.2).timeout
	_check(main.combat.simulation_time == frozen, "Pause freezes live projectile and hazard clock")
	main.hud.toggle_pause()
	await _reset()
	_check(main.combat.projectiles.is_empty() and main.combat._shockwaves.is_empty(), "Retry clears hazards and projectile")
	# Measure real render pacing while both actors and full effect layers are active.
	for action in ["thrust", "slam", "slash", "slam", "thrust", "slam"]:
		await _reset(Vector3(-2.5, .03, 3.0), Vector3(1, .03, -1.2))
		main.combat.hp = 10000
		main.combat.force_boss_action(action)
		main.combat.request_player_action("skill")
		recording = true
		await create_timer(3.0).timeout
		recording = false
	if not samples.is_empty():
		samples.sort()
		draw_calls.sort()
		var result := {"frames": samples.size(), "median_ms": samples[samples.size() / 2],
			"p95_ms": samples[int(samples.size() * .95)], "draw_calls_median": draw_calls[draw_calls.size() / 2],
			"draw_calls_p95": draw_calls[int(draw_calls.size() * .95)], "failures": failures,
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
			"device": RenderingServer.get_video_adapter_name(), "viewport": str(root.size)}
		var report := FileAccess.open("res://tests/v2_render_metrics.json", FileAccess.WRITE)
		report.store_string(JSON.stringify(result, "\t"))
		print("V2_RENDER_METRICS ", JSON.stringify(result))
	print("V2_VISUAL_REVIEW ", "PASS" if failures == 0 else "FAIL")
	main.free()
	quit(failures)
