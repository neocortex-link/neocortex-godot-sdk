extends Node3D

## Sample 7 (quiz show). Cora hosts a quiz for one to four players, from a question set.
## Her lines and the players' answers make up the chat in the middle; the question card
## shows the question, its scene keyword and the next scene; the "reply as" chips under
## the chat pick which player you answer for, and show each one's score (outlined by the
## last verdict, dimmed once they have answered this round). Type, tap an option, ask
## for a hint or pass. Abort silences the host; Resync restores the question after a
## lost turn.

## The quiz agent to drive. Set its character and question set.
@export var agent: NeocortexQuizAgent
## One to four players. One name plays a solo quiz.
@export var player_names: PackedStringArray = ["Anna", "Bence", "Csilla", "Dani"]
## Seconds each player gets to answer. 0 turns the clock off.
@export var answer_seconds: float = 0.0
## Cora: talks while the host's voice plays, thinks while a turn is in flight.
@export var character: NeocortexSampleCharacter

@export_group("UI")
@export var chat_panel: NeocortexChatPanel
@export var answer_input: NeocortexTextChatInput
@export var start_button: Button
@export var abort_button: Button
@export var resync_button: Button
@export var hint_button: Button
@export var pass_button: Button
@export var pass_rest_button: Button
@export var typed_toggle: Button
@export var status_label: Label
@export var progress_label: Label
@export var keyword_label: Label
@export var question_label: Label
@export var upcoming_label: Label
@export var options_box: Container
@export var players_box: BoxContainer

const GOOD := Color("#5CC98F")
const HALF := Color("#F0C45C")
const BAD := Color("#EE6B6B")
const MUTED := Color("#8C8C8C")
## How long a turn must be in flight before Cora starts thinking, so a request that
## fails at once does not flick her animation.
const THINK_AFTER := 0.35

var _cast: Array[NeocortexQuizParticipant] = []
var _seats: Array[Dictionary] = [] # { id, card, name, score, verdict }
var _current := 0
var _clock := 0.0
var _busy_for := 0.0
## The last failure, shown until the next action.
var _error := ""

func _ready() -> void:
	for player in player_names:
		if not player.strip_edges().is_empty() and _cast.size() < 4:
			_cast.append(NeocortexQuizParticipant.create("p%d" % (_cast.size() + 1), player.strip_edges()))
	for i in _cast.size():
		_add_seat(i)

	start_button.pressed.connect(_begin)
	abort_button.pressed.connect(func():
		agent.abort()
		_refresh())
	resync_button.pressed.connect(func():
		_error = ""
		agent.resync())
	hint_button.pressed.connect(func():
		if _accepting():
			_answer_as_current("Can I have a hint?", false))
	pass_button.pressed.connect(func(): _pass(_current))
	pass_rest_button.pressed.connect(_pass_rest)
	answer_input.send_submitted.connect(func(text: String): _answer_as_current(text, typed_toggle.button_pressed))
	_listen()
	_refresh()

func _process(delta: float) -> void:
	var voice = agent.audio_player
	character.talking = is_instance_valid(voice) and voice.playing
	_busy_for = _busy_for + delta if agent.is_busy else 0.0
	character.thinking = _busy_for >= THINK_AFTER and not character.talking
	if answer_seconds > 0.0 and _accepting():
		_clock -= delta
		if _clock <= 0.0:
			_pass(_current)

