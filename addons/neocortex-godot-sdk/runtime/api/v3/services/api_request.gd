class_name ApiRequest
extends WebRequest

## The Neocortex v3 API client.
##
## A voice turn runs in steps: recorded audio is
## transcribed first, then the chat turn runs on /v3/chat (one character is a cast of
## one), then speech is generated for the reply when asked. Every other endpoint is a
## coroutine that returns its result, or null (or "" / false) after raising
## request_failed and request_error.
##
## Lives in the scene tree: add it as a child (NeocortexSmartAgent and the other
## components do this for you).

const DEFAULT_BASE_URL := "https://api.neocortex.link/v3"

## Ceilings, not expectations: a turn that takes this long has already failed the
## player, and without one a request that never answers leaves an agent busy.
const TURN_TIMEOUT_SECONDS := 30.0
const AUDIO_TIMEOUT_SECONDS := 20.0
const LOOKUP_TIMEOUT_SECONDS := 15.0

const QUIZ_FINISHED_CODE := "quiz_finished"
const OPERATION_IN_PROGRESS_CODE := "operation_in_progress"
const STATE_CHANGED_CODE := "state_changed"
const QUIZ_BUSY_RETRIES := 2
const QUIZ_BUSY_RETRY_DELAY := 1.5

## Point every request at another server, for example your own proxy.
## Empty uses the public API.
static var base_url_override: String = ""

## False once a server has answered 404 for streamed speech; it will not grow the
## endpoint mid session, so the SDK stops paying for a doomed request every line.
static var streamed_speech_supported: bool = true

signal transcription_received(text: String)
signal chat_response_received(response: NeocortexChatResponse)
## An MP3 or WAV clip of a reply, ready for an AudioStreamPlayer.
signal audio_response_received(audio: AudioStream)
signal chat_history_received(history: Array) # Array[NeocortexChatHistoryEntry]

## How many times a request that failed with a retryable error (503
## database_unavailable, 504 upstream_timeout, a local timeout) is sent again before
## giving up. Applies to read only lookups, history and audio; a chat or quiz turn is
## never resent behind the game's back, check NeocortexApiError.is_retryable() instead.
var retry_attempts: int = 1
## Seconds between two attempts.
var retry_delay: float = 1.5

## Where perception is measured from (the speaking character). Nearest interactables
## win when the scene has more than max_perceived_entities. Null: no distance filter.
var perception_origin: Node3D = null
## Only perceive interactables within this many metres of the origin. 0: unlimited.
var perception_radius: float = 0.0
## Hard ceiling on how many interactables a single turn carries.
var max_perceived_entities: int = 24
## Name sent for the character itself when no interactable represents it.
var perception_self_name: String = ""

# ------------------------------------------------------------------
# BASE URL
# ------------------------------------------------------------------

## The base URL requests go to, without a trailing slash.
static func get_base_url() -> String:
	var url := base_url_override.strip_edges()
	if url.is_empty():
		url = DEFAULT_BASE_URL
	return url.trim_suffix("/")

# ------------------------------------------------------------------
# SEND PIPELINES (single character)
# ------------------------------------------------------------------

func send_text_to_text(character_id: String, message: String) -> void:
	_run_pipeline(character_id, message, false)

func send_text_to_audio(character_id: String, message: String) -> void:
	_run_pipeline(character_id, message, true)

func send_audio_to_text(character_id: String, audio: AudioStreamWAV) -> void:
	_run_pipeline(character_id, audio, false)

func send_audio_to_audio(character_id: String, audio: AudioStreamWAV) -> void:
	_run_pipeline(character_id, audio, true)

func _run_pipeline(character_id: String, input: Variant, produce_audio: bool) -> void:
	if character_id.is_empty():
		_fail_message("Character ID is required.")
		return
	if not _set_headers():
		return

	var message := ""
	if input is AudioStreamWAV:
		message = await request_transcription(character_id, input)
		if message.is_empty():
			return
		transcription_received.emit(message)
	else:
		message = str(input)

	var response := await request_chat_turn(character_id, message)
	if response == null:
		return
	chat_response_received.emit(response)

	if produce_audio:
		var audio := await generate_audio(character_id, response.message,
			NeocortexEnums.emotion_to_upper(response.emotion), response.spoken_message)
		if audio != null:
			audio_response_received.emit(audio)

