extends SceneTree
func _initialize() -> void:
	for setting in ProjectSettings.get_property_list():
		if "cache" in setting.name and "shader" in setting.name:
			print(setting.name, " = ", ProjectSettings.get_setting(setting.name))
	quit()
