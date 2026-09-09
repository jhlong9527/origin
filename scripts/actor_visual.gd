extends Node3D

const JOINT_NAMES: Array[String] = ["Hips", "Torso", "Head", "UpperArmR", "ForearmR", "HandR", "UpperArmL", "ForearmL", "HandL", "Shield", "ThighR", "ShinR", "FootR", "ThighL", "ShinL", "FootL", "Cape", "Tabard"]
var is_boss := false
var model: Node3D
var joints: Dictionary = {}
var rest_positions: Dictionary = {}
var materials: Array[StandardMaterial3D] = []
var base_colors: Array[Color] = []
var blade_hilt: Node3D
var blade_tip: Node3D
var blade_material: StandardMaterial3D
var phase := 0.0
var flash_amount := 0.0
var parry_glow := false
var sword_node: Node3D
var healing_flask: Node3D


func setup(boss: bool = false) -> void:
	is_boss = boss
	if is_instance_valid(model):
		model.queue_free()
	joints.clear()
	rest_positions.clear()
	materials.clear()
	base_colors.clear()
	var path := "res://assets/characters/thorn_lord.glb" if boss else "res://assets/characters/wayfarer.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Character asset missing: " + path)
		return
	model = packed.instantiate() as Node3D
	add_child(model)
	for joint_name in JOINT_NAMES:
		var node := model.find_child(joint_name, true, false) as Node3D
		if node:
			joints[joint_name] = node
			rest_positions[joint_name] = node.position
	blade_hilt = model.find_child("BladeHilt", true, false) as Node3D
	blade_tip = model.find_child("BladeTip", true, false) as Node3D
	sword_node = model.find_child("Sword", true, false) as Node3D
	var outline_shader := Shader.new()
	outline_shader.code = "shader_type spatial; render_mode unshaded, cull_front; void vertex(){ VERTEX += NORMAL * 0.008; } void fragment(){ ALBEDO = vec3(0.027, 0.033, 0.031); }"
	var outline := ShaderMaterial.new()
	outline.shader = outline_shader
	var replacements: Dictionary = {}
	_prepare_materials(model, replacements, outline)
	if not boss:
		_build_flask(outline)
	update_pose("idle", 0.0, Vector3.FORWARD, 0.0, 0, 1.0)


func configure(boss: bool) -> void:
	setup(boss)


func _build_flask(outline: ShaderMaterial) -> void:
	healing_flask = Node3D.new()
	healing_flask.name = "HealingFlask"
	(joints["HandL"] as Node3D).add_child(healing_flask)
	healing_flask.position = Vector3(.04,-.015,.035)
	for cap in [false,true]:
		var bottle := MeshInstance3D.new()
		var shape := CylinderMesh.new()
		shape.top_radius = .040 if cap else .052
		shape.bottom_radius = .040 if cap else .075
		shape.height = .06 if cap else .19
		shape.radial_segments = 8
		bottle.mesh = shape
		bottle.position.y = .12 if cap else .0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("d4ac59") if cap else Color("37b6a4")
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.next_pass = outline
		bottle.material_override = mat
		healing_flask.add_child(bottle)
	healing_flask.visible = false


