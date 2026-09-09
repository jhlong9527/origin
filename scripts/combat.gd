extends Node3D

signal stats_changed(data: Dictionary)
signal combat_event(kind: String, at: Vector3, direction: Vector3, amount: float)
signal encounter_ended(victory: bool)

const PLAYER_HP := 130.0
const BOSS_HP := 1100.0
const MAX_STAMINA := 100.0
const MOVE_SPEED := 4.2
const GRAVITY := 24.0
const ACTION_SCALE := 0.82
const PARRY_OPEN := 0.08
const PARRY_CLOSE := 0.25
const PROJECTILE_SPEED := 13.0
const PROJECTILE_DISTANCE := 9.0
const PROJECTILE_DAMAGE := 45.0
const PROJECTILE_RADIUS := 0.60
const SLAM_RADIUS := 7.0
const SHOCKWAVE_DURATION := 0.8
const THRUST_REACH := 3.2
const THRUST_FACING := 0.91
const COMBO_DURATION := [0.72, 0.78, 1.00]
const COMBO_DAMAGE := [30.0, 38.0, 55.0]
const COMBO_COST := [17.0, 19.0, 25.0]
const PLAYER_DURATION := {"skill": 1.1, "dodge": 0.64, "parry": 0.66, "hurt": 0.49, "stagger": 1.5, "heal": 1.45}
const BOSS_DURATION := {"slash": 1.65, "slam": 2.45, "thrust": 2.20, "stagger": 2.7, "hurt": 0.30}
const BOSS_SLASH_SECONDS := [1.10, .94, 1.72]
const THRUST_WINDUP := 1.0
const THRUST_DASH_SECONDS := .32
const BOSS_DAMAGE := {"slash": 27.0, "slam": 48.0, "thrust": 42.0}
const SKILL_COOLDOWN := 8.0
const WEAPON_SWITCH_DURATION := 0.62
const WEAPON_SWITCH_COMMIT := 0.50
const BOW_SHOT_DURATION := 1.05
const BOW_RELEASE_TIME := 0.72
const BOW_SKILL_DURATION := 1.70
const BOW_SKILL_SHOTS := [0.92, 1.14, 1.36]
const ARROW_SPEED := 24.0
const ARROW_GRAVITY := 4.5
const ARROW_DAMAGE := 37.0
const BOW_SKILL_ARROW_DAMAGE := 35.0
const ARROW_STICK_SECONDS := 4.0
const ARROW_FADE_SECONDS := 0.8
const MAX_ARROWS := 48

var player: CharacterBody3D
var boss: CharacterBody3D
var player_visual: Node3D
var boss_visual: Node3D
var camera: Camera3D
var hp := PLAYER_HP
var stamina := MAX_STAMINA
var boss_hp := BOSS_HP
var heals := 3
var skill_cd := 0.0
# Mouse aiming is the default.  Tab toggles the optional boss lock-on mode.
var locked := false
var parries := 0
var combo := 0
var player_state := "idle"
var weapon_mode := "sword"
var pending_weapon := "sword"
var boss_state := "idle"
var player_time := 0.0
var boss_time := 0.0
var player_direction := Vector3.FORWARD
var boss_direction := Vector3.BACK
var dodge_direction := Vector3.FORWARD
var boss_action := ""
var ended := false

var _ready_to_play := false
var _attack_buffer := false
var _player_hit := false
var _boss_hit := false
var _boss_glint := false
var _swing_emitted := false
var _heal_consumed := false
var _stamina_delay := 0.0
var _boss_wait := 1.1
var _boss_sequence := 0
var _boss_followup := false
var _boss_slash_index := 0
var _stats_time := 0.0
var _hit_stop := 0.0
var _shake_velocity := Vector3.ZERO
var _boss_duration := 1.0
var _parry_bonus := false
var _shockwaves: Array[Dictionary] = []
var _manual_block := false
var _manual_move := Vector3.ZERO
var _test_mode := false
var simulation_time := 0.0
var encounter_generation := 0
var projectiles: Array[Dictionary] = []
var _next_projectile_id := 0
var _projectile_shape := SphereShape3D.new()
var _boss_start := Vector3.ZERO
var _thrust_travel := 0.0
var _warning_polygon := PackedVector3Array()
var _next_wave_id := 0
var arrows: Array[Dictionary] = []
var _next_arrow_id := 0
var _bow_shots_fired := 0
var _bow_landed := false
var _bow_skill_direction := Vector3.FORWARD
var _bow_skill_target := Vector3.ZERO


func setup(view_camera: Camera3D) -> void:
	camera = view_camera
	if _ready_to_play:
		return
	_test_mode = OS.get_cmdline_user_args().has("--combat-test")
	_projectile_shape.radius = PROJECTILE_RADIUS
	player = _make_body("Player", 0.38, 1.8)
	boss = _make_body("Boss", 0.64, 2.8)
	var visual_script = load("res://scripts/actor_visual.gd")
	if visual_script:
		player_visual = Node3D.new()
		player_visual.set_script(visual_script)
		player.add_child(player_visual)
		player_visual.setup(false)
		boss_visual = Node3D.new()
		boss_visual.set_script(visual_script)
		boss.add_child(boss_visual)
		boss_visual.setup(true)
	_ready_to_play = true
	restart()


func _make_body(body_name: String, radius: float, height: float) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = body_name
	body.collision_layer = 2
	body.collision_mask = 3
	body.floor_snap_length = 0.3
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	shape_node.shape = shape
	shape_node.position.y = height * 0.5
	body.add_child(shape_node)
	add_child(body)
	return body