func _listen() -> void:
	agent.host_line.connect(func(line: NeocortexQuizLine): chat_panel.add_message(line.text, false, character.display_name))
	agent.question_changed.connect(_show_question)
	agent.upcoming_question.connect(func(next: NeocortexQuizTurnResponse.Upcoming):
		upcoming_label.text = "Next scene: %s" % (next.keyword if not next.keyword.is_empty() else "-"))
	agent.pending_changed.connect(func(_pending): _select_next())
	agent.result.connect(func(results: Array):
		for item in results:
			var seat := _seat(item.participant_id)
			if not seat.is_empty():
				seat.verdict = _verdict_color(item.verdict)
		_refresh())
	agent.leaderboard_changed.connect(func(board: Array):
		for entry in board:
			var seat := _seat(entry.participant_id)
			if not seat.is_empty():
				seat.score.text = str(entry.total_score))
	agent.expecting_changed.connect(func(_e): _refresh())
	agent.busy_changed.connect(func(_b): _refresh())
	agent.quiz_finished.connect(func(board: Array):
		var lines := PackedStringArray()
		for entry in board:
			lines.append("%d. %s  %d" % [entry.rank, entry.display_name, entry.total_score])
		question_label.text = "Final standings\n" + "\n".join(lines)
		_clear_options()
		_refresh())
	agent.input_dropped.connect(func(text: String, reason: NeocortexEnums.QuizInputDropReason):
		_note("Dropped \"%s\" (%s)." % [text, NeocortexEnums.QuizInputDropReason.keys()[reason].to_lower()], MUTED))
	agent.request_failed.connect(_fail)
	agent.credits_exhausted.connect(func(code: String): _fail("Out of credits (%s)." % code))

# ------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------

func _begin() -> void:
	_error = ""
	if _cast.is_empty() or agent.character_id.is_empty() or agent.question_set_id.is_empty():
		_fail("Set the quiz agent's character and question set, and at least one player name.")
		return
	chat_panel.clear_messages()
	question_label.text = ""
	keyword_label.text = ""
	upcoming_label.text = ""
	_clear_options()
	for seat in _seats:
		seat.verdict = Color.TRANSPARENT
		seat.score.text = "0"
	agent.begin(_cast)

func _answer_as_current(text: String, typed: bool) -> void:
	if not _accepting():
		return
	_error = ""
	chat_panel.add_message(text, true, _cast[_current].display_name)
	agent.say_as(_cast[_current].id, text, typed)
	_after_answer()

func _choose(option_id: String, option_text: String) -> void:
	if not _accepting():
		return
	_error = ""
	chat_panel.add_message(option_text, true, _cast[_current].display_name)
	agent.choose_as(_cast[_current].id, option_id)
	_after_answer()

func _pass(index: int) -> void:
	if not _accepting():
		return
	_error = ""
	_note("%s passes." % _cast[index].display_name, MUTED)
	agent.pass_as(_cast[index].id)
	_after_answer()

func _pass_rest() -> void:
	for player in _cast:
		if agent.pending_participants.has(player.id):
			agent.pass_as(player.id)

func _after_answer() -> void:
	_clock = answer_seconds
	_select_next()

# The next player the round still waits on, after the current one.
func _select_next() -> void:
	for step in range(1, _cast.size() + 1):
		var index := (_current + step) % _cast.size()
		var id := _cast[index].id
		if agent.pending_participants.has(id) and not agent.answered_participants.has(id):
			_select(index)
			return
	_refresh()

func _select(index: int) -> void:
	_current = clampi(index, 0, _cast.size() - 1)
	_clock = answer_seconds
	_refresh()

func _show_question(question: NeocortexQuizQuestion) -> void:
	keyword_label.text = "Scene: %s" % (question.keyword if not question.keyword.is_empty() else "-")
	question_label.text = question.question_text
	progress_label.text = "Question %d of %d" % [agent.progress.asked, agent.progress.total]
	_clear_options()
	if question.is_choice():
		for option in question.options:
			var button := Button.new()
			button.text = option.text
			button.custom_minimum_size.y = 48
			button.pressed.connect(_choose.bind(option.id, option.text))
			options_box.add_child(button)
	for seat in _seats:
		seat.verdict = Color.TRANSPARENT
	_select(0)

# ------------------------------------------------------------------
# STATE
# ------------------------------------------------------------------

func _accepting() -> bool:
	return not agent.session_id.is_empty() and not agent.is_finished and not agent.is_busy \
		and agent.expecting != NeocortexEnums.QuizExpecting.NOTHING

