class_name NeocortexChatHistoryEntry
extends RefCounted

## One stored turn of a past conversation, returned by chat history. Unlike a live chat
## line, this is a persisted record of a whole turn from either side, with who said it
## and when.

var content: String = ""
## "USER" (the player) or "ASSISTANT" (a character). Scene events carry their own value.
var sender: String = ""
## In a group session, which character spoke this line; empty for USER lines.
var speaker_character_id: String = ""
## Display name of the speaker; empty when there is none (USER lines).
var name: String = ""
## Group sessions: who this line was directed at ("Player" or a character name).
var addressed_to: String = ""
## The emotion an ASSISTANT line was delivered in; NEUTRAL when not stored.
var emotion: NeocortexEnums.Emotions = NeocortexEnums.Emotions.NEUTRAL
## Stacked action names this turn triggered; empty for USER lines.
var actions: PackedStringArray = PackedStringArray()
var created_at: String = ""

## True when the player said this line.
func is_user() -> bool:
	return sender.to_upper() == "USER"

static func from_dict(data: Dictionary) -> NeocortexChatHistoryEntry:
	var entry := NeocortexChatHistoryEntry.new()
	entry.content = NeocortexJson.get_string(data, "content")
	entry.sender = NeocortexJson.get_string(data, "sender")
	entry.speaker_character_id = NeocortexJson.get_string(data, "speakerCharacterId")
	entry.name = NeocortexJson.get_string(data, "name")
	entry.addressed_to = NeocortexJson.get_string(data, "addressedTo")
	entry.emotion = NeocortexEnums.emotion_from_string(NeocortexJson.get_string(data, "emotion"))
	entry.created_at = NeocortexJson.get_string(data, "createdAt")
	for item in NeocortexJson.get_array(data, "actions"):
		if item is Dictionary:
			entry.actions.append(NeocortexJson.get_string(item, "name"))
		elif item != null:
			entry.actions.append(str(item))
	return entry

static func list_from(raw: Array) -> Array[NeocortexChatHistoryEntry]:
	var out: Array[NeocortexChatHistoryEntry] = []
	for item in raw:
		if item is Dictionary:
			out.append(from_dict(item))
	return out
