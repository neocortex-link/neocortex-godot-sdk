class_name NeocortexQuizAgent
extends Node

## Runs a quiz, a game show or a spoken test hosted by one of your characters.
##
## Point it at a character and a question set and call begin(). After that the only
## thing a game does is hand over what the player said, with say() or choose().
## Question order, retries, hints, scoring and when the run ends are decided on the
## server from the question set.
##
## Listen to question_changed to build the scene and upcoming_question to prepare the
## next one while the host is still talking.

enum QuestionOrder { SET_DEFAULT, IN_ORDER, SHUFFLED }

## The character that hosts the quiz.
@export var character_id: String = ""
## The question set to play. Create one under Question Sets in the dashboard.
@export var question_set_id: String = ""
## Questions in one run. 0 uses the question set's count.
@export_range(0, 100) var question_count: int = 0
@export var question_order: QuestionOrder = QuestionOrder.SET_DEFAULT
## Your own id for this player. Empty uses the device's player id.
@export var player_id: String = ""
## Everyone playing, in a game with more than one player. Empty for one player.
@export var participants: Array[NeocortexQuizParticipant] = []
## Start the quiz as soon as the scene runs.
@export var begin_on_start: bool = false
## Speak the host's lines out loud in the character's voice.
@export var speak_host_lines: bool = true
## Play each line as its voice arrives. Falls back to whole clips on an older server.
@export var stream_host_speech: bool = true
## Where the host's voice plays. One is created when speaking and none is assigned.
@export var audio_player: Node

@export_group("Input")
## Hold what the player says while the host is busy, and send it once it is ready.
@export var queue_input_while_busy: bool = true
## How long a held answer stays worth sending, in seconds.
@export var max_pending_input_age: float = 4.0

## Each line the host says, as it starts, with the emotion to play it in.
signal host_line(line: NeocortexQuizLine)
signal emotion_changed(emotion: NeocortexEnums.Emotions)
## The host has finished speaking this turn.
signal host_finished
## Raised as the host starts asking, so the scene is set on the right line.
signal question_changed(question: NeocortexQuizQuestion)
## The question after this one, so its scene can be loaded early.
signal upcoming_question(upcoming: NeocortexQuizTurnResponse.Upcoming)
## What the game should collect next. Open the microphone on anything but NOTHING.
signal expecting_changed(expecting: NeocortexEnums.QuizExpecting)
## A turn judged an answer. Array of NeocortexQuizTurnResponse.Result.
signal result(results: Array)
## The standings changed. Array of NeocortexQuizTurnResponse.LeaderboardEntry.
signal leaderboard_changed(leaderboard: Array)
## The whole turn, if you would rather read it yourself.
signal turn_received(turn: NeocortexQuizTurnResponse)
## The host has signed off, with the final standings.
signal quiz_finished(leaderboard: Array)
## True while a turn is in flight. Drive a spinner here.
signal busy_changed(busy: bool)
## The players the round is still waiting on, whenever that changes.
signal pending_changed(pending: PackedStringArray)
## Something the player said that never reached the host, and why.
signal input_dropped(text: String, reason: NeocortexEnums.QuizInputDropReason)
signal request_failed(error: String)
signal request_error(error: NeocortexApiError)
## Credits ran out (the error code). Input stays closed until resync().
signal credits_exhausted(code: String)

## The run in progress, or "" before begin().
var session_id: String = ""
## The question on the table, or null before the quiz starts and once it ends.
var current_question: NeocortexQuizQuestion = null
## Which question is on the table and how many there are.
var progress := NeocortexQuizTurnResponse.Progress.new()
## What the game should be collecting right now.
var expecting: NeocortexEnums.QuizExpecting = NeocortexEnums.QuizExpecting.NOTHING
## True while a turn is in flight. Ignore player input until it clears.
var is_busy: bool = false
## True once the host has signed off.
var is_finished: bool = false
## Players the round is still waiting on, in roster order. Empty with one player.
var pending_participants := PackedStringArray()
## Players who have answered this round. Empty with one player.
var answered_participants := PackedStringArray()
## Which attempt at the open question this is, from 1. One player only.
var attempt: int = 0
## How many more goes the open question allows. One player only.
var attempts_left: int = 0
var hint_given: bool = false
## How the host read the last thing said.
var last_intent: NeocortexEnums.QuizIntent = NeocortexEnums.QuizIntent.UNCLEAR

