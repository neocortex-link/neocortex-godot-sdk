class_name NeocortexApiUsage
extends RefCounted

## Team credit status plus optional per-player / per-character usage from GET /v3/usage.
## Read-only and unmetered.

class PlayerUsage extends RefCounted:
	var interactions_today: int = 0
	var credits_used_all_time: int = 0
	var over_limit: bool = false

	static func from_dict(data: Dictionary) -> PlayerUsage:
		var usage := PlayerUsage.new()
		usage.interactions_today = int(data.get("interactionsToday", 0))
		usage.credits_used_all_time = int(data.get("creditsUsedAllTime", 0))
		usage.over_limit = bool(data.get("overLimit", false))
		return usage

class CharacterUsage extends RefCounted:
	var credits_used_all_time: int = 0
	var over_limit: bool = false

	static func from_dict(data: Dictionary) -> CharacterUsage:
		var usage := CharacterUsage.new()
		usage.credits_used_all_time = int(data.get("creditsUsedAllTime", 0))
		usage.over_limit = bool(data.get("overLimit", false))
		return usage

var status: NeocortexEnums.UsageStatus = NeocortexEnums.UsageStatus.OK
var credits_remaining: int = 0
## Only present when a playerId was passed; null otherwise.
var player: PlayerUsage = null
## Only present when a characterId was passed; null otherwise.
var character: CharacterUsage = null

static func from_dict(data: Dictionary) -> NeocortexApiUsage:
	var usage := NeocortexApiUsage.new()
	usage.status = NeocortexEnums.usage_status_from_string(str(data.get("status", "ok")))
	usage.credits_remaining = int(data.get("creditsRemaining", 0))

	if data.get("player", null) is Dictionary:
		usage.player = PlayerUsage.from_dict(data["player"])
	if data.get("character", null) is Dictionary:
		usage.character = CharacterUsage.from_dict(data["character"])

	return usage

func is_player_over_limit() -> bool:
	return player != null and player.over_limit

func is_character_over_limit() -> bool:
	return character != null and character.over_limit
