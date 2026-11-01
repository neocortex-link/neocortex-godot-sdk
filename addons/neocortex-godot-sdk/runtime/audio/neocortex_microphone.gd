class_name NeocortexMicrophone
extends RefCounted

## The engine's input device list and the player's saved choice. The choice is a player
## preference, so it lives in user://.

const CONFIG_PATH := "user://neocortex_settings.cfg"
const SECTION := "microphone"
const KEY := "neocortex-mic-index"

static func devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()

static func get_selected_index() -> int:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return 0
	return int(config.get_value(SECTION, KEY, 0))

static func set_selected_index(index: int) -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	config.set_value(SECTION, KEY, index)
	config.save(CONFIG_PATH)
	apply_selected_device()

## The saved device's name, or "" when there are no devices.
static func get_selected_device() -> String:
	var list := devices()
	if list.is_empty():
		return ""
	return list[clampi(get_selected_index(), 0, list.size() - 1)]

## Points the engine's input at the saved device.
static func apply_selected_device() -> void:
	var device := get_selected_device()
	if not device.is_empty() and AudioServer.input_device != device:
		AudioServer.input_device = device

## Asks for microphone permission where the OS requires it (Android). Returns true
## when recording is allowed already.
static func request_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	if OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
		return true
	OS.request_permissions()
	return false
