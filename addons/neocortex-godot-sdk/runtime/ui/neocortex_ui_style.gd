@tool
class_name NeocortexUiStyle
extends RefCounted

## The Neocortex look: dark pills with amber outlines,
## amber accents and bold Arial. `build_theme()` makes the Theme every SDK widget
## uses (saved as nodes/NeocortexTheme.tres); the colours are
## here so scripts can use them too.

const THEME_PATH := "res://addons/neocortex-godot-sdk/nodes/NeocortexTheme.tres"
const UI_IMAGES := "res://addons/neocortex-godot-sdk/images/ui/"

const AMBER := Color("#F59E0B")
## Widget rims and labels.
const AMBER_RIM := Color("#F19B0B")
## The inner disc of the round voice widgets.
const AMBER_DISC := Color("#C57D00")
## The live microphone level.
const AMBER_LEVEL := Color("#B94620")
## The silence countdown ring.
const AMBER_WAIT := Color("#A44117")
## The input field's outline.
const AMBER_FIELD := Color("#F38B01")
const SURFACE := Color("#202020")
const SURFACE_DARK := Color("#1F1F1F")
const INK := Color("#DBDBDB")
const BODY := Color("#C8C8C8")
const ICON := Color("#282828")
const PLACEHOLDER := Color(0.55, 0.55, 0.55, 0.5)
const CORNER := Color("#DAA520")

const FONT_NAMES := ["Arial", "Helvetica", "Liberation Sans", "Arimo", "sans-serif"]

## Arial, or the closest sans serif the system has.
static func font(bold: bool = false, italic: bool = false) -> SystemFont:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(FONT_NAMES)
	system_font.font_weight = 700 if bold else 400
	system_font.font_italic = italic
	return system_font

