extends Control

## Lists the samples as cards and opens the one you pick. Each sample has a Back
## button (Escape) to return here. The dropdowns above the cards pick the character,
## the quiz question set and the microphone every sample uses.

const DIR := "res://addons/neocortex-godot-sdk/samples/"
const MICROPHONE := preload("res://addons/neocortex-godot-sdk/nodes/NeocortexMicrophoneDropdown.tscn")
const SAMPLES := [
	["1_text_chat_demo", "Text Chat", "Type to Cora; each line drops in and is voiced in its own emotion."],
	["2_audio_chat_demo", "Audio Chat", "Talk through the microphone, with voice detection or push to talk."],
	["3_actions_demo", "Actions", "Ask Cora to dance or jump; stacked actions run in order."],
	["4_interactables_demo", "Interactables", "Cora perceives the shapes on the floor and walks to them."],
	["5_group_chat_demo", "Group Chat", "Three characters, one conversation, a live roster. Pro or Team key."],
	["6_usage_gating_demo", "Usage Gating", "Check credits and caps before every message."],
	["7_quiz_show_demo", "Quiz Show", "Cora hosts a quiz for one to four players."],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := NeocortexSampleFrame.create(self, null, "Godot SDK · Samples", true)

	# What every sample uses: a character, the quiz's question set, the microphone.
	var choices := HBoxContainer.new()
	choices.name = "Choices"
	choices.add_theme_constant_override("separation", 36)
	frame.add_child(choices)
	NeocortexSampleFrame.place(choices, Vector2(0.5, 0), Vector2(0.5, 0), Vector2(0, 150), Vector2(1608, 80))
	var character := NeocortexSampleCharacterPicker.new()
	character.name = "CharacterPicker"
	_choice(choices, "CHARACTER", character)
	var question_set := NeocortexSampleCharacterPicker.new()
	question_set.name = "QuestionSetPicker"
	question_set.kind = NeocortexSampleCharacterPicker.Kind.QUESTION_SETS
	_choice(choices, "QUESTION SET (QUIZ SHOW)", question_set)
	_choice(choices, "MICROPHONE", MICROPHONE.instantiate())

	# Three cards a row, the last row centred.
	var grid := HFlowContainer.new()
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	frame.add_child(grid)
	NeocortexSampleFrame.place(grid, Vector2(0.5, 0.5), Vector2(0.5, 0.5), Vector2(0, 48), Vector2(1608, 648))
	for i in SAMPLES.size():
		grid.add_child(_card(i + 1, SAMPLES[i]))

	if NeocortexSettings.get_settings().api_key.is_empty():
		var warning := NeocortexSampleFrame.label(frame, null, "Warning",
			"Add your API key in the Neocortex dock first.", "NeocortexHeading")
		warning.add_theme_color_override("font_color", Color("#EE6B6B"))
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		NeocortexSampleFrame.place(warning, Vector2(0.5, 1), Vector2(0.5, 1), Vector2(0, -64), Vector2(800, 32))

## A caption over a dropdown, one column of the choices row.
func _choice(row: HBoxContainer, caption: String, dropdown: Control) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)
	var label := NeocortexSampleFrame.label(column, null, "Caption", caption, "NeocortexHeading")
	label.add_theme_font_size_override("font_size", 18)
	dropdown.custom_minimum_size = Vector2(0, 48)
	column.add_child(dropdown)

func _card(number: int, sample: Array) -> Button:
	var card := Button.new()
	card.name = sample[0]
	card.custom_minimum_size = Vector2(520, 200)
	card.add_theme_stylebox_override("normal", NeocortexUiStyle.pill(Color(0, 0, 0, 0.91), Color(1, 1, 1, 0.08), 2, 24))
	card.add_theme_stylebox_override("hover", NeocortexUiStyle.pill(Color("#141414"), NeocortexUiStyle.AMBER_RIM, 2, 24))
	card.add_theme_stylebox_override("pressed", NeocortexUiStyle.pill(Color("#1F1F1F"), NeocortexUiStyle.AMBER, 2, 24))
	card.add_theme_stylebox_override("focus", NeocortexUiStyle.pill(Color.TRANSPARENT, Color(NeocortexUiStyle.AMBER, 0.6), 2, 24))
	card.pressed.connect(_open.bind(sample[0]))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 32
	column.offset_top = 28
	column.offset_right = -32
	column.offset_bottom = -24
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	var index := NeocortexSampleFrame.label(heading, null, "Number", "%02d" % number, "NeocortexHeading")
	index.add_theme_font_size_override("font_size", 28)
	var title := NeocortexSampleFrame.label(heading, null, "Title", sample[1], "NeocortexTitle")
	title.add_theme_font_size_override("font_size", 28)
	var about := NeocortexSampleFrame.label(column, null, "About", sample[2], "NeocortexBody")
	about.add_theme_font_size_override("font_size", 21)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return card

func _open(sample_name: String) -> void:
	# The Back button lives on the root, so it outlives the scene change.
	get_tree().root.add_child(load(DIR + "scripts/sample_back_button.gd").new())
	get_tree().change_scene_to_file(DIR + sample_name + ".tscn")