## One solo chat turn. Stores the session id for the character and returns the reply
## flattened to a NeocortexChatResponse, or null on failure. Raises nothing on success:
## the pipelines and agents raise chat_response_received themselves.
func request_chat_turn(character_id: String, message: String) -> NeocortexChatResponse:
	var turn := await request_chat(
		[character_id],
		NeocortexSessionManager.get_session_id(character_id),
		message, "", 0, null, null, character_id)
	if turn == null:
		return null

	NeocortexSessionManager.set_session_id(character_id, turn.session_id)
	var speaker: NeocortexGroupMessage = turn.messages[0] if not turn.messages.is_empty() else null
	var response := NeocortexChatResponse.from_group_message(speaker, turn.metadata)
	response.session_id = turn.session_id
	if response.character_id.is_empty():
		response.character_id = character_id
	return response

# ------------------------------------------------------------------
# CHAT
# ------------------------------------------------------------------

## Sends one turn to the unified v3 chat endpoint for a whole cast and returns every
## speaker's reply, in order. Pass 1 to 3 character ids. Leave speaker_character_id
## empty to let the AI director choose who speaks; set it to force a speaker. An empty
## message is an ambient turn (the cast talks among themselves). Scene metadata and
## the event log are gathered automatically when passed as null. A cast of two or
## more needs a Pro or Team API key. Returns null on failure.
func request_chat(
		character_ids: PackedStringArray,
		session_id: String = "",
		message: String = "",
		speaker_character_id: String = "",
		max_turns: int = 0,
		metadata = null,
		events = null,
		self_character_id: String = "",
		play_as: String = "") -> NeocortexGroupChatResponse:
	if not _set_headers():
		return null

	var data := _chat_body(character_ids, session_id, message, speaker_character_id, max_turns, metadata, events, self_character_id, play_as)
	var result := await send_async({
		"url": "%s/chat" % get_base_url(),
		"content_type": "application/json",
		"body": get_bytes(data),
		"timeout": TURN_TIMEOUT_SECONDS,
	})
	if not result.ok:
		_report(result)
		return null

	return NeocortexGroupChatResponse.from_dict(NeocortexJson.parse_object(result.body))

## Same as request_chat().
func request_group_chat(character_ids: PackedStringArray, session_id: String = "", message: String = "",
		speaker_character_id: String = "", max_turns: int = 0) -> NeocortexGroupChatResponse:
	return await request_chat(character_ids, session_id, message, speaker_character_id, max_turns)

func _chat_body(character_ids: PackedStringArray, session_id: String, message: String, speaker_character_id: String,
		max_turns: int, metadata, events, self_character_id: String, play_as: String) -> Dictionary:
	var data := {
		"characterIds": Array(character_ids),
		"playerId": NeocortexSessionManager.get_player_id(),
	}
	if not session_id.is_empty():
		data["sessionId"] = session_id
	if not message.is_empty():
		data["message"] = message
	if not speaker_character_id.is_empty():
		data["speakerCharacterId"] = speaker_character_id
	if not play_as.is_empty():
		data["playAs"] = play_as
	if max_turns > 0:
		data["maxTurns"] = max_turns

	var scene_metadata = metadata if metadata != null else create_metadata(self_character_id)
	if scene_metadata is String and not scene_metadata.is_empty():
		data["metadata"] = scene_metadata
	elif scene_metadata is Array and not scene_metadata.is_empty():
		data["metadata"] = JSON.stringify(scene_metadata)

	var event_log = events if events != null else NeocortexEventLogger.get_logs()
	if event_log is String and not event_log.is_empty():
		data["events"] = event_log
	return data

# ------------------------------------------------------------------
# HISTORY
# ------------------------------------------------------------------

