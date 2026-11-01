class_name NeocortexQuizParticipant
extends Resource

## A player taking part in a quiz. Only human players are supported for now. A Resource
## so a roster can be filled in from the inspector.

@export var id: String = ""
@export var display_name: String = ""
@export var type: String = "human"

static func create(participant_id: String, participant_name: String = "") -> NeocortexQuizParticipant:
	var participant := NeocortexQuizParticipant.new()
	participant.id = participant_id
	participant.display_name = participant_name
	return participant

static func from_dict(data: Dictionary) -> NeocortexQuizParticipant:
	var participant := create(NeocortexJson.get_string(data, "id"), NeocortexJson.get_string(data, "displayName"))
	participant.type = NeocortexJson.get_string(data, "type", "human")
	return participant

func to_dict() -> Dictionary:
	return { "id": id, "displayName": display_name, "type": type }
