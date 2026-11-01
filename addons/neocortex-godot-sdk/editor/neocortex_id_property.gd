@tool
extends EditorProperty

## An id field with a dropdown of the team's characters or question sets. The lists
## are fetched once per editor session (refresh with the button) and shared by every
## inspector. With no API key, or offline, it is a plain text field.

enum Kind { CHARACTERS, QUESTION_SETS }

# Kind -> Array of { id, label }; shared across inspectors for the editor session.
static var _cache: Dictionary = {}
static var _loading: Dictionary = {}

var _kind: Kind
var _picker := OptionButton.new()
var _field := LineEdit.new()
var _refresh := Button.new()
var _updating := false

func _init(kind: Kind) -> void:
	_kind = kind
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.clip_text = true
	_picker.item_selected.connect(_on_picked)
	row.add_child(_picker)
	_refresh.text = "Refresh"
	_refresh.tooltip_text = "Fetch the list again"
	_refresh.pressed.connect(func(): _load(true))
	row.add_child(_refresh)
	box.add_child(row)
	_field.placeholder_text = "Paste an id, or pick above"
	_field.text_submitted.connect(func(text: String): emit_changed(get_edited_property(), text.strip_edges()))
	_field.focus_exited.connect(func(): emit_changed(get_edited_property(), _field.text.strip_edges()))
	box.add_child(_field)
	add_child(box)
	set_bottom_editor(box)
	add_focusable(_field)
	add_focusable(_picker)

func _ready() -> void:
	_load(false)

func _update_property() -> void:
	_updating = true
	var value := str(get_edited_object().get(get_edited_property()))
	_field.text = value
	_fill(value)
	_updating = false

func _on_picked(index: int) -> void:
	if _updating:
		return
	var id := str(_picker.get_item_metadata(index))
	if not id.is_empty():
		emit_changed(get_edited_property(), id)

func _fill(current: String) -> void:
	_picker.clear()
	var items: Array = _cache.get(_kind, [])
	if NeocortexSettings.get_settings().api_key.is_empty():
		_picker.add_item("Add an API key in the Neocortex dock")
		_picker.set_item_metadata(0, "")
		_picker.disabled = true
		return
	_picker.disabled = false
	var noun := "character" if _kind == Kind.CHARACTERS else "question set"
	_picker.add_item("Loading..." if _loading.get(_kind, false) else "Pick a %s" % noun)
	_picker.set_item_metadata(0, "")
	for item in items:
		_picker.add_item(item.label)
		_picker.set_item_metadata(_picker.item_count - 1, item.id)
		if item.id == current:
			_picker.select(_picker.item_count - 1)

func _load(force: bool) -> void:
	if NeocortexSettings.get_settings().api_key.is_empty():
		_fill(_field.text)
		return
	if (_cache.has(_kind) and not force) or _loading.get(_kind, false):
		_fill(_field.text)
		return

	_loading[_kind] = true
	_fill(_field.text)
	var request := ApiRequest.new()
	add_child(request)
	var list = null
	if _kind == Kind.CHARACTERS:
		list = await request.get_characters()
	else:
		list = await request.get_question_sets()
	request.queue_free()
	_loading[_kind] = false

	var items: Array = []
	if list != null:
		for item in list:
			var text: String = item.name
			if _kind == Kind.QUESTION_SETS:
				text = "%s (%d questions)" % [item.name, item.question_count]
			items.append({ "id": item.id, "label": text })
		_cache[_kind] = items
	if is_inside_tree():
		_fill(_field.text)
