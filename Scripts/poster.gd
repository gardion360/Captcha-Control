# Attach to each poster plane (MeshInstance3D).
# Put poster1.png / poster1.jpg / poster1.ogv etc. in the "posters" folder next to the game.
# A video (.ogv) takes priority over an image with the same name.
extends MeshInstance3D

@export var file_name := "poster1"
@export var surface_index := 0
@export var max_size := 2048
@export var video_resolution := Vector2i(512, 768)   # fallback size if auto orientation is off

@export_group("Newest video")
@export var use_newest_video := false   # ignore the name and play the newest .ogv instead
@export var newest_rank := 0            # 0 = newest, 1 = second newest, ...

@export_group("Orientation")
@export var auto_orient := true         # reshape the plane to match the file (portrait / landscape / square)
@export_enum("X", "Y", "Z") var width_axis := 0    # the plane's local axis that runs left-right
@export_enum("X", "Y", "Z") var height_axis := 1   # the plane's local axis that runs up-down
@export var max_video_side := 768       # longest side of the video render, in pixels

const VIDEO_EXTENSIONS := ["ogv"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

var _base_scale := Vector3.ONE

func _ready() -> void:
	_base_scale = scale
	_load_poster.call_deferred()   # deferred so add_child() doesn't fail during scene setup

func _load_poster() -> void:
	var converter := get_node_or_null("/root/Converter")
	if converter and not converter.is_done:
		await converter.done
	var folder := Util.get_user_folder("posters")

	if use_newest_video:
		var newest := _find_newest_video(folder)
		if newest != "":
			_apply_video(newest)
			return

	for ext in VIDEO_EXTENSIONS:
		var path := folder.path_join(file_name + "." + ext)
		if FileAccess.file_exists(path):
			_apply_video(path)
			return
	for ext in IMAGE_EXTENSIONS:
		var path := folder.path_join(file_name + "." + ext)
		if FileAccess.file_exists(path):
			_apply_image(path)
			return
	# nothing found: the default material from Blender stays

func _find_newest_video(folder: String) -> String:
	var found: Array[Dictionary] = []
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() in VIDEO_EXTENSIONS:
			var path := folder.path_join(file)
			found.append({"path": path, "time": FileAccess.get_modified_time(path)})
	if found.size() <= newest_rank:
		return ""
	found.sort_custom(func(a, b): return a.time > b.time)
	return found[newest_rank].path

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
	_set_texture(ImageTexture.create_from_image(img))
	_fit_to_size(Vector2(img.get_width(), img.get_height()))

func _apply_video(path: String) -> void:
	var stream := VideoStreamTheora.new()
	stream.file = path

	var viewport := SubViewport.new()
	viewport.size = video_resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var player := VideoStreamPlayer.new()
	player.stream = stream
	player.expand = true
	player.size = Vector2(video_resolution)
	player.loop = true
	player.volume_db = -80.0   # posters stay silent
	viewport.add_child(player)
	player.play()

	_set_texture(viewport.get_texture())
	if auto_orient:
		_fit_to_video(player, viewport)

# waits for the first video frame so the real video size is known
func _fit_to_video(player: VideoStreamPlayer, viewport: SubViewport) -> void:
	for i in 120:
		var tex := player.get_video_texture()
		if tex and tex.get_width() > 0 and tex.get_height() > 0:
			var vid := Vector2(tex.get_width(), tex.get_height())
			var k := minf(1.0, float(max_video_side) / maxf(vid.x, vid.y))
			var render := Vector2i((vid * k).round())
			viewport.size = render
			player.size = Vector2(render)
			_fit_to_size(vid)
			return
		await get_tree().process_frame

# Reshape the plane to the file's aspect ratio, keeping roughly the same surface area.
func _fit_to_size(tex_size: Vector2) -> void:
	if not auto_orient or mesh == null or tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	if width_axis == height_axis:
		push_warning("Poster: width_axis and height_axis must differ")
		return
	var box := mesh.get_aabb().size
	if box[width_axis] <= 0.0 or box[height_axis] <= 0.0:
		push_warning("Poster: wrong axes chosen, the plane has no size along them")
		return
	var aspect := tex_size.x / tex_size.y
	var w0 := box[width_axis] * absf(_base_scale[width_axis])
	var h0 := box[height_axis] * absf(_base_scale[height_axis])
	var new_h := sqrt(w0 * h0 / aspect)
	var new_w := new_h * aspect
	var s := _base_scale
	s[width_axis] = new_w / box[width_axis] * signf(_base_scale[width_axis])
	s[height_axis] = new_h / box[height_axis] * signf(_base_scale[height_axis])
	scale = s

func _set_texture(tex: Texture2D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # remove to let room lighting affect it
	set_surface_override_material(surface_index, mat)
