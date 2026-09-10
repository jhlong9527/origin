extends SceneTree

var combat: Node3D
var scene: Node3D
var failures: Array[String] = []
var events: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_cmdline_user_args().has("--combat-test"):
		push_error("Pass --combat-test explicitly to run bow combat checks.")
		quit(2)
		return
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "block", "dodge", "skill", "heal", "lock_target", "switch_weapon"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	scene = Node3D.new()
	root.add_child(scene)
	_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	combat = Node3D.new()
	combat.set_script(load("res://scripts/combat.gd"))
	scene.add_child(combat)
	combat.setup(null)
	combat.combat_event.connect(func(kind: String, _at: Vector3, _dir: Vector3, _amount: float): events.append(kind))

	await _reset(false)
	_check(combat.weapon_mode == "sword", "Restart preserves sword and shield default")
	_check(combat.request_player_action("switch_weapon"), "Mouse-wheel weapon action starts transition")
	_check(not combat.request_player_action("attack") and not combat.request_player_action("switch_weapon"), "Weapon transition cannot overlap attacks or another transition")
	await _advance(0.23)
	_check(combat.weapon_mode == "sword" and combat.pending_weapon == "bow", "Old weapon remains equipped before handoff midpoint")
	await _advance(0.15)
	_check(combat.weapon_mode == "bow" and combat.player_state == "weapon_switch", "Weapon commits at midpoint before raise-hand recovery completes")
	await _advance(0.30)
	_check(combat.player_state == "idle" and combat.weapon_mode == "bow", "New weapon is ready after 0.62 second transition")
	_check(not combat.request_player_action("block") and not combat.request_player_action("parry"), "Bow has no invisible shield block or parry")

	await _reset()
	_check(combat.request_player_action("attack"), "Bow click begins automatic nock and draw")
	_check(combat.player_state == "bow_shot" and events.has("bow_draw"), "Bow action exposes its own pose and draw event")
	await _advance(0.61)
	_check(combat.arrows.is_empty(), "Arrow stays nocked until draw reaches release")
	await _advance(0.18)
	_check(combat.arrows.size() == 1 and events.count("bow_release") == 1, "Single click releases exactly one arrow at full draw")
	_check(not combat.request_player_action("dodge"), "Post-release follow-through is committed")
	await _advance(0.72)
	_check(events.count("bow_release") == 1 and combat.boss_hp == combat.BOSS_HP - combat.ARROW_DAMAGE, "Flying arrow hits once and does not repeat during recovery")
	_check(combat.arrows.size() == 1 and combat.arrows[0].stuck and combat.arrows[0].attached_to == "boss", "Boss impact retains a stuck arrow")
	if not combat.arrows.is_empty():
		var local_at: Vector3 = combat.arrows[0].local_at
		combat.boss.position += Vector3(2.0, 0.0, -1.0)
		combat.boss_direction = Vector3.RIGHT
		await _advance(0.06)
		var expected: Vector3 = combat.boss.global_position + combat._boss_arrow_basis() * local_at
		_check(combat.arrows[0].at.distance_to(expected) < 0.001, "Embedded arrow follows boss translation and facing")
		combat.arrows[0].stuck_age = 3.9
		combat._tick_arrows(0.05)
		_check(combat.arrows[0].fade == 1.0, "Embedded arrows remain fully visible for four seconds")
		combat._tick_arrows(0.45)
		_check(combat.arrows[0].fade > 0.45 and combat.arrows[0].fade < 0.55, "Arrow fades gradually after persistence interval")
		combat._tick_arrows(0.50)
		_check(combat.arrows.is_empty(), "Arrow is removed after fade finishes")

	await _reset()
	combat._manual_move = Vector3.RIGHT
	var before: Vector3 = combat.player.position
	combat.request_player_action("attack")
	await _advance(0.30)
	var distance: float = combat.player.position.distance_to(before)
	_check(distance > 0.35 and distance < 0.65, "Drawing permits movement at forty percent speed")
	_check(combat.request_player_action("dodge"), "Roll immediately cancels a pre-release draw")
	_check(combat.player_state == "dodge" and combat.dodge_direction.dot(Vector3.RIGHT) > 0.999, "Cancelled draw rolls in WASD movement direction")
	await _advance(0.90)
	_check(events.count("bow_release") == 0 and combat.arrows.is_empty(), "Cancelled draw never emits a delayed arrow")

	await _reset()
	combat.request_player_action("attack")
	combat.stamina = 5.0
	_check(not combat.request_player_action("dodge") and combat.player_state == "bow_shot", "Unaffordable roll leaves the ongoing draw intact")
	await _advance(0.80)
	_check(events.count("bow_release") == 1, "Uncancelled low-stamina draw still releases its paid-for arrow")

	await _reset()
	combat.request_player_action("attack")
	await _advance(0.35)
	_check(combat.request_player_action("switch_weapon"), "Weapon switch can cancel an unreleased arrow")
	await _advance(0.74)
	_check(combat.weapon_mode == "sword" and events.count("bow_release") == 0, "Cancelled draw swaps back to sword with no ghost arrow")
	_check(combat.request_player_action("attack") and combat.player_state == "attack", "Switching back restores normal sword attack")

	await _reset(false)
	combat.request_player_action("switch_weapon")
	await _advance(0.20)
	combat._receive_player_hit(5.0, combat.player.position + Vector3.FORWARD, false, false)
	_check(combat.player_state == "hurt" and combat.weapon_mode == "sword" and combat.pending_weapon == "sword", "Hit before handoff restores old weapon consistently")
	await _reset(false)
	combat.request_player_action("switch_weapon")
	await _advance(0.39)
	combat._receive_player_hit(5.0, combat.player.position + Vector3.FORWARD, false, false)
	_check(combat.player_state == "hurt" and combat.weapon_mode == "bow" and combat.pending_weapon == "bow", "Hit after handoff retains new weapon consistently")

	await _reset()
	before = combat.player.position
	_check(combat.request_player_action("skill") and combat.player_state == "bow_skill", "Bow Q starts backflip skill with shared cooldown")
	await _advance(0.40)
	combat._receive_player_hit(20.0, combat.boss.position, false, false)
	_check(combat.hp == combat.PLAYER_HP, "Airborne backflip has a brief invulnerability window")
	await _advance(0.44)
	_check(events.has("bow_land") and events.count("bow_release") == 0, "Backflip lands before the first volley arrow")
	var retreat: float = combat.player.position.z - before.z
	_check(retreat > 2.45 and retreat < 2.55, "Backflip retreats about 2.5 metres before the grounded volley")
	await _advance(0.20)
	_check(events.count("bow_release") == 1, "First volley arrow follows landing recovery")
	await _advance(0.24)
	_check(events.count("bow_release") == 2, "Second volley arrow fires separately")
	await _advance(0.70)
	_check(events.count("bow_release") == 3 and combat.skill_cd > 5.0, "Skill fires exactly three arrows and keeps shared cooldown")
	_check(not combat.request_player_action("skill"), "Bow Q cannot bypass its cooldown")
	combat.request_player_action("switch_weapon")
	await _advance(0.75)
	_check(combat.weapon_mode == "sword" and not combat.request_player_action("skill"), "Sword and bow Q share the same cooldown after swapping")

	await _reset()
	var wall := _box(Vector3(0, 1.5, 1), Vector3(6, 3, 0.08))
	await _advance(0.05)
	combat._launch_arrow(false)
	combat._tick_arrows(0.6)
	_check(combat.boss_hp == combat.BOSS_HP, "Swept arrow cannot damage a boss behind a thin wall")
	_check(combat.arrows.size() == 1 and combat.arrows[0].stuck and combat.arrows[0].attached_to == "", "Large simulation step embeds arrow in first wall intersection")
	wall.queue_free()
	await process_frame

	await _reset()
	wall = _box(Vector3(0, 1.5, 3.6), Vector3(6, 3, 0.08))
	await _advance(0.05)
	combat._launch_arrow(false)
	_check(combat.arrows.size() == 1 and combat.arrows[0].stuck and combat.boss_hp == combat.BOSS_HP, "Muzzle segment cannot spawn arrows through a nearby wall")
	wall.queue_free()
	await process_frame

	await _reset()
	combat._launch_arrow(false)
	combat._tick_arrows(0.6)
	_check(combat.boss_hp == combat.BOSS_HP - combat.ARROW_DAMAGE and combat.arrows[0].stuck, "Swept flight detects boss even if a frame skips its entire capsule")

	await _reset()
	combat.locked = false
	combat.boss.position = Vector3(12, 0, -6)
	await _advance(0.05)
	combat._launch_arrow(false)
	var initial_y: float = combat.arrows[0].velocity.y
	combat._tick_arrows(0.10)
	_check(combat.arrows[0].velocity.y < initial_y and combat.arrows[0].trail.size() > 1, "Arrow trajectory applies gravity and retains flight samples")
	combat._tick_arrows(1.5)
	_check(combat.arrows[0].stuck and combat.arrows[0].attached_to == "" and absf(combat.arrows[0].at.y) < 0.01, "Missed arrow lands and persists on actual arena ground")

	await _reset()
	wall = _box(Vector3(0, 1.5, 5), Vector3(6, 3, 0.2))
	await _advance(0.05)
	combat.request_player_action("skill")
	await _advance(0.84)
	_check(combat.player.position.z < 4.6, "Backflip capsule stops at arena obstacles")
	wall.queue_free()
	await process_frame

	await _reset()
	combat._launch_arrow(false)
	var initial_age: float = combat.arrows[0].age
	combat._hit_stop = 0.20
	await _advance(0.12)
	_check(combat.arrows[0].age == initial_age, "Hit-stop freezes arrow simulation with combat")
	combat._hit_stop = 0.0
	paused = true
	for index in 4: await process_frame
	_check(combat.arrows[0].age == initial_age, "Pause freezes arrow flight and persistence timers")
	paused = false
	combat.restart()
	_check(combat.arrows.is_empty() and combat.weapon_mode == "sword" and combat.pending_weapon == "sword", "Restart clears arrows and restores coherent weapon state")

	print("BOW_COMBAT_CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _reset(bow := true) -> void:
	combat.restart()
	combat.player.position = Vector3(0, 0.01, 4)
	combat.boss.position = Vector3(0, 0.01, -6)
	combat.player_direction = Vector3.FORWARD
	combat.boss_direction = Vector3.BACK
	combat.boss_state = "test_idle"
	combat._boss_wait = 100.0
	combat.locked = true
	combat.weapon_mode = "bow" if bow else "sword"
	combat.pending_weapon = combat.weapon_mode
	events.clear()
	await _advance(0.05)


func _advance(seconds: float) -> void:
	for frame in ceili(seconds * 60.0): await physics_frame


func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	scene.add_child(body)
	return body


func _check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)