func restart() -> void:
	if not _ready_to_play:
		return
	player.position = Vector3(-3, 0.03, 3)
	boss.position = Vector3(2, 0.03, -2)
	player.velocity = Vector3.ZERO
	boss.velocity = Vector3.ZERO
	hp = PLAYER_HP
	boss_hp = BOSS_HP
	stamina = MAX_STAMINA
	heals = 3
	skill_cd = 0.0
	parries = 0
	combo = 0
	locked = false
	ended = false
	player_state = "idle"
	weapon_mode = "sword"
	pending_weapon = "sword"
	_bow_shots_fired = 0
	_bow_landed = false
	boss_state = "idle"
	boss_action = ""
	player_time = 0.0
	boss_time = 0.0
	player_direction = _flat_direction(player.position, boss.position)
	boss_direction = -player_direction
	_attack_buffer = false
	_boss_wait = 1.0
	_boss_sequence = 0
	_boss_followup = false
	_boss_slash_index = 0
	_stamina_delay = 0.0
	_hit_stop = 0.0
	_shake_velocity = Vector3.ZERO
	_shockwaves.clear()
	projectiles.clear()
	arrows.clear()
	simulation_time = 0.0
	encounter_generation += 1
	_manual_move = Vector3.ZERO
	_manual_block = false
	_parry_bonus = false
	_update_visuals(0.0)
	stats_changed.emit(snapshot())


func snapshot() -> Dictionary:
	return {"hp": hp, "max_hp": PLAYER_HP, "stamina": stamina, "max_stamina": MAX_STAMINA,
		"boss_hp": boss_hp, "boss_max_hp": BOSS_HP, "skill_cd": skill_cd, "heals": heals,
		"locked": locked, "boss_state": boss_state, "player_state": player_state,
		"parries": parries, "combo": combo, "boss_phase": 2 if boss_hp <= BOSS_HP * 0.5 else 1,
		"boss_action": boss_action, "ended": ended, "weapon_mode": weapon_mode,
		"pending_weapon": pending_weapon}


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_play or ended or get_tree().paused:
		return
	if event.is_action_pressed("attack"):
		request_player_action("parry" if weapon_mode == "sword" and Input.is_action_pressed("block") else "attack")
	elif event.is_action_pressed("switch_weapon"):
		request_player_action("switch_weapon")
	elif event.is_action_pressed("dodge"):
		request_player_action("dodge")
	elif event.is_action_pressed("skill"):
		request_player_action("skill")
	elif event.is_action_pressed("heal"):
		request_player_action("heal")
	elif event.is_action_pressed("lock_target"):
		locked = not locked
		stats_changed.emit(snapshot())


func request_player_action(action: String) -> bool:
	if not _ready_to_play or ended:
		return false
	if action == "block":
		if weapon_mode != "sword": return false
		_manual_block = true
		return true
	if action == "release_block":
		_manual_block = false
		return true
	if action == "attack" and player_state == "attack":
		if combo < 2 and player_time / _player_duration() > 0.20:
			_attack_buffer = true
			return true
		return false
	# Nocking/drawing is cancellable. Once the arrow is loose the short recovery
	# is committed, just like a sword strike. Failed rolls do not cancel a draw.
	var can_cancel_draw := player_state == "bow_shot" and player_time < BOW_RELEASE_TIME
	if player_state not in ["idle", "move", "block"] and not (can_cancel_draw and action in ["dodge", "switch_weapon"]):
		return false
	_update_player_facing(1.0)
	match action:
		"switch_weapon":
			pending_weapon = "bow" if weapon_mode == "sword" else "sword"
			_manual_block = false
			_set_player_state("weapon_switch")
			combat_event.emit("weapon_switch", player.position + Vector3.UP, player_direction, WEAPON_SWITCH_DURATION)
		"attack":
			combo = 0
			if weapon_mode == "bow":
				if not _spend_stamina(14.0): return false
				_bow_shots_fired = 0
				_set_player_state("bow_shot")
				combat_event.emit("bow_draw", player.position + Vector3.UP * 1.35, player_direction, BOW_RELEASE_TIME)
				return true
			return _begin_player_attack()
		"dodge":
			if not _spend_stamina(26.0):
				return false
			dodge_direction = _movement_input()
			if dodge_direction.length_squared() < 0.01:
				dodge_direction = _mouse_direction()
				if dodge_direction.length_squared() < 0.01:
					dodge_direction = player_direction
			_set_player_state("dodge")
			combat_event.emit("dodge", player.position, dodge_direction, PLAYER_DURATION.dodge * ACTION_SCALE)
		"parry":
			if weapon_mode != "sword": return false
			if not _spend_stamina(16.0):
				return false
			_set_player_state("parry")
		"skill":
			if skill_cd > 0.0 or not _spend_stamina(36.0):
				return false
			skill_cd = SKILL_COOLDOWN
			if weapon_mode == "bow":
				_bow_shots_fired = 0
				_bow_landed = false
				_bow_skill_direction = player_direction
				_bow_skill_target = _arrow_aim_target(player_direction)
				_set_player_state("bow_skill")
			else:
				_set_player_state("skill")
		"heal":
			if heals <= 0 or hp >= PLAYER_HP:
				return false
			_heal_consumed = false
			_set_player_state("heal")
		_:
			return false
	return true


