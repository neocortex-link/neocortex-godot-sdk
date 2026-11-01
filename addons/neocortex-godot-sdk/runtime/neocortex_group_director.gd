class_name NeocortexGroupDirector
extends Node

## Runs a group conversation across several NeocortexSmartAgents: sends one turn for the
## whole cast and routes each speaker's reply back to its own agent, one after the
## other. send() lets the cast decide who answers, send_to() addresses one,
## continue_scene() lets them talk among themselves. A cast of two or more needs a Pro
## or Team API key.

## The characters in the scene, each a NeocortexSmartAgent.
@export var agents: Array[NeocortexSmartAgent] = []

## Most characters that speak in one director driven turn before it hands back.
@export_range(1, 5) var max_turns: int = 5

## Raised before a character speaks its turn: use it for a shared transcript or name label.
signal speaker(message: NeocortexGroupMessage)
## The whole group turn, once, before the speakers are played out.
signal group_response_received(response: NeocortexGroupChatResponse)
## A turn starts, for example to lock the input field while the cast talks.
signal turn_started
## Every speaker in the turn has finished (also raised when a turn could not run).
signal turn_finished
signal request_failed(error: String)
signal request_error(error: NeocortexApiError)
## The shared session's transcript, when get_history() returns.
signal history_received(history: Array) # Array[NeocortexChatHistoryEntry]
## The transcript of the player's spoken input (send_audio()), so a UI can show it.
signal player_speech(text: String)

## The shared scene session. Empty until the first turn; the server mints it.
var session_id: String = ""

var _api_request: ApiRequest
var _busy := false

## True while a group turn is being fetched or played out.
var is_busy: bool:
	get:
		return _busy

func _ready() -> void:
	_api_request = ApiRequest.new()
	_api_request.name = "ApiRequest"
	add_child(_api_request)
	_api_request.request_error.connect(_handle_request_error)

	# The director speaks for the cast, so no member may answer the player on its own.
	for agent in agents:
		if agent != null:
			agent.auto_voice_input = false

## Adds a character to the cast mid scene; the server acknowledges the join naturally.
func add_agent(agent: NeocortexSmartAgent) -> void:
	if agent != null and not agents.has(agent):
		agent.auto_voice_input = false
		agents.append(agent)

## Removes a character from the cast mid scene.
func remove_agent(agent: NeocortexSmartAgent) -> void:
	agents.erase(agent)

## Forgets the scene session so the next turn starts a fresh conversation.
func clear_session() -> void:
	session_id = ""

## The player says something to the group; an AI director decides who answers.
func send(message: String) -> void:
	_run_turn(message, "")

## The player addresses one character (an agent or its character id); it answers.
func send_to(target, message: String) -> void:
	if target is NeocortexSmartAgent:
		_run_turn(message, target.character_id)
	elif target is String and not target.is_empty():
		_run_turn(message, target)

## No player input: the cast talks among themselves (an ambient turn).
func continue_scene() -> void:
	_run_turn("", "")

## Transcribes the player's speech and sends it to the group like send(), raising
## player_speech with the transcript.
func send_audio(audio: AudioStreamWAV) -> void:
	if audio == null:
		return
	if _busy:
		push_warning("[Neocortex] A group turn is already in progress; ignoring input until it finishes.")
		return

	var any_id := ""
	for agent in agents:
		if agent != null and not agent.character_id.is_empty():
			any_id = agent.character_id
			break
	if any_id.is_empty():
		push_warning("[Neocortex] The group director has no agents with a character_id.")
		turn_finished.emit()
		return

	# Claim the turn BEFORE awaiting: a second trigger would otherwise start a second
	# transcription and bill it twice.
	_busy = true
	var text := await _api_request.request_transcription(any_id, audio)
	if not is_inside_tree():
		return
	_busy = false

	# Nothing heard, or the request failed. End the turn anyway, or a UI that locked
	# its mic on send waits forever for a turn that never runs.
	if text.is_empty():
		turn_finished.emit()
		return

	player_speech.emit(text)
	_run_turn(text, "")

## Loads the scene's transcript (every speaker, oldest first) and raises
## history_received. Pass the previous page's next_cursor as `before` to page back.
## Returns null before the first turn.
func get_history(limit: int = 20, before: String = "") -> NeocortexApiChatHistory:
	if session_id.is_empty():
		return null
	var history := await _api_request.request_chat_history(session_id, limit, before)
	if history != null:
		history_received.emit(history.messages)
	return history

func _run_turn(message: String, speaker_character_id: String) -> void:
	if _busy:
		push_warning("[Neocortex] A group turn is already in progress; ignoring input until it finishes.")
		return

	var character_ids := PackedStringArray()
	for agent in agents:
		if agent != null and not agent.character_id.is_empty() and not character_ids.has(agent.character_id):
			character_ids.append(agent.character_id)

	if character_ids.is_empty():
		push_warning("[Neocortex] The group director has no agents with a character_id.")
		turn_finished.emit()
		return

	_busy = true
	turn_started.emit()

	var response := await _api_request.request_chat(character_ids, session_id, message, speaker_character_id, max_turns)
	if not is_inside_tree():
		return
	if response == null:
		# request_failed was already raised.
		_busy = false
		turn_finished.emit()
		return

	if not response.session_id.is_empty():
		session_id = response.session_id
	group_response_received.emit(response)

	# Speakers play strictly in order, each finishing before the next starts.
	for message_item in response.messages:
		if not is_inside_tree():
			return
		speaker.emit(message_item)
		var agent := _find_agent(message_item.character_id)
		if agent != null:
			await agent.speak(message_item)

	if not is_inside_tree():
		return
	_busy = false
	turn_finished.emit()

func _find_agent(character_id: String) -> NeocortexSmartAgent:
	for agent in agents:
		if agent != null and agent.character_id == character_id:
			return agent
	return null

func _handle_request_error(error: NeocortexApiError) -> void:
	_busy = false
	request_error.emit(error)
	request_failed.emit(error.message)
