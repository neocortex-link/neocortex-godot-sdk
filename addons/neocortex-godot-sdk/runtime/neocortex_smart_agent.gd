class_name NeocortexSmartAgent
extends Node

## A Neocortex character: sends messages, speaks the reply as chat lines, and runs the
## actions it triggers.
##
## Set character_id, then call text_to_text(), text_to_audio(), audio_to_text() or
## audio_to_audio(). chat_lines_mode decides how a reply is delivered:
##   PER_LINE_AUDIO  each line is voiced separately (about 1 audio credit per line)
##   SINGLE_AUDIO    lines drop in while one clip voices the whole reply (1 credit)
##   TEXT            lines drop in with an emotion each, no audio
##   OFF             one reply, delivered whole, nothing played for you
## Both audio modes stream speech: the voice starts as it arrives, not when the clip
## is done. In every mode but OFF, input sent while the character is still speaking
## is queued and sent once the reply ends.

@export var character_id: String = ""

@export var chat_lines_mode: NeocortexEnums.ChatLinesMode = NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO

## Where line audio plays: an AudioStreamPlayer, AudioStreamPlayer2D or
## AudioStreamPlayer3D. Falls back to one under this node, and one is created for an
## audio mode when there is none.
@export var audio_player: Node

## Fetch and replay this character's stored conversation (chat_history_received) on ready.
@export var load_history_on_start: bool = false

## Listen through a NeocortexAudioReceiver under (or beside) this node and answer by
## itself. Turn off when a chat UI, a group director or your own script feeds the agent.
@export var auto_voice_input: bool = true

## When a reply's actions run: on arrival, as speech starts, or after the reply is
## spoken. The last two need an audio or TEXT mode; OFF falls back to on arrival.
@export var action_trigger: NeocortexEnums.ActionTrigger = NeocortexEnums.ActionTrigger.WHEN_RESPONSE_RECEIVED

@export_group("Streaming")
## Play speech as it is synthesized (/v3/audio/stream) instead of waiting for whole
## clips. Falls back to whole clips on a server without the endpoint.
@export var stream_speech: bool = true
## EXPERIMENTAL, Godot only: stream the reply itself (/v3/chat/stream), so the first
## line starts while the rest is still being written. Raises text_delta as text arrives.
@export var stream_replies: bool = false

@export_group("Perception")
## Where the character stands, for perception. Defaults to the parent when it is a Node3D.
@export var body: Node3D
## Only perceive interactables within this many metres. 0: unlimited.
@export var perception_radius: float = 0.0
@export var max_perceived_entities: int = 10

signal chat_response_received(response: NeocortexChatResponse)
## A clip of speech: the whole reply in OFF mode, each spoken line otherwise.
signal audio_response_received(audio: AudioStream)
signal transcription_received(text: String)
signal request_failed(error: String)
## The same failures as request_failed, classified (status, code, is_retryable()).
signal request_error(error: NeocortexApiError)
signal chat_history_received(history: Array) # Array[NeocortexChatHistoryEntry]

## A chat line drops in. Add it to your chat panel here.
signal chat_line_started(line: NeocortexChatLine)
## Each line's emotion as it drops in. Drive animation here.
signal emotion_changed(emotion: NeocortexEnums.Emotions)
## TEXT mode: raised during the pause BEFORE the next line, for a typing indicator.
signal composing_next_line
## The whole reply has finished playing.
signal reply_finished
## A reply's actions have all been run.
signal actions_completed
## An action arrived that has no handler registered.
signal unhandled_action(action: NeocortexChatAction)
## stream_replies only: text of the line being written, as it arrives.
signal text_delta(text: String, line_index: int)

enum _ReplyState { IDLE, WAITING_FOR_REPLY, PLAYING }

## Fixed pause between two characters in a group turn.
const GROUP_SPEAKER_GAP := 1.0

var _api_request: ApiRequest
var _voice_input: NeocortexAudioReceiverBase
var _state: _ReplyState = _ReplyState.IDLE
var _pending_inputs: Array[Callable] = []
var _playback_token: int = 0
var _usage_gate: NeocortexUsageGate
var _stream_player: NeocortexStreamingAudioPlayer

var _action_handlers: Dictionary = {} # keyword -> Callable
var _action_queue: Array[NeocortexChatAction] = []
var _actions_running := false
var _warned_off_mode := false
var _debug_line := ""
var _debug_error := ""
var _debug_state := -1

