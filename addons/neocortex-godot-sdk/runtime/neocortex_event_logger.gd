class_name NeocortexEventLogger
extends RefCounted

## Short-term gameplay event buffer sent to the character on each chat request.
##
## Push events as they happen; GetLogs() selects up to MAX_TOTAL entries, newest-
## first within each priority (High -> Low), then emits them in original order.

const MAX_TOTAL := 20
const MAX_CONTENT_LENGTH := 64

# Priorities in descending order: higher priority events are sent first.
const _PRIORITIES_DESC: Array[NeocortexEnums.EventPriority] = [
	NeocortexEnums.EventPriority.HIGH,
	NeocortexEnums.EventPriority.MEDIUM,
	NeocortexEnums.EventPriority.LOW,
]

static var _buffer: Array[NeocortexEventLog] = []

static func push_log(log: NeocortexEventLog) -> void:
	if log.content != null and log.content.length() > MAX_CONTENT_LENGTH:
		push_warning("NeocortexEventLog dropped (content > %d chars): %s" % [MAX_CONTENT_LENGTH, log.content])
		return
	_buffer.append(log)

static func push(priority: NeocortexEnums.EventPriority, content: String, date: String = "") -> void:
	push_log(NeocortexEventLog.create(priority, content, date))

## Returns the selected logs as a JSON string, or "" when the buffer is empty.
static func get_logs() -> String:
	if _buffer.is_empty():
		return ""

	var selected_indexes := {}
	var count := 0

	# Priority-first, newest-first selection.
	for priority in _PRIORITIES_DESC:
		for i in range(_buffer.size() - 1, -1, -1):
			if _buffer[i].priority == priority:
				selected_indexes[i] = true
				count += 1
				if count == MAX_TOTAL:
					break
		if count == MAX_TOTAL:
			break

	# Emit in original order.
	var result: Array = []
	for i in _buffer.size():
		if selected_indexes.has(i):
			result.append(_buffer[i].to_dict())

	return JSON.stringify(result)

static func clear() -> void:
	_buffer.clear()
