class_name NeocortexMessage
extends MarginContainer

## One chat bubble: the sender's name, the text, and an initial avatar. The bubble is as
## wide as its text, up to the panel's width. With show_typing(true) it becomes the
## writing indicator: three pulsing dots in an outlined bubble.

@onready var container: HBoxContainer = $HBoxContainer
@onready var label: Label = $HBoxContainer/Panel/VBox/Label
@onready var sender_label: Label = $HBoxContainer/Panel/VBox/Sender
@onready var background: PanelContainer = $HBoxContainer/Panel
@onready var avatar: PanelContainer = $HBoxContainer/Avatar
@onready var avatar_label: Label = $HBoxContainer/Avatar/Initial
@onready var left_padding: Control = $HBoxContainer/LeftPadding
@onready var right_padding: Control = $HBoxContainer/RightPadding
@onready var dots: HBoxContainer = get_node_or_null("HBoxContainer/Panel/VBox/Dots")

## Run RTL text through NeocortexText.correct_rtl (the bundled Arabic reshaper). Off by
## default: Godot's Label shapes Arabic natively.
var use_arabic_fixer := false

var _background_color := NeocortexUiStyle.SURFACE_DARK
var _text_color := NeocortexUiStyle.AMBER
var _typing := false
var _time := 0.0

func _ready() -> void:
	set_process(false)

## Fills the bubble. A user bubble sits on the trailing side (right in LTR).
func set_message(text: String, is_user: bool, is_ltr: bool = true, sender: String = "", display_avatar: bool = true,
		display_name: bool = true) -> void:
	if not is_ltr:
		label.text = NeocortexText.correct_rtl(text) if use_arabic_fixer else text
		label.text_direction = Control.TEXT_DIRECTION_RTL
	else:
		label.text = text
		label.text_direction = Control.TEXT_DIRECTION_LTR

	sender_label.text = sender if display_name else ""
	sender_label.visible = not sender_label.text.is_empty() and not _typing
	avatar.visible = display_avatar and not sender.is_empty()
	avatar_label.text = sender.substr(0, 1).to_upper()

	var on_left := not is_ltr if is_user else is_ltr
	left_padding.visible = not on_left
	right_padding.visible = on_left
	# The avatar sits on the outer edge of the bubble.
	container.move_child(avatar, 0 if on_left else container.get_child_count() - 1)
	container.alignment = BoxContainer.ALIGNMENT_BEGIN if on_left else BoxContainer.ALIGNMENT_END
	background.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if on_left else Control.SIZE_SHRINK_END
	# Text reads from its own start; only the sender's name follows the bubble's side.
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if is_ltr else HORIZONTAL_ALIGNMENT_RIGHT
	sender_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if on_left else HORIZONTAL_ALIGNMENT_RIGHT
	_apply_colors()
	_fit()

## Turns the bubble into the writing indicator (three pulsing dots) and back.
func show_typing(typing: bool) -> void:
	_typing = typing
	label.visible = not typing
	sender_label.visible = not typing and not sender_label.text.is_empty()
	if dots:
		dots.visible = typing
	_time = 0.0
	set_process(typing)
	_apply_colors()
	_fit()

## Bubble and text colors; the avatar follows them.
func set_color(background_color: Color, text_color: Color) -> void:
	_background_color = background_color
	_text_color = text_color
	if is_node_ready():
		_apply_colors()

func overwrite_font(font: Font) -> void:
	if font:
		label.add_theme_font_override("font", font)
		sender_label.add_theme_font_override("font", font)
		avatar_label.add_theme_font_override("font", font)
		_fit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_fit()

func _process(delta: float) -> void:
	_time += delta
	if dots:
		for i in dots.get_child_count():
			dots.get_child(i).modulate.a = 0.3 + 0.7 * maxf(0.0, sin(_time * 5.0 - i * 0.9))

## Sizes the bubble to its text, wrapping at the space the panel leaves. Measured
## against the scrolling panel, whose width does not follow its content.
func _fit() -> void:
	if _typing:
		label.custom_minimum_size.x = 0
		return
	var scroll := _scroll_parent()
	var room := (scroll.size.x if scroll != null else size.x)
	room -= background.get_theme_stylebox("panel").get_minimum_size().x
	var separation := container.get_theme_constant("separation")
	for child in container.get_children():
		if child != background and child.visible:
			room -= child.custom_minimum_size.x + separation
	var font := label.get_theme_font("font")
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
	if sender_label.visible:
		width = maxf(width, sender_label.get_theme_font("font").get_string_size(sender_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sender_label.get_theme_font_size("font_size")).x)
	var fitted := clampf(ceilf(width) + 2.0, 0.0, maxf(floorf(room) - 2.0, 64.0))
	if not is_equal_approx(fitted, label.custom_minimum_size.x):
		label.custom_minimum_size.x = fitted

func _scroll_parent() -> Control:
	var node := get_parent()
	while node != null:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null

func _apply_colors() -> void:
	label.add_theme_color_override("font_color", _text_color)
	sender_label.add_theme_color_override("font_color", Color(_text_color, 0.7))
	avatar_label.add_theme_color_override("font_color", _text_color)
	var outline := NeocortexUiStyle.AMBER_RIM if _typing else Color.TRANSPARENT
	background.add_theme_stylebox_override("panel",
		NeocortexUiStyle.pill(_background_color, outline, 2 if _typing else 0, 24, 18, 10))
	avatar.add_theme_stylebox_override("panel", NeocortexUiStyle.pill(_background_color, Color(_text_color, 0.5), 2, 999, 0, 0))
	if dots:
		for dot in dots.get_children():
			dot.add_theme_stylebox_override("panel", NeocortexUiStyle.pill(_text_color, Color.TRANSPARENT, 0, 999, 0, 0))