var _api_request: ApiRequest
# Every point that resumes after an await checks this, so a turn abandoned by a
# restart, a scene change or a freed host stops there.
var _turn_token: int = 0
# One held input per player, oldest first.
var _pending: Array[Dictionary] = []
var _last_emotion: NeocortexEnums.Emotions = NeocortexEnums.Emotions.NEUTRAL
var _emotion_raised := false
var _stream_player: NeocortexStreamingAudioPlayer

## The API error code of the last failed request, or "" for a transport failure.
var last_error_code: String:
	get:
		return _api_request.last_error_code if _api_request != null else ""

func _ready() -> void:
	_api_request = ApiRequest.new()
	_api_request.name = "ApiRequest"
	add_child(_api_request)
	_api_request.request_error.connect(func(error: NeocortexApiError):
		request_error.emit(error)
		request_failed.emit(error.message))

	if speak_host_lines and audio_player == null:
		for child in get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer2D or child is AudioStreamPlayer3D:
				audio_player = child
				break
		if audio_player == null:
			audio_player = AudioStreamPlayer.new()
			audio_player.name = "HostVoice"
			add_child(audio_player)

	if begin_on_start:
		begin.call_deferred()

func _exit_tree() -> void:
	_turn_token += 1
	if _api_request != null:
		_api_request.abort()
	_stop_speaking()

## Starts the quiz. The host welcomes the players and asks the first question. Pass a
## roster (NeocortexQuizParticipant) to replace `participants`.
func begin(players: Array = []) -> void:
	if not players.is_empty():
		participants.clear()
		for player in players:
			if player is NeocortexQuizParticipant:
				participants.append(player)

	# Starting again is fair; two runs answering into one scene is not.
	abort()

	is_finished = false
	current_question = null
	progress = NeocortexQuizTurnResponse.Progress.new()
	_emotion_raised = false
	_set_round(PackedStringArray(), PackedStringArray(), 0, 0, false)

	var mode := ""
	match question_order:
		QuestionOrder.IN_ORDER:
			mode = "sequential"
		QuestionOrder.SHUFFLED:
			mode = "random"
	_run_turn(func(): return await _api_request.begin_quiz(character_id, question_set_id, player_id, participants, question_count, mode))

## Abandons whatever is in flight and silences the host, without ending the run on
## the server. resync() picks the session up again.
func abort() -> void:
	_turn_token += 1
	if _api_request != null:
		_api_request.abort()
	_stop_speaking()
	_drop_pending(NeocortexEnums.QuizInputDropReason.SUPERSEDED)
	_set_busy(false)
	_set_expecting(NeocortexEnums.QuizExpecting.NOTHING)

## Hands the host what the player said, from speech to text or a text box. An empty
## string is a deliberate pass (no credit). Do NOT send an empty transcription this
## way. A typed answer is judged as written: a misspelling is not a mishearing.
func say(text: String, typed: bool = false) -> void:
	_send({ "text": text, "typed": typed })

## Hands the host a tapped choice, for a multiple choice or true or false question.
func choose(option_id: String) -> void:
	_send({ "option_id": option_id })

## say(), naming which player spoke in a multi player game.
func say_as(participant_id: String, text: String, typed: bool = false) -> void:
	_send({ "text": text, "participant_id": participant_id, "typed": typed })

## choose(), naming which player tapped in a multi player game.
func choose_as(participant_id: String, option_id: String) -> void:
	_send({ "option_id": option_id, "participant_id": participant_id })

## The player gives no answer: time ran out, or they skipped. Your game owns the timer.
func pass_turn() -> void:
	say("")

## pass_turn() for one player of a multi player game.
func pass_as(participant_id: String) -> void:
	say_as(participant_id, "")

