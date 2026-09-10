extends SceneTree
## Full arena captures and real rendered frame times with the new skinned hero.
var main: Node3D
var samples: Array[float] = []
var calls: Array[int] = []
var recording := false
var last_frame := 0

func _initialize() -> void:
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and last_frame > 0:
		samples.append((now-last_frame)/1000.0)
		calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	last_frame=now
	return false

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/rigging/arena_"+label+".png")

func run() -> void:
	main=load("res://main.tscn").instantiate()
	root.add_child(main)
	main.shake_enabled=false
	main.combat._test_mode=true
	main.combat.locked=true
	main.combat._boss_wait=100.0
	await create_timer(1.5).timeout
	await shot("sword")
	main.combat.request_player_action("switch_weapon")
	await create_timer(.75).timeout
	main.combat.request_player_action("attack")
	await create_timer(.60).timeout
	await shot("bow_draw")
	await create_timer(.65).timeout
	main.combat.request_player_action("skill")
	await create_timer(.42).timeout
	await shot("backflip")
	await create_timer(.77).timeout
	await shot("volley")
	await create_timer(.7).timeout
	for mode in ["sword","bow"]:
		for action in ["slam","thrust"]:
			main.combat.restart()
			main.combat._test_mode=true
			main.combat.locked=true
			main.combat._boss_wait=100.0
			main.combat.hp=10000
			main.combat.weapon_mode=mode
			main.combat.pending_weapon=mode
			main.combat.force_boss_action(action)
			main.combat.request_player_action("skill")
			recording=true
			await create_timer(3.0).timeout
			recording=false
	samples.sort()
	calls.sort()
	var report := {"frames":samples.size(),"median_ms":samples[samples.size()/2],
		"p95_ms":samples[int(samples.size()*.95)],"draw_calls_median":calls[calls.size()/2],
		"device":RenderingServer.get_video_adapter_name(),"viewport":str(root.size),
		"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"model":ProjectSettings.get_setting("gameplay/hero_model")}
	FileAccess.open("res://captures/rigging/render_metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RIGGED_SCENE_METRICS ",JSON.stringify(report))
	main.free()
	quit()
