class_name NeocortexQuizLine
extends NeocortexChatLine

## One line the quiz host says, with what that line is doing.

var role: NeocortexEnums.QuizLineRole = NeocortexEnums.QuizLineRole.REACTION

## True when this line is the one that actually puts the question to the player.
func is_question() -> bool:
	return role == NeocortexEnums.QuizLineRole.QUESTION

static func from_quiz_dict(data: Dictionary) -> NeocortexQuizLine:
	var line := NeocortexQuizLine.new()
	line.read_dict(data)
	line.role = NeocortexEnums.quiz_line_role_from_string(NeocortexJson.get_string(data, "role"))
	return line

static func list_from(raw: Array) -> Array[NeocortexQuizLine]:
	var out: Array[NeocortexQuizLine] = []
	for item in raw:
		if item is Dictionary:
			out.append(from_quiz_dict(item))
	return out
