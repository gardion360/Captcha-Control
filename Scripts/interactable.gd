class_name Interactable
extends CollisionObject3D

signal interacted(action: String)

@export var object_name := "Object"

func interact(action: String) -> void:
	interacted.emit(action)