## Fire and forget history load for one character's session, raised through
## chat_history_received. For paging or a group session use request_chat_history().
func get_chat_history(character_id: String, limit: int = 10) -> void:
	var history := await request_chat_history(NeocortexSessionManager.get_session_id(character_id), limit)
	if history != null:
		chat_history_received.emit(history.messages)

## A session's transcript, oldest turn first. Pass the previous page's next_cursor as
## `before` to page back. Returns null on failure.
func request_chat_history(session_id: String, limit: int = 10, before: String = "") -> NeocortexApiChatHistory:
	if session_id.is_empty():
		_fail_message("A session id is required to load chat history.")
		return null
	if not _set_headers():
		return null

	var data := { "sessionId": session_id, "limit": limit }
	if not before.is_empty():
		data["before"] = before

	var result := await _send_with_retry({
		"url": "%s/chat/session" % get_base_url(),
		"content_type": "application/json",
		"body": get_bytes(data),
		"timeout": LOOKUP_TIMEOUT_SECONDS,
	})
	if not result.ok:
		_report(result)
		return null
	return NeocortexApiChatHistory.from_dict(NeocortexJson.parse_object(result.body))

# ------------------------------------------------------------------
# AUDIO
# ------------------------------------------------------------------

## Transcribes speech to text WITHOUT chatting. Any character the key owns works; it
## is used for metering. Returns "" on failure.
func request_transcription(character_id: String, audio: AudioStreamWAV) -> String:
	if not _set_headers():
		return ""

	var boundary := "NeocortexBoundary%d" % Time.get_ticks_usec()
	var result := await _send_with_retry({
		"url": "%s/audio/transcribe" % get_base_url(),
		"content_type": "multipart/form-data; boundary=%s" % boundary,
		"body": _build_multipart(boundary, character_id, audio),
		"timeout": AUDIO_TIMEOUT_SECONDS,
	})
	if not result.ok:
		_report(result)
		return ""

	var json := NeocortexJson.parse_object(result.body)
	return NeocortexJson.get_string(json, "response", NeocortexJson.get_string(json, "text"))