## Reads the run back from the server and puts this agent in step with it, after a
## turn whose response never arrived. Whatever was said on the lost turn is not resent.
func resync() -> void:
	if session_id.is_empty():
		return

	_turn_token += 1
	var token := _turn_token
	_set_busy(true)

	var state := await _api_request.get_quiz_session(session_id)
	if not _is_current(token):
		return

	if state != null:
		is_finished = state.is_finished()
		current_question = state.active_question
		_set_round(state.pending_participant_ids, state.answered_participant_ids,
			state.attempt, state.attempts_left, state.hint_given)
		progress = NeocortexQuizTurnResponse.Progress.new()
		progress.asked = maxi(0, state.total_questions - state.questions_remaining)
		progress.total = state.total_questions
		if not state.leaderboard.is_empty():
			leaderboard_changed.emit(state.leaderboard)
		if current_question != null:
			question_changed.emit(current_question)
		if is_finished:
			quiz_finished.emit(state.leaderboard)

	_set_busy(false)
	# Last, so a game reopening input on this signal finds the agent settled.
	_set_expecting(state.expecting if state != null else NeocortexEnums.QuizExpecting.NOTHING)

# ------------------------------------------------------------------
# TURNS
# ------------------------------------------------------------------

static func _spoken(input: Dictionary) -> String:
	if input.has("text"):
		return str(input.text)
	return str(input.get("option_id", ""))

func _send(input: Dictionary) -> void:
	input["at"] = Time.get_ticks_msec()

	if session_id.is_empty():
		request_failed.emit("Call begin() before sending answers to the quiz.")
		input_dropped.emit(_spoken(input), NeocortexEnums.QuizInputDropReason.NO_SESSION)
		return
	if is_finished:
		request_failed.emit("This quiz has already finished.")
		input_dropped.emit(_spoken(input), NeocortexEnums.QuizInputDropReason.FINISHED)
		return

	if is_busy:
		if not queue_input_while_busy:
			input_dropped.emit(_spoken(input), NeocortexEnums.QuizInputDropReason.BUSY)
			return
		# Last one wins, per player: "triangle... TRIANGLE" is one answer, and the
		# freshest words aim at what the host has just asked.
		var who := str(input.get("participant_id", ""))
		for i in _pending.size():
			if str(_pending[i].get("participant_id", "")) == who:
				input_dropped.emit(_spoken(_pending[i]), NeocortexEnums.QuizInputDropReason.SUPERSEDED)
				_pending.remove_at(i)
				break
		_pending.append(input)
		return

	var say_value = input.get("text", null)
	var option_id := str(input.get("option_id", ""))
	var participant_id := str(input.get("participant_id", ""))
	var typed := bool(input.get("typed", false))
	_run_turn(func(): return await _api_request.continue_quiz(session_id, say_value, option_id, participant_id, typed))

## Runs one turn from end to end: busy on, request, apply, busy off.
func _run_turn(request: Callable) -> void:
	_turn_token += 1
	var token := _turn_token

	_set_busy(true)
	# Nothing is collected while a turn is in the air.
	_set_expecting(NeocortexEnums.QuizExpecting.NOTHING)

	var turn: NeocortexQuizTurnResponse = await request.call()
	if not _is_current(token):
		return

	if turn != null:
		await _apply(turn, token)
		if not _is_current(token):
			return
		_set_busy(false)
		_flush_pending()
		return

	_set_busy(false)
	_drop_pending(NeocortexEnums.QuizInputDropReason.FAILED)
	# Resyncing would reopen input into the same refusal.
	var code := last_error_code
	if NeocortexApiError.CREDIT_CODES.has(code):
		_set_expecting(NeocortexEnums.QuizExpecting.NOTHING)
		credits_exhausted.emit(code)
	elif _api_request.was_cancelled:
		return
	else:
		resync()

func _flush_pending() -> void:
	if _pending.is_empty():
		return
	var next: Dictionary = _pending.pop_front()

	if is_finished or expecting == NeocortexEnums.QuizExpecting.NOTHING:
		input_dropped.emit(_spoken(next), NeocortexEnums.QuizInputDropReason.FINISHED)
		return
	# An answer to a question the host has since moved past is worse than none.
	if Time.get_ticks_msec() - int(next.at) > int(max_pending_input_age * 1000.0):
		input_dropped.emit(_spoken(next), NeocortexEnums.QuizInputDropReason.EXPIRED)
		return
	_send(next)

func _drop_pending(reason: NeocortexEnums.QuizInputDropReason) -> void:
	var dropped := _pending.duplicate()
	_pending.clear()
	for held in dropped:
		input_dropped.emit(_spoken(held), reason)

