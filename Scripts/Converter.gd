# AUTOLOAD: register as "Converter" in Project Settings > Globals, BELOW "Util".
# On startup, converts any video/gif in the posters folder to .ogv using FFmpeg (in a background thread).
extends Node

signal done
var is_done := false

const SOURCE_EXTENSIONS := ["mp4", "gif", "webm", "mov", "avi", "mkv"]
const OUTPUT_HEIGHT := 768   # converted videos are scaled to this height

var _thread: Thread

func _ready() -> void:
	_thread = Thread.new()
	_thread.start(_run)

func _run() -> void:
	var folder := Util.get_user_folder("posters")
	var ffmpeg := _find_ffmpeg()
	if ffmpeg == "":
		push_warning("Converter: FFmpeg not found, skipping video conversion")
	else:
		for file in DirAccess.get_files_at(folder):
			if file.get_extension().to_lower() in SOURCE_EXTENSIONS:
				_convert(ffmpeg, folder.path_join(file))
	_finish.call_deferred()

func _convert(ffmpeg: String, source: String) -> void:
	var target := source.get_basename() + ".ogv"
	# skip if already converted and the source hasn't changed since
	if FileAccess.file_exists(target) and FileAccess.get_modified_time(target) >= FileAccess.get_modified_time(source):
		return
	var args := [
		"-y", "-loglevel", "error", "-i", source,
		"-vf", "scale=-2:%d" % OUTPUT_HEIGHT,
		"-pix_fmt", "yuv420p", "-an",
		"-c:v", "libtheora", "-q:v", "6",
		target,
	]
	var output := []
	var code := OS.execute(ffmpeg, args, output, true)
	if code != 0:
		push_warning("Converter: could not convert %s (%s)" % [source.get_file(), output])

func _find_ffmpeg() -> String:
	var base: String
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir()
	var exe := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	for candidate in [base.path_join("ffmpeg").path_join(exe), base.path_join(exe)]:
		if FileAccess.file_exists(candidate):
			return candidate
	# fall back to an FFmpeg installed on the system PATH
	if OS.execute("ffmpeg", ["-version"], []) == 0:
		return "ffmpeg"
	return ""

func _finish() -> void:
	_thread.wait_to_finish()
	is_done = true
	done.emit()
