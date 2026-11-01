class_name NeocortexChatAction
extends RefCounted

## One action the character triggered, in the order it intends to perform it.
## `target_id` is the entity it applies to (an interactable's id), or empty when it
## needs no object.

var name: String = ""
var target_id: String = ""

static func create(action_name: String, action_target_id: String = "") -> NeocortexChatAction:
	var action := NeocortexChatAction.new()
	action.name = action_name
	action.target_id = action_target_id
	return action

static func from_dict(data: Dictionary) -> NeocortexChatAction:
	return create(NeocortexJson.get_string(data, "name"), NeocortexJson.get_string(data, "targetId"))

## Reads an `actions` array that may hold objects or, from older servers, bare names.
static func list_from(raw: Array) -> Array[NeocortexChatAction]:
	var out: Array[NeocortexChatAction] = []
	for item in raw:
		if item is Dictionary:
			var action := from_dict(item)
			if not action.name.is_empty():
				out.append(action)
		elif item is String and not item.is_empty():
			out.append(create(item))
	return out
