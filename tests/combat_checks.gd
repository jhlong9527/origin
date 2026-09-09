extends SceneTree

var combat: Node3D
var failures: Array[String] = []
var events: Array[String] = []
var scene: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not OS.get_cmdline_user_args().has("--combat-test"):
		push_error("Pass --combat-test explicitly to run combat checks.")
		quit(2)
		return
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "block", "dodge", "skill", "heal", "lock_target"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	scene = Node3D.new()
	root.add_child(scene)
	_box(Vector3(0,-0.5,0), Vector3(50,1,50))
	combat = Node3D.new()
	combat.set_script(load("res://scripts/combat.gd"))
	scene.add_child(combat)
	combat.setup(null)
	combat.combat_event.connect(func(kind: String, _at: Vector3, _dir: Vector3, _amount: float): events.append(kind))
	await _reset()
	await _advance(0.2)
	_check(combat.player.is_on_floor() and absf(combat.player.position.y) < 0.03, "Native capsule rests on static floor")
	_check(combat.request_player_action("attack"), "First sword attack starts")
	_check(not combat.request_player_action("dodge"), "Committed attack cannot cancel into a roll")
	await _advance(0.30)
	_check(combat.request_player_action("attack"), "Second attack buffers in first swing")
	await _advance(0.41)
	_check(combat.combo == 1, "Buffered reverse slash starts")
	await _advance(0.27)
	_check(combat.request_player_action("attack"), "Third attack buffers in reverse slash")
	await _advance(0.65)
	_check(combat.combo == 2, "Overhead finisher starts")
	await _advance(0.78)
	_check(is_equal_approx(combat.boss_hp, 1100.0-30.0-38.0-55.0), "Three distinct strikes deal damage once each")
	_check(combat.stamina < 70.0, "Full combo meaningfully consumes stamina")

	await _reset()
	combat.force_boss_action("slash")
	await _advance(1.07)
	_check(combat.hp == 103.0, "Boss ordinary slash hits once during active swing")

	await _reset()
	combat.request_player_action("block")
	combat.force_boss_action("slash")
	await _advance(1.07)
	_check(combat.hp > 125.0 and combat.hp < 130.0 and events.has("block"), "Forward shield reduces slash damage with stamina cost")

	await _reset()
	combat.stamina = 4.0
	combat.request_player_action("block")
	combat.force_boss_action("slash")
	await _advance(0.78)
	_check(combat.player_state == "stagger" and events.has("guard_break"), "Insufficient stamina causes costly guard break")

	await _reset()
	combat.force_boss_action("slash")
	await _advance(0.23)
	combat.request_player_action("dodge")
	await _advance(0.40)
	_check(combat.hp == 130.0 and combat._boss_hit, "Timed roll evades an actual colliding boss attack")
	_check(combat.player.position.distance_to(combat.boss.position) >= 0.99, "Roll capsule cannot tunnel through boss capsule")

	await _reset()
	combat.force_boss_action("thrust")
	await _advance(0.87)
	combat.request_player_action("parry")
	await _advance(0.41)
	_check(combat.hp == 130.0 and combat.parries == 1 and combat.boss_state == "stagger", "Timed shield parry stops red-glint thrust and staggers boss")
	_check(events.has("boss_parry_ready") and events.has("parry"), "Parry glint and impact events emit")
	await _advance(0.40)
	combat.request_player_action("attack")
	await _advance(0.9)
	_check(combat.boss_hp <= 1000.0, "Parry opens enhanced counterattack window")

	await _reset()
	combat.force_boss_action("thrust")
	await _advance(0.10)
	combat.request_player_action("parry")
	await _advance(1.10)
	_check(combat.hp == 88.0 and combat.parries == 0, "Early parry is punished by thrust damage")

	await _reset()
	combat.force_boss_action("slash")
	await _advance(0.45)
	combat.request_player_action("parry")
	await _advance(0.50)
	_check(combat.parries == 0 and combat.hp < 130.0, "Normal slash cannot be parried")

	await _reset()
	combat.force_boss_action("slam")
	await _advance(1.85)
	_check(combat.hp == 82.0 and events.has("shockwave"), "Expanding slam shockwave damages once")

	await _reset()
	combat.force_boss_action("slam")
	# The faster slam reaches its impact at ~0.92 s. Roll shortly before the
	# expanding front arrives so the shortened i-frame interval overlaps it.
	await _advance(0.72)
	combat.request_player_action("dodge")
	await _advance(0.65)
	_check(combat.hp == 130.0, "Slam shockwave can be rolled through")

	await _reset()
	combat.hp = 40.0
	combat.request_player_action("heal")
	await _advance(0.58)
	_check(combat.hp == 40.0 and combat.heals == 3, "Heal is committed and has no immediate benefit")
	await _advance(0.78)
	_check(combat.hp == 102.0 and combat.heals == 2, "Completed heal consumes one flask and restores health")

	await _reset()
	combat.request_player_action("skill")
	await _advance(1.15)
	_check(combat.boss_hp <= 955.0 and combat.skill_cd > 6.0, "Lunge skill deals one hit and begins cooldown")
	_check(not combat.request_player_action("skill"), "Skill cannot repeat during cooldown")

	await _reset()
	var wall := _box(Vector3(0,1.1,1.2), Vector3(6,2.2,0.22))
	await _advance(0.06)
	combat.request_player_action("attack")
	await _advance(0.86)
	_check(combat.boss_hp == 1100.0, "Static obstacle blocks melee damage")
	wall.queue_free()
	await process_frame

	await _reset()
	combat.boss_hp = 10.0
	combat.request_player_action("attack")
	await _advance(0.75)
	_check(combat.ended and combat.boss_state == "dead", "Lethal sword attack wins encounter")
	combat.restart()
	_check(not combat.ended and combat.hp == 130.0 and combat.boss_hp == 1100.0 and combat.heals == 3, "Restart restores full encounter state")

	await _reset()
	combat.hp = 1.0
	combat.force_boss_action("thrust")
	await _advance(1.20)
	_check(combat.ended and combat.player_state == "dead", "Lethal boss attack ends encounter in death")
	_check(not combat.request_player_action("attack"), "Dead player cannot attack")

	print("COMBAT_CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _reset() -> void:
	combat.restart()
	combat.player.position = Vector3(0,0.01,2.4)
	combat.boss.position = Vector3(0,0.01,0)
	combat.player_direction = Vector3.FORWARD
	combat.boss_direction = Vector3.BACK
	combat._boss_wait = 100.0
	events.clear()
	await _advance(0.05)


func _advance(seconds: float) -> void:
	for frame in ceili(seconds * 60.0):
		await physics_frame


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
	print("PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)