## True when the text has a letter or digit to speak.
static func has_something_to_say(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		var s := text[i]
		if s.to_upper() != s.to_lower() or (c >= 48 and c <= 57) or c > 0x2E7F:
			return true
	return false

## Generates speech for a piece of text, voiced in the given emotion (uppercase, for
## example "HAPPY"). IMPORTANT: every call costs 1 audio credit. Returns null on
## failure, and without a request for a line with nothing to speak ("...", an emoji).
func generate_audio(character_id: String, message: String, emotion: String, spoken_text: String = "") -> AudioStream:
	var speech := spoken_text if has_something_to_say(spoken_text) else message
	if not has_something_to_say(speech):
		return null
	if not _set_headers():
		return null

	var result := await _send_with_retry({
		"url": "%s/audio/generate" % get_base_url(),
		"content_type": "application/json",
		"body": get_bytes({
			"characterId": character_id,
			"message": speech,
			"spokenText": speech,
			"emotion": emotion.to_upper(),
		}),
		"timeout": AUDIO_TIMEOUT_SECONDS,
	})
	if not result.ok:
		_report(result)
		return null

	var audio := NeocortexAudioUtils.decode_audio(result.body)
	if audio == null:
		_fail_message("The speech response could not be decoded.")
	return audio

## EXPERIMENTAL. Speaks text by streaming it into `player` as it is synthesized, so
## playback starts before the whole line is ready. Returns false when nothing could
## be streamed, so the caller can fall back to generate_audio(). Leave report_errors
## off when falling back, so a recovered line does not look like a broken one.
## `on_frame` is called once per frame while bytes arrive: tick the player there when
## it should be heard (a line fetched ahead of time is not ticked until its turn), and
## return true to stop the download.
func generate_audio_stream(character_id: String, message: String, emotion: String,
		player: NeocortexStreamingAudioPlayer, report_errors: bool = true, on_frame: Callable = Callable()) -> bool:
	if not streamed_speech_supported:
		return false
	if not has_something_to_say(message):
		return false
	if not _set_headers():
		return false

	var parser := NeocortexPcmStreamParser.new()
	parser.format_received.connect(player.begin)
	parser.samples_received.connect(player.feed)

	var http := _open_stream("%s/audio/stream" % get_base_url(), get_bytes({
		"characterId": character_id,
		"message": message,
		"spokenText": message,
		"emotion": emotion.to_upper(),
	}), AUDIO_TIMEOUT_SECONDS)
	http.chunk_received.connect(parser.feed)

	var state := { "error": null, "done": false }
	http.finished.connect(func(error: NeocortexApiError):
		state.error = error
		state.done = true)

	while not state.done:
		if on_frame.is_valid() and on_frame.call():
			http.cancel()
			return false
		await get_tree().process_frame

	parser.complete()
	var error: NeocortexApiError = state.error
	if error != null:
		if error.cancelled:
			return false
		last_api_error = error
		last_error = error.message
		last_error_code = error.code
		last_response_code = error.status
		if error.status == 404:
			streamed_speech_supported = false
		if report_errors:
			_report_error(error)
		return false

	if parser.is_not_audio():
		if report_errors:
			_fail_message(parser.raw_text if not parser.raw_text.is_empty() else "Speech stream returned no audio.")
		return false
	return parser.is_header_parsed()

# ------------------------------------------------------------------
# ACCOUNT, USAGE, LISTS
# ------------------------------------------------------------------

## Developer account info (tier, masked owner email, credits, next refresh). Read
## only and unmetered. Returns null on failure.
func get_account() -> NeocortexApiAccount:
	var json = await _get_json("/account")
	return NeocortexApiAccount.from_dict(json) if json != null else null

## Team credit status plus optional per-player and per-character usage. An unknown
## player id returns zero usage, not an error. Returns null on failure.
func get_usage(player_id: String = "", character_id: String = "") -> NeocortexApiUsage:
	var query := PackedStringArray()
	if not player_id.is_empty():
		query.append("playerId=%s" % player_id.uri_encode())
	if not character_id.is_empty():
		query.append("characterId=%s" % character_id.uri_encode())
	var path := "/usage" + (("?" + "&".join(query)) if not query.is_empty() else "")
	var json = await _get_json(path)
	return NeocortexApiUsage.from_dict(json) if json != null else null

## The key's team's characters (id and name). Powers the dock's character picker.
## Returns null on failure.
func get_characters(): # Array[NeocortexApiLists.CharacterSummary], or null
	var json = await _get_json("/characters")
	return NeocortexApiLists.characters_from(json) if json != null else null

## The team's question sets (id, name, question count). Returns null on failure.
func get_question_sets(): # Array[NeocortexApiLists.QuestionSetSummary], or null
	var json = await _get_json("/question-sets")
	return NeocortexApiLists.question_sets_from(json) if json != null else null

func _get_json(path: String):
	if not _set_headers():
		return null
	var result := await _send_with_retry({
		"url": get_base_url() + path,
		"method": HTTPClient.METHOD_GET,
		"timeout": LOOKUP_TIMEOUT_SECONDS,
	})
	if not result.ok:
		_report(result)
		return null
	return NeocortexJson.parse_object(result.body)

# ------------------------------------------------------------------
# QUIZ
# ------------------------------------------------------------------

## Starts a quiz and returns its first turn (the host's welcome). Keep the turn's
## session_id and pass it to continue_quiz(). question_count 0 and an empty
## selection_mode use the question set's own settings ("sequential" or "random"
## override the order). Returns null on failure.
func begin_quiz(character_id: String, question_set_id: String, player_id: String = "",
		participants: Array = [], question_count: int = 0, selection_mode: String = "") -> NeocortexQuizTurnResponse:
	if character_id.is_empty():
		_fail_message("Character ID is required.")
		return null
	if question_set_id.is_empty():
		_fail_message("Question Set ID is required.")
		return null
	if not _set_headers():
		return null

	var data := {
		"characterId": character_id,
		"questionSetId": question_set_id,
		"playerId": player_id if not player_id.is_empty() else NeocortexSessionManager.get_player_id(),
	}
	if not participants.is_empty():
		var roster: Array = []
		for participant in participants:
			roster.append(participant.to_dict() if participant is NeocortexQuizParticipant else participant)
		data["participants"] = roster
	if question_count > 0:
		data["questionCount"] = question_count
	if not selection_mode.is_empty():
		data["selectionMode"] = selection_mode

	var result := await send_async({
		"url": "%s/quiz" % get_base_url(),
		"content_type": "application/json",
		"body": get_bytes(data),
		"timeout": TURN_TIMEOUT_SECONDS,
	})
	if not result.ok:
		_report(result)
		return null
	return NeocortexQuizTurnResponse.from_dict(NeocortexJson.parse_object(result.body))

## Sends what the player just did and returns the next turn. Pass speech or typing as
## `say` (null to send nothing, "" to pass on the question), or a tapped choice as
## `option_id`. A 409 quiz_finished replays the closing turn; operation_in_progress
## and state_changed are retried. Returns null on failure.
func continue_quiz(session_id: String, say = null, option_id: String = "",
		participant_id: String = "", typed: bool = false) -> NeocortexQuizTurnResponse:
	if session_id.is_empty():
		_fail_message("Session ID is required.")
		return null
	if not _set_headers():
		return null

	var data := { "sessionId": session_id }
	# An empty string is a deliberate pass, so only a null is left out.
	if say != null:
		data["say"] = str(say)
	if not option_id.is_empty():
		data["optionId"] = option_id
	if not participant_id.is_empty():
		data["participantId"] = participant_id
	# Typed words are judged as written; a misspelling is not a mishearing.
	if typed and say != null and not str(say).is_empty():
		data["typed"] = true

	var body := get_bytes(data)
	var attempt := 0
	while true:
		var result := await send_async({
			"url": "%s/quiz" % get_base_url(),
			"content_type": "application/json",
			"body": body,
			"timeout": TURN_TIMEOUT_SECONDS,
			"handled_codes": PackedStringArray([QUIZ_FINISHED_CODE, OPERATION_IN_PROGRESS_CODE, STATE_CHANGED_CODE]),
		})
		if result.ok:
			return NeocortexQuizTurnResponse.from_dict(NeocortexJson.parse_object(result.body))
		if result.cancelled:
			return null
		if last_response_code != 409:
			_report(result)
			return null

		# The run is over and the server hands back the closing turn it already gave.
		# That is an answer, not a failure: a client whose last response was lost
		# still gets to speak the sign off.
		if last_error_code == QUIZ_FINISHED_CODE:
			var json := NeocortexJson.parse_object(result.body)
			if NeocortexJson.has_dict(json, "turn"):
				return NeocortexQuizTurnResponse.from_dict(json["turn"])
			_report(result)
			return null

		var busy := last_error_code == OPERATION_IN_PROGRESS_CODE
		var moved := last_error_code == STATE_CHANGED_CODE
		if (not busy and not moved) or attempt >= QUIZ_BUSY_RETRIES:
			_report(result)
			return null
		attempt += 1
		if busy:
			await get_tree().create_timer(QUIZ_BUSY_RETRY_DELAY).timeout
	return null

## Reads a quiz run back: the standings, the question on the table and what the host
## is waiting for. Read only and unmetered. Returns null on failure.
func get_quiz_session(session_id: String) -> NeocortexQuizPublicState:
	if session_id.is_empty():
		_fail_message("Session ID is required.")
		return null
	var json = await _get_json("/quiz/session?sessionId=%s" % session_id.uri_encode())
	return NeocortexQuizPublicState.from_session_dict(json) if json != null else null

# ------------------------------------------------------------------
# PERCEPTION
# ------------------------------------------------------------------

## Builds what the character can perceive: every interactable in the scene, nearest
## first and capped, plus the character's own location when perception_origin is set
## and no interactable represents it. Returns a JSON array string, or "" when empty.
func create_metadata(self_character_id: String = "") -> String:
	if not is_inside_tree():
		return ""

	var perceived: Array = []
	for node in get_tree().get_nodes_in_group(NeocortexInteractable.GROUP):
		if node is NeocortexInteractable:
			perceived.append(node)

	if perception_origin != null and is_instance_valid(perception_origin):
		var origin := perception_origin.global_position
		if perception_radius > 0.0:
			perceived = perceived.filter(func(n): return origin.distance_to(n.global_position) <= perception_radius)
		perceived.sort_custom(func(a, b): return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))

	var entities: Array = []
	for node in perceived.slice(0, maxi(1, max_perceived_entities)):
		entities.append(node.to_interactable().to_dict())

	if not self_character_id.is_empty() and perception_origin != null and is_instance_valid(perception_origin):
		var represented := false
		for entity in entities:
			if entity.get("characterId", "") == self_character_id:
				represented = true
				break
		if not represented:
			var self_name := perception_self_name if not perception_self_name.is_empty() else str(perception_origin.name)
			var me := NeocortexInteractableData.new()
			me.id = self_character_id
			me.character_id = self_character_id
			me.name = self_name
			me.position = perception_origin.global_position
			me.properties = [{ "name": "name", "value": self_name }, { "name": "kind", "value": "character" }]
			me.type = "CHARACTER"
			entities.insert(0, me.to_dict())

	return JSON.stringify(entities) if not entities.is_empty() else ""