func _prepare_materials(node: Node, replacements: Dictionary, outline: ShaderMaterial) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in range(instance.mesh.get_surface_count()):
			var original := instance.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var cloth := str(node.get_parent().name) in ["Cape", "Tabard", "Plume"]
			var key := str(original.get_instance_id()) + ("_cloth" if cloth else "_armor")
			if not replacements.has(key):
				var mat := original.duplicate() as StandardMaterial3D
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
				mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
				mat.roughness = .98 if cloth else (.66 if is_boss else .94)
				mat.metallic = 0.0 if cloth else (.52 if is_boss else .22)
				var surface_kind := "cloth" if cloth else "metal"
				mat.albedo_texture = load("res://assets/surfaces/" + surface_kind + "_albedo.png")
				mat.normal_enabled = true
				mat.normal_texture = load("res://assets/surfaces/" + surface_kind + "_normal.png")
				mat.normal_scale = .38 if cloth else .23
				mat.roughness_texture = load("res://assets/surfaces/" + surface_kind + "_roughness.png")
				mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				mat.uv1_triplanar = true
				mat.uv1_scale = Vector3.ONE * (1.3 if cloth else .9)
				mat.albedo_color = _material_tint(original.resource_name, original.albedo_color)
				if original.resource_name.begins_with("Ref "):
					# The reference models carry explicit skin, cloth, timber and metal
					# materials. Do not turn faces and leather into generic armor.
					var family := original.resource_name.split(" ")[1]
					mat.albedo_color = original.albedo_color
					mat.metallic = original.metallic
					mat.roughness = original.roughness
					if is_boss and family == "metal":
						# Lift the dark purple armor into the sunset light while keeping
						# the material unmistakably metallic.
						mat.albedo_color = mat.albedo_color.lightened(0.16)
						mat.metallic = maxf(mat.metallic, 0.62)
						mat.roughness = minf(mat.roughness, 0.66)
					mat.albedo_texture = null
					mat.normal_texture = null
					mat.roughness_texture = null
					mat.normal_enabled = false
					if family in ["cloth", "metal", "leather", "wood"]:
						var detail := "cloth" if family in ["cloth", "leather"] else ("bark" if family == "wood" else "metal")
						mat.albedo_texture = load("res://assets/surfaces/"+detail+"_albedo.png")
						mat.normal_texture = load("res://assets/surfaces/"+detail+"_normal.png")
						mat.normal_enabled = true
						mat.normal_scale = .14 if family == "wood" else .11
						mat.uv1_triplanar = true
						mat.uv1_scale = Vector3.ONE*2.3
				if "Vertex Palette" in original.resource_name:
					mat.vertex_color_use_as_albedo = true
					mat.vertex_color_is_srgb = false
					mat.albedo_color = Color.WHITE
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.next_pass = outline
				replacements[key] = mat
				materials.append(mat)
				base_colors.append(mat.albedo_color)
			instance.set_surface_override_material(surface, replacements[key])
			if "Moonsteel" in str(node.name):
				blade_material = replacements[key]
	for child in node.get_children():
		_prepare_materials(child, replacements, outline)


func _material_tint(material_name: String, original: Color) -> Color:
	var label := material_name.to_lower()
	if "storm silver" in label:
		return Color("688793")
	if "iron plum" in label:
		return Color("503c55")
	if "edge highlights" in label:
		return Color("937986") if is_boss else Color("a6bdc4")
	if "moonsteel" in label:
		return Color("aac7ce")
	if "antique brass" in label:
		return Color("b98b44") if is_boss else Color("b39151")
	if "deep teal" in label:
		return Color("1d7264")
	if "madder red" in label:
		return Color("70263d")
	if "worn folds" in label:
		return Color("983750") if is_boss else Color("369c80")
	return original


func _angles(x: float, y: float = 0.0, z: float = 0.0) -> Vector3:
	return Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))


func _blend_pose(pose: Dictionary, target: Dictionary, weight: float) -> void:
	for joint in target:
		pose[joint] = (pose.get(joint, Vector3.ZERO) as Vector3).lerp(target[joint], weight)


func _step(a: float, b: float, p: float) -> float:
	var value := clampf((p - a) / maxf(b - a, 0.001), 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)


