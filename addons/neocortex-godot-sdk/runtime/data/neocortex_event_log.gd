class_name NeocortexEventLog
extends RefCounted

## A single gameplay event supplied to the character as short-term context. Serialized
## with the priority as an int (0/1/2), as the API expects.

var priority: NeocortexEnums.EventPriority = NeocortexEnums.EventPriority.LOW
var content: String
var date: String

static func create(priority: NeocortexEnums.EventPriority, content: String, date: String = "") -> NeocortexEventLog:
	var log := NeocortexEventLog.new()
	log.priority = priority
	log.content = content
	log.date = date
	return log

func to_dict() -> Dictionary:
	return {
		"priority": int(priority),
		"date": date,
		"content": content,
	}
