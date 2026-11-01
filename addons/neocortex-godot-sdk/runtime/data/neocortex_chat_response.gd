class_name NeocortexChatResponse
extends RefCounted

## One character's reply, flattened from the v3 chat response so a single character
## agent can read `message`, `emotion` and `action` directly.

## The whole reply: every line's text joined.
var message: String = ""
## The reply as it should be spoken (numbers, dates and currencies spelled out).
var spoken_message: String = ""
## Name of the first of `actions`, kept for integrations that read a single action.
var action: String = ""
## Every stacked action the character triggered this turn, in order. Empty when none.
var actions: Array[NeocortexChatAction] = []
## The Conversation Flow checkpoint this turn landed on. Empty when the character has no
## flow.
var flow_state: String = ""
## The first line's emotion.
var emotion: NeocortexEnums.Emotions = NeocortexEnums.Emotions.NEUTRAL
## The scene's interactables after the turn, as the server echoed them (Dictionaries).
var metadata: Array = []
## Ordered per-emotion lines that make up the reply.
var lines: Array[NeocortexChatLine] = []
## The character that produced this reply and its display name.
var character_id: String = ""
var name: String = ""
## The conversation session this turn belongs to.
var session_id: String = ""

## Flattens one speaker of a v3 turn: message is the lines joined, emotion the first
## line's emotion, action the first stacked action.
static func from_group_message(source: NeocortexGroupMessage, scene_metadata: Array = []) -> NeocortexChatResponse:
	var response := NeocortexChatResponse.new()
	response.metadata = scene_metadata
	if source == null:
		return response

	response.character_id = source.character_id
	response.name = source.name
	response.lines = source.lines
	response.actions = source.actions
	response.flow_state = source.flow_state

	var text := ""
	var spoken := ""
	var any_spoken := false
	for line in source.lines:
		text += line.text
		spoken += line.speech_text()
		if not line.spoken_text.is_empty():
			any_spoken = true

	response.message = text
	if any_spoken:
		response.spoken_message = spoken
	elif not source.spoken_message.is_empty():
		response.spoken_message = source.spoken_message
	else:
		response.spoken_message = text

	if not source.lines.is_empty():
		response.emotion = source.lines[0].emotion
	if not source.actions.is_empty():
		response.action = source.actions[0].name
	return response

## The action names in order, for code that only needs the keywords.
func action_names() -> PackedStringArray:
	var out := PackedStringArray()
	for item in actions:
		out.append(item.name)
	return out

## The lines to play. A reply with no lines (an older server) plays as one line.
func resolve_lines() -> Array[NeocortexChatLine]:
	if not lines.is_empty():
		return lines
	var single: Array[NeocortexChatLine] = [NeocortexChatLine.create(message, emotion, spoken_message)]
	return single