func update_pose(state: String, progress: float, _direction: Vector3, moving_speed: float, combo: int = 0, delta: float = 0.01667) -> void:
	if joints.is_empty():
		return
	phase += delta * (7.8 if is_boss else 10.0)
	var p := clampf(progress, 0.0, 1.0)
	var gait := clampf(moving_speed / (2.6 if is_boss else 4.5), 0.0, 1.0)
	var breath := sin(phase * 0.22)
	var pose: Dictionary = {
		"Hips": Vector3.ZERO,
		"Torso": _angles(-5.0 + breath * 1.1, 0.0, 0.0),
		"Head": _angles(1.0),
		"UpperArmR": _angles(19.0, -7.0, -9.0),
		"ForearmR": _angles(63.0),
		"HandR": _angles(-10.0, 0.0, 0.0),
		"UpperArmL": _angles(5.0, 9.0, 16.0),
		"ForearmL": _angles(42.0),
		"HandL": Vector3.ZERO,
		"Shield": _angles(-40.0, -8.0, 0.0),
		"ThighR": _angles(4.0),
		"ShinR": _angles(-7.0),
		"FootR": _angles(3.0),
		"ThighL": _angles(-4.0),
		"ShinL": _angles(-5.0),
		"FootL": _angles(9.0),
		"Cape": _angles(3.0 + breath * 2.0),
		"Tabard": _angles(-3.0)
	}
	var hip_offset := Vector3(0.0, breath * 0.009, 0.0)
	var root_roll := 0.0
	var root_height := 0.0
	var shield_offset := Vector3.ZERO
	if is_instance_valid(healing_flask):
		healing_flask.visible = state == "heal" and p > .14 and p < .96
		healing_flask.rotation.x = deg_to_rad(-14.0 - 57.0 * _step(.51,.70,p)) if state == "heal" else 0.0
	if state == "idle" or state == "move" or state == "block":
		var stride := sin(phase)
		pose["ThighR"] = _angles(4.0 + stride * 29.0 * gait)
		pose["ThighL"] = _angles(-4.0 - stride * 29.0 * gait)
		pose["ShinR"] = _angles(-7.0 - maxf(-stride, 0.0) * 40.0 * gait)
		pose["ShinL"] = _angles(-5.0 - maxf(stride, 0.0) * 40.0 * gait)
		pose["FootR"] = _angles(3.0 + maxf(-stride, 0.0) * 14.0 * gait)
		pose["FootL"] = _angles(9.0 + maxf(stride, 0.0) * 14.0 * gait)
		pose["Hips"] = _angles(0.0, stride * 4.0 * gait, stride * 2.5 * gait)
		pose["Torso"] = _angles(-5.0 - gait * 7.0, -stride * 4.0 * gait)
		pose["UpperArmR"] += _angles(-stride * 7.0 * gait)
		pose["UpperArmL"] += _angles(stride * 6.0 * gait)
		pose["Cape"] = _angles(8.0 + gait * 15.0 + sin(phase - .8) * 5.0 * gait, sin(phase * .5) * gait * 4.0)
		pose["Tabard"] = _angles(-3.0 - absf(stride) * 14.0 * gait)
		hip_offset.y += absf(cos(phase)) * .037 * gait
	var boss_attack_pose := is_boss and state in ["boss_thrust", "boss_overhead", "boss_slam"]
	if state == "attack" or state == "skill" or boss_attack_pose:
		var cut := combo % 3
		if state == "skill" or state == "boss_slam":
			cut = 2 if is_boss else 0
		if state == "boss_overhead": cut = 2
		var anticipation: Dictionary
		var follow: Dictionary
		var thrust := is_boss and state == "boss_thrust"
		if thrust:
			anticipation = {"Torso": _angles(-12,-18,-3), "Head": _angles(9,18), "UpperArmR": _angles(45,-44,-12), "ForearmR": _angles(103,0,0), "HandR": _angles(-65,0,0), "UpperArmL": _angles(-18,16,25), "ThighR": _angles(69), "ShinR": _angles(-90), "FootR": _angles(18), "ThighL": _angles(-39), "ShinL": _angles(-16)}
			follow = {"Torso": _angles(-23,19,-2), "Head": _angles(12,-14), "UpperArmR": _angles(86,38,-8), "ForearmR": _angles(18,0,0), "HandR": _angles(-3,0,0), "UpperArmL": _angles(-23,-10,29), "ThighR": _angles(69), "ShinR": _angles(-90), "FootR": _angles(18), "ThighL": _angles(-39), "ShinL": _angles(-16)}
		elif cut == 0:
			anticipation = {"Torso": _angles(-9,-32,-5), "UpperArmR": _angles(70,-67,-22), "ForearmR": _angles(32,-9,0), "HandR": _angles(-10,-14,0), "UpperArmL": _angles(29,28,18), "ThighR": _angles(-19), "ThighL": _angles(18), "ShinL": _angles(-23)}
			follow = {"Torso": _angles(-13,34,6), "UpperArmR": _angles(81,72,-7), "ForearmR": _angles(17,10,0), "HandR": _angles(-12,8,0), "UpperArmL": _angles(18,-18,24), "ThighR": _angles(30), "ShinR": _angles(-30), "ThighL": _angles(-18), "ShinL": _angles(-15)}
		elif cut == 1:
			anticipation = {"Torso": _angles(-10,34,5), "UpperArmR": _angles(81,65,0), "ForearmR": _angles(26,10,0), "HandR": _angles(-8,15,0), "UpperArmL": _angles(20,-15,18), "ThighR": _angles(19), "ThighL": _angles(-16)}
			follow = {"Torso": _angles(-13,-39,-7), "UpperArmR": _angles(78,-64,-27), "ForearmR": _angles(18,-4,0), "HandR": _angles(-14,-12,0), "UpperArmL": _angles(32,18,21), "ThighR": _angles(-22), "ThighL": _angles(30), "ShinL": _angles(-30)}
		else:
			anticipation = {"Torso": _angles(9,-10,-3), "Head": _angles(-6,10), "UpperArmR": _angles(146,-4,-12), "ForearmR": _angles(-44,0,0), "HandR": _angles(66,0,0), "UpperArmL": _angles(44,21,20), "ThighR": _angles(-19), "ThighL": _angles(20), "ShinL": _angles(-28)}
			follow = {"Torso": _angles(-30,9,-3), "Head": _angles(14,-5), "UpperArmR": _angles(79,0,-10), "ForearmR": _angles(11,0,0), "HandR": _angles(-32,0,0), "UpperArmL": _angles(31,16,30), "ThighR": _angles(39), "ShinR": _angles(-46), "ThighL": _angles(-24), "ShinL": _angles(-13)}
		# Weight shifts first; the blade then accelerates through its live collision window.
		var wind := _step(0.0, 0.25, p)
		if thrust: wind = _step(0.0, 1.0 / 1.77, p)
		# A thrust keeps its chambered elbow and forward blade through the warning.
		# Extension starts exactly at the combat window, then the elbow recoils.
		var slash := _step(1.0 / 1.77, 1.23 / 1.77, p) if thrust else _step(0.29, 0.54, p)
		var recover := 1.0 - _step(1.32 / 1.77, 1.0, p) if thrust else 1.0 - _step(0.65, 1.0, p)
		if state == "boss_overhead":
			slash = _step(.29,.47,p)
			recover = 1.0 - _step(.74,1.0,p)
			follow = {"Torso": _angles(-48,4,-2), "Head": _angles(21), "UpperArmR": _angles(58,0,-8), "ForearmR": _angles(30), "HandR": _angles(-69), "UpperArmL": _angles(22,4,27), "ThighR": _angles(66), "ShinR": _angles(-96), "ThighL": _angles(-29), "ShinL": _angles(-45)}
		if state == "boss_slam":
			# Raise both hands above the helmet; invert the wrist so the tip
			# stays downward, then drive the sword into the ground and kneel.
			anticipation = {"Torso": _angles(4), "Head": _angles(-9), "UpperArmR": _angles(151,0,-12), "ForearmR": _angles(-39), "HandR": _angles(-116), "UpperArmL": _angles(149,0,12), "ForearmL": _angles(-35), "HandL": _angles(-102), "ThighR": _angles(4), "ShinR": _angles(-7), "ThighL": _angles(-4), "ShinL": _angles(-7)}
			follow = {"Torso": _angles(-43), "Head": _angles(21), "UpperArmR": _angles(71,0,-9), "ForearmR": _angles(40), "HandR": _angles(-76), "UpperArmL": _angles(69,0,9), "ForearmL": _angles(41), "HandL": _angles(-77), "ThighR": _angles(67), "ShinR": _angles(-99), "ThighL": _angles(64), "ShinL": _angles(-97)}
			slash = _step(.36,.46,p)
			recover = 1.0 - _step(.76,1.0,p)
		_blend_pose(pose, anticipation, wind * recover)
		_blend_pose(pose, follow, slash * recover)
		hip_offset.y -= sin(p * PI) * (0.07 if cut < 2 else .13)
		if thrust: hip_offset.y -= .17 * wind * recover
		if state in ["boss_slam", "boss_overhead"]: hip_offset.y -= .22 * slash * recover
		hip_offset.z -= slash * recover * .16
		pose["Cape"] = _angles(7.0 + sin(p * PI) * 26.0, -sin(p * TAU) * 14.0)
		pose["Tabard"] = _angles(-8.0 - sin(p * PI) * 17.0)
	if state == "block":
		_blend_pose(pose, {"Torso": _angles(-13,10), "Head": _angles(4,-10), "UpperArmL": _angles(45,-17,13), "ForearmL": _angles(88,-13,0), "HandL": _angles(0,0,-8), "Shield": _angles(-122,5,0), "UpperArmR": _angles(24,-17,-14), "ForearmR": _angles(56)}, 1.0)
		hip_offset.y -= .07
	if state == "parry":
		var sweep := _step(.18,.57,p)
		var release := 1.0 - _step(.68,1.0,p)
		var guard_pose := {"Torso": _angles(-12,22), "UpperArmL": _angles(46,-42,15), "ForearmL": _angles(85,-15,0), "Shield": _angles(-122,5,-8), "UpperArmR": _angles(13,-28,-19), "ForearmR": _angles(55)}
		var sweep_pose := {"Torso": _angles(-13,-22,-5), "UpperArmL": _angles(77,38,28), "ForearmL": _angles(25,9,0), "Shield": _angles(-93,10,6), "UpperArmR": _angles(24,-14,-15), "ForearmR": _angles(65)}
		_blend_pose(pose, guard_pose, _step(0,.14,p) * release)
		_blend_pose(pose, sweep_pose, sweep * release)
		hip_offset.y -= sin(p * PI) * .08
	if state == "dodge":
		var tuck := sin(p * PI)
		_blend_pose(pose, {"Torso": _angles(-45), "Head": _angles(23), "UpperArmR": _angles(5,-30,-16), "ForearmR": _angles(65), "HandR": _angles(-20), "UpperArmL": _angles(35,-22,4), "ForearmL": _angles(119), "Shield": _angles(-133,15), "ThighR": _angles(83), "ShinR": _angles(-112), "ThighL": _angles(97), "ShinL": _angles(-118), "Cape": _angles(43), "Tabard": _angles(-28)}, _step(0,.17,p) * (1.0 - _step(.83,1.0,p)))
		root_roll = -TAU * _step(.07,.91,p)
		root_height = -.34 * tuck
	if state == "hurt":
		var recoil := sin(p * PI)
		_blend_pose(pose, {"Torso": _angles(23,7), "Head": _angles(-15), "UpperArmR": _angles(7,-25,-29), "UpperArmL": _angles(11,22,25), "ThighR": _angles(-24), "ThighL": _angles(16), "ShinL": _angles(-25)},recoil)
		hip_offset.z += .09 * recoil
	if state == "heal":
		var recover := 1.0 - _step(.79,1.0,p)
		var reach := _step(.02,.18,p) * recover
		var drink := _step(.20,.45,p) * recover
		var tip := _step(.52,.70,p) * recover
		_blend_pose(pose, {"Torso": _angles(-3), "Head": _angles(4,-10), "UpperArmR": _angles(8,-14,-17), "ForearmR": _angles(57), "HandR": _angles(-4), "UpperArmL": _angles(-9,9,21), "ForearmL": _angles(33), "Shield": _angles(-18,12,52)},reach)
		_blend_pose(pose, {"Torso": _angles(2), "Head": _angles(-7,-10), "UpperArmL": _angles(60,-60,4), "ForearmL": _angles(95,0,0), "HandL": _angles(-37,0,-5), "Shield": _angles(-115,93,18)},drink)
		pose["Head"].x -= deg_to_rad(7.0) * tip
		pose["HandL"].x -= deg_to_rad(12.0) * tip
		shield_offset = Vector3(-.25,0,.025) * drink
	if state == "stagger":
		var slump := _step(0,.18,p)
		_blend_pose(pose, {"Torso": _angles(-43,6,4), "Head": _angles(23), "UpperArmR": _angles(-12,2,-9), "ForearmR": _angles(19), "HandR": _angles(-48), "UpperArmL": _angles(8,2,10), "ForearmL": _angles(20), "Shield": _angles(-17), "ThighR": _angles(69), "ShinR": _angles(-103), "ThighL": _angles(-18), "ShinL": _angles(-84)},slump)
		hip_offset.y -= .24 * slump
	if state == "dead":
		var fall := _step(.03,.78,p)
		_blend_pose(pose, {"Torso": _angles(-18,9,4), "Head": _angles(17,9), "UpperArmR": _angles(4,-14,-48), "ForearmR": _angles(22), "UpperArmL": _angles(28,15,45), "ForearmL": _angles(35), "Shield": _angles(-45), "ThighR": _angles(27), "ShinR": _angles(-45), "ThighL": _angles(-13), "ShinL": _angles(-34)},fall)
		root_roll = -PI * .48 * fall
		root_height = -.68 * fall
		var sword_pitch := lerpf(deg_to_rad(67.0), -PI * .5, _step(.02,.40,p))
		pose["HandR"].x = sword_pitch - root_roll - pose["Torso"].x - pose["UpperArmR"].x - pose["ForearmR"].x
	var smoothing := 1.0 - exp(-42.0 * delta)
	for joint_name in pose:
		if joints.has(joint_name):
			var joint := joints[joint_name] as Node3D
			var target: Vector3 = pose[joint_name]
			joint.rotation = joint.rotation.lerp(target, smoothing)
	var hips := joints["Hips"] as Node3D
	hips.position = (rest_positions["Hips"] as Vector3) + hip_offset
	(joints["Shield"] as Node3D).position = (rest_positions["Shield"] as Vector3) + shield_offset
	# Rotate the visual about the hip; the physical capsule stays grounded throughout a roll.
	var scaled_pivot := 0.87 * (1.47 if is_boss else 1.0)
	model.rotation.x = root_roll
	model.position = Vector3(0,scaled_pivot + root_height,0) - model.basis * Vector3(0,scaled_pivot,0)
	if state != "dodge" and state != "dead":
		_ground_support()
	else:
		_ground_tumbling_body()
	if is_boss:
		_boss_weapon_constraints(state,p)
	if flash_amount > 0.0:
		set_flash(maxf(0.0,flash_amount - delta * 5.0))
	if parry_glow and blade_material:
		blade_material.emission_energy_multiplier = .3 + sin(phase * 2.4) * .15


