class_name NeocortexTextChatInput
extends HBoxContainer

## A text field + send button. Emits send_submitted with the typed message when the user
## presses Send or Enter, then clears the field.

signal send_submitted(message: String)

@export var font_overwrite: Font
## The field's hint, for example "Say something to Cora...".
@export var placeholder: String = "":
	set(value):
		placeholder = value
		if is_node_ready() and not value.is_empty():
			input_field.placeholder_text = value

@onready var input_field: LineEdit = $InputField
@onready var send_button: Button = $SendButton

var _italic: Font

func _ready() -> void:
	send_button.pressed.connect(_send)
	input_field.text_submitted.connect(func(_text): _send())
	if font_overwrite:
		input_field.add_theme_font_override("font", font_overwrite)
	if not placeholder.is_empty():
		input_field.placeholder_text = placeholder
	_italic_placeholder()
	input_field.text_changed.connect(func(_text): _italic_placeholder())

func _send() -> void:
	var message := input_field.text
	if message.length() > 0:
		send_submitted.emit(message)
		input_field.clear()
		_italic_placeholder()
		input_field.grab_focus()

# The placeholder is italic and the typed text upright; a LineEdit has one font.
func _italic_placeholder() -> void:
	if font_overwrite:
		return
	if input_field.text.is_empty():
		if _italic == null:
			_italic = NeocortexUiStyle.font(false, true)
		input_field.add_theme_font_override("font", _italic)
	else:
		input_field.remove_theme_font_override("font")
