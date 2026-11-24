extends Control

signal approved
signal denied
signal closed

@onready var approve_button: Button = %ApproveButton
@onready var deny_button: Button = %DenyButton
@onready var log_off_button: Button = %LogOffButton
@onready var info_label: Label = %InfoLabel

func _ready() -> void:
	approve_button.pressed.connect(func(): approved.emit())
	deny_button.pressed.connect(func(): denied.emit())
	log_off_button.pressed.connect(func(): closed.emit())

# call this from your game logic to show the current traveler
func show_traveler(traveler_name: String, country: String) -> void:
	info_label.text = "Name: %s\nCountry: %s" % [traveler_name, country]
