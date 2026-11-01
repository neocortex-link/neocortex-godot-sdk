class_name NeocortexChatPanel
extends ScrollContainer

## A scrolling list of chat bubbles, newest at the bottom, with a writing indicator
## shown after the player's message. Older messages fade out toward the top.

@export var writing_direction: NeocortexEnums.WritingDirection = NeocortexEnums.WritingDirection.LEFT_TO_RIGHT
@export var font_overwrite: Font
## Show an initial avatar beside each named bubble.
@export var display_avatars: bool = true
## Show the sender's name inside each bubble (useful when several characters talk).
@export var display_sender_names: bool = false
## Run RTL messages through the bundled Arabic reshaper (NeocortexText.correct_rtl).
## Leave off to use Godot's native Arabic shaping.
@export var use_arabic_fixer: bool = false
## Bubble scene; must use the NeocortexMessage script.
@export var message_scene: PackedScene = preload("res://addons/neocortex-godot-sdk/nodes/NeocortexMessage.tscn")
## Fade messages out toward the top edge, from fully clear at the top to fully
## opaque at this fraction of the height. 0 turns the fade off.
@export_range(0.0, 1.0) var fade: float = 0.6:
	set(value):
		fade = value
		if is_node_ready():
			_apply_fade()

@export_group("Colors")
@export var player_background := NeocortexUiStyle.AMBER
@export var player_text := NeocortexUiStyle.SURFACE_DARK
@export var character_background := NeocortexUiStyle.SURFACE_DARK
@export var character_text := NeocortexUiStyle.AMBER

@onready var messages_container: VBoxContainer = $Messages

var message_items: Array[NeocortexMessage] = []
var writing_indicator: NeocortexMessage

func _ready() -> void:
	writing_indicator = message_scene.instantiate()
	writing_indicator.visible = false
	messages_container.add_child(writing_indicator)
	writing_indicator.set_color(character_background, character_text)
	writing_indicator.set_message("", false, true, "", false)
	writing_indicator.show_typing(true)
	_apply_fade()

## Adds a bubble. `sender` labels it (and gives the avatar its initial).
func add_message(text: String, is_user: bool, sender: String = "") -> void:
	var is_ltr := writing_direction == NeocortexEnums.WritingDirection.LEFT_TO_RIGHT

	var item: NeocortexMessage = message_scene.instantiate()
	messages_container.add_child(item)
	message_items.append(item)

	item.use_arabic_fixer = use_arabic_fixer
	item.set_color(player_background if is_user else character_background, player_text if is_user else character_text)
	item.set_message(text, is_user, is_ltr, sender, display_avatars, display_sender_names)
	item.overwrite_font(font_overwrite)

	# The writing indicator only follows a player message.
	writing_indicator.visible = is_user
	writing_indicator.set_message("", false, is_ltr, "", false)
	messages_container.move_child(writing_indicator, -1)

	await _scroll_to_bottom()

## Shows or hides the typing bubble, for a reply that is on its way.
func show_writing_indicator(visible_now: bool) -> void:
	writing_indicator.visible = visible_now
	messages_container.move_child(writing_indicator, -1)
	if visible_now:
		_scroll_to_bottom()

func clear_messages() -> void:
	for message in message_items:
		message.queue_free()
	message_items.clear()
	writing_indicator.visible = false

func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	scroll_vertical = int(get_v_scroll_bar().max_value)

## Masks the messages with a vertical gradient: the panel draws the gradient and
## clips its children to it, so bubbles fade as they scroll up.
func _apply_fade() -> void:
	if fade <= 0.0:
		clip_children = CLIP_CHILDREN_DISABLED
		remove_theme_stylebox_override("panel")
		return
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 1))
	gradient.set_offset(1, fade)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 128
	var mask := StyleBoxTexture.new()
	mask.texture = texture
	add_theme_stylebox_override("panel", mask)
	clip_children = CLIP_CHILDREN_ONLY
