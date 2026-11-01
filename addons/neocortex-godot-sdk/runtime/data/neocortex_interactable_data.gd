class_name NeocortexInteractableData
extends RefCounted

## One thing a character can perceive: an object, another character, or the player. Sent
## as chat metadata so the character knows what is around it and where.

## Stable unique id. Actions reference entities by this, never by name.
var id: String = ""
## Set when this entity IS a Neocortex character.
var character_id: String = ""
var name: String = ""
var position: Vector3 = Vector3.ZERO
## What this thing is and its state, as { "name": String, "value": String } pairs.
var properties: Array = []
## Legacy CHARACTER or OBJECT split, derived SDK side.
var type: String = ""
var is_subject: bool = false

func to_dict() -> Dictionary:
	var out := {
		"id": id,
		"name": name,
		"position": { "x": position.x, "y": position.y, "z": position.z },
		"properties": properties,
		"type": type,
		"isSubject": is_subject,
	}
	if not character_id.is_empty():
		out["characterId"] = character_id
	return out

static func from_dict(data: Dictionary) -> NeocortexInteractableData:
	var item := NeocortexInteractableData.new()
	item.id = NeocortexJson.get_string(data, "id")
	item.character_id = NeocortexJson.get_string(data, "characterId")
	item.name = NeocortexJson.get_string(data, "name")
	item.type = NeocortexJson.get_string(data, "type")
	item.is_subject = NeocortexJson.get_bool(data, "isSubject")
	item.properties = NeocortexJson.get_array(data, "properties")
	var point := NeocortexJson.get_dict(data, "position")
	item.position = Vector3(
		NeocortexJson.get_float(point, "x"),
		NeocortexJson.get_float(point, "y"),
		NeocortexJson.get_float(point, "z"))
	return item