func _boss_solve_arm(side: String, target: Vector3, pole: Vector3) -> void:
	# Analytic two-bone IK preserves bone length and bends each elbow outward.
	var upper: Node3D = joints["UpperArm" + side]
	var fore: Node3D = joints["Forearm" + side]
	var hand: Node3D = joints["Hand" + side]
	var shoulder := upper.global_position
	var length_a := shoulder.distance_to(fore.global_position)
	var length_b := fore.global_position.distance_to(hand.global_position)
	var forward := (target - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target),.02,length_a + length_b - .004)
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var perpendicular := pole - forward * pole.dot(forward)
	if perpendicular.length_squared() < .001: perpendicular = global_basis.x
	var elbow := shoulder + forward * along + perpendicular.normalized() * sqrt(maxf(0,length_a * length_a - along * along))
	var q := Quaternion((fore.global_position - shoulder).normalized(),(elbow - shoulder).normalized())
	upper.global_basis = Basis(q) * upper.global_basis
	q = Quaternion((hand.global_position - fore.global_position).normalized(),(target - fore.global_position).normalized())
	fore.global_basis = Basis(q) * fore.global_basis


func _boss_point_sword(direction: Vector3) -> void:
	var hand: Node3D = joints.HandR
	var current := (blade_tip.global_position - blade_hilt.global_position).normalized()
	hand.global_basis = Basis(Quaternion(current,direction.normalized())) * hand.global_basis