func force_boss_action(action: String) -> bool:
	if action not in ["slash", "slam", "thrust"] or not _ready_to_play or ended:
		return false
	_start_boss_action(action)
	return true


func _physics_process(delta: float) -> void:
	if not _ready_to_play:
		return
	if _hit_stop > 0.0:
		_hit_stop = maxf(_hit_stop - delta, 0.0)
		return
	if ended:
		player_time += delta
		boss_time += delta
		_update_visuals(delta)
		return
	player_time += delta
	boss_time += delta
	simulation_time += delta
	skill_cd = maxf(skill_cd - delta, 0.0)
	_stamina_delay = maxf(_stamina_delay - delta, 0.0)
	var move := _movement_input()
	_tick_player(delta, move)
	if ended: return
	_tick_boss(delta)
	if ended: return
	_tick_shockwaves(delta)
	if ended: return
	_tick_projectiles(delta)
	if ended: return
	_tick_arrows(delta)
	if _stamina_delay <= 0.0 and player_state in ["idle", "move", "block"]:
		stamina = minf(MAX_STAMINA, stamina + delta * (8.0 if player_state == "block" else 24.0))
	_update_visuals(delta)
	_stats_time += delta
	if _stats_time >= 0.05:
		_stats_time = 0.0
		stats_changed.emit(snapshot())


func _tick_player(delta: float, move: Vector3) -> void:
	var horizontal := Vector3.ZERO
	var free := player_state in ["idle", "move", "block"]
	if free:
		var blocking := weapon_mode == "sword" and (_manual_block or Input.is_action_pressed("block"))
		player_state = "block" if blocking else ("move" if move.length_squared() > 0.01 else "idle")
		horizontal = move * (MOVE_SPEED * 0.40 if blocking else MOVE_SPEED)
		_update_player_facing(delta)
	else:
		var progress := clampf(player_time / _player_duration(), 0.0, 1.0)
		match player_state:
			"weapon_switch":
				horizontal = move * MOVE_SPEED * 0.60
				_update_player_facing(delta)
				if progress >= WEAPON_SWITCH_COMMIT:
					weapon_mode = pending_weapon
			"bow_shot":
				horizontal = move * MOVE_SPEED * 0.40
				if _bow_shots_fired == 0:
					_update_player_facing(delta)
					if player_time >= BOW_RELEASE_TIME:
						_bow_shots_fired = 1
						_launch_arrow(false)
			"bow_skill":
				if player_time >= 0.12 and player_time < 0.70:
					# Backward travel follows the committed cast direction and uses the
					# same capsule collision as a normal roll; the visual supplies lift.
					var airborne := (player_time - 0.12) / 0.58
					horizontal = -_bow_skill_direction * (4.6 * sin(airborne * PI))
				if player_time >= 0.70 and not _bow_landed:
					_bow_landed = true
					combat_event.emit("bow_land", player.position, _bow_skill_direction, 1.0)
				# Volley begins only after the backflip has completed and the landing
				# event has fired, so every arrow is visibly shot from the grounded pose.
				while _bow_landed and _bow_shots_fired < BOW_SKILL_SHOTS.size() and player_time >= BOW_SKILL_SHOTS[_bow_shots_fired]:
					_bow_shots_fired += 1
					_launch_arrow(true)
			"dodge":
				horizontal = dodge_direction * lerpf(9.4, 1.6, smoothstep(0.16, 1.0, progress)) / ACTION_SCALE
			"attack":
				horizontal = player_direction * (2.1 / ACTION_SCALE if progress > 0.20 and progress < 0.52 else 0.0)
				if progress >= 0.30 and progress <= 0.60:
					if not _swing_emitted:
						_swing_emitted = true
						combat_event.emit("swing", player.position + Vector3.UP, player_direction, float(combo))
					_check_player_attack(progress)
			"skill":
				horizontal = player_direction * (8.8 / ACTION_SCALE if progress > 0.27 and progress < 0.53 else 0.0)
				if progress >= 0.30 and progress <= 0.62:
					if not _swing_emitted:
						_swing_emitted = true
						combat_event.emit("skill", player.position + Vector3.UP * 0.85, player_direction, 1.0)
						_launch_projectile()
					_check_player_attack(progress)
			"heal":
				if progress >= 0.76 and not _heal_consumed:
					_heal_consumed = true
					heals -= 1
					hp = minf(PLAYER_HP, hp + 62.0)
					combat_event.emit("heal", player.position + Vector3.UP, player_direction, 62.0)
		if progress >= 1.0:
			if player_state == "attack" and _attack_buffer and combo < 2:
				combo += 1
				if not _begin_player_attack():
					_set_player_state("idle")
			else:
				_set_player_state("idle")
				horizontal = Vector3.ZERO
	horizontal += _shake_velocity
	_shake_velocity = _shake_velocity.move_toward(Vector3.ZERO, delta * 17.0)
	_move_body(player, horizontal, delta)


func _movement_input() -> Vector3:
	if _test_mode and _manual_move.length_squared() > 0.0:
		return _manual_move.normalized()
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not is_instance_valid(camera):
		return Vector3(input.x, 0.0, input.y)
	var right := camera.global_basis.x
	right.y = 0.0
	var down := camera.global_basis.z
	down.y = 0.0
	return (right.normalized() * input.x + down.normalized() * input.y).limit_length(1.0)


