class_name NeocortexChatStream
extends RefCounted

## One streamed chat turn from /v3/chat/stream, as signals. Returned by
## ApiRequest.request_chat_stream(), already running. EXPERIMENTAL on the server.
##
## A solo turn raises: session_started, text_delta*, emotion_changed, line_completed*,
## action_received*, flow_state_changed?, then completed. A cast turn raises
## speaker_started before each speaker and message_completed after it. Every event
## after session_started names the character it belongs to. Exactly one of completed
## or failed ends the stream.

signal session_started(session_id: String)
signal speaker_started(character_id: String, speaker_name: String)
## A piece of text for the line at `line_index`, for typewriter style display.
signal text_delta(character_id: String, text: String, line_index: int)
signal emotion_changed(character_id: String, emotion: NeocortexEnums.Emotions)
## A whole chat line, ready to show and speak.
signal line_completed(character_id: String, line: NeocortexChatLine)
signal action_received(character_id: String, action: NeocortexChatAction)
signal flow_state_changed(character_id: String, flow_state: String)
## One speaker of a cast turn is done.
signal message_completed(message: NeocortexGroupMessage)
## The whole turn, in the same shape /v3/chat returns.
signal completed(response: NeocortexGroupChatResponse)
signal failed(error: NeocortexApiError)
# Raised after either ending, so wait() has one thing to await.
signal _finished

var session_id: String = ""
var response: NeocortexGroupChatResponse = null
var error: NeocortexApiError = null

var _solo_character_id: String = ""
var _http: NeocortexHttpStream
var _parser := NeocortexSseParser.new()
var _ended := false

func _init(solo_character_id: String = "") -> void:
	_solo_character_id = solo_character_id
	_parser.event_received.connect(_on_event)

## True once completed or failed has been raised.
func is_done() -> bool:
	return _ended

## Stops the stream. Raises failed with a cancelled error.
func cancel() -> void:
	if _http != null and is_instance_valid(_http):
		_http.cancel()

## Awaitable: returns the whole turn, or null on failure.
func wait() -> NeocortexGroupChatResponse:
	if not _ended:
		await _finished
	return response

func attach(http: NeocortexHttpStream) -> void:
	_http = http
	http.chunk_received.connect(_parser.feed)
	http.finished.connect(_on_http_finished)

func _on_http_finished(http_error: NeocortexApiError) -> void:
	_parser.complete()
	if _ended:
		return
	if http_error != null:
		_fail(http_error)
	else:
		var missing := NeocortexApiError.new()
		missing.message = "The chat stream ended before the turn was complete."
		_fail(missing)

func _on_event(event_name: String, data: Dictionary) -> void:
	if _ended:
		return
	var character_id := NeocortexJson.get_string(data, "characterId", _solo_character_id)

	match event_name:
		"session":
			session_id = NeocortexJson.get_string(data, "sessionId")
			session_started.emit(session_id)
		"speaker":
			speaker_started.emit(character_id, NeocortexJson.get_string(data, "name"))
		"delta":
			text_delta.emit(character_id, NeocortexJson.get_string(data, "text"), NeocortexJson.get_int(data, "line"))
		"emotion":
			emotion_changed.emit(character_id, NeocortexEnums.emotion_from_string(NeocortexJson.get_string(data, "emotion")))
		"line":
			line_completed.emit(character_id, NeocortexChatLine.from_dict(data))
		"action":
			var action := NeocortexChatAction.from_dict(data)
			if not action.name.is_empty():
				action_received.emit(character_id, action)
		"flowState":
			flow_state_changed.emit(character_id, NeocortexJson.get_string(data, "flowState"))
		"message":
			pass # The full speaker arrives on `done`; nothing here a game needs first.
		"done":
			_complete(data)
		"error":
			var failure := NeocortexApiError.new()
			failure.status = NeocortexJson.get_int(data, "status", 500)
			failure.code = NeocortexJson.get_string(data, "code")
			failure.message = NeocortexJson.get_string(data, "error", "The chat stream failed.")
			_fail(failure)

func _complete(data: Dictionary) -> void:
	var result := NeocortexGroupChatResponse.new()
	result.session_id = NeocortexJson.get_string(data, "sessionId", session_id)
	result.metadata = NeocortexJson.get_array(data, "metadata")

	if data.get("messages", null) is Array:
		result.messages = NeocortexGroupMessage.list_from(data["messages"])
	else:
		# A solo `done` is the flat reply; it becomes a cast of one.
		var solo := NeocortexGroupMessage.from_dict(data)
		if solo.character_id.is_empty():
			solo.character_id = _solo_character_id
		result.messages = [solo]

	session_id = result.session_id
	response = result
	_ended = true
	for message in result.messages:
		message_completed.emit(message)
	completed.emit(result)
	_finished.emit()

func _fail(failure: NeocortexApiError) -> void:
	_ended = true
	error = failure
	failed.emit(failure)
	_finished.emit()
