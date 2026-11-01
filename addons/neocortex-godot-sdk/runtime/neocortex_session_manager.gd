class_name NeocortexSessionManager
extends RefCounted

## Per-character conversation session ids, persisted to user:// so they survive restarts
## and work in exported builds (res:// is read only there).
##
## Also owns the player id sent with every request: the device's id. OS.get_unique_id()
## is empty on some platforms, the web among them, so a random id is minted once and
## stored instead.

const CONFIG_PATH := "user://neocortex_sessions.cfg"
const SECTION := "sessions"
const KEY_PREFIX := "neocortex-session-id_"
const PLAYER_SECTION := "player"
const PLAYER_KEY := "player_id"

## Set this to your own player id (an account id, a platform user id) to have usage
## and memory tracked per player across devices. Empty uses the device id.
static var player_id_override: String = ""

static func set_session_id(character_id: String, session_id: String) -> void:
	var config := _load()
	config.set_value(SECTION, KEY_PREFIX + character_id, session_id)
	config.save(CONFIG_PATH)

static func get_session_id(character_id: String) -> String:
	return str(_load().get_value(SECTION, KEY_PREFIX + character_id, ""))

static func clean_session_id(character_id: String) -> void:
	set_session_id(character_id, "")

## The id this player is known by: the override, the device id, or a stored random id.
static func get_player_id() -> String:
	if not player_id_override.is_empty():
		return player_id_override

	var device := OS.get_unique_id()
	if not device.is_empty():
		return device

	var config := _load()
	var stored := str(config.get_value(PLAYER_SECTION, PLAYER_KEY, ""))
	if stored.is_empty():
		var crypto := Crypto.new()
		stored = crypto.generate_random_bytes(16).hex_encode()
		config.set_value(PLAYER_SECTION, PLAYER_KEY, stored)
		config.save(CONFIG_PATH)
	return stored

static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH) # a missing file is fine on first use
	return config