func _update_player_facing(delta: float) -> void:
	var target := player_direction
	if locked and boss_hp > 0.0:
		target = _flat_direction(player.position, boss.position)
	else:
		var mouse_target := _mouse_direction()
		if mouse_target.length_squared() > 0.01:
			target = mouse_target
	if target.length_squared() > 0.01:
		player_direction = _turn_flat(player_direction, target, minf(delta * 15.0, 1.0))


func _mouse_direction() -> Vector3:
	# Aim on the player's ground plane, independent of keyboard movement.
	# No camera or a cursor directly over the player preserves the last facing.
	if not is_instance_valid(camera) or not is_instance_valid(player):
		return Vector3.ZERO
	var cursor := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(cursor)
	var ray := camera.project_ray_normal(cursor)
	var intersect = Plane(Vector3.UP, player.global_position.y).intersects_ray(origin, ray)
	if intersect == null:
		return Vector3.ZERO
	var offset: Vector3 = intersect - player.global_position
	offset.y = 0.0
	return offset.normalized() if offset.length_squared() > 0.01 else Vector3.ZERO


func _player_duration() -> float:
	if player_state == "weapon_switch": return WEAPON_SWITCH_DURATION
	if player_state == "bow_shot": return BOW_SHOT_DURATION
	if player_state == "bow_skill": return BOW_SKILL_DURATION
	if player_state == "attack":
		return COMBO_DURATION[combo] * ACTION_SCALE
	return PLAYER_DURATION.get(player_state, 1.0) * ACTION_SCALE


func _set_player_state(next: String) -> void:
	if player_state == "weapon_switch" and next != "weapon_switch":
		# Hurt before the midpoint keeps the old weapon; hurt afterwards keeps
		# the new one. Never leave an invisible or half-swapped weapon equipped.
		pending_weapon = weapon_mode
	player_state = next
	player_time = 0.0
	_player_hit = false
	_swing_emitted = false
	if next != "attack":
		_attack_buffer = false


func _begin_player_attack() -> bool:
	if not _spend_stamina(COMBO_COST[combo]):
		return false
	# Each combo strike samples the cursor afresh, then commits through its
	# active swing so moving the mouse cannot redirect an already moving blade.
	_update_player_facing(1.0)
	_attack_buffer = false
	_set_player_state("attack")
	return true


func _spend_stamina(cost: float) -> bool:
	if stamina < cost:
		combat_event.emit("empty", player.position + Vector3.UP, player_direction, cost)
		return false
	stamina -= cost
	_stamina_delay = 0.85
	return true


func _tick_boss(delta: float) -> void:
	if boss_hp <= 0.0:
		return
	var horizontal := Vector3.ZERO
	var separation := _flat_distance(player.position, boss.position)
	if boss_state in ["idle", "move"]:
		boss_direction = _turn_flat(boss_direction, _flat_direction(boss.position, player.position), minf(delta * 6.0, 1.0))
		_boss_wait = maxf(_boss_wait - delta, 0.0)
		if separation > 2.8:
			horizontal = boss_direction * (2.45 if boss_hp > BOSS_HP * 0.5 else 2.8)
			boss_state = "move"
		elif separation < 1.7 and _boss_wait > 0.25:
			horizontal = -boss_direction * 0.65
			boss_state = "move"
		else:
			boss_state = "idle"
		if _boss_wait <= 0.0 and separation <= 5.6:
			var sequence := ["slash", "thrust", "slash", "slam", "thrust", "slam"]
			var next: String = sequence[_boss_sequence % sequence.size()]
			_boss_sequence += 1
			if separation > 3.5 and next == "slash":
				next = "thrust"
			_start_boss_action(next)
	elif boss_state == "stagger":
		if boss_time >= _boss_duration:
			boss_state = "idle"
			_boss_wait = 0.6
			_parry_bonus = false
	elif boss_state == "attack":
		var progress := clampf(boss_time / _boss_duration, 0.0, 1.0)
		if boss_action == "thrust":
			if boss_time >= THRUST_WINDUP - .18 and not _boss_glint:
				_boss_glint = true
				combat_event.emit("boss_parry_ready", boss.position + Vector3.UP * 2.3, boss_direction, THRUST_DASH_SECONDS + .18)
			horizontal = boss_direction * (_thrust_speed() if _thrust_active() and separation > 1.08 else 0.0)
			if _thrust_active():
				_boss_melee(THRUST_REACH, THRUST_FACING)
		elif boss_action == "slash":
			var finish := .50 if _boss_slash_index == 2 else .60
			horizontal = boss_direction * (1.9 if progress >= .25 and progress < finish and separation > 1.12 else 0.0)
			if progress >= .30 and progress <= finish:
				_boss_melee(3.4, .72 if _boss_slash_index == 2 else -.03, progress)
		elif boss_action == "slam":
			if progress >= 0.46 and not _boss_hit:
				_boss_hit = true
				var center := boss.position + boss_direction * 1.15
				center.y = 0.07
				_next_wave_id += 1
				_shockwaves.append({"id": _next_wave_id, "at": center, "time": 0.0, "hit": false, "radius": 0.0})
				combat_event.emit("slam", center, boss_direction, SLAM_RADIUS)
				combat_event.emit("shockwave", center, boss_direction, SLAM_RADIUS)
		var swing_ready := _thrust_active() if boss_action == "thrust" else progress >= .30
		if swing_ready and not _swing_emitted_boss:
			_swing_emitted_boss = true
			combat_event.emit("boss_swing", boss.position + Vector3.UP, boss_direction, 1.0 if boss_action == "thrust" else 0.0)
		if progress >= 1.0 and boss_state == "attack":
			if boss_action == "slash" and _boss_slash_index < 2:
				_boss_slash_index += 1
				_start_boss_action("slash", true)
			else:
				boss_state = "idle"
				_boss_followup = false
				_boss_wait = 0.80 if boss_hp > BOSS_HP * 0.5 else 0.54
	_move_body(boss, horizontal, delta)


