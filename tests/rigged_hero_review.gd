extends SceneTree
var actor: Node3D
var stage: Node3D
var camera: Camera3D
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",text)

func maximum_skin_stretch() -> float:
	var body: MeshInstance3D=actor.model.find_child("HeroBody",true,false)
	var baked:=body.bake_mesh_from_current_skeleton_pose()
	var excess:=0.0
	for surface in baked.get_surface_count():
		var original: PackedVector3Array=body.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var deformed: PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=body.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		for triangle in range(0,indices.size(),3):
			for edge in 3:
				var a:=indices[triangle+edge]
				var b:=indices[triangle+(edge+1)%3]
				excess=maxf(excess,deformed[a].distance_to(deformed[b])-original[a].distance_to(original[b]))
	return excess

func run() -> void:
	root.size = Vector2i(1000,900)
	stage=Node3D.new()
	root.add_child(stage)
	actor=Node3D.new()
	actor.set_script(load("res://scripts/rigged_hero_visual.gd"))
	stage.add_child(actor)
	actor.setup(false)
	check(actor.skeleton.get_bone_count()>=19,"Skinned skeleton contains anatomical and equipment bones")
	print("CLIPS ",actor.animation_player.get_animation_list())
	for clip in ["idle","move","bow_draw","bow_draw_move","bow_skill","attack0","attack1","attack2","block","parry","dodge","heal"]:
		check(actor.animation_player.has_animation(clip),"Clip "+clip)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("303842")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("ccd8e8")
	env.environment.ambient_light_energy=.6
	stage.add_child(env)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-43,-32,0)
	light.light_energy=1.15
	light.light_color=Color("ffe3b7")
	light.shadow_enabled=true
	stage.add_child(light)
	var floor_mesh:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(12,12)
	floor_mesh.mesh=plane
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("4e5555")
	floor_mesh.material_override=mat
	stage.add_child(floor_mesh)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=3.05
	stage.add_child(camera)
	camera.current=true
	camera.position=Vector3(3,2.1,-7)
	camera.look_at(Vector3(0,1,0))
	var render:=DisplayServer.get_name()!="headless"
	var variants=[
		["idle","sword","idle",0.0,0.0,0],
		["attack0","sword","attack",.47,0.0,0],
		["attack2","sword","attack",.35,0.0,2],
		["bow_draw","bow","bow_shot",.63,0.0,0],
		["bow_walk","bow","bow_shot",.4,1.68,0],
		["flip_start","bow","bow_skill",.14/1.7,0.0,0],
		["flip_inverted","bow","bow_skill",.41/1.7,0.0,0],
		["flip_land","bow","bow_skill",.70/1.7,0.0,0],
		["volley","bow","bow_skill",.90/1.7,0.0,0]]
	for spec in variants:
		actor.set_weapon_state(spec[1])
		actor.update_pose(spec[2],spec[3],Vector3.FORWARD,spec[4],spec[5],1.0/60)
		# Skeleton skin uploads are deferred by Godot; let them reach the render
		# server before baking, otherwise this reads the preceding pose.
		await process_frame
		if spec[0] in ["bow_draw","attack0","flip_inverted"]:
			var excess:=maximum_skin_stretch()
			print("SKIN_EDGE_STRETCH ",spec[0]," ",excess)
			check(excess < .24,"No long stretched skin triangles in "+spec[0])
		if render:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://captures/rigging/"+spec[0]+"_godot.png")
		print("SAMPLE ",spec[0]," motion=",actor.motion.position," left=",actor.joints.HandL.position," right=",actor.joints.HandR.position)
	check(not actor.shield_node.visible and not actor.sword_node.visible,"Bow hides source sword and shield")
	check(actor.bow_node.visible,"Bow visible")
	actor.update_pose("bow_shot",.63,Vector3.FORWARD,0.0,0,0)
	check(actor.joints.HandL.position.z < -.40 and actor.joints.HandR.position.z < -.10,
		"Both archery hands remain in front of the torso")
	check(actor.joints.HandL.position.distance_to(actor.joints.HandR.position) > .24,
		"Full draw visibly separates the grip from the string hand")
	if render:
		camera.position=Vector3(6,2.2,-3)
		camera.look_at(Vector3(0,1,0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/rigging/bow_side_godot.png")
	var lowest := INF
	var peak := 0.0
	# Bake actual skin to CPU geometry. Checks hidden-bone false positives too.
	for frame in range(103):
		actor.update_pose("bow_skill",frame/102.0,Vector3.FORWARD,0.0,0,0)
		await process_frame
		var body: MeshInstance3D=actor.model.find_child("HeroBody",true,false)
		var baked:=body.bake_mesh_from_current_skeleton_pose()
		var mesh_to_actor: Transform3D=actor.global_transform.affine_inverse()*body.global_transform
		var frame_low:=INF
		for surface in baked.get_surface_count():
			var verts: PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v in verts: frame_low=minf(frame_low,(mesh_to_actor*v).y)
		lowest=minf(lowest,frame_low)
		peak=maxf(peak,frame_low)
	print("SKIN_CLEARANCE min=",lowest," peak=",peak)
	check(lowest>=-.012,"Actual backflip skin stays above floor throughout")
	check(peak>.40,"Backflip has visible extra height")
	stage.free()
	print("RIGGED_HERO_REVIEW failures=",failures)
	quit(failures)
