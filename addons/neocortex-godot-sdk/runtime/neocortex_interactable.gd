@tool
class_name NeocortexInteractable
extends Node3D

## Marks a scene object the character can perceive. Every interactable in the scene is
## sent as chat metadata, so the character knows what is around it and where, and an
## action can target it by id (NeocortexChatAction.target_id).

const GROUP := "neocortex_interactable"

## Stable id actions refer to. Leave empty to derive one from the node's name and path.
@export var id: String = ""

## What this thing is and its state, as { "name": String, "value": String } pairs, for
## example { name: color, value: red }. A "name" property is what the character calls it.
@export var properties: Array[Dictionary] = []

## Legacy CHARACTER or OBJECT tag. Derived automatically when a NeocortexSmartAgent sits
## on this node or directly under it.
@export var type: NeocortexEnums.InteractableType = NeocortexEnums.InteractableType.OBJECT

var is_subject: bool = false

func _ready() -> void:
	add_to_group(GROUP)
	if Engine.is_editor_hint() and properties.is_empty():
		properties = [{ "name": "name", "value": str(name) }]

## The id actions use: the explicit one, or "<sanitized-name>-<hash of the node path>".
func get_id() -> String:
	if not id.strip_edges().is_empty():
		return id.strip_edges()
	var path := str(get_path()) if is_inside_tree() else str(name)
	return "%s-%08x" % [_sanitize(str(name)), path.hash() & 0xFFFFFFFF]

## The "name" property (any casing), or the node name.
func get_display_name() -> String:
	for property in properties:
		if str(property.get("name", "")).to_lower() == "name":
			return str(property.get("value", ""))
	return str(name)

## The agent this interactable represents, when it is a character.
func get_agent() -> NeocortexSmartAgent:
	if get_parent() is NeocortexSmartAgent:
		return get_parent()
	for child in get_children():
		if child is NeocortexSmartAgent:
			return child
	return null

func to_interactable() -> NeocortexInteractableData:
	var data := NeocortexInteractableData.new()
	var agent := get_agent()
	data.id = get_id()
	data.name = get_display_name()
	data.position = global_position
	data.is_subject = is_subject
	data.properties = properties
	data.character_id = agent.character_id if agent != null else ""
	var as_character := agent != null or type == NeocortexEnums.InteractableType.CHARACTER
	data.type = "CHARACTER" if as_character else "OBJECT"
	return data

static func _sanitize(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	return out
