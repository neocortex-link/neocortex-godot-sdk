class_name NeocortexGroupChatResponse
extends RefCounted

## A whole v3 chat turn: `messages` are the speakers in the order they spoke (one for a
## solo cast), `session_id` the shared session, and `metadata` the scene's interactables
## after the turn, echoed once for the whole scene.

var session_id: String = ""
var messages: Array[NeocortexGroupMessage] = []
var metadata: Array = []

static func from_dict(data: Dictionary) -> NeocortexGroupChatResponse:
	var response := NeocortexGroupChatResponse.new()
	response.session_id = NeocortexJson.get_string(data, "sessionId")
	response.messages = NeocortexGroupMessage.list_from(NeocortexJson.get_array(data, "messages"))
	response.metadata = NeocortexJson.get_array(data, "metadata")
	return response
