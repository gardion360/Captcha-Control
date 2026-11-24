# Attach to your Camera3D
extends Camera3D

@export var sensitivity := 0.003
@export var max_yaw := deg_to_rad(60)
@export var max_pitch := deg_to_rad(40)
@export var interact_distance := 5.0
@export var hold_distance := 1.0

var yaw := 0.0
var pitch := 0.0
var look_enabled := true
var base_rotation := Vector3.ZERO
var held_object: Node3D = null

func _ready() -> void:
	base_rotation = rotation   # keep whatever direction you aimed it in the editor
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not look_enabled:
		return
	if event is InputEventMouseMotion:
		yaw = clamp(yaw - event.relative.x * sensitivity, -max_yaw, max_yaw)
		pitch = clamp(pitch - event.relative.y * sensitivity, -max_pitch, max_pitch)
		rotation = base_rotation + Vector3(pitch, yaw, 0)
	elif event.is_action_pressed("interact_primary"):
		_try_interact("primary")
	elif event.is_action_pressed("interact_secondary"):
		_try_interact("secondary")

func _try_interact(action: String) -> void:
	print("1. click received: ", action)
	if action == "secondary" and held_object:
		drop()
		return

	var space := get_world_3d().direct_space_state
	var from := global_position
	var to := from + (-global_transform.basis.z) * 20.0
	var result := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	print("2. ray hit: ", result.get("collider", "nothing"))
	if result.is_empty():
		return

	var hit: Object = result.collider
	print("3. is Interactable: ", hit is Interactable)
	if action == "secondary" and hit is Node3D and hit.is_in_group("pickable"):
		pick_up(hit)
	elif hit is Interactable:
		hit.interact(action)

func _process(_delta: float) -> void:
	if held_object:
		var target := global_position + (-global_transform.basis.z) * hold_distance
		held_object.global_position = held_object.global_position.lerp(target, 0.3)

func pick_up(obj: Node3D) -> void:
	held_object = obj
	if obj is RigidBody3D:
		obj.freeze = true

func drop() -> void:
	if held_object is RigidBody3D:
		held_object.freeze = false
	held_object = null
