@tool
class_name NeocortexSettings
extends Resource

## Project wide Neocortex settings, edited from the Neocortex dock and saved at
## SETTINGS_PATH.
##
## The file holds your API key, so add it to your .gitignore, and treat exported builds
## as able to read it.

const SETTINGS_PATH := "res://addons/neocortex-godot-sdk/neocortex_settings.tres"
## The settings file of SDK 0.1, read once so an existing key carries over.
const LEGACY_CONFIG_PATH := "res://addons/neocortex-godot-sdk/data.cfg"

@export var api_key: String = ""

## Send every request to this server instead of the public API. Only honoured when the
## game runs from the editor, so a forgotten value can never ship in an export. Leave
## empty normally.
@export var base_url_override: String = ""

static var _cached: NeocortexSettings = null

## The project's settings, loaded once and cached. Never null.
static func get_settings() -> NeocortexSettings:
	if _cached == null:
		_cached = _load()
	return _cached

## Drops the cache so the next get_settings() reads the file again, for example
## after the file was changed outside the editor. (Not named reload: that is Script.reload.)
static func reload_settings() -> void:
	_cached = null

func save_settings() -> Error:
	var error := ResourceSaver.save(self, SETTINGS_PATH)
	_cached = self
	return error

static func _load() -> NeocortexSettings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var loaded = ResourceLoader.load(SETTINGS_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
		if loaded is NeocortexSettings:
			return loaded

	var settings := NeocortexSettings.new()
	var legacy := ConfigFile.new()
	if legacy.load(LEGACY_CONFIG_PATH) == OK:
		settings.api_key = str(legacy.get_value("data", "api_key", ""))
	return settings
