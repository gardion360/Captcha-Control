extends Node

@export var screen_mesh: MeshInstance3D          # the screen mesh from the room
@export var ui_scene: PackedScene                # the UI scene to show on this screen
@export var resolution := Vector2i(512, 384)
@export var surface_index := 0                   # material slot of the screen
@export var flip_vertical := false               # tick if the screen is upside down

var viewport: SubViewport
var ui: Node

func _ready() -> void:
	if screen_mesh == null:
		push_warning("MonitorDisplay: screen_mesh is not assigned")
		return

	viewport = SubViewport.new()
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	if ui_scene:
		ui = ui_scene.instantiate()
		viewport.add_child(ui)
		if ui is Control:
			ui.set_anchors_preset(Control.PRESET_FULL_RECT)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = viewport.get_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if flip_vertical:
		mat.uv1_scale = Vector3(1, -1, 1)
		mat.uv1_offset = Vector3(0, 1, 0)
	screen_mesh.set_surface_override_material(surface_index, mat)
