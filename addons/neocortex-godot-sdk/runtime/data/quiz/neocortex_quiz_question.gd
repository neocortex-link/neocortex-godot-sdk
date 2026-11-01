class_name NeocortexQuizQuestion
extends RefCounted

## The question on screen. Carries everything a game may show and nothing it may not:
## the expected answer, the rubric and the hint text stay on the server until the run is
## over.

class Option extends RefCounted:
	var id: String = ""
	var text: String = ""

	static func from_dict(data: Dictionary) -> Option:
		var option := Option.new()
		option.id = NeocortexJson.get_string(data, "id")
		option.text = NeocortexJson.get_string(data, "text")
		return option

## Generated id. Use `keyword` to decide what to put on screen.
var question_id: String = ""
## The author's name for the scene this question needs, such as SHOW_RED_APPLE.
var keyword: String = ""
## "free_text", "multiple_choice" or "true_false". Kept as a string on purpose: an
## unknown value must not quietly become a type the game then renders wrongly.
var type: String = ""
var question_text: String = ""
## The choices to show, empty for an open answer.
var options: Array[Option] = []
## Whether the author wrote a clue the player can ask for.
var has_hint: bool = false

## True when the player picks from `options` rather than speaking freely.
func is_choice() -> bool:
	return type == "multiple_choice" or type == "true_false"

static func from_dict(data: Dictionary) -> NeocortexQuizQuestion:
	var question := NeocortexQuizQuestion.new()
	question.question_id = NeocortexJson.get_string(data, "questionId")
	question.keyword = NeocortexJson.get_string(data, "keyword")
	question.type = NeocortexJson.get_string(data, "type")
	question.question_text = NeocortexJson.get_string(data, "questionText")
	question.has_hint = NeocortexJson.get_bool(data, "hasHint")
	for item in NeocortexJson.get_array(data, "options"):
		if item is Dictionary:
			question.options.append(Option.from_dict(item))
	return question

## Null when the key is missing or null, which on a turn means "unchanged".
static func from_optional(data: Dictionary, key: String) -> NeocortexQuizQuestion:
	return from_dict(data[key]) if NeocortexJson.has_dict(data, key) else null