var _swing_emitted_boss := false


func _start_boss_action(action: String, followup := false) -> void:
	boss_state = "attack"
	boss_action = action
	boss_time = 0.0
	_boss_hit = false
	_boss_glint = false
	_swing_emitted_boss = false
	boss_direction = _flat_direction(boss.position, player.position)
	if not followup: _boss_slash_index = 0
	_boss_followup = action == "slash" and _boss_slash_index == 1
	_boss_duration = BOSS_DURATION[action] * ACTION_SCALE / (1.15 if boss_hp <= BOSS_HP * 0.5 else 1.0)
	if action == "slash":
		_boss_duration = BOSS_SLASH_SECONDS[_boss_slash_index] / (1.10 if boss_hp <= BOSS_HP * .5 else 1.0)
	elif action == "thrust":
		_boss_duration = THRUST_WINDUP + THRUST_DASH_SECONDS + .45
	_boss_start = boss.position
	_thrust_travel = _thrust_speed() * THRUST_DASH_SECONDS
	if action == "thrust":
		_warning_polygon = _build_thrust_polygon()
	if action != "slash":
		var warning_center := boss.position + (boss_direction * 1.15 if action == "slam" else Vector3.ZERO)
		combat_event.emit("boss_telegraph", warning_center, boss_direction, SLAM_RADIUS if action == "slam" else THRUST_REACH + _thrust_travel)


func _check_player_attack(progress: float) -> void:
	if _player_hit or boss_hp <= 0.0:
		return
	var offset := boss.position - player.position
	offset.y = 0.0
	var reach := 3.15 if player_state == "skill" else (2.90 if combo == 2 else 2.95)
	if offset.length() > reach or offset.length() < 0.01:
		return
	var to_boss := offset.normalized()
	if player_direction.dot(to_boss) < (0.70 if combo == 2 or player_state == "skill" else 0.0):
		return
	if player_state == "attack" and combo < 2:
		var arc := lerpf(-1.1, 1.1, clampf((progress - 0.30) / 0.30, 0.0, 1.0))
		if combo == 1:
			arc = -arc
		var sword_ray := player_direction.rotated(Vector3.UP, arc)
		var closest := Geometry3D.get_closest_point_to_segment(boss.position + Vector3.UP, player.position + Vector3.UP + sword_ray * 0.4, player.position + Vector3.UP + sword_ray * reach)
		if closest.distance_to(boss.position + Vector3.UP) > 0.80:
			return
	if not _clear_path(player.position, boss.position):
		return
	_player_hit = true
	var damage: float = 100.0 if player_state == "skill" else COMBO_DAMAGE[combo]
	if boss_state == "stagger":
		damage *= 1.50
		if _parry_bonus:
			damage += 55.0
			_parry_bonus = false
	boss_hp = maxf(boss_hp - damage, 0.0)
	combat_event.emit("hit", boss.position + Vector3.UP * 1.3, player_direction, damage)
	_hit_stop = 0.06 if combo == 2 or player_state == "skill" else 0.035
	if boss_hp <= 0.0:
		_end_encounter(true)


func _boss_melee(reach: float, facing: float, progress := 0.45) -> void:
	if _boss_hit:
		return
	var offset := player.position - boss.position
	offset.y = 0.0
	if offset.length() > reach or offset.length() < 0.01 or boss_direction.dot(offset.normalized()) < facing:
		return
	if boss_action == "slash" and _boss_slash_index < 2:
		var arc := lerpf(-1.2, 1.2, clampf((progress - 0.30) / 0.30, 0.0, 1.0))
		if _boss_followup:
			arc = -arc
		var ray := boss_direction.rotated(Vector3.UP, arc)
		var nearest := Geometry3D.get_closest_point_to_segment(player.position, boss.position + ray * 0.45, boss.position + ray * reach)
		if nearest.distance_to(player.position) > 0.66:
			return
	if not _clear_path(boss.position, player.position):
		return
	_boss_hit = true
	_receive_player_hit(BOSS_DAMAGE[boss_action], boss.position, boss_action == "thrust", false)


func _tick_shockwaves(delta: float) -> void:
	for index in range(_shockwaves.size() - 1, -1, -1):
		var wave := _shockwaves[index]
		wave.time += delta
		var radius: float = minf(wave.time / SHOCKWAVE_DURATION, 1.0) * SLAM_RADIUS
		wave.radius = radius
		var distance := _flat_distance(wave.at, player.position)
		if not wave.hit and distance <= minf(radius + 0.38, SLAM_RADIUS + 0.38) and distance >= radius - 0.45:
			wave.hit = true
			if _clear_path(wave.at, player.position):
				_receive_player_hit(BOSS_DAMAGE.slam, wave.at, false, true)
				if ended: return
		if wave.time > 0.9:
			_shockwaves.remove_at(index)


