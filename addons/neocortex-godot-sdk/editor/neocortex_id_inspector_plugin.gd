@tool
extends EditorInspectorPlugin

## Inspector help for the Neocortex nodes:
## - NeocortexSmartAgent and NeocortexQuizAgent: a warning when there is no API key
##   (with a button to the settings), a prompt when no character or question set is
##   picked, and pickers on character_id and question_set_id.
## - NeocortexInteractable: the resolved id actions use, with Copy.
## - Microphone receivers: a device picker and where to find the live level monitor.

const IdProperty := preload("res://addons/neocortex-godot-sdk/editor/neocortex_id_property.gd")

var _open_settings: Callable

func _init(open_settings: Callable = Callable()) -> void:
	_open_settings = open_settings

func _can_handle(object: Object) -> bool:
	return object is NeocortexSmartAgent or object is NeocortexQuizAgent \
		or object is NeocortexInteractable or object is NeocortexAudioReceiverBase

func _parse_begin(object: Object) -> void:
	if object is NeocortexSmartAgent or object is NeocortexQuizAgent:
		_agent_help(object)
	elif object is NeocortexInteractable:
		_interactable_help(object)
	elif object is NeocortexAudioReceiverBase:
		_receiver_help()

func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint: PropertyHint,
		_hint_string: String, _usage: int, _wide: bool) -> bool:
	if name == "character_id":
		add_property_editor(name, IdProperty.new(IdProperty.Kind.CHARACTERS))
		return true
	if name == "question_set_id":
		add_property_editor(name, IdProperty.new(IdProperty.Kind.QUESTION_SETS))
		return true
	return false

func _agent_help(agent: Object) -> void:
	if NeocortexSettings.get_settings().api_key.strip_edges().is_empty():
		var box := _note("No API key yet. Add one in the Neocortex settings to pick a character and talk to it.", true)
		if _open_settings.is_valid():
			var button := Button.new()
			button.text = "Open Neocortex Settings"
			button.pressed.connect(_open_settings)
			box.add_child(button)
		add_custom_control(box)
		return

	var missing := PackedStringArray()
	if str(agent.get("character_id")).is_empty():
		missing.append("a character")
	if agent is NeocortexQuizAgent and str(agent.get("question_set_id")).is_empty():
		missing.append("a question set")
	if not missing.is_empty():
		add_custom_control(_note("Pick %s below." % " and ".join(missing), false))

func _interactable_help(interactable: NeocortexInteractable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Resolved id: %s" % interactable.get_id()
	label.tooltip_text = "Actions target this interactable by this id (NeocortexChatAction.target_id)."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var copy := Button.new()
	copy.text = "Copy"
	copy.pressed.connect(func(): DisplayServer.clipboard_set(interactable.get_id()))
	row.add_child(copy)
	add_custom_control(row)

func _receiver_help() -> void:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Microphone"
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.clip_text = true
	var devices := NeocortexMicrophone.devices()
	for device in devices:
		picker.add_item(device)
	if not devices.is_empty():
		picker.select(clampi(NeocortexMicrophone.get_selected_index(), 0, devices.size() - 1))
	picker.item_selected.connect(NeocortexMicrophone.set_selected_index)
	row.add_child(picker)
	box.add_child(row)
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		box.add_child(_note("Enable Project Settings > Audio > Driver > Enable Input, or the microphone stays silent.", true))
	box.add_child(_note("While the game runs, Debugger > Neocortex shows the live input level against the threshold and the silence countdown.", false))
	add_custom_control(box)

func _note(text: String, warning: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200
	if warning:
		label.add_theme_color_override("font_color", Color("#F0C45C"))
	else:
		label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(label)
	return box
