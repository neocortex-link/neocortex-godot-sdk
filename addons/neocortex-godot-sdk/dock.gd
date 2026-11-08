@tool
extends ScrollContainer

## The Neocortex dock: API key, account status, the team's characters and question sets,
## in compact cards drawn with the editor's own theme.

const DASHBOARD_KEYS_URL := "https://neocortex.link/dashboard/api-keys"
const DASHBOARD_CHARACTERS_URL := "https://neocortex.link/dashboard/characters"
const DASHBOARD_QUESTION_SETS_URL := "https://neocortex.link/dashboard/modules/quiz/sets"
const LOGO := preload("res://addons/neocortex-godot-sdk/images/ui/neocortex_logo.png")
const ACCENT := Color("#F59E0B")
const GOOD := Color("#5CC98F")
const BAD := Color("#EE6B6B")

## Set by plugin.gd so the dock can assign ids to the selected node.
var editor_interface: Object
## Fetch the account as soon as the dock is ready (the settings window waits until it
## opens).
var auto_refresh := true

var _settings: NeocortexSettings
var _api_key: LineEdit
var _reveal: Button
var _chip: Label
var _status: Label
var _tier: Label
var _email: Label
var _credits: Label
var _next_refresh: Label
var _characters: VBoxContainer
var _question_sets: VBoxContainer
var _character_count: Label
var _question_set_count: Label
var _refresh_button: Button

func _ready() -> void:
	name = "Neocortex"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings = NeocortexSettings.get_settings()
	_build()
	if _settings.api_key.is_empty():
		_set_chip("No key", BAD)
	elif auto_refresh:
		_refresh.call_deferred()