func _boss_weapon_constraints(state: String, p: float) -> void:
	var right: Node3D = joints.HandR
	var left: Node3D = joints.HandL
	if state == "boss_slam":
		var grip_weight := _step(.02,.19,p) * (1.0 - _step(.93,1.0,p))
		if grip_weight <= 0: return
		var plunge := _step(.36,.46,p)
		var release := _step(.76,1.0,p)
		var blade_length := right.global_position.distance_to(blade_tip.global_position)
		var tip_local := Vector3(0,lerpf(.80,.045,plunge) + .65 * release,lerpf(-.55,-1.15,plunge))
		# The long blade lands forward of the knees. Both wrists remain above
		# its guard, so the point is driven down without passing through the torso.
		var blade_dir := (global_basis * Vector3(0,-.985,-.172)).normalized()
		var target := to_global(tip_local) - blade_dir * blade_length
		_boss_solve_arm("R",right.global_position.lerp(target,grip_weight),global_basis.x)
		_boss_point_sword((blade_tip.global_position - blade_hilt.global_position).normalized().lerp(blade_dir,grip_weight).normalized())
		var left_target := right.global_position + blade_dir * .15
		_boss_solve_arm("L",left.global_position.lerp(left_target,grip_weight),-global_basis.x)
		left.global_basis = right.global_basis
	elif state == "boss_overhead":
		var planted := _step(.42,.50,p) * (1.0 - _step(.83,1.0,p))
		if planted > 0:
			var length := right.global_position.distance_to(blade_tip.global_position)
			var tip := to_global(Vector3(.18,.055,-1.55))
			var offset := tip - right.global_position
			var drop := minf(length-.01, right.global_position.y - tip.y)
			var horizontal := Vector3(offset.x,0,offset.z).normalized()
			var direction := horizontal * sqrt(maxf(0.0,length * length - drop * drop)) + Vector3.DOWN * drop
			_boss_point_sword((blade_tip.global_position - blade_hilt.global_position).normalized().lerp(direction.normalized(),planted))