func _set_round(waiting_on: PackedStringArray, answered: PackedStringArray, attempt_number: int, left: int, hint: bool) -> void:
	answered_participants = answered
	attempt = attempt_number
	attempts_left = left
	hint_given = hint
	if pending_participants == waiting_on:
		return
	pending_participants = waiting_on
	pending_changed.emit(waiting_on)

func _apply(turn: NeocortexQuizTurnResponse, token: int, resumed_from_welcome: bool = false) -> void:
	if not turn.session_id.is_empty():
		session_id = turn.session_id
	last_intent = turn.intent
	_set_round(turn.pending, turn.answered, turn.attempt, turn.attempts_left, turn.hint_given)
	turn_received.emit(turn)

	# A turn carries the question only when it changes; its arrival IS the change.
	var question_changed_now := turn.question != null
	if question_changed_now:
		current_question = turn.question
		if turn.progress != null:
			progress = turn.progress
	elif turn.done:
		current_question = null
		if turn.progress != null:
			progress = turn.progress

	if turn.upcoming != null:
		upcoming_question.emit(turn.upcoming)
	if not turn.result.is_empty():
		result.emit(turn.result)
	if not turn.leaderboard.is_empty():
		leaderboard_changed.emit(turn.leaderboard)

	# Over the moment the turn says so, even while the sign off is still spoken.
	is_finished = turn.done

	# The welcome: the host greeted the players and the first question comes next. It
	# is asked for NOW, while the greeting plays. What marks the welcome is that the
	# player has nothing to do yet (expecting NOTHING); a retry offer or a clue also
	# arrives without a question but expects an answer. resumed_from_welcome stops a
	# server that keeps answering with no question from looping.
	var is_welcome := not turn.done and turn.question == null \
		and turn.expecting == NeocortexEnums.QuizExpecting.NOTHING and not resumed_from_welcome
	var up_next := { "done": false, "turn": null }
	if is_welcome:
		_fetch_next_turn(up_next)

	await _speak_lines(turn.lines, turn.question if question_changed_now else null, token)
	if not _is_current(token):
		return
	host_finished.emit()

	if is_welcome:
		while not up_next.done:
			await get_tree().process_frame
			if not _is_current(token):
				return
		if up_next.turn != null:
			await _apply(up_next.turn, token, true)
			return
		# The greeting was spoken but the question never came: read the run back.
		resync()
		return

	if turn.done:
		quiz_finished.emit(turn.leaderboard)
		return
	_set_expecting(turn.expecting)

func _fetch_next_turn(job: Dictionary) -> void:
	job.turn = await _api_request.continue_quiz(session_id)
	job.done = true

func _set_busy(next: bool) -> void:
	if is_busy == next:
		return
	is_busy = next
	busy_changed.emit(next)

func _set_expecting(next: NeocortexEnums.QuizExpecting) -> void:
	if expecting == next:
		return
	expecting = next
	expecting_changed.emit(next)

func _raise_emotion(emotion: NeocortexEnums.Emotions) -> void:
	if _emotion_raised and _last_emotion == emotion:
		return
	_emotion_raised = true
	_last_emotion = emotion
	emotion_changed.emit(emotion)

func _is_current(token: int) -> bool:
	return is_inside_tree() and token == _turn_token

# ------------------------------------------------------------------
# HOST SPEECH
# ------------------------------------------------------------------

# Says the lines in order, putting the new question on screen as the line that asks
# it begins. If no line claims to be the question, the scene is set before the first
# line rather than never. Each line's speech is requested while the line before it
# still plays, so the gap between two lines is a frame, not a round trip.
func _speak_lines(lines: Array[NeocortexQuizLine], pending_question: NeocortexQuizQuestion, token: int) -> void:
	var ctx := { "question": pending_question }

	var spoken: Array[NeocortexQuizLine] = []
	var any_asks := false
	for line in lines:
		if line == null or line.text.is_empty():
			continue
		if line.is_question():
			any_asks = true
		spoken.append(line)
	if not any_asks:
		_reveal_question(ctx)

	var voicing := speak_host_lines and audio_player != null and not character_id.is_empty()
	var next: Dictionary = _request_speech(spoken[0], token) if voicing and not spoken.is_empty() else {}

	for i in spoken.size():
		var line := spoken[i]
		var speech := next
		next = {}
		var begun := { "started": false }

		# Raised as the line becomes audible, so caption and voice are one event. The
		# next line is asked for here, so it never competes with this one's first sound.
		var begin_line := func():
			if begun.started:
				return
			begun.started = true
			if voicing and i + 1 < spoken.size():
				begun["next"] = _request_speech(spoken[i + 1], token)
			if line.is_question():
				_reveal_question(ctx)
			host_line.emit(line)
			_raise_emotion(line.emotion)

		if not speech.is_empty():
			await _play_speech(speech, token, begin_line)
		if not _is_current(token):
			if begun.has("next"):
				_discard_speech(begun.next)
			return
		begin_line.call()
		next = begun.get("next", {})

	_reveal_question(ctx)

