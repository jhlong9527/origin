extends SceneTree
func _initialize() -> void:
	check.call_deferred()
func check() -> void:
	var model = load("res://assets/characters/wayfarer.glb").instantiate()
	root.add_child(model)
	for node in model.find_children("*", "MeshInstance3D"):
		if "Torso" in node.name or "Head" in node.name or "UpperArmR" in node.name:
			var colors: PackedColorArray = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var unique: Dictionary = {}
			for color in colors:
				unique[color] = true
			var material: StandardMaterial3D = node.mesh.surface_get_material(0)
			print(node.name," material=",material.resource_name," albedo=",material.albedo_color," srgb=",material.vertex_color_is_srgb," colors=",unique.keys())
	quit()
