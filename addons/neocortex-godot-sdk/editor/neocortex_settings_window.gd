@tool
extends Window

## Project > Tools > Neocortex > Settings: the same API key, account, character and
## question set view as the dock, in its own window.

const DOCK_SCENE := preload("res://addons/neocortex-godot-sdk/dock.tscn")

var _panel: Control

func setup(editor_interface: Object) -> void:
	title = "Neocortex Settings"
	min_size = Vector2i(420, 560)
	size = Vector2i(460, 680)
	transient = true
	exclusive = false
	wrap_controls = true
	close_requested.connect(hide)

	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_panel = DOCK_SCENE.instantiate()
	_panel.editor_interface = editor_interface
	_panel.auto_refresh = false
	margin.add_child(_panel)

## Shows the window centred on the editor and refreshes the account view.
func open() -> void:
	popup_centered()
	if _panel != null and _panel.has_method("reload"):
		_panel.reload()