func _receive_player_hit(damage: float, origin: Vector3, parryable: bool, heavy: bool) -> void:
	if ended or player_state == "dead":
		return
	if player_state == "dodge" and player_time >= 0.09 * ACTION_SCALE and player_time <= 0.43 * ACTION_SCALE:
		return
	if player_state == "bow_skill" and player_time >= 0.18 and player_time <= 0.56:
		return
	var toward := _flat_direction(player.position, origin)
	var frontal := player_direction.dot(toward) > 0.45
	if parryable and frontal and player_state == "parry" and player_time >= PARRY_OPEN and player_time <= PARRY_CLOSE:
		boss_state = "stagger"
		boss_time = 0.0
		_boss_duration = BOSS_DURATION.stagger * ACTION_SCALE
		boss.velocity = Vector3.ZERO
		parries += 1
		stamina = minf(stamina + 22.0, MAX_STAMINA)
		_parry_bonus = true
		combat_event.emit("parry", player.position + toward * 0.8 + Vector3.UP * 1.2, toward, 1.0)
		_hit_stop = 0.12
		return
	if player_state == "block" and frontal:
		var cost := damage * (1.25 if heavy else 0.95)
		_stamina_delay = 1.05
		if stamina >= cost:
			stamina -= cost
			damage *= 0.22 if heavy else 0.07
			combat_event.emit("block", player.position + toward * 0.65 + Vector3.UP, toward, cost)
			_shake_velocity = -toward * (3.0 if heavy else 1.8)
			_hit_stop = 0.045
		else:
			stamina = 0.0
			damage *= 1.20
			_set_player_state("stagger")
			combat_event.emit("guard_break", player.position + Vector3.UP, toward, damage)
			_shake_velocity = -toward * 4.0
	else:
		_set_player_state("hurt")
		combat_event.emit("hurt", player.position + Vector3.UP, -toward, damage)
		_shake_velocity = -toward * (4.5 if heavy else 3.0)
		_hit_stop = 0.07
	hp = maxf(hp - damage, 0.0)
	if hp <= 0.0:
		_end_encounter(false)
	stats_changed.emit(snapshot())


func _end_encounter(victory: bool) -> void:
	ended = true
	_shockwaves.clear()
	projectiles.clear()
	arrows.clear()
	pending_weapon = weapon_mode
	player.velocity = Vector3.ZERO
	boss.velocity = Vector3.ZERO
	if victory:
		boss_state = "dead"
		boss_time = 0.0
		player_state = "idle"
		combat_event.emit("victory", boss.position + Vector3.UP, Vector3.UP, 1.0)
	else:
		player_state = "dead"
		player_time = 0.0
		boss_state = "idle"
		combat_event.emit("death", player.position + Vector3.UP, Vector3.UP, 1.0)
	stats_changed.emit(snapshot())
	encounter_ended.emit(victory)


func _move_body(body: CharacterBody3D, horizontal: Vector3, delta: float) -> void:
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if body.is_on_floor():
		body.velocity.y = -0.4
	else:
		body.velocity.y -= GRAVITY * delta
	body.move_and_slide()