func _ground_support() -> void:
	if not is_inside_tree():
		return
	var lowest := INF
	for joint_name in ["FootL", "FootR"]:
		var foot := joints[joint_name] as Node3D
		for sole_point in [Vector3(-.07,-.08,-.17), Vector3(.07,-.08,-.17), Vector3(-.07,-.08,.05), Vector3(.07,-.08,.05)]:
			lowest = minf(lowest, to_local(foot.to_global(sole_point)).y)
	# Keep the supporting boot planted while the bent trailing leg remains free to step.
	model.position.y -= lowest - .009


func _ground_tumbling_body() -> void:
	if not is_inside_tree():
		return
	var lowest := INF
	var contacts := {
		"Head": [Vector3(0,.38,0),Vector3(0,.12,-.24),Vector3(0,.12,.20)],
		"Torso": [Vector3(0,.25,-.24),Vector3(0,.25,.20),Vector3(-.28,.25,0),Vector3(.28,.25,0)],
		"Hips": [Vector3(0,-.12,0),Vector3(0,0,.17)],
		"UpperArmR": [Vector3(.14,0,0)],
		"UpperArmL": [Vector3(-.14,0,0)]
	}
	for joint_name in contacts:
		var joint := joints[joint_name] as Node3D
		for point in contacts[joint_name]:
			lowest = minf(lowest,to_local(joint.to_global(point)).y)
	model.position.y += maxf(0.0,.012 - lowest)


func get_blade_points() -> PackedVector3Array:
	if is_instance_valid(blade_hilt) and is_instance_valid(blade_tip):
		return PackedVector3Array([blade_hilt.global_position, blade_tip.global_position])
	return PackedVector3Array([global_position + Vector3.UP, global_position + Vector3.UP - global_basis.z])


func set_flash(amount: float) -> void:
	flash_amount = clampf(amount, 0.0, 1.0)
	for index in materials.size():
		materials[index].albedo_color = base_colors[index].lerp(Color(1.0,.80,.58), flash_amount * .85)
		if "Vertex Palette" in materials[index].resource_name:
			materials[index].emission_enabled = flash_amount > .001
			materials[index].emission = Color(1.0,.65,.25)
			materials[index].emission_energy_multiplier = flash_amount * .6


func set_parry_glow(enabled: bool) -> void:
	parry_glow = enabled
	if blade_material:
		blade_material.emission_enabled = enabled
		blade_material.albedo_color = Color("f4b94c") if enabled else Color("aac7ce")
		blade_material.emission = Color("e69228")
		blade_material.emission_energy_multiplier = .3 if enabled else 0.0