func _build() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# Header: the mark, the name and version, and whether the key works.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(22, 22) * _scale()
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(logo)
	var title := _label("Neocortex")
	title.theme_type_variation = &"HeaderSmall"
	header.add_child(title)
	var version := _muted(_version())
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(version)
	_chip = _label("")
	header.add_child(_chip)

	# API key.
	var key_card := _card(root, "API Key")
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 4)
	key_card.add_child(key_row)
	_api_key = LineEdit.new()
	_api_key.secret = true
	_api_key.placeholder_text = "Paste your API key"
	_api_key.text = _settings.api_key
	_api_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_api_key.text_submitted.connect(func(_text): _save_key())
	_style_field(_api_key)
	key_row.add_child(_api_key)
	_reveal = _icon_button("GuiVisibilityHidden", "Show the key", func():
		_api_key.secret = not _api_key.secret
		_reveal.icon = _icon("GuiVisibilityHidden" if _api_key.secret else "GuiVisibilityVisible"))
	key_row.add_child(_reveal)
	key_row.add_child(_button("Save", _save_key))
	key_card.add_child(_wide_button("Get a Key", "ExternalLink", DASHBOARD_KEYS_URL))
	_status = _muted("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	key_card.add_child(_status)

	# Account, two by two.
	var account_card := _card(root, "Account")
	_refresh_button = _icon_button("Reload", "Refresh", _refresh)
	account_card.get_parent().get_child(0).add_child(_refresh_button)
	_tier = _field(account_card, "Tier")
	_credits = _field(account_card, "Credits")
	_email = _field(account_card, "Owner")
	_next_refresh = _field(account_card, "Refills")

	# The team's characters and question sets.
	var characters_card := _card(root, "Characters")
	_character_count = _count_label(characters_card)
	_characters = VBoxContainer.new()
	_characters.add_theme_constant_override("separation", 2)
	characters_card.add_child(_characters)
	_characters.add_child(_muted("Add a key to list your characters."))
	var sets_card := _card(root, "Question Sets")
	_question_set_count = _count_label(sets_card)
	_question_sets = VBoxContainer.new()
	_question_sets.add_theme_constant_override("separation", 2)
	sets_card.add_child(_question_sets)

## Shows the saved settings again and refreshes the account (the settings window and
## the dock share one settings resource).
func reload() -> void:
	if _api_key == null:
		return
	_settings = NeocortexSettings.get_settings()
	_api_key.text = _settings.api_key
	_refresh()

# ------------------------------------------------------------------
# SETTINGS
# ------------------------------------------------------------------

func _save_key() -> void:
	_settings.api_key = _api_key.text.strip_edges()
	_persist()
	_refresh()

func _persist() -> void:
	var error := _settings.save_settings()
	if error != OK:
		_say("Could not save %s (error %d)." % [NeocortexSettings.SETTINGS_PATH, error])

# ------------------------------------------------------------------
# ACCOUNT AND LISTS
# ------------------------------------------------------------------

func _refresh() -> void:
	if _settings.api_key.is_empty():
		_set_chip("No key", BAD)
		_say("")
		return

	_set_chip("Checking...", Color(1, 1, 1, 0.5))
	_say("")
	_refresh_button.disabled = true

	# A fresh request node each time, so a key saved after the dock opened is used.
	var request := ApiRequest.new()
	add_child(request)
	var errors := PackedStringArray()
	request.request_failed.connect(func(message: String): errors.append(message))

	var account := await request.get_account()
	var characters = null
	var question_sets = null
	if account != null:
		characters = await request.get_characters()
		question_sets = await request.get_question_sets()
	request.queue_free()
	_refresh_button.disabled = false

	if account != null:
		_set_chip("Connected", GOOD)
		_tier.text = account.tier.capitalize()
		_email.text = account.email
		_credits.text = _thousands(account.credits_remaining)
		_next_refresh.text = account.next_refresh.left(10) if not account.next_refresh.is_empty() else "-"
	else:
		_set_chip("Not connected", BAD)
		for field in [_tier, _email, _credits, _next_refresh]:
			field.text = "-"
	_say("" if errors.is_empty() else errors[0])
	_status.add_theme_color_override("font_color", BAD)

	_fill(_characters, _character_count, characters, "character_id", "Create a character", DASHBOARD_CHARACTERS_URL)
	_fill(_question_sets, _question_set_count, question_sets, "question_set_id", "Create a question set", DASHBOARD_QUESTION_SETS_URL)

func _fill(list: VBoxContainer, count: Label, items, property: String, create_text: String, create_url: String) -> void:
	_clear(list)
	count.text = ""
	if items == null:
		list.add_child(_muted("Not loaded."))
		return
	count.text = str(items.size())
	if items.is_empty():
		list.add_child(_wide_button(create_text, "Add", create_url))
		return
	for item in items:
		var detail := "%d questions" % item.question_count if property == "question_set_id" else ""
		list.add_child(_row(item.name, detail, item.id, property))

func _row(title: String, detail: String, id: String, property: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var name_label := _label(title)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = id
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if not detail.is_empty():
		row.add_child(_muted(detail))
	row.add_child(_icon_button("ActionCopy", "Copy the id", func():
		DisplayServer.clipboard_set(id)
		_status.remove_theme_color_override("font_color")
		_say("Copied %s." % title)))
	row.add_child(_icon_button("Edit", "Use on the selected node", func(): _assign(property, id)))
	return row

# Writes the id into every selected node that has the property, with undo.
func _assign(property: String, id: String) -> void:
	_status.remove_theme_color_override("font_color")
	if editor_interface == null:
		return
	var selected: Array = editor_interface.get_selection().get_selected_nodes()
	var targets := selected.filter(func(node): return property in node)
	if targets.is_empty():
		_say("Select a node with a %s first." % property)
		return
	var undo: EditorUndoRedoManager = editor_interface.get_editor_undo_redo() if editor_interface.has_method("get_editor_undo_redo") else null
	for node in targets:
		if undo != null:
			undo.create_action("Set Neocortex %s" % property)
			undo.add_do_property(node, property, id)
			undo.add_undo_property(node, property, node.get(property))
			undo.commit_action()
		else:
			node.set(property, id)
	_say("Set on %d node(s)." % targets.size())

# ------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------

## A rounded card with a heading row; returns the box to fill.
func _card(parent: Control, heading: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = _editor_color("dark_color_1", Color(0, 0, 0, 0.2))
	box.set_corner_radius_all(int(6 * _scale()))
	box.set_content_margin_all(8 * _scale())
	card.add_theme_stylebox_override("panel", box)
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := _label(heading.to_upper())
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_font_size_override("font_size", int(get_theme_font_size("font_size", "Label") * 0.85))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	column.add_child(body)
	return body

func _count_label(body: VBoxContainer) -> Label:
	var count := _muted("")
	body.get_parent().get_child(0).add_child(count)
	return count

## A caption with its value beside it, on one line; returns the value label.
func _field(body: VBoxContainer, caption: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var name_label := _muted(caption)
	name_label.custom_minimum_size.x = 64 * _scale()
	row.add_child(name_label)
	var value := _label("-")
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value

## A full width button that opens a dashboard page.
func _wide_button(text: String, icon_name: String, url: String) -> Button:
	var button := _button(text, func(): OS.shell_open(url))
	button.icon = _icon(icon_name)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

## Sets a text field apart from the card: a darker well with a thin edge, amber when
## focused.
func _style_field(field: LineEdit) -> void:
	var well := StyleBoxFlat.new()
	well.bg_color = Color(0, 0, 0, 0.35)
	well.border_color = Color(1, 1, 1, 0.14)
	well.set_border_width_all(1)
	well.set_corner_radius_all(int(4 * _scale()))
	well.content_margin_left = 8 * _scale()
	well.content_margin_right = 8 * _scale()
	well.content_margin_top = 4 * _scale()
	well.content_margin_bottom = 4 * _scale()
	field.add_theme_stylebox_override("normal", well)
	var focus := well.duplicate()
	focus.border_color = ACCENT
	field.add_theme_stylebox_override("focus", focus)

## Shows a short message under the key (hidden when there is none).
func _say(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()

func _set_chip(text: String, color: Color) -> void:
	_chip.text = "● " + text
	_chip.add_theme_color_override("font_color", color)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _muted(text: String) -> Label:
	var label := _label(text)
	label.modulate = Color(1, 1, 1, 0.55)
	return label

func _button(text: String, action: Callable, flat: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = flat
	button.pressed.connect(action)
	return button

func _icon_button(icon_name: String, tooltip: String, action: Callable) -> Button:
	var button := Button.new()
	button.icon = _icon(icon_name)
	button.flat = true
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	return button

func _icon(icon_name: String) -> Texture2D:
	return get_theme_icon(icon_name, "EditorIcons") if has_theme_icon(icon_name, "EditorIcons") else null

func _editor_color(color_name: String, fallback: Color) -> Color:
	return get_theme_color(color_name, "Editor") if has_theme_color(color_name, "Editor") else fallback

func _scale() -> float:
	return EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0

func _version() -> String:
	var config := ConfigFile.new()
	config.load("res://addons/neocortex-godot-sdk/plugin.cfg")
	return "v" + str(config.get_value("plugin", "version", ""))

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(-3)
	return ("-" if value < 0 else "") + text + out