## True while a reply is pending or its chat lines are still being played.
var is_speaking: bool:
	get:
		return _state != _ReplyState.IDLE

## True while the reply's actions are being run.
var is_running_actions: bool:
	get:
		return _actions_running

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if audio_player == null:
		audio_player = _find_audio_player()
	if audio_player == null and _needs_audio(chat_lines_mode):
		audio_player = AudioStreamPlayer.new()
		audio_player.name = "NeocortexVoice"
		add_child(audio_player)

	_api_request = ApiRequest.new()
	_api_request.name = "ApiRequest"
	add_child(_api_request)
	if body == null and get_parent() is Node3D:
		body = get_parent()
	_api_request.perception_origin = body
	_api_request.perception_radius = perception_radius
	_api_request.max_perceived_entities = max_perceived_entities

	_api_request.chat_response_received.connect(_handle_chat_response)
	_api_request.audio_response_received.connect(func(audio): audio_response_received.emit(audio))
	_api_request.transcription_received.connect(func(text): transcription_received.emit(text))
	_api_request.chat_history_received.connect(func(history): chat_history_received.emit(history))
	_api_request.request_error.connect(_handle_request_error)

	# Deferred, so anything that drives the agent itself has had its _ready to opt out.
	_start.call_deferred()

func _start() -> void:
	# An empty session id would be rejected by the server, so only load when one exists.
	if load_history_on_start and not get_session_id().is_empty():
		get_chat_history()
	if auto_voice_input:
		_bind_voice_input()

func _exit_tree() -> void:
	NeocortexDebug.forget(self)
	_playback_token += 1 # cancels any in-flight playback
	_cancel_audio()

# ------------------------------------------------------------------
# PUBLIC API
# ------------------------------------------------------------------

func text_to_text(message: String) -> void:
	_dispatch(func(): _send(message, false))

func text_to_audio(message: String) -> void:
	# In a chat lines mode the agent voices the reply itself, so only text is asked
	# for, rather than also paying for a full reply clip.
	_dispatch(func(): _send(message, chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF))

func audio_to_text(audio: AudioStreamWAV) -> void:
	_dispatch(func(): _send(audio, false))

func audio_to_audio(audio: AudioStreamWAV) -> void:
	_dispatch(func(): _send(audio, chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF))

## Fetches the last messages of this character's session (chat_history_received).
func get_chat_history(limit: int = 10) -> void:
	_api_request.get_chat_history(character_id, limit)

## Fetches this character's history with paging, without raising the signal. Pass the
## previous page's next_cursor as `before` to load older messages.
func request_chat_history(limit: int = 10, before: String = "") -> NeocortexApiChatHistory:
	return await _api_request.request_chat_history(get_session_id(), limit, before)

## Generates one clip for a chat line, voiced in its emotion. Costs 1 audio credit.
func generate_chat_line_audio(line: NeocortexChatLine) -> AudioStream:
	return await _api_request.generate_audio(character_id, line.text, NeocortexEnums.emotion_to_upper(line.emotion), line.spoken_text)

## Assigns what performs an action keyword (as authored on the character's Actions
## node). The handler receives the NeocortexChatAction, whose target_id names the
## interactable it applies to. It may be a coroutine, or return a Signal; the next
## action waits until it is done.
##   agent.register_action("JUMP", func(action): animator.travel("Jump"))
##   agent.register_action("DANCE", func(action): return get_tree().create_timer(2.0).timeout)
func register_action(keyword: String, handler: Callable) -> void:
	_action_handlers[keyword] = handler

func unregister_action(keyword: String) -> void:
	_action_handlers.erase(keyword)

## Speaks a reply produced elsewhere (a NeocortexGroupDirector turn) through this
## character. Awaitable, so a director can let one character finish before the next.
func speak(message: NeocortexGroupMessage) -> void:
	var response := NeocortexChatResponse.from_group_message(message)
	chat_response_received.emit(response)
	_capture_actions(response.actions)

	if chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF:
		return

	_state = _ReplyState.PLAYING
	_playback_token += 1
	var token := _playback_token
	await _play_reply(response.resolve_lines(), token)
	# A beat before the next character speaks.
	await _wait_for_seconds(GROUP_SPEAKER_GAP, _playback_token)

## Stops whatever the character is saying and drops queued input.
func stop_speaking() -> void:
	_playback_token += 1
	_cancel_audio()
	_pending_inputs.clear()
	if _state != _ReplyState.IDLE:
		_state = _ReplyState.IDLE
		reply_finished.emit()

