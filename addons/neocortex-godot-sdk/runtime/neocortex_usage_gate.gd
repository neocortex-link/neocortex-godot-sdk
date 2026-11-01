class_name NeocortexUsageGate
extends RefCounted

## Turns the read-only account/usage endpoints into simple flags and events so a game
## can gate smart NPC features instead of failing mid-conversation. Results are cached;
## usage is only re-fetched when the cache is older than min_refresh_interval, on an
## explicit refresh, or via start_auto_refresh(). These endpoints never cost a credit.
##
## Construct with a host Node (the ApiRequest it uses must live in the scene tree):
##   var gate := NeocortexUsageGate.new(self)

signal usage_updated(usage: NeocortexApiUsage)
signal low_credits(usage: NeocortexApiUsage)
signal credits_empty(usage: NeocortexApiUsage)
signal player_over_limit(usage: NeocortexApiUsage)
signal character_over_limit(usage: NeocortexApiUsage)
signal request_failed(error: String)

## Seconds a cached usage result is served before a new request is made.
var min_refresh_interval: float = 30.0

var last_account: NeocortexApiAccount = null
var last_usage: NeocortexApiUsage = null

var _api_request: ApiRequest
var _last_fetch_ms: int = -1
var _last_query_key: String = ""
var _was_low: bool = false
var _was_empty: bool = false
var _was_player_over: bool = false
var _was_character_over: bool = false
var _auto_refresh_token: int = 0

func _init(host: Node) -> void:
	_api_request = ApiRequest.new()
	host.add_child(_api_request)
	_api_request.request_failed.connect(func(error: String): request_failed.emit(error))

## Fetches usage and raises the gating events. An empty playerId falls back to the
## player id the SDK sends on every chat request
## (NeocortexSessionManager.get_player_id()). Returns null on failure (the last cached
## value stays in last_usage).
func refresh_usage(player_id: String = "", character_id: String = "") -> NeocortexApiUsage:
	if player_id.is_empty():
		player_id = NeocortexSessionManager.get_player_id()

	var usage := await _api_request.get_usage(player_id, character_id)
	if usage == null:
		return null

	_last_fetch_ms = Time.get_ticks_msec()
	_last_query_key = _query_key(player_id, character_id)
	last_usage = usage

	_raise_usage_events(usage)
	return usage

## Fetches the developer account info. Returns null on failure.
func refresh_account() -> NeocortexApiAccount:
	var account := await _api_request.get_account()
	if account != null:
		last_account = account
	return account

## Returns usage, served from the cache while it is younger than
## min_refresh_interval. Falls back to the last cached value when the request
## fails; null when nothing has ever been fetched.
func get_usage_cached(player_id: String = "", character_id: String = "") -> NeocortexApiUsage:
	if player_id.is_empty():
		player_id = NeocortexSessionManager.get_player_id()

	var cache_is_fresh := last_usage != null \
		and _last_query_key == _query_key(player_id, character_id) \
		and Time.get_ticks_msec() - _last_fetch_ms < int(min_refresh_interval * 1000.0)

	if cache_is_fresh:
		return last_usage

	var usage := await refresh_usage(player_id, character_id)
	return usage if usage != null else last_usage

## Returns false when team credits are empty or the player/character is over a
## developer-configured cap. Fails open: returns true when no usage data is
## available at all (e.g. offline before the first fetch).
func can_use_smart_npc(player_id: String = "", character_id: String = "") -> bool:
	var usage := await get_usage_cached(player_id, character_id)
	if usage == null:
		return true

	return usage.status != NeocortexEnums.UsageStatus.EMPTY \
		and not usage.is_player_over_limit() \
		and not usage.is_character_over_limit()

## Same as can_use_smart_npc().
func can_use_service(player_id: String = "", character_id: String = "") -> bool:
	return await can_use_smart_npc(player_id, character_id)

## Refreshes usage on a low-frequency interval until stop_auto_refresh() is called.
func start_auto_refresh(interval_seconds: float = 300.0, player_id: String = "", character_id: String = "") -> void:
	stop_auto_refresh()
	_auto_refresh_token += 1
	_auto_refresh_loop(interval_seconds, player_id, character_id, _auto_refresh_token)

func stop_auto_refresh() -> void:
	_auto_refresh_token += 1

func _auto_refresh_loop(interval_seconds: float, player_id: String, character_id: String, token: int) -> void:
	while token == _auto_refresh_token:
		await refresh_usage(player_id, character_id)
		if token != _auto_refresh_token:
			return
		if not is_instance_valid(_api_request) or not _api_request.is_inside_tree():
			return
		await _api_request.get_tree().create_timer(interval_seconds).timeout

func _raise_usage_events(usage: NeocortexApiUsage) -> void:
	usage_updated.emit(usage)

	var is_low := usage.status == NeocortexEnums.UsageStatus.LOW
	var is_empty := usage.status == NeocortexEnums.UsageStatus.EMPTY
	var player_over := usage.is_player_over_limit()
	var character_over := usage.is_character_over_limit()

	# Threshold events fire on the transition only, so a popup hooked to them
	# shows once instead of on every refresh.
	if is_low and not _was_low:
		low_credits.emit(usage)
	if is_empty and not _was_empty:
		credits_empty.emit(usage)
	if player_over and not _was_player_over:
		player_over_limit.emit(usage)
	if character_over and not _was_character_over:
		character_over_limit.emit(usage)

	_was_low = is_low
	_was_empty = is_empty
	_was_player_over = player_over
	_was_character_over = character_over

func _query_key(player_id: String, character_id: String) -> String:
	return "%s|%s" % [player_id, character_id]
