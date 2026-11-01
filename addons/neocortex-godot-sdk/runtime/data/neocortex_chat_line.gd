class_name NeocortexChatLine
extends RefCounted

## One ordered piece of a reply with the emotion it should be delivered in. A reply is
## split into chat lines that drop in one after another; their text joined equals the
## full reply.

var text: String = ""
## The phonetic text for speech synthesis (numbers, dates and currencies spelled out).
## Empty when the server sent none; speak `text` then.
var spoken_text: String = ""
var emotion: NeocortexEnums.Emotions = NeocortexEnums.Emotions.NEUTRAL

static func create(line_text: String, line_emotion: NeocortexEnums.Emotions = NeocortexEnums.Emotions.NEUTRAL, line_spoken_text: String = "") -> NeocortexChatLine:
	var line := NeocortexChatLine.new()
	line.text = line_text
	line.spoken_text = line_spoken_text
	line.emotion = line_emotion
	return line

static func from_dict(data: Dictionary) -> NeocortexChatLine:
	var line := NeocortexChatLine.new()
	line.read_dict(data)
	return line

func read_dict(data: Dictionary) -> void:
	text = NeocortexJson.get_string(data, "text")
	spoken_text = NeocortexJson.get_string(data, "spokenText")
	emotion = NeocortexEnums.emotion_from_string(NeocortexJson.get_string(data, "emotion"))

## What to send to speech synthesis: the spoken text when there is one, else the text.
func speech_text() -> String:
	return spoken_text if not spoken_text.is_empty() else text

func to_dict() -> Dictionary:
	return {
		"text": text,
		"spokenText": spoken_text,
		"emotion": NeocortexEnums.emotion_to_string(emotion).to_lower(),
	}
