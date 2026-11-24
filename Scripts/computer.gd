extends Interactable

@export var computer_menu: Control
@export var player_camera: Camera3D

func _ready() -> void:
	if computer_menu == null:
		push_warning("Computer menu not assigned")
		return
	if computer_menu.has_signal("closed"):
			computer_menu.closed.connect(close_menu)
	interacted.connect(_on_interacted)
	computer_menu.hide()

func _on_interacted(action: String) -> void:
	if action == "primary":
		open_menu()

func _unhandled_input(event: InputEvent) -> void:
	if computer_menu.visible and event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	computer_menu.show()
	player_camera.look_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# connect your "Log off" button's pressed signal to this
func close_menu() -> void:
	computer_menu.hide()
	player_camera.look_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
