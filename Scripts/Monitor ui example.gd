# Example UI script: attach to the root Control of a monitor UI scene
# Scene: Control (this script) > ColorRect (full rect, dark) + Label
extends Control

@onready var label: Label = $Label

func _process(_delta: float) -> void:
	label.text = "BORDER CONTROL\n" + Time.get_time_string_from_system()