## A rounded box. `radius` 999 makes a pill or a circle.
static func pill(background: Color, border: Color = Color.TRANSPARENT, border_width: int = 0,
		radius: int = 999, margin_x: float = 16, margin_y: float = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(radius)
	box.corner_detail = 12
	box.anti_aliasing_size = 1.0
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box

## The saved theme, or a fresh one when it has not been generated yet.
static func get_theme() -> Theme:
	if ResourceLoader.exists(THEME_PATH):
		return load(THEME_PATH)
	return build_theme()

static func build_theme() -> Theme:
	var theme := Theme.new()
	var regular := font()
	var bold := font(true)
	var italic := font(false, true)
	theme.default_font = regular
	theme.default_font_size = 24

	theme.set_color("font_color", "Label", INK)

	# Buttons: a dark pill with an amber outline.
	theme.set_font("font", "Button", bold)
	theme.set_color("font_color", "Button", AMBER)
	theme.set_color("font_hover_color", "Button", AMBER.lightened(0.2))
	theme.set_color("font_pressed_color", "Button", AMBER.lightened(0.3))
	theme.set_color("font_focus_color", "Button", AMBER)
	theme.set_color("font_hover_pressed_color", "Button", AMBER.lightened(0.3))
	theme.set_color("font_disabled_color", "Button", Color(AMBER, 0.35))
	theme.set_color("icon_normal_color", "Button", ICON)
	theme.set_color("icon_hover_color", "Button", ICON)
	theme.set_color("icon_pressed_color", "Button", ICON)
	theme.set_color("icon_focus_color", "Button", ICON)
	theme.set_color("icon_disabled_color", "Button", Color(ICON, 0.6))
	theme.set_stylebox("normal", "Button", pill(Color("#212121"), Color(AMBER, 0.5), 2, 999, 24, 8))
	theme.set_stylebox("hover", "Button", pill(Color("#2A2A2A"), Color(AMBER, 0.8), 2, 999, 24, 8))
	theme.set_stylebox("pressed", "Button", pill(Color("#171717"), AMBER, 2, 999, 24, 8))
	theme.set_stylebox("hover_pressed", "Button", pill(Color("#171717"), AMBER, 2, 999, 24, 8))
	theme.set_stylebox("disabled", "Button", pill(Color("#1A1A1A"), Color(AMBER, 0.2), 2, 999, 24, 8))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# A round amber button with a dark icon (send, push to talk).
	theme.add_type("NeocortexRoundButton")
	theme.set_type_variation("NeocortexRoundButton", "Button")
	theme.set_stylebox("normal", "NeocortexRoundButton", pill(AMBER, Color.TRANSPARENT, 0, 999, 8, 8))
	theme.set_stylebox("hover", "NeocortexRoundButton", pill(AMBER.lightened(0.12), Color.TRANSPARENT, 0, 999, 8, 8))
	theme.set_stylebox("pressed", "NeocortexRoundButton", pill(AMBER.darkened(0.2), Color.TRANSPARENT, 0, 999, 8, 8))
	theme.set_stylebox("hover_pressed", "NeocortexRoundButton", pill(AMBER.darkened(0.2), Color.TRANSPARENT, 0, 999, 8, 8))
	theme.set_stylebox("disabled", "NeocortexRoundButton", pill(Color(AMBER, 0.4), Color.TRANSPARENT, 0, 999, 8, 8))

	# The text field.
	theme.set_font("font", "LineEdit", regular)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", PLACEHOLDER)
	theme.set_color("caret_color", "LineEdit", AMBER)
	theme.set_color("selection_color", "LineEdit", Color(AMBER, 0.35))
	theme.set_stylebox("normal", "LineEdit", pill(SURFACE, AMBER_FIELD, 2, 999, 22, 12))
	theme.set_stylebox("focus", "LineEdit", pill(Color.TRANSPARENT, AMBER.lightened(0.25), 2, 999, 22, 12))
	theme.set_stylebox("read_only", "LineEdit", pill(SURFACE, Color(AMBER_FIELD, 0.4), 2, 999, 22, 12))

	# Dropdowns (the microphone picker) and their lists.
	theme.set_font("font", "OptionButton", bold)
	theme.set_color("font_color", "OptionButton", AMBER_RIM)
	theme.set_color("font_hover_color", "OptionButton", AMBER_RIM.lightened(0.2))
	theme.set_color("font_pressed_color", "OptionButton", AMBER_RIM.lightened(0.2))
	theme.set_color("font_focus_color", "OptionButton", AMBER_RIM)
	theme.set_stylebox("normal", "OptionButton", pill(SURFACE, AMBER_RIM, 2, 999, 24, 8))
	theme.set_stylebox("hover", "OptionButton", pill(Color("#2A2A2A"), AMBER_RIM, 2, 999, 24, 8))
	theme.set_stylebox("pressed", "OptionButton", pill(Color("#171717"), AMBER_RIM, 2, 999, 24, 8))
	theme.set_stylebox("disabled", "OptionButton", pill(SURFACE, Color(AMBER_RIM, 0.3), 2, 999, 24, 8))
	theme.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	theme.set_icon("arrow", "OptionButton", load(UI_IMAGES + "dropdown_arrow.png"))
	theme.set_constant("arrow_margin", "OptionButton", 20)
	theme.set_font("font", "PopupMenu", bold)
	theme.set_font_size("font_size", "PopupMenu", 22)
	theme.set_color("font_color", "PopupMenu", AMBER_RIM)
	theme.set_color("font_hover_color", "PopupMenu", SURFACE_DARK)
	theme.set_stylebox("panel", "PopupMenu", pill(SURFACE, AMBER_RIM, 2, 16, 8, 8))
	theme.set_stylebox("hover", "PopupMenu", pill(AMBER_RIM, Color.TRANSPARENT, 0, 12, 8, 4))
	theme.set_constant("v_separation", "PopupMenu", 12)

	# Toggles: label first, an amber outlined box after it.
	theme.set_font("font", "CheckBox", bold)
	theme.set_color("font_color", "CheckBox", AMBER_RIM)
	theme.set_color("font_hover_color", "CheckBox", AMBER_RIM.lightened(0.2))
	theme.set_color("font_pressed_color", "CheckBox", AMBER_RIM)
	theme.set_color("font_hover_pressed_color", "CheckBox", AMBER_RIM.lightened(0.2))
	theme.set_color("font_focus_color", "CheckBox", AMBER_RIM)
	theme.set_color("font_disabled_color", "CheckBox", Color(AMBER_RIM, 0.4))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	var off: Texture2D = load(UI_IMAGES + "toggle_off.png")
	var on: Texture2D = load(UI_IMAGES + "toggle_on.png")
	theme.set_icon("unchecked", "CheckBox", off)
	theme.set_icon("checked", "CheckBox", on)
	theme.set_icon("unchecked_disabled", "CheckBox", off)
	theme.set_icon("checked_disabled", "CheckBox", on)
	theme.set_constant("h_separation", "CheckBox", 16)

	# Rich text: the demo briefs.
	theme.set_font("normal_font", "RichTextLabel", regular)
	theme.set_font("bold_font", "RichTextLabel", bold)
	theme.set_font("italics_font", "RichTextLabel", italic)
	theme.set_font("bold_italics_font", "RichTextLabel", font(true, true))
	theme.set_color("default_color", "RichTextLabel", BODY)
	theme.set_constant("line_separation", "RichTextLabel", 12)

	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", pill(Color(0, 0, 0, 0.91), Color.TRANSPARENT, 0, 24, 24, 24))

	# Thin amber scroll bars.
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, pill(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 0, 4, 3, 3))
		theme.set_stylebox("grabber", bar, pill(Color(AMBER, 0.6), Color.TRANSPARENT, 0, 4, 3, 3))
		theme.set_stylebox("grabber_highlight", bar, pill(AMBER, Color.TRANSPARENT, 0, 4, 3, 3))
		theme.set_stylebox("grabber_pressed", bar, pill(AMBER, Color.TRANSPARENT, 0, 4, 3, 3))

	# Header and brief text (the samples' screens).
	_label_variation(theme, "NeocortexTitle", bold, 32, Color.WHITE)
	_label_variation(theme, "NeocortexSubtitle", regular, 20, Color(1, 1, 1, 0.59))
	_label_variation(theme, "NeocortexHeading", bold, 22, AMBER)
	_label_variation(theme, "NeocortexBody", regular, 24, BODY)
	return theme

static func _label_variation(theme: Theme, type_name: String, label_font: Font, size: int, color: Color) -> void:
	theme.add_type(type_name)
	theme.set_type_variation(type_name, "Label")
	theme.set_font("font", type_name, label_font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)