func get_session_id() -> String:
	return NeocortexSessionManager.get_session_id(character_id)

## Forgets the conversation, so the next message starts a new session.
func clean_session_id() -> void:
	NeocortexSessionManager.clean_session_id(character_id)

## The request node this agent uses, for the endpoints it does not wrap.
func get_api_request() -> ApiRequest:
	return _api_request

# ------------------------------------------------------------------
# DISPATCH
# ------------------------------------------------------------------

# Sends immediately in OFF mode. In a chat lines mode, queues the input while the
# character is still speaking so nothing is submitted mid reply.
func _dispatch(send: Callable) -> void:
	if chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF:
		send.call()
		return
	if _state != _ReplyState.IDLE:
		_pending_inputs.append(send)
		return
	_state = _ReplyState.WAITING_FOR_REPLY
	send.call()

func _dispatch_next() -> void:
	if _pending_inputs.is_empty():
		return
	var next: Callable = _pending_inputs.pop_front()
	_state = _ReplyState.WAITING_FOR_REPLY
	next.call()

func _send(input: Variant, produce_audio: bool) -> void:
	if stream_replies:
		_send_streamed(input)
		return
	if input is AudioStreamWAV:
		if produce_audio:
			_api_request.send_audio_to_audio(character_id, input)
		else:
			_api_request.send_audio_to_text(character_id, input)
	elif produce_audio:
		_api_request.send_text_to_audio(character_id, str(input))
	else:
		_api_request.send_text_to_text(character_id, str(input))

# ------------------------------------------------------------------
# RESPONSES
# ------------------------------------------------------------------

func _handle_chat_response(response: NeocortexChatResponse) -> void:
	chat_response_received.emit(response)
	_capture_actions(response.actions)

	if chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF:
		return

	_state = _ReplyState.PLAYING
	_playback_token += 1
	_play_reply(response.resolve_lines(), _playback_token)

func _handle_request_error(error: NeocortexApiError) -> void:
	_debug_error = "%s%s" % [error.message, (" [%s]" % error.code) if not error.code.is_empty() else ""]
	_report_debug()
	request_error.emit(error)
	request_failed.emit(error.message)

	# A failed turn must not leave the mic closed, or the character goes deaf.
	_rearm_microphone()

	# Only a failure before playback unblocks the queue; a line's audio failing during
	# playback is handled inline (the text still shows, playback advances).
	if chat_lines_mode != NeocortexEnums.ChatLinesMode.OFF and _state == _ReplyState.WAITING_FOR_REPLY:
		_state = _ReplyState.IDLE
		_playback_token += 1
		_dispatch_next()

# ------------------------------------------------------------------
# PLAYBACK
# ------------------------------------------------------------------

func _play_reply(lines: Array[NeocortexChatLine], token: int) -> void:
	# A previous reply's speech must not outlive the reply that replaced it.
	_cancel_audio()

	match chat_lines_mode:
		NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO:
			await _play_per_line_audio(lines, token)
		NeocortexEnums.ChatLinesMode.SINGLE_AUDIO:
			await _play_single_audio(lines, token)
		_:
			await _drop_lines(lines, token)
	if _is_current(token):
		_finish_reply(token)

func _play_single_audio(lines: Array[NeocortexChatLine], token: int) -> void:
	if audio_player == null:
		push_warning("[Neocortex] SINGLE_AUDIO needs an audio_player. Showing text only (no credits spent).")
		await _drop_lines(lines, token)
		return
	if await _is_out_of_credits(token):
		if _is_current(token):
			await _drop_lines(lines, token)
		return
	await _play_one_clip_and_drop(lines, token)

func _play_per_line_audio(lines: Array[NeocortexChatLine], token: int) -> void:
	if audio_player == null:
		push_warning("[Neocortex] PER_LINE_AUDIO needs an audio_player. Showing text only (no credits spent).")
		await _drop_lines(lines, token)
		return

	# Credit aware: empty means text only, low means one clip for the whole reply.
	var usage := await _get_usage()
	if not _is_current(token):
		return
	if usage != null and usage.status == NeocortexEnums.UsageStatus.EMPTY:
		await _drop_lines(lines, token)
		return
	if usage != null and usage.status == NeocortexEnums.UsageStatus.LOW:
		await _play_one_clip_and_drop(lines, token)
		return

	for line in lines:
		if not _is_current(token):
			return
		await _speak_line(line, token)

