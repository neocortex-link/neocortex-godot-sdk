extends Node

## Sample 6 (usage gating). Before each message the NeocortexUsageGate checks the team's
## credits and the per player and per character caps (free, unmetered calls, cached for
## 30 seconds) and only then lets the character answer. The log shows the account, the
## usage and every gate signal.

@export var agent: NeocortexSmartAgent
@export var text_input: NeocortexTextChatInput
@export var chat_panel: NeocortexChatPanel
@export var log_label: RichTextLabel
@export var refresh_button: Button
@export var new_session_button: Button
@export var character: NeocortexSampleCharacter

var _gate: NeocortexUsageGate
var _talking := false

func _ready() -> void:
	_gate = NeocortexUsageGate.new(self)
	_gate.usage_updated.connect(func(u: NeocortexApiUsage): _log("Usage updated: %s, %d credits left" % [_status(u), u.credits_remaining]))
	_gate.low_credits.connect(func(_u): _log("[color=orange]Credits are running low.[/color]"))
	_gate.credits_empty.connect(func(_u): _log("[color=red]Credits are empty. Smart features are off.[/color]"))
	_gate.player_over_limit.connect(func(_u): _log("[color=red]This player reached the cap set on the API key.[/color]"))
	_gate.character_over_limit.connect(func(_u): _log("[color=red]This character reached the cap set on the API key.[/color]"))
	_gate.request_failed.connect(func(error: String): _log("[color=red]Usage request failed: %s[/color]" % error))

	agent.chat_lines_mode = NeocortexEnums.ChatLinesMode.TEXT
	agent.chat_line_started.connect(func(line: NeocortexChatLine):
		chat_panel.add_message(line.text, false, character.display_name if character != null else "Character")
		_log("Line (%s): %s" % [NeocortexEnums.emotion_to_string(line.emotion), line.text]))
	agent.request_error.connect(func(error: NeocortexApiError):
		var hint := " (retry in a moment)" if error.is_retryable() else ""
		if error.is_out_of_credits():
			hint = " (out of credits)"
		_log("[color=red]%s%s[/color]" % [error.message, hint]))

	text_input.send_submitted.connect(_submit)
	refresh_button.pressed.connect(print_limits)
	new_session_button.pressed.connect(func():
		agent.clean_session_id()
		chat_panel.clear_messages())
	agent.chat_line_started.connect(func(_line): _talking = true)
	agent.reply_finished.connect(func(): _talking = false)
	print_limits()

func _process(_delta: float) -> void:
	if character != null:
		character.talking = _talking
		character.thinking = agent.is_speaking and not _talking

## Logs the account and this character's usage.
func print_limits() -> void:
	var account := await _gate.refresh_account()
	if account != null:
		_log("Account: %s tier, owner %s, %d credits, next refresh %s" % [
			account.tier, account.email, account.credits_remaining,
			account.next_refresh if not account.next_refresh.is_empty() else "-"])
	var usage := await _gate.refresh_usage("", agent.character_id)
	if usage == null:
		return
	if usage.player != null:
		_log("Player: %d interactions today, %d credits all time, over limit: %s" % [
			usage.player.interactions_today, usage.player.credits_used_all_time, usage.player.over_limit])
	if usage.character != null:
		_log("Character: %d credits all time, over limit: %s" % [
			usage.character.credits_used_all_time, usage.character.over_limit])

func _submit(message: String) -> void:
	chat_panel.add_message(message, true, "You")
	if not await _gate.can_use_service("", agent.character_id):
		_log("[color=orange]Blocked by the usage gate; the message was not sent.[/color]")
		return
	agent.text_to_text(message)

func _status(usage: NeocortexApiUsage) -> String:
	return NeocortexEnums.UsageStatus.keys()[usage.status]

func _log(text: String) -> void:
	log_label.append_text(text + "\n")
