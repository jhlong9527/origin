extends SceneTree

var failures = 0
var main: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	print("PASS " if ok else "FAIL ", description)
	if not ok: failures += 1

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _key(code: Key, pressed: bool) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _mouse(button: MouseButton, pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = main.get_viewport().get_screen_transform() * main.get_viewport().get_mouse_position()
	event.global_position = event.position
	Input.parse_input_event(event)

func _cursor_at(world_position: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	event.position = main.get_viewport().get_screen_transform() * main.camera.unproject_position(world_position)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _aim_direction(world_position: Vector3) -> Vector3:
	var offset: Vector3 = world_position - main.combat.player.global_position
	offset.y = 0.0
	return offset.normalized()

func _aim_for_frames(world_position: Vector3, count: int) -> void:
	# Reproject each frame while the encounter camera tracks the player.
	for i in count:
		_cursor_at(world_position)
		await physics_frame

func _reset() -> void:
	main.combat.restart()
	main.combat._boss_wait = 100.0
	main.combat.boss.position = Vector3(8, 0.03, -6)
	await _frames(2)

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(8)
	await _reset()
	_check(not main.combat.locked, "Encounter starts with free mouse aim")
	var cursor_target: Vector3 = main.combat.player.global_position + Vector3(-4.0, 0.0, 0.0)
	await _aim_for_frames(cursor_target, 24)
	_check(main.combat.player_direction.dot(_aim_direction(cursor_target)) > .995, "Idle player faces the cursor projected on the ground")
	# This aim point is deliberately opposite the boss and keyboard movement.
	var start: Vector3 = main.combat.player.position
	_key(KEY_D, true)
	await _aim_for_frames(cursor_target, 20)
	_key(KEY_D, false)
	_check(main.combat.player.position.x > start.x + .6, "Physical D key moves player right")
	_check(main.combat.player_direction.dot(_aim_direction(cursor_target)) > .995, "Movement does not override mouse-facing")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _aim_for_frames(cursor_target, 3)
	_check(main.combat.player_state == "block", "Holding physical right mouse raises shield")
	_check(main.combat.player_direction.dot(_aim_direction(cursor_target)) > .995, "Raised shield faces cursor instead of boss")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(main.combat.player_state == "parry", "Right mouse held + left click selects parry instead of attack")
	_mouse(MOUSE_BUTTON_LEFT, false)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _reset()
	cursor_target = main.combat.player.global_position + Vector3(-3.0, 0.0, -3.0)
	_cursor_at(cursor_target)
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _frames(2)
	_check(main.combat.player_state == "attack", "Unmodified left click starts sword attack")
	var first_direction: Vector3 = main.combat.player_direction
	_check(first_direction.dot(_aim_direction(cursor_target)) > .995, "Attack samples current cursor direction immediately on click")
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(12)
	cursor_target = main.combat.player.global_position + Vector3(4.0, 0.0, 0.0)
	_cursor_at(cursor_target)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	_check(main.combat.player_direction.dot(first_direction) > .999, "Active strike keeps its committed direction")
	for i in 45:
		_cursor_at(cursor_target)
		await physics_frame
		if main.combat.combo == 1: break
	_check(main.combat.combo == 1 and main.combat.player_direction.dot(_aim_direction(cursor_target)) > .995, "Buffered reverse slash samples new cursor direction")
	await _reset()
	cursor_target = main.combat.player.global_position + Vector3(-4.0, 0.0, 0.0)
	_cursor_at(cursor_target)
	_key(KEY_SHIFT, true)
	await _frames(2)
	_check(main.combat.player_state == "dodge", "Physical Shift starts roll")
	_check(main.combat.dodge_direction.dot(Vector3.LEFT) > .995, "Stationary roll falls back to mouse direction")
	_key(KEY_SHIFT, false)
	await _reset()
	cursor_target = main.combat.player.global_position + Vector3(-4.0, 0.0, 0.0)
	_cursor_at(cursor_target)
	_key(KEY_D, true)
	_key(KEY_SHIFT, true)
	await _frames(2)
	var roll_direction: Vector3 = main.combat.dodge_direction
	_check(roll_direction.dot(Vector3.RIGHT) > .995, "Moving roll uses WASD movement even when mouse points opposite")
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	_cursor_at(main.combat.player.global_position + Vector3.FORWARD * 4.0)
	await _frames(8)
	_check(main.combat.dodge_direction.dot(roll_direction) > .999, "Changing cursor during roll does not bend roll direction")
	await _reset()
	cursor_target = main.combat.player.global_position + Vector3(-4.0, 0.0, 0.0)
	_cursor_at(cursor_target)
	_key(KEY_Q, true)
	await _frames(2)
	_check(main.combat.player_state == "skill", "Physical Q starts skill")
	_check(main.combat.player_direction.dot(Vector3.LEFT) > .995, "Q dash and projectile launch direction follow cursor")
	_key(KEY_Q, false)
	await _reset()
	main.hud.toggle_pause()
	var stopped: Vector3 = main.combat.player.position
	var stopped_time: float = main.combat.boss_time
	_key(KEY_D, true)
	await _frames(15)
	_key(KEY_D, false)
	_check(main.combat.player.position.distance_to(stopped) < .001 and main.combat.boss_time == stopped_time, "Pause freezes combat simulation")
	main.hud.toggle_pause()
	await _frames(3)
	_check(not paused and not main.hud.menu.visible, "Resume restores combat and hides menu")
	main.hud._retry()
	await _frames(2)
	_check(main.combat.hp == 130 and main.combat.boss_hp == 1100 and main.combat.heals == 3, "HUD retry restores full encounter")
	main.combat._boss_wait = 100.0
	main.combat.player.position = Vector3(10, .03, 0)
	main.combat.boss.position = Vector3(-8, .03, -5)
	_key(KEY_D, true)
	await _frames(60)
	_key(KEY_SHIFT, true)
	await _frames(40)
	_key(KEY_SHIFT, false)
	_key(KEY_D, false)
	_check(main.combat.player.position.x < 10.65, "Walking and rolling cannot cross actual arena border")
	_check(main.hud.hp.size.x > 250 and main.hud.hp.size.y < 22, "Health gauge has stable compact dimensions")
	var texture := main.get_viewport().get_texture()
	_check(texture != null, "Scene owns render target")
	print("INTEGRATION_CHECKS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(failures)
