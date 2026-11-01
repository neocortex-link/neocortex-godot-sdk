extends CanvasLayer

## Escape, or the Back button beside the header, returns to the sample list. Added to
## every sample by the launcher, so the samples themselves stay free of navigation code.

const LAUNCHER := "res://addons/neocortex-godot-sdk/samples/neocortex_samples.tscn"

func _ready() -> void:
	layer = 100
	var frame := NeocortexSampleFrame.new()
	frame.size = NeocortexSampleFrame.REFERENCE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme = NeocortexUiStyle.get_theme()
	add_child(frame)
	var button := Button.new()
	button.text = "Back to Samples"
	button.tooltip_text = "Esc"
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_back)
	frame.add_child(button)
	NeocortexSampleFrame.place(button, Vector2.ZERO, Vector2.ZERO, Vector2(488, 76), Vector2(190, 40))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()

func _back() -> void:
	queue_free()
	get_tree().change_scene_to_file(LAUNCHER)
