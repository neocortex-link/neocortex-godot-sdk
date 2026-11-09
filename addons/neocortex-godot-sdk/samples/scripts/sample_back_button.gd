extends Button

## Back to the sample list, on press or on Escape. Every sample has one beside its header.

const LAUNCHER := "res://addons/neocortex-godot-sdk/samples/neocortex_samples.tscn"

func _ready() -> void:
	pressed.connect(_back)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()

func _back() -> void:
	get_tree().change_scene_to_file(LAUNCHER)
