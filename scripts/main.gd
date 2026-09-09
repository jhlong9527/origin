extends Node3D

const Arena = preload("res://scripts/arena.gd")
const Combat = preload("res://scripts/combat.gd")
const HUD = preload("res://scripts/hud.gd")
const Effects = preload("res://scripts/effects.gd")
const Atmosphere = preload("res://scripts/atmosphere.gd")
var combat: Node3D
var hud: CanvasLayer
var effects: Node3D
var camera: Camera3D
var trauma = 0.0
var shake_enabled = true
var clock = 0.0
var camera_target = Vector3.ZERO
var saved_stats: Dictionary = {}
var reticle: Node3D
var debug_driver = false
var frame_ms: Array[float] = []
var forest_focus: MeshInstance3D

func _ready() -> void:
	_inputs()
	_lighting()
	var arena = Node3D.new()
	arena.name = "Arena"
	arena.set_script(Arena)
	add_child(arena)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.5
	camera.near = .1
	camera.far = 100.0
	add_child(camera)
	camera.position = Vector3(0, 23, 17)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	_setup_forest_focus()
	effects = Node3D.new()
	effects.name = "Effects"
	effects.set_script(Effects)
	add_child(effects)
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(HUD)
	add_child(hud)
	hud.pause_toggled.connect(func(on: bool): get_tree().paused = on)
	hud.retry_requested.connect(_restart)
	hud.quit_requested.connect(func(): get_tree().quit())
	hud.sound_toggled.connect(func(on: bool): effects.active_audio = on)
	hud.shake_toggled.connect(func(on: bool): shake_enabled = on)
	hud.focus_toggled.connect(func(on: bool): forest_focus.visible = on)
	combat = Node3D.new()
	combat.name = "Combat"
	combat.set_script(Combat)
	add_child(combat)
	combat.stats_changed.connect(_stats)
	combat.combat_event.connect(_feedback)
	combat.encounter_ended.connect(hud.show_result)
	combat.setup(camera)
	effects.sync_combat(combat)
	effects.parry_anchor = combat.boss
	_target_ring()
	var args = OS.get_cmdline_user_args()
	debug_driver = args.has("--capture") or args.has("--visual-test") or args.has("--ui-test")
	if debug_driver: _capture_run(args)
	elif args.has("--start-paused"): hud.toggle_pause()

func _lighting() -> void:
	var atmosphere = Node3D.new()
	atmosphere.name = "SunsetAtmosphere"
	atmosphere.set_script(Atmosphere)
	add_child(atmosphere)
	atmosphere.setup()

func _setup_forest_focus() -> void:
	forest_focus = MeshInstance3D.new()
	forest_focus.name = "DistantForestFocus"
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	forest_focus.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/forest_focus.gdshader")
	material.render_priority = -128
	forest_focus.material_override = material
	forest_focus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	forest_focus.extra_cull_margin = 16384
	camera.add_child(forest_focus)
	forest_focus.position.z = -1