func _refresh() -> void:
	var open := _accepting()
	answer_input.input_field.editable = open
	answer_input.send_button.disabled = not open
	answer_input.input_field.placeholder_text = ("Reply as %s..." % _cast[_current].display_name) \
		if open and not _cast.is_empty() else "Wait for the question..."
	hint_button.disabled = not open or agent.current_question == null or not agent.current_question.has_hint
	pass_button.disabled = not open
	pass_rest_button.disabled = not open or _cast.size() < 2
	abort_button.disabled = agent.session_id.is_empty() or agent.is_finished
	resync_button.disabled = agent.session_id.is_empty() or agent.is_finished
	for child in options_box.get_children():
		child.disabled = not open
	start_button.text = "Restart" if not agent.session_id.is_empty() else "Start"

	for i in _seats.size():
		_style_seat(_seats[i], i == _current)

	if not _error.is_empty():
		_note(_error, BAD)
	elif agent.session_id.is_empty():
		_note("Press Start to begin the show.", MUTED)
	elif agent.is_finished:
		_note("Show over. Press Restart to play again.", MUTED)
	elif agent.is_busy:
		_note("Cora is thinking...", MUTED)
	elif agent.expecting == NeocortexEnums.QuizExpecting.NOTHING:
		_note("Cora is speaking.", MUTED)
	elif agent.pending_participants.size() > 1:
		_note("Waiting on %d players." % agent.pending_participants.size(), MUTED)
	else:
		_note("Waiting for %s." % _cast[_current].display_name, MUTED)

# Shows a failure on the question card until the next action.
func _fail(message: String) -> void:
	_error = message
	_refresh()

func _note(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)

# ------------------------------------------------------------------
# PLAYER CARDS
# ------------------------------------------------------------------

func _add_seat(index: int) -> void:
	var chip := Button.new()
	chip.custom_minimum_size = Vector2(140, 48)
	chip.tooltip_text = "Reply as %s" % _cast[index].display_name
	chip.pressed.connect(_select.bind(index))
	players_box.add_child(chip)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seats.append({
		"id": _cast[index].id,
		"card": chip,
		"name": _cell(row, _cast[index].display_name, "NeocortexTitle"),
		"score": _cell(row, "0", "NeocortexHeading"),
		"verdict": Color.TRANSPARENT,
	})

func _cell(row: Control, text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override("font_size", 20)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return label

# The player you reply as is filled amber, like your chat bubbles; the others are
# outlined in their last verdict's colour, and dimmed once they have answered.
func _style_seat(seat: Dictionary, selected: bool) -> void:
	var card: Button = seat.card
	var verdict: Color = seat.verdict
	var outline := verdict if verdict.a > 0.0 else Color(1, 1, 1, 0.12)
	var box := NeocortexUiStyle.pill(NeocortexUiStyle.AMBER, Color.TRANSPARENT, 0, 999, 16, 6)
	if not selected:
		box = NeocortexUiStyle.pill(Color("#151515"), outline, 2, 999, 16, 6)
	for state in ["normal", "hover", "pressed", "focus"]:
		card.add_theme_stylebox_override(state, box)
	var ink := NeocortexUiStyle.SURFACE_DARK if selected else Color.WHITE
	seat.name.add_theme_color_override("font_color", ink)
	seat.score.add_theme_color_override("font_color", ink if selected else NeocortexUiStyle.AMBER)
	var answered: bool = agent.answered_participants.has(seat.id) and not agent.pending_participants.has(seat.id)
	card.modulate.a = 0.55 if answered and not selected else 1.0

func _seat(participant_id: String) -> Dictionary:
	for seat in _seats:
		if seat.id == participant_id:
			return seat
	return {}

func _clear_options() -> void:
	for child in options_box.get_children():
		child.queue_free()

func _verdict_color(verdict: NeocortexEnums.QuizVerdict) -> Color:
	match verdict:
		NeocortexEnums.QuizVerdict.CORRECT:
			return GOOD
		NeocortexEnums.QuizVerdict.PARTIAL:
			return HALF
		NeocortexEnums.QuizVerdict.INCORRECT:
			return BAD
	return MUTED