func _clear_path(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.9, to + Vector3.UP * 0.9, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _update_visuals(delta: float) -> void:
	if is_instance_valid(player_visual):
		if player_visual.has_method("set_weapon_state"):
			if player_state == "weapon_switch" and player_visual.has_method("set_weapon_transition"):
				player_visual.set_weapon_transition(clampf(player_time / WEAPON_SWITCH_DURATION, 0.0, 1.0), weapon_mode, pending_weapon)
			else:
				player_visual.set_weapon_state(weapon_mode, pending_weapon)
		var visual_direction := dodge_direction if player_state == "dodge" else player_direction
		player_visual.rotation.y = atan2(-visual_direction.x, -visual_direction.z)
		var pose := player_state
		player_visual.update_pose(pose, clampf(player_time / _player_duration(), 0.0, 1.0), visual_direction, Vector2(player.velocity.x, player.velocity.z).length(), combo, delta)
	if is_instance_valid(boss_visual):
		boss_visual.rotation.y = atan2(-boss_direction.x, -boss_direction.z)
		var pose := boss_state
		var boss_combo := 0
		if boss_state == "attack":
			pose = _boss_pose()
			boss_combo = _boss_slash_index if boss_action == "slash" else 0
		boss_visual.update_pose(pose, clampf(boss_time / _boss_duration, 0.0, 1.0), boss_direction, Vector2(boss.velocity.x, boss.velocity.z).length(), boss_combo, delta)


func _boss_pose() -> String:
	if boss_action == "thrust": return "boss_thrust"
	if boss_action == "slam": return "boss_slam"
	return "boss_overhead" if _boss_slash_index == 2 else "attack"


func _flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var offset := to - from
	offset.y = 0.0
	return offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


func _turn_flat(from: Vector3, to: Vector3, weight: float) -> Vector3:
	# Yaw interpolation avoids a numerically unstable slerp axis for parallel vectors.
	var yaw := lerp_angle(atan2(from.x, from.z), atan2(to.x, to.z), weight)
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _thrust_speed() -> float:
	return 7.8 / ACTION_SCALE

func _thrust_active() -> bool:
	return boss_time >= THRUST_WINDUP and boss_time <= THRUST_WINDUP + THRUST_DASH_SECONDS


func _launch_projectile() -> void:
	_next_projectile_id += 1
	var at := player.position + Vector3.UP * 0.95 + player_direction * 0.12
	projectiles.append({"id": _next_projectile_id, "at": at, "previous": at, "direction": player_direction,
		"traveled": 0.0, "age": 0.0, "radius": PROJECTILE_RADIUS, "trail": PackedVector3Array([at])})
	combat_event.emit("projectile", at, player_direction, PROJECTILE_DISTANCE)


func _arrow_aim_target(direction: Vector3) -> Vector3:
	if locked and boss_hp > 0.0:
		return boss.global_position + Vector3.UP * 1.35
	if is_instance_valid(camera):
		var cursor := get_viewport().get_mouse_position()
		var target = Plane(Vector3.UP, player.global_position.y + 0.04).intersects_ray(camera.project_ray_origin(cursor), camera.project_ray_normal(cursor))
		if target != null:
			var offset: Vector3 = target - player.global_position
			offset.y = 0.0
			if offset.length() >= 1.1:
				return player.global_position + offset.limit_length(40.0) + Vector3.UP * 0.04
	return player.global_position + direction * 18.0 + Vector3.UP * 0.04


func _launch_arrow(skill: bool) -> void:
	var facing := _bow_skill_direction if skill else player_direction
	var target := _bow_skill_target if skill else _arrow_aim_target(facing)
	var shoulder := player.global_position + Vector3.UP * 1.32
	var at := shoulder + facing * 0.70
	var displacement := target - at
	var flat := Vector3(displacement.x, 0.0, displacement.z)
	var flight_seconds := maxf(flat.length() / ARROW_SPEED, 0.06)
	var velocity := flat.normalized() * ARROW_SPEED
	velocity.y = displacement.y / flight_seconds + 0.5 * ARROW_GRAVITY * flight_seconds
	_next_arrow_id += 1
	var arrow := {"id": _next_arrow_id, "at": at, "previous": shoulder,
		"velocity": velocity, "direction": velocity.normalized(), "age": 0.0,
		"trail": PackedVector3Array([at]), "stuck": false, "stuck_age": 0.0,
		"fade": 1.0, "attached_to": "", "skill": skill,
		"damage": BOW_SKILL_ARROW_DAMAGE if skill else ARROW_DAMAGE}
	# Test the short shoulder-to-tip segment as well, so firing while pressed
	# against a wall cannot spawn the arrow through its far face.
	var initial_hit := _arrow_collision(shoulder, at)
	if not initial_hit.is_empty():
		_stick_arrow(arrow, initial_hit)
	if ended: return
	if arrows.size() >= MAX_ARROWS:
		arrows.pop_front()
	arrows.append(arrow)
	combat_event.emit("bow_release", at, velocity.normalized(), 1.0 if skill else 0.0)


func _arrow_collision(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var wall_query := PhysicsRayQueryParameters3D.create(from, to, 1)
	wall_query.hit_from_inside = true
	var wall := space.intersect_ray(wall_query)
	var body_query := PhysicsRayQueryParameters3D.create(from, to, 2, [player.get_rid()])
	body_query.hit_from_inside = true
	var target := space.intersect_ray(body_query)
	# Resolve the entire previous-tip to next-tip segment. Environment wins
	# equal distances, including a boss capsule touching the rear of a wall.
	if not wall.is_empty() and (target.is_empty() or from.distance_squared_to(wall.position) <= from.distance_squared_to(target.position) + 0.0001):
		return wall
	return target


func _boss_arrow_basis() -> Basis:
	return Basis(Vector3.UP, atan2(-boss_direction.x, -boss_direction.z))


func _stick_arrow(arrow: Dictionary, hit: Dictionary) -> void:
	arrow.at = hit.position
	arrow.stuck = true
	arrow.stuck_age = 0.0
	arrow.fade = 1.0
	arrow.trail = PackedVector3Array()
	if hit.get("collider") == boss and boss_hp > 0.0:
		arrow.attached_to = "boss"
		var basis := _boss_arrow_basis()
		arrow.local_at = basis.inverse() * (arrow.at - boss.global_position)
		arrow.local_direction = basis.inverse() * arrow.direction
		var damage: float = arrow.damage * (1.25 if boss_state == "stagger" else 1.0)
		boss_hp = maxf(boss_hp - damage, 0.0)
		combat_event.emit("hit", arrow.at, arrow.direction, damage)
		combat_event.emit("arrow_hit", arrow.at, arrow.direction, damage)
		_hit_stop = maxf(_hit_stop, 0.025)
		if boss_hp <= 0.0:
			_end_encounter(true)
	else:
		combat_event.emit("arrow_hit", arrow.at, arrow.direction, 0.0)


func _tick_arrows(delta: float) -> void:
	for index in range(arrows.size() - 1, -1, -1):
		var arrow := arrows[index]
		arrow.age += delta
		if arrow.stuck:
			arrow.stuck_age += delta
			if arrow.attached_to == "boss":
				var basis := _boss_arrow_basis()
				arrow.at = boss.global_position + basis * arrow.local_at
				arrow.direction = (basis * arrow.local_direction).normalized()
			arrow.fade = 1.0 - clampf((arrow.stuck_age - ARROW_STICK_SECONDS) / ARROW_FADE_SECONDS, 0.0, 1.0)
			if arrow.stuck_age >= ARROW_STICK_SECONDS + ARROW_FADE_SECONDS:
				arrows.remove_at(index)
			continue
		arrow.previous = arrow.at
		var acceleration := Vector3.DOWN * ARROW_GRAVITY
		var next: Vector3 = arrow.at + arrow.velocity * delta + acceleration * (0.5 * delta * delta)
		arrow.velocity += acceleration * delta
		arrow.direction = arrow.velocity.normalized()
		var hit := _arrow_collision(arrow.previous, next)
		if not hit.is_empty():
			_stick_arrow(arrow, hit)
			if ended: return
		else:
			arrow.at = next
			var trail: PackedVector3Array = arrow.trail
			trail.insert(0, next)
			if trail.size() > 12: trail.resize(12)
			arrow.trail = trail
			# A safety bound only handles shots outside the authored world.
			# Ordinary missed arrows use gravity and stick in the real ground.
			if arrow.age > 6.0 or arrow.at.y < -15.0:
				arrows.remove_at(index)


func _sweep_fraction(at: Vector3, motion: Vector3, mask: int) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _projectile_shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = mask
	query.exclude = [player.get_rid()]
	query.margin = 0.002
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return 0.0
	query.motion = motion
	var fractions := space.cast_motion(query)
	return fractions[0] if not fractions.is_empty() else 1.0


func _tick_projectiles(delta: float) -> void:
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var travel := minf(PROJECTILE_SPEED * delta, PROJECTILE_DISTANCE - projectile.traveled)
		var motion: Vector3 = projectile.direction * travel
		var wall_fraction := _sweep_fraction(projectile.at, motion, 1)
		var boss_fraction := _sweep_fraction(projectile.at, motion, 2)
		var fraction := minf(wall_fraction, boss_fraction)
		projectile.previous = projectile.at
		projectile.at += motion * fraction
		projectile.traveled += travel * fraction
		projectile.age += delta
		var trail: PackedVector3Array = projectile.trail
		trail.insert(0, projectile.at)
		if trail.size() > 10: trail.resize(10)
		projectile.trail = trail
		if fraction < 1.0:
			projectiles.remove_at(index)
			# A wall wins ties, so targets touching its far face cannot be hit through it.
			if boss_fraction < wall_fraction and boss_hp > 0.0:
				boss_hp = maxf(0.0, boss_hp - PROJECTILE_DAMAGE)
				combat_event.emit("hit", projectile.at, projectile.direction, PROJECTILE_DAMAGE)
				combat_event.emit("projectile_impact", projectile.at, projectile.direction, PROJECTILE_DAMAGE)
				_hit_stop = maxf(_hit_stop, 0.04)
				if boss_hp <= 0.0:
					_end_encounter(true)
					return
			else:
				combat_event.emit("projectile_impact", projectile.at, -projectile.direction, 0.0)
		elif projectile.traveled >= PROJECTILE_DISTANCE - 0.001:
			projectiles.remove_at(index)


func _build_thrust_polygon() -> PackedVector3Array:
	var points := PackedVector2Array()
	var half_angle := acos(THRUST_FACING)
	for along in [0.0, _thrust_travel]:
		var center: Vector3 = _boss_start + boss_direction * along
		points.append(Vector2(center.x, center.z))
		for step in 17:
			var direction := boss_direction.rotated(Vector3.UP, lerpf(-half_angle, half_angle, step / 16.0))
			var point: Vector3 = center + direction * THRUST_REACH
			points.append(Vector2(point.x, point.z))
	var hull := Geometry2D.convex_hull(points)
	var polygon := PackedVector3Array()
	for point in hull:
		var endpoint := Vector3(point.x, 0.07, point.y)
		var query := PhysicsRayQueryParameters3D.create(_boss_start + Vector3.UP * 0.9, endpoint + Vector3.UP * 0.83, 1)
		var obstacle := get_world_3d().direct_space_state.intersect_ray(query)
		if not obstacle.is_empty():
			endpoint = obstacle.position
			endpoint.y = 0.07
		polygon.append(endpoint)
	return polygon


# All dangerous presentation reads this state; no independent effect timer controls damage.
func visual_state() -> Dictionary:
	var warning := {}
	var progress := boss_time / maxf(_boss_duration, 0.01)
	if not ended and boss_state == "attack":
		if boss_action == "slam" and progress < 0.46:
			warning = {"kind": "slam", "at": boss.position + boss_direction * 1.15,
				"radius": SLAM_RADIUS, "progress": progress / 0.46}
		elif boss_action == "thrust" and boss_time <= THRUST_WINDUP + THRUST_DASH_SECONDS:
			warning = {"kind": "thrust", "at": _boss_start, "direction": boss_direction,
				"polygon": _warning_polygon, "reach": THRUST_REACH + _thrust_travel,
				"progress": progress, "active": _thrust_active(),
				"glint": boss_time >= THRUST_WINDUP - .18, "boss_at": boss.position}
	var boss_active := {}
	if not ended and boss_state == "attack":
		var live: bool = _thrust_active() if boss_action == "thrust" else (progress >= .30 and progress <= (.50 if _boss_slash_index == 2 else .60))
		if boss_action == "slam": live = progress >= .36 and progress <= .46
		boss_active = {"kind": "boss_" + boss_action, "pose": _boss_pose(), "combo": _boss_slash_index,
			"progress": clampf(progress, 0.0, 1.0), "time": boss_time, "active": live,
			"parryable": boss_action == "thrust" and _thrust_active(),
			"glint": boss_action == "thrust" and boss_time >= THRUST_WINDUP - .18 and boss_time <= THRUST_WINDUP + THRUST_DASH_SECONDS,
			"charge": boss_action == "slam" and progress < .46,
			"position": boss.position, "direction": boss_direction}
	return {"generation": encounter_generation, "time": simulation_time, "ended": ended,
		"warning": warning, "boss_active": boss_active,
		"projectiles": projectiles, "arrows": arrows, "shockwaves": _shockwaves}

