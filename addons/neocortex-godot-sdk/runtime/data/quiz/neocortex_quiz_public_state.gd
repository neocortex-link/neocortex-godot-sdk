class_name NeocortexQuizPublicState
extends RefCounted

## A quiz run read back as it stands right now (GET /quiz/session), rather than as a
## turn that just happened. Lets a client that lost a response put itself back in step
## instead of restarting.

## "created", "started", "collecting", "ready", "evaluated" or "finished".
var phase: String = ""
var round_number: int = 0
var total_questions: int = 0
var questions_remaining: int = 0
var participants: Array[NeocortexQuizParticipant] = []
## The question on the table, or null between questions and once the run ends.
var active_question: NeocortexQuizQuestion = null
var answered_participant_ids: PackedStringArray = PackedStringArray()
var pending_participant_ids: PackedStringArray = PackedStringArray()
var attempt: int = 0
var attempts_left: int = 0
var hint_given: bool = false
var leaderboard: Array[NeocortexQuizTurnResponse.LeaderboardEntry] = []
var expecting: NeocortexEnums.QuizExpecting = NeocortexEnums.QuizExpecting.NOTHING
var started_at: String = ""
var finished_at: String = ""

func is_finished() -> bool:
	return phase == "finished"

## Reads the GET /quiz/session body: { state, leaderboard, startedAt, finishedAt }.
static func from_session_dict(data: Dictionary) -> NeocortexQuizPublicState:
	var state := from_dict(NeocortexJson.get_dict(data, "state"))
	if state.leaderboard.is_empty():
		state.leaderboard = NeocortexQuizTurnResponse.LeaderboardEntry.list_from(NeocortexJson.get_array(data, "leaderboard"))
	if state.started_at.is_empty():
		state.started_at = NeocortexJson.get_string(data, "startedAt")
	if state.finished_at.is_empty():
		state.finished_at = NeocortexJson.get_string(data, "finishedAt")
	return state

static func from_dict(data: Dictionary) -> NeocortexQuizPublicState:
	var state := NeocortexQuizPublicState.new()
	state.phase = NeocortexJson.get_string(data, "phase")
	state.round_number = NeocortexJson.get_int(data, "roundNumber")
	state.total_questions = NeocortexJson.get_int(data, "totalQuestions")
	state.questions_remaining = NeocortexJson.get_int(data, "questionsRemaining")
	for item in NeocortexJson.get_array(data, "participants"):
		if item is Dictionary:
			state.participants.append(NeocortexQuizParticipant.from_dict(item))
	state.active_question = NeocortexQuizQuestion.from_optional(data, "activeQuestion")
	state.answered_participant_ids = NeocortexJson.get_strings(data, "answeredParticipantIds")
	state.pending_participant_ids = NeocortexJson.get_strings(data, "pendingParticipantIds")
	state.attempt = NeocortexJson.get_int(data, "attempt")
	state.attempts_left = NeocortexJson.get_int(data, "attemptsLeft")
	state.hint_given = NeocortexJson.get_bool(data, "hintGiven")
	state.leaderboard = NeocortexQuizTurnResponse.LeaderboardEntry.list_from(NeocortexJson.get_array(data, "leaderboard"))
	state.expecting = NeocortexEnums.quiz_expecting_from_string(NeocortexJson.get_string(data, "expecting"))
	state.started_at = NeocortexJson.get_string(data, "startedAt")
	state.finished_at = NeocortexJson.get_string(data, "finishedAt")
	return state