# Voices one line, streamed when possible, announcing it as the voice starts.
func _speak_line(line: NeocortexChatLine, token: int) -> void:
	var spoke := await _speak_streamed(line, token, func(): _begin_line(line))
	if _is_current(token) and not spoke:
		await _speak_buffered(line, token, true)

# Speaks the whole reply as one piece of audio while the lines drop in on top of it,
# holding the speaking state until it ends so queued input does not cut in.
func _play_one_clip_and_drop(lines: Array[NeocortexChatLine], token: int) -> void:
	var whole := NeocortexChatLine.create(_join_text(lines), lines[0].emotion, _join_spoken(lines))
	var job := { "done": false, "spoke": false }
	_speak_job(whole, token, job)

	# The voice covers the gap, so no typing cue while the character speaks.
	await _drop_lines(lines, token, false)
	while _is_current(token) and not job.done:
		await get_tree().process_frame
	if _is_current(token) and not job.spoke:
		await _speak_buffered(whole, token, false)

func _speak_job(line: NeocortexChatLine, token: int, job: Dictionary) -> void:
	job.spoke = await _speak_streamed(line, token, Callable())
	job.done = true

# The pre streaming path, kept as the fallback for an older server or a failed
# stream: fetch the whole clip, then play it.
func _speak_buffered(line: NeocortexChatLine, token: int, announce: bool) -> void:
	if announce:
		_begin_line(line)
	var clip := await generate_chat_line_audio(line)
	if not _is_current(token) or clip == null:
		return
	audio_response_received.emit(clip)
	await _play_clip(clip, token)

## Voices one line, playing it as it is synthesized. Returns false when nothing was
## spoken, so the caller can fall back to a whole clip.
func _speak_streamed(line: NeocortexChatLine, token: int, on_started: Callable) -> bool:
	if audio_player == null or not stream_speech or not ApiRequest.streamed_speech_supported:
		return false
	if await _is_out_of_credits(token) or not _is_current(token):
		return false

	var player := NeocortexStreamingAudioPlayer.new(audio_player)
	_stream_player = player
	var state := { "announced": false }
	var announce := func():
		if player.has_started() and not state.announced:
			state.announced = true
			if on_started.is_valid():
				on_started.call()

	await _api_request.generate_audio_stream(
		character_id, line.speech_text(), NeocortexEnums.emotion_to_upper(line.emotion), player,
		# Recoverable: the caller falls back to a whole clip, which reports if it fails too.
		false,
		func():
			if _is_current(token):
				player.tick()
				announce.call()
			return not _is_current(token))

	if not _is_current(token):
		player.stop()
		return state.announced

	# Audio short enough to arrive in one go never started during the download.
	player.complete()
	player.tick()
	announce.call()
	if not player.has_started():
		return false

	await player.wait_until_finished(get_tree(), func(): return _is_current(token))
	if not _is_current(token):
		return true

	# A clip for listeners that want the whole line, lip sync among them.
	var finished := player.to_wav()
	if finished != null:
		audio_response_received.emit(finished)
	return true

# Drops each line in, pausing a reading time estimate between them so the reply
# arrives at a natural pace instead of all at once.
func _drop_lines(lines: Array[NeocortexChatLine], token: int, signal_composing: bool = true) -> void:
	for i in lines.size():
		if not _is_current(token):
			return
		_begin_line(lines[i])
		if i < lines.size() - 1:
			if signal_composing:
				composing_next_line.emit()
			await _wait_for_seconds(_line_delay(lines[i].text), token)

static func _line_delay(text: String) -> float:
	return clampf(text.length() / 15.0, 0.5, 3.0)

func _begin_line(line: NeocortexChatLine) -> void:
	_debug_line = "%s (%s)" % [line.text, NeocortexEnums.emotion_to_string(line.emotion)]
	_report_debug()
	chat_line_started.emit(line)
	emotion_changed.emit(line.emotion)
	if action_trigger == NeocortexEnums.ActionTrigger.WHEN_SPEECH_STARTS:
		_run_pending_actions()

func _finish_reply(token: int) -> void:
	if token != _playback_token:
		return
	_state = _ReplyState.IDLE
	reply_finished.emit()
	if action_trigger == NeocortexEnums.ActionTrigger.AFTER_REPLY_SPOKEN:
		_run_pending_actions()
	_rearm_microphone()
	_dispatch_next()

