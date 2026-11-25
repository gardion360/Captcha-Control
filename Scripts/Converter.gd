# AUTOLOAD: register as "Converter" in Project Settings > Globals, BELOW "Util".
#
# 1. Looks for FFmpeg (user folder, next to the game, then the system PATH).
# 2. If found, converts videos/gifs in the posters folder to .ogv in a background thread,
#    showing a loading screen while it works.
# 3. If not found (Windows only), asks the player to download it, verifies the checksum,
#    unpacks ffmpeg.exe into the user data folder, converts, then reloads the scene.
extends Node

signal done                                    # conversion finished (posters wait for this)
signal download_progress(percent: float)       # 0-100
signal download_finished(success: bool)

const SOURCE_EXTENSIONS := ["mp4", "gif", "webm", "mov", "avi", "mkv"]
const OUTPUT_HEIGHT := 768
const FFMPEG_ZIP_URL := "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
const FFMPEG_HASH_URL := FFMPEG_ZIP_URL + ".sha256"

var is_done := false
var ffmpeg_path := ""

var _thread: Thread
var _reload_after := false
var _downloading := false
var _zip_request: HTTPRequest
var _expected_hash := ""
var _dialog: ConfirmationDialog

# loading screen
var _loading_layer: CanvasLayer
var _loading_title: Label
var _loading_detail: Label
var _loading_bar: ProgressBar
var _loading_base_title := ""
var _dot_time := 0.0

func _ready() -> void:
	_build_loading_screen()
	download_progress.connect(_on_download_progress)

	ffmpeg_path = _find_ffmpeg()
	if ffmpeg_path != "":
		_run_conversion()
		return
	# no FFmpeg: let the game start, and offer a download if something actually needs converting
	if OS.get_name() == "Windows" and not _pending_sources().is_empty():
		_ask_to_download.call_deferred()
	else:
		push_warning("Converter: FFmpeg not found, skipping video conversion")
	is_done = true
	done.emit()

# ---------------------------------------------------------------- loading screen

func _build_loading_screen() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 100            # above everything else
	_loading_layer.visible = false
	add_child(_loading_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks underneath
	_loading_layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	_loading_title = Label.new()
	_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title.add_theme_font_size_override("font_size", 34)
	box.add_child(_loading_title)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(0, 20)
	_loading_bar.show_percentage = false
	box.add_child(_loading_bar)

	_loading_detail = Label.new()
	_loading_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_detail.add_theme_font_size_override("font_size", 18)
	_loading_detail.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_loading_detail)

# percent < 0 shows an animated "working" bar instead of a filled one
func _show_loading(title: String, detail: String, percent: float) -> void:
	_loading_base_title = title
	_dot_time = 0.0
	_loading_title.text = title
	_set_status(detail, percent)
	_loading_layer.visible = true

func _set_status(detail: String, percent: float) -> void:
	_loading_detail.text = detail
	_loading_bar.indeterminate = percent < 0.0
	if percent >= 0.0:
		_loading_bar.value = percent

func _hide_loading() -> void:
	_loading_layer.visible = false

func _on_download_progress(percent: float) -> void:
	_set_status("Downloading FFmpeg...  %d%%" % int(percent), percent)

# ---------------------------------------------------------------- finding FFmpeg

func _find_ffmpeg() -> String:
	var base: String
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir()
	var exe := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	var candidates := [
		_download_dir().path_join(exe),
		base.path_join("ffmpeg").path_join(exe),
		base.path_join(exe),
	]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	if OS.execute("ffmpeg", ["-version"], []) == 0:   # installed on the system PATH
		return "ffmpeg"
	return ""

func _download_dir() -> String:
	return ProjectSettings.globalize_path("user://ffmpeg")

# ---------------------------------------------------------------- converting

func _pending_sources() -> Array[String]:
	var list: Array[String] = []
	var folder := Util.get_user_folder("posters")
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() in SOURCE_EXTENSIONS:
			var source := folder.path_join(file)
			var target := source.get_basename() + ".ogv"
			if not FileAccess.file_exists(target) \
					or FileAccess.get_modified_time(target) < FileAccess.get_modified_time(source):
				list.append(source)
	return list

func _run_conversion(reload := false) -> void:
	var pending := _pending_sources()
	if pending.is_empty():          # nothing to do: no loading screen, no delay
		is_done = true
		done.emit()
		return
	is_done = false
	_reload_after = reload
	_show_loading("Converting videos", "Preparing...", 0.0)
	_thread = Thread.new()
	_thread.start(_worker.bind(pending))

func _worker(pending: Array[String]) -> void:
	var total := pending.size()
	for i in total:
		_set_status.call_deferred("%s   (%d of %d)" % [pending[i].get_file(), i + 1, total], 100.0 * i / total)
		_convert(pending[i])
	_set_status.call_deferred("Done", 100.0)
	_finish.call_deferred()

