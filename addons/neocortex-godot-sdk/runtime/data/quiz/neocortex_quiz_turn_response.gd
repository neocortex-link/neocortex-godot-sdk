class_name NeocortexQuizTurnResponse
extends RefCounted

## One turn of a quiz: what the host says now, what the game should put on screen, and
## what to collect next. Question order, retries, hints and when the run ends are
## decided on the server; a game reads this and renders it.

## The question after the one on screen, so its scene can be built early.
class Upcoming extends RefCounted:
	var question_id: String = ""
	var keyword: String = ""

	static func from_dict(data: Dictionary) -> Upcoming:
		var upcoming := Upcoming.new()
		upcoming.question_id = NeocortexJson.get_string(data, "questionId")
		upcoming.keyword = NeocortexJson.get_string(data, "keyword")
		return upcoming

## How far through the run the players are.
class Progress extends RefCounted:
	## Which question is on the table, counting from one. Zero before the first.
	var asked: int = 0
	var total: int = 0

	func remaining() -> int:
		return maxi(0, total - asked)

	static func from_dict(data: Dictionary) -> Progress:
		var progress := Progress.new()
		progress.asked = NeocortexJson.get_int(data, "asked")
		progress.total = NeocortexJson.get_int(data, "total")
		return progress

## How one player's attempt was judged, and what it was worth.
class Result extends RefCounted:
	var participant_id: String = ""
	var verdict: NeocortexEnums.QuizVerdict = NeocortexEnums.QuizVerdict.UNANSWERED
	var score: int = 0

	static func from_dict(data: Dictionary) -> Result:
		var result := Result.new()
		result.participant_id = NeocortexJson.get_string(data, "participantId")
		result.verdict = NeocortexEnums.quiz_verdict_from_string(NeocortexJson.get_string(data, "verdict"))
		result.score = NeocortexJson.get_int(data, "score")
		return result

## One player's standing. Players on the same score share a rank.
class LeaderboardEntry extends RefCounted:
	var participant_id: String = ""
	var display_name: String = ""
	var total_score: int = 0
	var rank: int = 0

	static func from_dict(data: Dictionary) -> LeaderboardEntry:
		var entry := LeaderboardEntry.new()
		entry.participant_id = NeocortexJson.get_string(data, "participantId")
		entry.display_name = NeocortexJson.get_string(data, "displayName")
		entry.total_score = NeocortexJson.get_int(data, "totalScore")
		entry.rank = NeocortexJson.get_int(data, "rank")
		return entry

	static func list_from(raw: Array) -> Array[LeaderboardEntry]:
		var out: Array[LeaderboardEntry] = []
		for item in raw:
			if item is Dictionary:
				out.append(from_dict(item))
		return out

## Which run this turn belongs to.
var session_id: String = ""
## What the host says, in order. Time the scene to the line whose role is QUESTION.
var lines: Array[NeocortexQuizLine] = []
## Game actions the host triggered. target_id is a participant id when it is about one
## player.
var actions: Array[NeocortexChatAction] = []
var expecting: NeocortexEnums.QuizExpecting = NeocortexEnums.QuizExpecting.NOTHING
## How the host read the last thing said. UNCLEAR on the opening turn.
var intent: NeocortexEnums.QuizIntent = NeocortexEnums.QuizIntent.UNCLEAR
## The question now on screen. Only carried on the turn it changes: null means "unchanged".
var question: NeocortexQuizQuestion = null
## The question after this one. Null on the last one.
var upcoming: Upcoming = null
var progress: Progress = null
## How the last answer was judged; empty on a turn that judged nothing.
var result: Array[Result] = []
var leaderboard: Array[LeaderboardEntry] = []
## Players the round is still waiting on, in a game with more than one player.
var pending: PackedStringArray = PackedStringArray()
## Players who have answered this round, in a game with more than one player.
var answered: PackedStringArray = PackedStringArray()
## Which attempt at the open question this is, from 1. One player only; 0 in a group.
var attempt: int = 0
## How many more goes the open question allows after this one. One player only.
var attempts_left: int = 0
var hint_given: bool = false
## True once the host has signed off. Stop sending turns.
var done: bool = false

static func from_dict(data: Dictionary) -> NeocortexQuizTurnResponse:
	var turn := NeocortexQuizTurnResponse.new()
	turn.session_id = NeocortexJson.get_string(data, "sessionId")
	turn.lines = NeocortexQuizLine.list_from(NeocortexJson.get_array(data, "lines"))
	turn.actions = NeocortexChatAction.list_from(NeocortexJson.get_array(data, "actions"))
	turn.expecting = NeocortexEnums.quiz_expecting_from_string(NeocortexJson.get_string(data, "expecting"))
	turn.intent = NeocortexEnums.quiz_intent_from_string(NeocortexJson.get_string(data, "intent"))
	turn.question = NeocortexQuizQuestion.from_optional(data, "question")
	if NeocortexJson.has_dict(data, "upcoming"):
		turn.upcoming = Upcoming.from_dict(data["upcoming"])
	if NeocortexJson.has_dict(data, "progress"):
		turn.progress = Progress.from_dict(data["progress"])
	for item in NeocortexJson.get_array(data, "result"):
		if item is Dictionary:
			turn.result.append(Result.from_dict(item))
	turn.leaderboard = LeaderboardEntry.list_from(NeocortexJson.get_array(data, "leaderboard"))
	turn.pending = NeocortexJson.get_strings(data, "pending")
	turn.answered = NeocortexJson.get_strings(data, "answered")
	turn.attempt = NeocortexJson.get_int(data, "attempt")
	turn.attempts_left = NeocortexJson.get_int(data, "attemptsLeft")
	turn.hint_given = NeocortexJson.get_bool(data, "hintGiven")
	turn.done = NeocortexJson.get_bool(data, "done")
	return turn
