class_name NeocortexApiLists
extends RefCounted

## Small read-only lists the editor tooling uses: the API key's team's characters (GET
## /v3/characters) and question sets (GET /v3/question-sets).

class CharacterSummary extends RefCounted:
	var id: String = ""
	var name: String = ""

	static func from_dict(data: Dictionary) -> CharacterSummary:
		var item := CharacterSummary.new()
		item.id = NeocortexJson.get_string(data, "id")
		item.name = NeocortexJson.get_string(data, "name")
		return item

class QuestionSetSummary extends RefCounted:
	var id: String = ""
	var name: String = ""
	## How many questions it holds, so a picker can say so without loading the set.
	var question_count: int = 0

	static func from_dict(data: Dictionary) -> QuestionSetSummary:
		var item := QuestionSetSummary.new()
		item.id = NeocortexJson.get_string(data, "id")
		item.name = NeocortexJson.get_string(data, "name")
		item.question_count = NeocortexJson.get_int(data, "questionCount")
		return item

static func characters_from(data: Dictionary) -> Array[CharacterSummary]:
	var out: Array[CharacterSummary] = []
	for item in NeocortexJson.get_array(data, "characters"):
		if item is Dictionary:
			out.append(CharacterSummary.from_dict(item))
	return out

static func question_sets_from(data: Dictionary) -> Array[QuestionSetSummary]:
	var out: Array[QuestionSetSummary] = []
	for item in NeocortexJson.get_array(data, "questionSets"):
		if item is Dictionary:
			out.append(QuestionSetSummary.from_dict(item))
	return out
