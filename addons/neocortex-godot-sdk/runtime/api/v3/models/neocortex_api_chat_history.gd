class_name NeocortexApiChatHistory
extends RefCounted

## A page of a session's transcript (POST /v3/chat/session), oldest turn first.

var session_id: String = ""
var messages: Array[NeocortexChatHistoryEntry] = []
## Cursor to the next, older page; pass it back as `before`. Empty at the start of history.
var next_cursor: String = ""

static func from_dict(data: Dictionary) -> NeocortexApiChatHistory:
	var history := NeocortexApiChatHistory.new()
	history.session_id = NeocortexJson.get_string(data, "sessionId")
	history.messages = NeocortexChatHistoryEntry.list_from(NeocortexJson.get_array(data, "messages"))
	history.next_cursor = NeocortexJson.get_string(data, "nextCursor")
	return history