func _inputs() -> void:
	var mapping = {"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"dodge": KEY_SHIFT, "skill": KEY_Q, "heal": KEY_R, "lock_target": KEY_TAB,
		"pause": KEY_ESCAPE, "retry": KEY_F5, "fullscreen": KEY_F11}
	for action in mapping:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = mapping[action]
		InputMap.action_add_event(action, event)
	for action in {"attack": MOUSE_BUTTON_LEFT, "block": MOUSE_BUTTON_RIGHT}:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var mouse = InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT if action == "attack" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, mouse)
	if not InputMap.has_action("parry"): InputMap.add_action("parry")
	var gamepad = {"attack": JOY_BUTTON_RIGHT_SHOULDER, "block": JOY_BUTTON_LEFT_SHOULDER,
		"dodge": JOY_BUTTON_A, "skill": JOY_BUTTON_Y, "heal": JOY_BUTTON_X,
		"lock_target": JOY_BUTTON_RIGHT_STICK, "pause": JOY_BUTTON_START}
	for action in gamepad:
		var event = InputEventJoypadButton.new()
		event.button_index = gamepad[action]
		InputMap.action_add_event(action, event)
	for spec in [["move_left", JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_AXIS_LEFT_X, 1.0], ["move_up", JOY_AXIS_LEFT_Y, -1.0], ["move_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var axis = InputEventJoypadMotion.new()
		axis.axis = spec[1]
		axis.axis_value = spec[2]
		InputMap.action_add_event(spec[0], axis)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		hud.toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("retry"):
		hud._retry()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fullscreen"):
		var fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _stats(data: Dictionary) -> void:
	if int(data.get("boss_phase", 1)) == 2 and int(saved_stats.get("boss_phase", 1)) == 1:
		hud.announce("荆冠觉醒")
	saved_stats = data
	hud.apply_stats(data)

func _feedback(kind: String, at: Vector3, direction: Vector3, amount: float) -> void:
	effects.feedback(kind, at, direction, amount)
	match kind:
		"hit":
			trauma = minf(trauma + .26, 1)
			combat.boss_visual.set_flash(.48)
		"hurt":
			trauma = minf(trauma + .42, 1)
			combat.player_visual.set_flash(.55)
		"slam": trauma = minf(trauma + .42, 1)
		"block": trauma = minf(trauma + .18, 1)
		"parry":
			trauma = minf(trauma + .6, 1)
			hud.announce("破绽")
		"guard_break": hud.announce("防御崩溃")
		"victory": trauma = .65

func _target_ring() -> void:
	reticle = Node3D.new()
	add_child(reticle)
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for arc in 4:
		for i in 12:
			var a = arc * PI / 2 + .1 + i * .06
			var b = a + .06
			var points = [Vector3(cos(a), 0, sin(a)), Vector3(cos(b), 0, sin(b))]
			for p in [points[0] * .88, points[1] * .88, points[0] * .83, points[1] * .88, points[1] * .83, points[0] * .83]: mesh.surface_add_vertex(p)
	mesh.surface_end()
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("eedaa1")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reticle.add_child(instance)

func _process(delta: float) -> void:
	clock += delta
	if not is_instance_valid(combat) or not is_instance_valid(combat.player): return
	var focus = combat.player.position.lerp(combat.boss.position, .45) * .18
	focus.y = 0
	focus.x = clampf(focus.x, -1.6, 1.6)
	focus.z = clampf(focus.z, -.8, .8)
	camera_target = camera_target.lerp(focus, 1.0 - exp(-delta * 2.4))
	trauma = maxf(trauma - delta * 1.8, 0.0)
	var shake = Vector3(sin(clock * 61), cos(clock * 49) * .25, sin(clock * 43)) * trauma * trauma * .16 if shake_enabled else Vector3.ZERO
	camera.position = camera_target + Vector3(0, 23, 17) + shake
	camera.look_at(camera_target + shake)
	reticle.position = combat.boss.position + Vector3.UP * .04
	reticle.visible = combat.locked and not combat.ended
	reticle.rotation.y = clock * .13
	var pstate = combat.player_state
	var bstate = combat.boss_state
	var pp = combat.player_time / maxf(combat._player_duration(), .01)
	var bp = combat.boss_time / maxf(combat._boss_duration, .01)
	var boss_fx: Dictionary = combat.visual_state().get("boss_active", {})
	combat.boss_visual.set_parry_glow(bool(boss_fx.get("glint", false)))
	effects.add_blade_sample(0, combat.player_visual.get_blade_points(), pstate in ["attack", "skill"] and pp >= .30 and pp <= .60, pstate == "skill")
	effects.add_blade_sample(1, combat.boss_visual.get_blade_points(), bool(boss_fx.get("active", false)))
	if debug_driver and clock > 2.0: frame_ms.append(delta * 1000.0)

func _restart() -> void:
	effects.clear()
	hud.notice_time = 0.0
	hud.notice.text = ""
	trauma = 0.0
	combat.restart()

func _capture_run(args: PackedStringArray) -> void:
	await get_tree().create_timer(2.0).timeout
	var folder = ProjectSettings.globalize_path("res://captures")
	DirAccess.make_dir_recursive_absolute(folder)
	if args.has("--ui-test"):
		combat._boss_wait = 100.0
		for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 960)]:
			DisplayServer.window_set_size(resolution)
			await get_tree().create_timer(.35).timeout
			await _shot(folder.path_join("ui_%dx%d.png" % [resolution.x, resolution.y]))
		hud.toggle_pause()
		await _shot(folder.path_join("pause.png"))
		hud.toggle_pause()
		await hud.show_result(false)
		await _shot(folder.path_join("defeat.png"))
		hud._retry()
		combat._boss_wait = 100.0
		await hud.show_result(true)
		await _shot(folder.path_join("victory.png"))
	elif args.has("--visual-test"):
		combat.restart()
		combat._test_mode = true
		combat._boss_wait = 100.0
		combat.player.position = Vector3(-1.5, 0, 1.5)
		combat.boss.position = Vector3(2, 0, -1.5)
		await _shot(folder.path_join("01_arena.png"))
		for action in ["attack", "block", "parry", "dodge", "skill"]:
			combat.restart()
			combat._boss_wait = 100.0
			combat.player.position = Vector3(-1.0, 0, 1.0)
			combat.boss.position = Vector3(2, 0, -1.5)
			combat.request_player_action(action)
			await get_tree().create_timer(.47 if action == "skill" else (.28 if action != "block" else .15)).timeout
			await _shot(folder.path_join("pose_" + action + ".png"))
			await get_tree().create_timer(1.3).timeout
		for action in ["slash", "slam", "thrust"]:
			combat.restart()
			combat._boss_wait = 100.0
			combat.force_boss_action(action)
			await get_tree().create_timer(.63).timeout
			await _shot(folder.path_join("boss_" + action + ".png"))
			await get_tree().create_timer(2.3).timeout
		print("VISUAL_TEST_COMPLETED")
	else:
		await _shot(folder.path_join("arena.png"))
	if not frame_ms.is_empty():
		frame_ms.sort()
		print("FRAME_MS_MEDIAN=", frame_ms[frame_ms.size() / 2], " P95=", frame_ms[int(frame_ms.size() * .95)])
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var error = image.save_png(path)
	print("CAPTURE ", path, " ", error)