func _convert(source: String) -> void:
	var target := source.get_basename() + ".ogv"
	var args := [
		"-y", "-loglevel", "error", "-i", source,
		"-vf", "scale=-2:%d" % OUTPUT_HEIGHT,
		"-pix_fmt", "yuv420p", "-an",
		"-c:v", "libtheora", "-q:v", "6",
		target,
	]
	var output := []
	var code := OS.execute(ffmpeg_path, args, output, true)
	if code != 0:
		push_warning("Converter: could not convert %s (%s)" % [source.get_file(), output])

func _finish() -> void:
	_thread.wait_to_finish()
	is_done = true
	done.emit()
	if _reload_after:
		get_tree().reload_current_scene()   # so the posters pick up the new files
		await get_tree().create_timer(0.3).timeout
	_hide_loading()

# ---------------------------------------------------------------- asking the player

func _ask_to_download() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Video converter needed"
	_dialog.dialog_text = "Some videos or GIFs in the posters folder need FFmpeg to be converted.\nDownload it now? (about 100 MB, one time only)"
	_dialog.ok_button_text = "Download"
	_dialog.cancel_button_text = "Not now"
	_dialog.confirmed.connect(_on_dialog_confirmed)
	_dialog.canceled.connect(_on_dialog_canceled)
	get_tree().root.add_child(_dialog)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dialog.popup_centered()

func _on_dialog_confirmed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_dialog.queue_free()
	request_download()

func _on_dialog_canceled() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_dialog.queue_free()

# ---------------------------------------------------------------- downloading
# You can also call Converter.request_download() yourself, e.g. from a settings-menu button.

func request_download() -> void:
	if _downloading or ffmpeg_path != "":
		return
	if OS.get_name() != "Windows":
		push_warning("Converter: automatic download is Windows-only. Install FFmpeg with your package manager.")
		download_finished.emit(false)
		return
	_downloading = true
	DirAccess.make_dir_recursive_absolute(_download_dir())
	_show_loading("Downloading video converter", "Contacting server...", -1.0)
	# step 1: get the official checksum so the download can be verified
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_hash_received.bind(req))
	if req.request(FFMPEG_HASH_URL) != OK:
		req.queue_free()
		_fail("could not contact the download server")

func _on_hash_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("could not get the checksum (are you offline?)")
		return
	_expected_hash = body.get_string_from_utf8().strip_edges().split(" ")[0].to_lower()
	if _expected_hash.length() != 64:
		_fail("checksum file looked wrong")
		return
	# step 2: download the zip straight to disk
	_zip_request = HTTPRequest.new()
	_zip_request.download_file = _zip_path()
	_zip_request.use_threads = true
	add_child(_zip_request)
	_zip_request.request_completed.connect(_on_zip_downloaded)
	if _zip_request.request(FFMPEG_ZIP_URL) != OK:
		_zip_request.queue_free()
		_zip_request = null
		_fail("could not start the download")

func _process(delta: float) -> void:
	if _loading_layer.visible:   # animate the dots after the title
		_dot_time += delta
		var dots := int(_dot_time * 2.0) % 4
		_loading_title.text = _loading_base_title + ".".repeat(dots) + " ".repeat(3 - dots)
	if _zip_request == null:
		return
	var total := _zip_request.get_body_size()
	if total > 0:
		download_progress.emit(100.0 * _zip_request.get_downloaded_bytes() / total)

func _on_zip_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_zip_request.queue_free()
	_zip_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("download failed (code %d)" % code)
		return
	# step 3: verify, then pull ffmpeg.exe out of the zip
	_set_status("Verifying download...", -1.0)
	await get_tree().process_frame   # let the screen update before the heavy work
	if FileAccess.get_sha256(_zip_path()).to_lower() != _expected_hash:
		_fail("checksum mismatch, the file was discarded")
		return
	_set_status("Unpacking...", -1.0)
	await get_tree().process_frame
	if not _extract_ffmpeg():
		_fail("could not unpack ffmpeg.exe")
		return
	ffmpeg_path = _download_dir().path_join("ffmpeg.exe")
	_downloading = false
	download_finished.emit(true)
	_run_conversion(true)

func _extract_ffmpeg() -> bool:
	var zip := ZIPReader.new()
	if zip.open(_zip_path()) != OK:
		return false
	var ok := false
	for entry in zip.get_files():
		if entry.ends_with("/bin/ffmpeg.exe"):
			var out := FileAccess.open(_download_dir().path_join("ffmpeg.exe"), FileAccess.WRITE)
			if out:
				out.store_buffer(zip.read_file(entry))
				out.close()
				ok = true
			break
	zip.close()
	DirAccess.remove_absolute(_zip_path())
	return ok

func _zip_path() -> String:
	return _download_dir().path_join("ffmpeg_download.zip")

func _fail(message: String) -> void:
	push_warning("Converter: FFmpeg download failed - " + message)
	if FileAccess.file_exists(_zip_path()):
		DirAccess.remove_absolute(_zip_path())
	_downloading = false
	_hide_loading()
	download_finished.emit(false)
