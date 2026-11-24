extends Node

func get_user_folder(folder_name: String) -> String:
	var base: String
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir()
	var path := base.path_join(folder_name)
	DirAccess.make_dir_recursive_absolute(path)
	return path
