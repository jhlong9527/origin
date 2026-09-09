extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	var actor := Node3D.new()
	actor.set_script(load("res://scripts/actor_visual.gd"))
	root.add_child(actor)
	actor.setup(true)
	var samples := {}
	for p in [.25,.35,.40,.45,.50,.55,.60,.80,.96]:
		actor.update_pose("attack",p,Vector3.FORWARD,0.0,2,1.0)
		var blade: PackedVector3Array = actor.get_blade_points()
		samples[p] = {"hilt":blade[0],"tip":blade[1],"direction":(blade[1]-blade[0]).normalized(),"elbow":actor.joints["ForearmR"].rotation_degrees.x}
		print("THRUST_SAMPLE ",p," ",samples[p])
	assert(samples[.35].tip.distance_to(samples[.25].tip)<.15,"Blade extends before the active thrust window")
	assert(samples[.55].tip.z < samples[.35].tip.z - .55,"Thrust does not send the tip forwards")
	assert(samples[.55].elbow < samples[.35].elbow - 60,"Thrust elbow does not visibly extend")
	assert(samples[.96].tip.z > samples[.55].tip.z + .40,"Thrust does not retract into recovery")
	var min_alignment := 1.0
	var min_x := INF
	var max_x := -INF
	for p in [.35,.40,.45,.50,.55]:
		min_alignment = minf(min_alignment,samples[p].direction.dot(Vector3.FORWARD))
		min_x = minf(min_x,samples[p].tip.x)
		max_x = maxf(max_x,samples[p].tip.x)
	assert(min_alignment>.95,"Blade sweeps away from the facing direction during thrust")
	assert(max_x-min_x<.35,"Thrust has excessive lateral sweep")
	for duration in [1.95*.82,1.95*.82/1.15]:
		actor.update_pose("idle",0,Vector3.FORWARD,0,0,1.0)
		var realtime_alignment := 1.0
		for frame in range(int(ceil(duration*120.0))+1):
			var progress := clampf(frame/120.0/duration,0,1)
			actor.update_pose("attack",progress,Vector3.FORWARD,0,2,1.0/120.0)
			if progress >= .35 and progress <= .55:
				var blade: PackedVector3Array = actor.get_blade_points()
				realtime_alignment=minf(realtime_alignment,(blade[1]-blade[0]).normalized().dot(Vector3.FORWARD))
		assert(realtime_alignment>.95,"Smoothed thrust deviates from facing at runtime")
		print("THRUST_RUNTIME duration=",duration," alignment=",realtime_alignment)
	print("THRUST_PASS forward_alignment=",min_alignment," lateral_travel=",max_x-min_x," extension=",samples[.35].tip.z-samples[.55].tip.z)
	quit()
