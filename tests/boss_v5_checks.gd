extends SceneTree

var combat: Node3D
var errors := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: errors += 1

func _reset() -> void:
	combat.restart()
	combat.player.position = Vector3(0,.03,2.4)
	combat.boss.position = Vector3(0,.03,0)
	combat.player_direction = Vector3.FORWARD
	combat.boss_direction = Vector3.BACK
	combat._boss_wait = 100

func _run() -> void:
	for action in ["move_left","move_right","move_up","move_down","block"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	combat = Node3D.new()
	combat.set_script(load("res://scripts/combat.gd"))
	root.add_child(combat)
	combat.setup(null)
	combat.set_physics_process(false)
	await physics_frame
	for low_health in [false,true]:
		_reset()
		if low_health: combat.boss_hp = 400
		combat.force_boss_action("slash")
		for strike in 3:
			_check(combat._boss_slash_index == strike, "Three-strike sequence phase %d at phase-two=%s" % [strike,str(low_health)])
			_check(combat.visual_state().warning.is_empty(), "Ordinary strike has no ground warning")
			combat.boss_time = combat._boss_duration * .46
			combat._update_visuals(1.0)
			combat.player.position = combat.boss.position + combat.boss_direction * 2.0
			var health_before: float = combat.hp
			combat._boss_hit = false
			combat._boss_melee(3.4,.72 if strike == 2 else -.03,.45)
			combat._boss_melee(3.4,.72 if strike == 2 else -.03,.45)
			_check(is_equal_approx(health_before - combat.hp,27.0), "Each combo strike deals exactly one hit")
			if strike == 2:
				_check(combat._boss_pose() == "boss_overhead", "Overhead has a distinct pose, separate from thrust")
			combat.boss_time = combat._boss_duration
			combat._tick_boss(0.0)
		_check(combat.boss_state == "idle", "Third strike ends after committed crouch recovery")
	_reset()
	combat.force_boss_action("thrust")
	combat.boss_time = .95
	_check(not combat.visual_state().boss_active.active and combat.visual_state().boss_active.glint, "One-second thrust charge is readable before damage")
	for instant in [1.0,1.16,1.32]:
		combat.boss_time = instant
		var active: Dictionary = combat.visual_state().boss_active
		_check(active.active and active.parryable and active.glint, "Whole dash is live and parryable at %.2fs" % instant)
	combat.boss_time = 1.34
	_check(not combat.visual_state().boss_active.active and not combat.visual_state().boss_active.parryable, "Dash recovery does not retain damage or parry cues")
	combat.boss_time = .92
	combat._update_visuals(1.0)
	_check(absf(rad_to_deg(combat.boss_visual.joints.ShinR.rotation.x) + 90) < 2, "Thrust wind-up bends front knee to 90 degrees")
	_reset()
	combat.force_boss_action("slam")
	combat.boss_time = combat._boss_duration * .30
	combat._update_visuals(1.0)
	_check(combat._boss_pose() == "boss_slam" and combat.visual_state().boss_active.charge, "Slam has dedicated charged two-hand pose")
	var shoulder_y: float = maxf(combat.boss_visual.joints.UpperArmL.global_position.y,combat.boss_visual.joints.UpperArmR.global_position.y)
	_check(combat.boss_visual.joints.HandL.global_position.y > shoulder_y + .45 and combat.boss_visual.joints.HandR.global_position.y > shoulder_y + .45, "Both slam hands rise above shoulder line after IK")
	var charged_blade: PackedVector3Array = combat.boss_visual.get_blade_points()
	_check(charged_blade[1].y < charged_blade[0].y, "Charged slam points the blade downward")
	combat.boss_time = combat._boss_duration * .46
	combat._tick_boss(0)
	_check(combat._shockwaves.size() == 1 and combat.visual_state().warning.is_empty(), "Ground impact emits one wave and removes warning")
	combat._tick_boss(0)
	_check(combat._shockwaves.size() == 1, "Held impact pose cannot duplicate damage wave")
	combat.boss_time = combat._boss_duration * .62
	combat._update_visuals(1)
	_check(rad_to_deg(combat.boss_visual.joints.ShinL.rotation.x) < -90 and rad_to_deg(combat.boss_visual.joints.ShinR.rotation.x) < -90, "Slam impact holds a deep two-knee crouch")
	var blade: PackedVector3Array = combat.boss_visual.get_blade_points()
	var blade_length: float = blade[0].distance_to(blade[1])
	var finite := true
	for state in ["boss_thrust","boss_slam","boss_overhead"]:
		for frame in 61:
			combat.boss_visual.update_pose(state,frame / 60.0,Vector3.FORWARD,0,0,1.0 / 60.0)
			blade = combat.boss_visual.get_blade_points()
			finite = finite and blade[0].is_finite() and blade[1].is_finite() and absf(blade[0].distance_to(blade[1])-blade_length) < .002
	_check(finite, "183 boss pose samples keep a rigid finite blade")
	print("BOSS_V5_CHECKS: ", "PASS" if errors == 0 else "FAIL", " failures=", errors)
	quit(errors)
