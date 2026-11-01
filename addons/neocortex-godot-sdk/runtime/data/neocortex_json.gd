class_name NeocortexJson
extends RefCounted

## Null-safe readers for parsed JSON. JSON.parse_string gives floats for numbers and
## null for missing values, and the API omits optional fields, so every model reads
## through these instead of indexing the Dictionary directly.

static func get_string(data: Dictionary, key: String, fallback: String = "") -> String:
	var value = data.get(key, null)
	if value == null:
		return fallback
	return str(value)

static func get_int(data: Dictionary, key: String, fallback: int = 0) -> int:
	var value = data.get(key, null)
	if value is float or value is int:
		return int(value)
	if value is String and value.is_valid_int():
		return value.to_int()
	return fallback

static func get_float(data: Dictionary, key: String, fallback: float = 0.0) -> float:
	var value = data.get(key, null)
	if value is float or value is int:
		return float(value)
	return fallback

static func get_bool(data: Dictionary, key: String, fallback: bool = false) -> bool:
	var value = data.get(key, null)
	if value is bool:
		return value
	return fallback

static func get_dict(data: Dictionary, key: String) -> Dictionary:
	var value = data.get(key, null)
	return value if value is Dictionary else {}

static func get_array(data: Dictionary, key: String) -> Array:
	var value = data.get(key, null)
	return value if value is Array else []

static func has_dict(data: Dictionary, key: String) -> bool:
	return data.get(key, null) is Dictionary

static func get_strings(data: Dictionary, key: String) -> PackedStringArray:
	var out := PackedStringArray()
	for item in get_array(data, key):
		if item != null:
			out.append(str(item))
	return out

## Parses a UTF-8 body into a Dictionary, or {} when it is not a JSON object.
static func parse_object(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return {}
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}