# ------------------------------------------------------------------
# STREAMED REPLIES (Godot only, experimental)
# ------------------------------------------------------------------

func _send_streamed(input: Variant) -> void:
	var message := ""
	if input is AudioStreamWAV:
		message = await _api_request.request_transcription(character_id, input)
		if message.is_empty():
			return # request_failed already raised and handled
		transcription_received.emit(message)
	else:
		message = str(input)

	_playback_token += 1
	var token := _playback_token
	var lines: Array[NeocortexChatLine] = []
	var feed := { "done": false, "failed": false, "response": null }

	var stream := _api_request.request_chat_stream(
		PackedStringArray([character_id]), get_session_id(), message, "", 0, null, null, character_id, false)
	stream.session_started.connect(func(session_id: String):
		if not session_id.is_empty():
			NeocortexSessionManager.set_session_id(character_id, session_id))
	stream.text_delta.connect(func(_id: String, text: String, index: int): text_delta.emit(text, index))
	stream.line_completed.connect(func(_id: String, line: NeocortexChatLine): lines.append(line))
	stream.completed.connect(func(turn: NeocortexGroupChatResponse):
		var speaker: NeocortexGroupMessage = turn.messages[0] if not turn.messages.is_empty() else null
		var response := NeocortexChatResponse.from_group_message(speaker, turn.metadata)
		response.session_id = turn.session_id
		if not turn.session_id.is_empty():
			NeocortexSessionManager.set_session_id(character_id, turn.session_id)
		feed.response = response
		feed.done = true)
	stream.failed.connect(func(error: NeocortexApiError):
		feed.failed = true
		feed.done = true
		if not error.cancelled:
			_handle_request_error(error))

	# OFF and SINGLE_AUDIO need the whole reply; the others play lines as they land.
	var progressive := chat_lines_mode == NeocortexEnums.ChatLinesMode.TEXT \
		or chat_lines_mode == NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO
	var played := 0
	var usage_checked := false
	var text_only := audio_player == null

	while _is_current(token):
		if progressive and played < lines.size():
			if _state == _ReplyState.WAITING_FOR_REPLY:
				_state = _ReplyState.PLAYING
				_cancel_audio()
			var line := lines[played]
			played += 1
			if chat_lines_mode == NeocortexEnums.ChatLinesMode.TEXT or text_only:
				if played > 1:
					composing_next_line.emit()
					await _wait_for_seconds(_line_delay(lines[played - 2].text), token)
				_begin_line(line)
			else:
				if not usage_checked:
					usage_checked = true
					var usage := await _get_usage()
					text_only = usage != null and usage.status == NeocortexEnums.UsageStatus.EMPTY
					if text_only:
						_begin_line(line)
						continue
				await _speak_line(line, token)
			continue
		if feed.done:
			break
		await get_tree().process_frame

	if not _is_current(token):
		return
	if feed.failed:
		# Lines already played: the reply ends here rather than hanging mid way.
		if _state == _ReplyState.PLAYING:
			_finish_reply(token)
		return

	var response: NeocortexChatResponse = feed.response
	chat_response_received.emit(response)
	_capture_actions(response.actions)

	if chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF:
		return
	if not progressive:
		_state = _ReplyState.PLAYING
		await _play_reply(response.resolve_lines(), token)
		return
	# Lines the stream never sent separately (an older server) still get played.
	if played == 0:
		await _play_reply(response.resolve_lines(), token)
		return
	_finish_reply(token)

# ------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------

# Queues a reply's actions in order, then runs them now or waits for the trigger.
func _capture_actions(actions: Array[NeocortexChatAction]) -> void:
	for action in actions:
		if action != null and not action.name.is_empty():
			_action_queue.append(action)

	var deferred := action_trigger != NeocortexEnums.ActionTrigger.WHEN_RESPONSE_RECEIVED
	# The deferred triggers wait for a playback event OFF mode never raises.
	if deferred and chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF:
		if not _warned_off_mode:
			_warned_off_mode = true
			push_warning("[Neocortex] action_trigger fires on speech, but chat_lines_mode is OFF and raises no speech events. Running actions on arrival instead.")
		deferred = false
	if not deferred:
		_run_pending_actions()

# Safe to call more than once; the running and empty guards make it a no-op.
func _run_pending_actions() -> void:
	if not _actions_running and not _action_queue.is_empty():
		_process_actions()

