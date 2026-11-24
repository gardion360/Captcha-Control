extends MeshInstance3D

@export var file_name := "poster1"
@export var surface_index := 0
@export var max_size := 2048

const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

func _ready() -> void:
	var folder := Util.get_user_folder("posters")
	for ext in EXTENSIONS:
		var path := folder.path_join(file_name + "." + ext)
		if FileAccess.file_exists(path):
			_apply_image(path)
			return
	# no file found: the default material from Blender stays

func _apply_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("Could not load poster: " + path)
		return
	var longest := maxi(img.get_width(), img.get_height())
	if longest > max_size:
		var s := float(max_size) / longest
		img.resize(int(img.get_width() * s), int(img.get_height() * s))
	img.generate_mipmaps()

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # remove to let room lighting affect it
	set_surface_override_material(surface_index, mat)