# ------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------

func _set_headers() -> bool:
	headers.clear()
	var api_key := NeocortexSettings.get_settings().api_key.strip_edges()
	if api_key.is_empty():
		_fail_message("API Key is required. Add it in the Neocortex dock (Project > Neocortex or the right dock).")
		return false
	headers["x-api-key"] = api_key
	return true

func _send_with_retry(payload: Dictionary) -> Dictionary:
	var result := await send_async(payload)
	var attempt := 0
	while not result.ok and not result.cancelled and attempt < retry_attempts \
			and result.error != null and result.error.is_retryable():
		attempt += 1
		await get_tree().create_timer(retry_delay).timeout
		result = await send_async(payload)
	return result

func _open_stream(url: String, body: PackedByteArray, timeout: float, extra_headers: PackedStringArray = PackedStringArray()) -> NeocortexHttpStream:
	var http := NeocortexHttpStream.new()
	http.timeout_seconds = timeout
	add_child(http)
	var request_headers := PackedStringArray(["Content-Type: application/json"])
	for key in headers.keys():
		request_headers.append("%s: %s" % [key, headers[key]])
	request_headers.append_array(extra_headers)
	http.open(url, HTTPClient.METHOD_POST, request_headers, body)
	return http

func _build_multipart(boundary: String, character_id: String, audio: AudioStreamWAV) -> PackedByteArray:
	var body := PackedByteArray()
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array('Content-Disposition: form-data; name="audio"; filename="audio.wav"\r\n'.to_utf8_buffer())
	body.append_array("Content-Type: audio/wav\r\n\r\n".to_utf8_buffer())
	body.append_array(NeocortexAudioUtils.encode_wav(audio))
	body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array('Content-Disposition: form-data; name="characterId"\r\n\r\n'.to_utf8_buffer())
	body.append_array(character_id.to_utf8_buffer())
	body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body

func _report(result: Dictionary) -> void:
	if result.get("cancelled", false):
		return
	var error: NeocortexApiError = result.get("error", null)
	if error == null:
		error = NeocortexApiError.new()
		error.message = "Request failed."
	_report_error(error)

func _report_error(error: NeocortexApiError) -> void:
	last_api_error = error
	last_error = error.message
	last_error_code = error.code
	last_response_code = error.status
	request_error.emit(error)
	request_failed.emit(error.message)

func _fail_message(message: String) -> void:
	var error := NeocortexApiError.new()
	error.message = message
	last_api_error = error
	last_error = message
	last_error_code = ""
	push_error("[Neocortex] %s" % message)
	_report_error(error)