func _process_actions() -> void:
	_actions_running = true
	while not _action_queue.is_empty():
		var action: NeocortexChatAction = _action_queue.pop_front()
		if _action_handlers.has(action.name):
			var handler: Callable = _action_handlers[action.name]
			var result = await handler.call(action)
			if result is Signal:
				await result
		else:
			unhandled_action.emit(action)
			push_warning("[Neocortex] %s asked for action '%s', which has no handler. Register one with register_action()." % [name, action.name])
		if not is_inside_tree():
			return
	_actions_running = false
	actions_completed.emit()

# ------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _state != _debug_state:
		_report_debug()

# What this agent is doing, for the editor's Debugger > Neocortex tab.
func _report_debug() -> void:
	_debug_state = _state
	if not NeocortexDebug.is_active():
		return
	NeocortexDebug.report("agent", self, {
		"character_id": character_id,
		"mode": NeocortexEnums.ChatLinesMode.keys()[chat_lines_mode],
		"state": _ReplyState.keys()[_state],
		"queued": _pending_inputs.size(),
		"line": _debug_line,
		"error": _debug_error,
		"session": get_session_id(),
	})

func _is_current(token: int) -> bool:
	return is_inside_tree() and token == _playback_token

func _get_usage() -> NeocortexApiUsage:
	if _usage_gate == null:
		_usage_gate = NeocortexUsageGate.new(self)
	return await _usage_gate.get_usage_cached("", character_id)

# True only when usage positively reports an empty balance; an unknown or failed
# lookup returns false so a hiccup never blocks a paid feature.
func _is_out_of_credits(token: int) -> bool:
	var usage := await _get_usage()
	if not _is_current(token):
		return false
	return usage != null and usage.status == NeocortexEnums.UsageStatus.EMPTY

func _play_clip(clip: AudioStream, token: int) -> void:
	audio_player.stream = clip
	audio_player.play()
	# A deadline as well as `playing`: a paused tree or a muted bus can leave that
	# flag stuck, which would hang the whole reply.
	var deadline := Time.get_ticks_msec() + int((clip.get_length() + 0.25) * 1000.0)
	while _is_current(token) and is_instance_valid(audio_player) and audio_player.playing \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _wait_for_seconds(seconds: float, token: int) -> void:
	var end_time := Time.get_ticks_msec() + int(seconds * 1000.0)
	while _is_current(token) and Time.get_ticks_msec() < end_time:
		await get_tree().process_frame

# Silences anything playing; in-flight downloads stop on the token change.
func _cancel_audio() -> void:
	if _stream_player != null:
		_stream_player.stop()
		_stream_player = null
	if is_instance_valid(audio_player) and audio_player.playing:
		audio_player.stop()

static func _join_text(lines: Array[NeocortexChatLine]) -> String:
	var text := ""
	for line in lines:
		text += line.text
	return text

static func _join_spoken(lines: Array[NeocortexChatLine]) -> String:
	var text := ""
	for line in lines:
		text += line.speech_text()
	return text

static func _needs_audio(mode: NeocortexEnums.ChatLinesMode) -> bool:
	return mode == NeocortexEnums.ChatLinesMode.SINGLE_AUDIO or mode == NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO

func _find_audio_player() -> Node:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D or child is AudioStreamPlayer3D:
			return child
	return null

# ------------------------------------------------------------------
# VOICE INPUT
# ------------------------------------------------------------------

# Hooks a microphone under or beside this node straight into the agent, so an agent
# on its own can hear the player and answer with nothing else involved.
func _bind_voice_input() -> void:
	_voice_input = _find_receiver(self)
	if _voice_input == null and get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is NeocortexAudioReceiverBase:
				_voice_input = sibling
				break
	if _voice_input == null:
		return
	_voice_input.audio_recorded.connect(audio_to_audio)
	_rearm_microphone()

static func _find_receiver(root: Node) -> NeocortexAudioReceiverBase:
	for child in root.get_children():
		if child is NeocortexAudioReceiverBase:
			return child
		var nested := _find_receiver(child)
		if nested != null:
			return nested
	return null

# Voice activity mode listens continuously; push to talk re-arms on its button.
func _rearm_microphone() -> void:
	if _voice_input != null and is_instance_valid(_voice_input) and not _voice_input.use_push_to_talk:
		_voice_input.start_microphone()
