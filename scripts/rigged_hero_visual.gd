extends Node3D
## High-detail skinned hero. Combat owns time; AnimationPlayer only samples it.
const MODEL_PATH := "res://assets/characters/wayfarer_rigged.glb"
var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var motion: Node3D
var sword_node: MeshInstance3D
var shield_node: MeshInstance3D
var bow_node: Node3D
var quiver_node: Node3D
var nocked_arrow: Node3D
var bow_string: MeshInstance3D
var string_mesh := ImmediateMesh.new()
var weapon_mode := "sword"
var pending_weapon := "sword"
var phase := 0.0
var current_clip := ""
var bone_ids: Dictionary = {}
var rest_global: Dictionary = {}
var materials: Array[StandardMaterial3D] = []
var flash_amount := 0.0
var joints: Dictionary = {}
var healing_flask: MeshInstance3D

func setup(_boss := false) -> void:
	model = (load(MODEL_PATH) as PackedScene).instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	motion = model.find_child("Motion",true,false)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for i in skeleton.get_bone_count():
		var label := skeleton.get_bone_name(i)
		bone_ids[label] = i
		rest_global[label] = skeleton.get_bone_global_rest(i)
		var socket := Node3D.new()
		socket.name = label + "Socket"
		add_child(socket)
		joints[label] = socket
	sword_node = model.find_child("HeroSword",true,false)
	shield_node = model.find_child("HeroShield",true,false)
	var copies := {}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(surface)
			if original is StandardMaterial3D:
				if not copies.has(original):
					var material := original.duplicate() as StandardMaterial3D
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
					copies[original] = material
					materials.append(material)
				mesh.set_surface_override_material(surface,copies[original])
	bow_node = (load("res://assets/weapons/longbow.glb") as PackedScene).instantiate()
	add_child(bow_node)
	var old_string := bow_node.find_child("BowString",true,false) as Node3D
	if old_string: old_string.visible = false
	bow_string = MeshInstance3D.new()
	bow_string.mesh = string_mesh
	var string_mat := StandardMaterial3D.new()
	string_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	string_mat.albedo_color = Color("d4c3a1")
	bow_string.material_override = string_mat
	add_child(bow_string)
	quiver_node = (load("res://assets/weapons/quiver.glb") as PackedScene).instantiate()
	add_child(quiver_node)
	nocked_arrow = (load("res://assets/weapons/arrow.glb") as PackedScene).instantiate()
	add_child(nocked_arrow)
	healing_flask = MeshInstance3D.new()
	var bottle := CapsuleMesh.new()
	bottle.radius = .045
	bottle.height = .16
	healing_flask.mesh = bottle
	var flask_mat := StandardMaterial3D.new()
	flask_mat.albedo_color = Color("45bba9")
	healing_flask.material_override = flask_mat
	(joints["HandL"] as Node3D).add_child(healing_flask)
	set_weapon_state("sword")
	update_pose("idle",0,Vector3.FORWARD,0,0,0)
	print("HIGH_DETAIL_HERO bones=",skeleton.get_bone_count()," clips=",animation_player.get_animation_list().size())

func set_weapon_state(mode: String, pending := "") -> void:
	weapon_mode = mode
	if pending != "": pending_weapon = pending
	_show_gear(mode)

func set_weapon_transition(progress: float, current: String, next: String) -> void:
	set_weapon_state(current if progress < .5 else next,next)

func _show_gear(mode: String) -> void:
	sword_node.visible = mode == "sword"
	shield_node.visible = mode == "sword"
	bow_node.visible = mode == "bow"
	bow_string.visible = mode == "bow"
	quiver_node.visible = mode == "bow"

func update_pose(state: String, progress: float, _direction: Vector3, speed: float, combo := 0, delta := .01667) -> void:
	phase += delta
	var clip := state
	var looping := state in ["idle","move","block"]
	match state:
		"idle","move":
			clip = ("bow_" if weapon_mode == "bow" else "") + ("move" if speed > .1 else "idle")
		"attack": clip = "attack" + str(combo % 3)
		"bow_shot": clip = "bow_draw_move" if speed > .1 else "bow_draw"
	if not animation_player.has_animation(clip): clip = "idle"
	var animation := animation_player.get_animation(clip)
	if current_clip != clip:
		animation_player.play(clip)
		current_clip = clip
	var sample := fmod(phase,animation.length) if looping else clampf(progress,0,1)*animation.length
	animation_player.seek(sample,true)
	animation_player.advance(0)
	skeleton.force_update_all_bone_transforms()
	for label in joints:
		(joints[label] as Node3D).global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone_ids[label])
	# glTF bones have anatomical rest axes; sockets use rest-relative rotations.
	for label in joints:
		var socket: Node3D = joints[label]
		socket.global_basis = skeleton.global_basis * skeleton.get_bone_global_pose(bone_ids[label]).basis * (rest_global[label] as Transform3D).basis.inverse()
	var left: Node3D = joints["HandL"]
	var right: Node3D = joints["HandR"]
	var torso: Node3D = joints["Torso"]
	# The grip follows the left wrist; the bow remains vertical in the aiming
	# frame while forearm pronation turns the hand around the grip.
	bow_node.global_transform = Transform3D(skeleton.global_basis * Basis.from_euler(Vector3(0,0,-.08)),left.global_position)
	bow_node.scale *= .72
	quiver_node.global_transform = torso.global_transform * Transform3D(Basis.from_euler(Vector3(-.10,-.25,.25)),Vector3(.28,.0,.30))
	quiver_node.scale *= .70
	var draw_visible := weapon_mode == "bow" and state == "bow_shot" and progress > .10 and progress < .72/1.05
	if state == "bow_skill" and weapon_mode == "bow":
		var t := progress * 1.70
		for release in [.92,1.14,1.36]:
			draw_visible = draw_visible or (t > release-.15 and t < release)
	nocked_arrow.visible = draw_visible
	if draw_visible:
		var forward := (left.global_position-right.global_position).normalized()
		var tip := right.global_position + forward * .7125
		nocked_arrow.global_transform = Transform3D(Basis.looking_at(forward,global_basis.y),tip)
		nocked_arrow.scale *= .75
	string_mesh.clear_surfaces()
	if weapon_mode == "bow":
		var top := bow_node.to_global(Vector3(0,.867,.143))
		var bottom := bow_node.to_global(Vector3(0,-.867,.143))
		var nock := right.global_position if draw_visible else bow_node.to_global(Vector3(0,0,.18))
		string_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for point in [top,nock,nock,bottom]: string_mesh.surface_add_vertex(to_local(point))
		string_mesh.surface_end()
	healing_flask.visible = state == "heal" and progress > .15 and progress < .9
	if flash_amount > 0: set_flash(maxf(0,flash_amount-delta*5))

func get_blade_points() -> PackedVector3Array:
	var deform := skeleton.global_transform * skeleton.get_bone_global_pose(bone_ids["Sword"]) * (rest_global["Sword"] as Transform3D).affine_inverse()
	return PackedVector3Array([deform * Vector3(.50,.60,-.32),deform * Vector3(.91,.29,-.73)])

func get_arrow_origin() -> Vector3:
	return (joints["HandL"] as Node3D).global_position - global_basis.z * .14

func set_flash(amount: float) -> void:
	flash_amount = amount
	for material in materials:
		material.emission_enabled = amount > .001
		material.emission = Color(1,.6,.2)
		material.emission_energy_multiplier = amount*.55

func set_parry_glow(_enabled: bool) -> void:
	pass
