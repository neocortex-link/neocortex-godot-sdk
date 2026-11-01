class_name NeocortexGroupMessage
extends RefCounted

## One character's turn inside a v3 chat reply: the ordered chat lines it speaks (each
## with its own emotion), the actions it triggered and its Conversation Flow state. A
## solo chat carries exactly one of these.

var character_id: String = ""
## The character's display name, handy for labelling the line in a shared transcript.
var name: String = ""
var lines: Array[NeocortexChatLine] = []
var actions: Array[NeocortexChatAction] = []
## The Conversation Flow checkpoint this turn landed on. Empty when the character has no
## flow.
var flow_state: String = ""
var spoken_message: String = ""

static func from_dict(data: Dictionary) -> NeocortexGroupMessage:
	var message := NeocortexGroupMessage.new()
	message.character_id = NeocortexJson.get_string(data, "characterId")
	message.name = NeocortexJson.get_string(data, "name")
	message.flow_state = NeocortexJson.get_string(data, "flowState")
	message.spoken_message = NeocortexJson.get_string(data, "spokenMessage")
	for item in NeocortexJson.get_array(data, "lines"):
		if item is Dictionary:
			message.lines.append(NeocortexChatLine.from_dict(item))
	message.actions = NeocortexChatAction.list_from(NeocortexJson.get_array(data, "actions"))
	return message

static func list_from(raw: Array) -> Array[NeocortexGroupMessage]:
	var out: Array[NeocortexGroupMessage] = []
	for item in raw:
		if item is Dictionary:
			out.append(from_dict(item))
	return out
