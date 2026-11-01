class_name NeocortexSseParser
extends RefCounted

## Splits a Server-Sent Events body into events as it arrives. Each frame is
## `event: <name>` and `data: <json>` lines ended by a blank line; a frame split
## across network chunks is held until it is whole.

## One whole event. `data` is the parsed JSON object, or {} when it was not JSON.
signal event_received(event_name: String, data: Dictionary)

var _pending := PackedByteArray()
var _event_name := ""
var _data_lines := PackedStringArray()

func feed(bytes: PackedByteArray) -> void:
	_pending.append_array(bytes)

	# Lines are split on raw bytes, so a multi-byte character cut by the network is
	# never decoded half way.
	while true:
		var newline := _pending.find(10)
		if newline < 0:
			return
		var line := _pending.slice(0, newline).get_string_from_utf8()
		_pending = _pending.slice(newline + 1)
		_handle_line(line.trim_suffix("\r"))

## Flushes a last event that was not followed by a blank line.
func complete() -> void:
	if not _pending.is_empty():
		_handle_line(_pending.get_string_from_utf8().trim_suffix("\r"))
		_pending = PackedByteArray()
	_dispatch()

func _handle_line(line: String) -> void:
	if line.is_empty():
		_dispatch()
		return
	if line.begins_with(":"):
		return

	var colon := line.find(":")
	var field := line if colon < 0 else line.substr(0, colon)
	var value := "" if colon < 0 else line.substr(colon + 1)
	if value.begins_with(" "):
		value = value.substr(1)

	if field == "event":
		_event_name = value
	elif field == "data":
		_data_lines.append(value)

func _dispatch() -> void:
	if _data_lines.is_empty() and _event_name.is_empty():
		return

	var text := "\n".join(_data_lines)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var name := _event_name
	if name.is_empty():
		name = NeocortexJson.get_string(data, "type", "message")

	_event_name = ""
	_data_lines = PackedStringArray()
	event_received.emit(name, data)