func _reveal_question(ctx: Dictionary) -> void:
	if ctx.question == null:
		return
	var question: NeocortexQuizQuestion = ctx.question
	ctx.question = null
	question_changed.emit(question)

# One line's voice, asked for before the line is due: streamed, or a whole clip.
func _request_speech(line: NeocortexQuizLine, token: int) -> Dictionary:
	var speech := { "line": line, "player": null, "stream_done": false, "stream_ok": false,
		"clip": null, "clip_done": false, "clip_started": false }
	if stream_host_speech and ApiRequest.streamed_speech_supported:
		speech.player = NeocortexStreamingAudioPlayer.new(audio_player)
		_stream_job(speech, token)
	else:
		_clip_job(speech, token)
	return speech

func _stream_job(speech: Dictionary, token: int) -> void:
	var line: NeocortexQuizLine = speech.line
	speech.stream_ok = await _api_request.generate_audio_stream(
		character_id, line.speech_text(), NeocortexEnums.emotion_to_upper(line.emotion), speech.player,
		# Recoverable: the line falls back to a whole clip, which reports if it fails too.
		false,
		func(): return not _is_current(token))
	speech.stream_done = true

func _clip_job(speech: Dictionary, token: int) -> void:
	speech.clip_started = true
	var line: NeocortexQuizLine = speech.line
	speech.clip = await _api_request.generate_audio(character_id, line.text, NeocortexEnums.emotion_to_upper(line.emotion), line.spoken_text)
	speech.clip_done = true

# Plays one line, calling on_start as it becomes audible.
func _play_speech(speech: Dictionary, token: int, on_start: Callable) -> void:
	if speech.player != null:
		if await _play_streamed(speech, token, on_start) or not _is_current(token):
			return
		# Nothing arrived, so the line is fetched whole instead.
		_clip_job(speech, token)

	while not speech.clip_done:
		if not _is_current(token):
			return
		await get_tree().process_frame
	if not _is_current(token) or speech.clip == null:
		return

	on_start.call()
	var clip: AudioStream = speech.clip
	audio_player.stream = clip
	audio_player.play()
	# A deadline as well as `playing`, so a paused tree cannot hang the turn.
	var deadline := Time.get_ticks_msec() + int((clip.get_length() + 0.25) * 1000.0)
	while _is_current(token) and audio_player.playing and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

# False when no audio arrived at all, so the caller can fall back.
func _play_streamed(speech: Dictionary, token: int, on_start: Callable) -> bool:
	var player: NeocortexStreamingAudioPlayer = speech.player
	_stream_player = player

	while not speech.stream_done:
		if not _is_current(token):
			return true
		player.tick()
		if player.has_started():
			on_start.call()
		await get_tree().process_frame
	if not _is_current(token):
		return true

	# A stream that ends early still plays what it delivered.
	player.complete()
	player.tick()
	if not player.has_started():
		player.stop()
		_stream_player = null
		return false
	on_start.call()

	var deadline := Time.get_ticks_msec() + int((player.buffered_seconds() + 0.25) * 1000.0)
	while _is_current(token) and not player.is_finished() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if _is_current(token):
			player.tick()

	if _is_current(token):
		player.stop()
		_stream_player = null
	return true

# A line fetched ahead but never played: its download stops on the token change.
func _discard_speech(speech: Dictionary) -> void:
	if speech.is_empty():
		return
	if speech.player != null:
		speech.player.stop()

func _stop_speaking():
	if _stream_player != null:
		_stream_player.stop()
		_stream_player = null
	if is_instance_valid(audio_player) and audio_player.playing:
		audio_player.stop()
