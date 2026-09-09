extends SceneTree


func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var sampled_frames := 0
	for boss in [false,true]:
		var actor := Node3D.new()
		actor.set_script(load("res://scripts/actor_visual.gd"))
		root.add_child(actor)
		actor.setup(boss)
		assert(actor.joints.size() == 18,"Imported character is missing a required articulation pivot")
		var blade_length: float = actor.get_blade_points()[0].distance_to(actor.get_blade_points()[1])
		for state in ["idle","move","attack","skill","dodge","block","parry","hurt","stagger","dead","heal"]:
			for combo in range(3 if state == "attack" else 1):
				for frame in range(61):
					actor.update_pose(state,frame/60.0,Vector3.FORWARD,3.0 if state == "move" else 0.0,combo,1.0/60.0)
					var points: PackedVector3Array = actor.get_blade_points()
					assert(points.size() == 2 and points[0].is_finite() and points[1].is_finite(),"Non-finite weapon endpoint")
					assert(absf(points[0].distance_to(points[1]) - blade_length) < .002,"Sword deforms during articulation")
					assert(actor.model.position.is_finite(),"Non-finite ground support offset")
					sampled_frames += 1
		actor.set_flash(1.0)
		actor.set_parry_glow(true)
		assert(actor.blade_material != null,"Parry glow material not resolved")
		if not boss:
			actor.update_pose("heal",.72,Vector3.FORWARD,0,0,1.0)
			assert(actor.healing_flask.visible,"Flask absent at healing payoff")
			assert(actor.healing_flask.get_parent() == actor.joints["HandL"],"Flask must be held in the left hand")
			assert(actor.sword_node.visible,"Healing must keep the sword in the lowered right hand")
			var mouth: Vector3 = actor.joints["Head"].to_global(Vector3(0,.04,-.22))
			var bottle_mouth: Vector3 = actor.healing_flask.to_global(Vector3(0,.15,0))
			assert(mouth.distance_to(bottle_mouth) < .25,"Flask does not reach the helmet during the drink")
			print("HEAL_PAYOFF bottle_to_helmet=",mouth.distance_to(bottle_mouth))
		actor.update_pose("idle",0.0,Vector3.FORWARD,0,0,1.0)
		if not boss:
			assert(not actor.healing_flask.visible,"Flask remains visible after healing")
		actor.set_parry_glow(false)
		actor.free()
	print("CHARACTER_ANIMATION_PASS sampled_frames=",sampled_frames," actors=2 actions=11 combos=3")
	quit()
