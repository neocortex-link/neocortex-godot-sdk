extends Control

## The sample list. The scene holds the cards and the choices every sample uses (the
## character, the quiz question set, the microphone); this script opens the sample a
## card names, and warns when there is no API key yet.

const DIR := "res://addons/neocortex-godot-sdk/samples/"

## The cards; each card's name is the scene it opens.
@export var samples: Control
## Shown when the project has no API key.
@export var no_key_warning: Control

func _ready() -> void:
	for card in samples.get_children():
		if card is BaseButton:
			card.pressed.connect(_open.bind(String(card.name)))
	no_key_warning.visible = NeocortexSettings.get_settings().api_key.is_empty()

func _open(sample_name: String) -> void:
	get_tree().change_scene_to_file(DIR + sample_name + ".tscn")
