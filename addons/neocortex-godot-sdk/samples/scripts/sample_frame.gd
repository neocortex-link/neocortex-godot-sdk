class_name NeocortexSampleFrame
extends Control

## The samples' screen: everything under it is laid out on a 1920 x 1080 canvas and
## scaled to the window (width and height weighed by `match_width_or_height`), so the
## samples keep their proportions at any window size. The static helpers draw the
## samples' chrome: the dot grid, the amber corner brackets, the logo header and the
## demo brief.

const REFERENCE := Vector2(1920, 1080)
const VISUALS := "res://addons/neocortex-godot-sdk/samples/visuals/"

## 0 scales with the window's width, 1 with its height, 0.5 with both equally.
@export_range(0.0, 1.0) var match_width_or_height: float = 0.5

func _enter_tree() -> void:
	# Every sample has a frame, so this is where the launcher's character pick reaches
	# the sample's agents, before their _ready, however the sample was started.
	var scene: Node = self
	while scene.get_parent() != null and scene.get_parent() != get_tree().root:
		scene = scene.get_parent()
	NeocortexSampleCharacterPicker.apply_to_scene(scene)

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var by_width := log(screen.x / REFERENCE.x) / log(2.0)
	var by_height := log(screen.y / REFERENCE.y) / log(2.0)
	var factor := pow(2.0, lerpf(by_width, by_height, match_width_or_height))
	position = Vector2.ZERO
	scale = Vector2(factor, factor)
	size = screen / factor

# ------------------------------------------------------------------
# BUILDERS
# ------------------------------------------------------------------

## A frame under a new CanvasLayer of `parent`, with the dot grid, the corner brackets
## and the header ("NEOCORTEX" over `subtitle`). `opaque` paints a black backdrop, for
## scenes without a 3D world.
static func create(parent: Node, owner: Node, subtitle: String, opaque: bool = false) -> NeocortexSampleFrame:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	_add(parent, layer, owner)
	var frame := NeocortexSampleFrame.new()
	frame.name = "Frame"
	frame.size = REFERENCE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.theme = NeocortexUiStyle.get_theme()
	_add(layer, frame, owner)

	var background := Control.new()
	background.name = "Background"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(frame, background, owner)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if opaque:
		var black := ColorRect.new()
		black.name = "Black"
		black.color = Color.BLACK
		black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_add(background, black, owner)
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dots := TextureRect.new()
	dots.name = "Dots"
	dots.texture = load(VISUALS + "dots.png")
	dots.stretch_mode = TextureRect.STRETCH_TILE
	dots.modulate = Color(1, 1, 1, 0.1)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(background, dots, owner)
	dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var corner_texture: Texture2D = load(VISUALS + "corner.png")
	for corner in [["LeftTop", Vector2(0, 0)], ["RightTop", Vector2(1, 0)], ["LeftBottom", Vector2(0, 1)], ["RightBottom", Vector2(1, 1)]]:
		var bracket := TextureRect.new()
		bracket.name = corner[0]
		bracket.texture = corner_texture
		bracket.modulate = NeocortexUiStyle.CORNER
		bracket.flip_h = corner[1].x > 0
		bracket.flip_v = corner[1].y > 0
		bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_add(background, bracket, owner)
		place(bracket, corner[1], corner[1], Vector2(32 - 64 * corner[1].x, 32 - 64 * corner[1].y), Vector2(64, 64))

	var icon := TextureRect.new()
	icon.name = "Logo"
	icon.texture = load(VISUALS + "logo.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(background, icon, owner)
	place(icon, Vector2.ZERO, Vector2.ZERO, Vector2(64, 64), Vector2(64, 64))
	var title := label(background, owner, "Title", "NEOCORTEX", "NeocortexTitle")
	place(title, Vector2.ZERO, Vector2.ZERO, Vector2(144, 60), Vector2(400, 40))
	var demo := label(background, owner, "DemoName", subtitle, "NeocortexSubtitle")
	place(demo, Vector2.ZERO, Vector2.ZERO, Vector2(144, 100), Vector2(480, 28))
	return frame

## The "DEMO BRIEF" column on the right, from BBCode. `panel` puts it on a dark card
## (for scenes with a floor behind it).
static func add_brief(frame: Control, owner: Node, bbcode: String, panel: bool = false, height: float = 512) -> Control:
	var brief: Control
	if panel:
		var card := Panel.new()
		card.add_theme_stylebox_override("panel", NeocortexUiStyle.pill(Color(0, 0, 0, 0.91), Color.TRANSPARENT, 0, 24))
		brief = card
	else:
		brief = Control.new()
	brief.name = "Brief"
	brief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(frame, brief, owner)
	place(brief, Vector2(1, 0.5), Vector2(1, 0.5), Vector2(-32 if panel else 0, 0), Vector2(512, height))
	var inset := 8.0 if panel else 0.0
	add_section(brief, owner, "DEMO BRIEF", inset)
	var body := RichTextLabel.new()
	body.name = "Body"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.text = bbcode
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(brief, body, owner)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = inset
	body.offset_top = inset + 64
	body.offset_right = -inset - 64
	body.offset_bottom = -inset
	return brief

## A dark card with a heading, like the brief; returns the VBox to fill.
static func add_card(frame: Control, owner: Node, card_name: String, heading: String,
		anchor: Vector2, pivot: Vector2, offset: Vector2, card_size: Vector2) -> VBoxContainer:
	var card := Panel.new()
	card.name = card_name
	card.add_theme_stylebox_override("panel", NeocortexUiStyle.pill(Color(0, 0, 0, 0.91), Color.TRANSPARENT, 0, 24))
	_add(frame, card, owner)
	place(card, anchor, pivot, offset, card_size)
	add_section(card, owner, heading, 24)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 12)
	_add(card, content, owner)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 24
	content.offset_top = 24 + 64
	content.offset_right = -24
	content.offset_bottom = -24
	return content

## An amber heading with the thin rule under it.
static func add_section(parent: Control, owner: Node, heading: String, inset: float) -> void:
	var title := label(parent, owner, "Title", heading, "NeocortexHeading")
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = inset
	title.offset_top = inset
	title.offset_right = -inset
	title.offset_bottom = inset + 32
	var rule := ColorRect.new()
	rule.name = "Separator"
	rule.color = Color(1, 1, 1, 0.1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(parent, rule, owner)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_left = inset
	rule.offset_top = inset + 36
	rule.offset_right = -inset - 64
	rule.offset_bottom = inset + 40

## A label with one of the theme's text styles.
static func label(parent: Node, owner: Node, label_name: String, text: String, variation: String = "") -> Label:
	var item := Label.new()
	item.name = label_name
	item.text = text
	if not variation.is_empty():
		item.theme_type_variation = variation
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(parent, item, owner)
	return item

## Positions `control` by a point of its parent (`anchor`, 0 to 1), the
## point of the control that sits there (`pivot`), an offset in pixels and a size.
static func place(control: Control, anchor: Vector2, pivot: Vector2, offset: Vector2, control_size: Vector2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	var top_left := offset - control_size * pivot
	control.offset_left = top_left.x
	control.offset_top = top_left.y
	control.offset_right = top_left.x + control_size.x
	control.offset_bottom = top_left.y + control_size.y

static func _add(parent: Node, node: Node, owner: Node) -> void:
	parent.add_child(node)
	if owner != null:
		node.owner = owner
