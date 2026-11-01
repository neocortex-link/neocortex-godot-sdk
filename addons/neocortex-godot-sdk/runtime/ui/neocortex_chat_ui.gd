class_name NeocortexChatUI
extends Node

## Wires one NeocortexSmartAgent to a chat panel, a text input, a voice input and a
## thinking indicator: what the player types or says goes to the agent, and each chat
## line comes back as a bubble.
##
## Every reference is optional and found among this node's descendants when unset.

@export var agent: NeocortexSmartAgent
## How the player is labelled in the panel.
@export var player_name: String = "You"
@export var chat_panel: NeocortexChatPanel
@export var text_input: NeocortexTextChatInput
@export var audio_input: NeocortexAudioChatInput
@export var thinking_indicator: NeocortexThinkingIndicator
@export var voice_input: NeocortexAudioReceiverBase

var _character_name := ""

func _ready() -> void:
	_resolve_references()
	if agent == null:
		push_warning("[Neocortex] NeocortexChatUI has no agent.")
		return

	# This UI feeds the agent, so the agent must not also answer the mic itself.
	agent.auto_voice_input = false
	if audio_input != null and voice_input != null:
		audio_input.set_audio_receiver(voice_input)

	if text_input != null:
		text_input.send_submitted.connect(_on_text)
	if voice_input != null:
		voice_input.audio_recorded.connect(_on_audio)

	agent.transcription_received.connect(func(text: String): _add(text, true))
	agent.chat_line_started.connect(func(line: NeocortexChatLine):
		_thinking(false)
		_add(line.text, false))
	agent.composing_next_line.connect(func(): _thinking(true))
	agent.chat_response_received.connect(_on_response)
	agent.reply_finished.connect(_rearm)
	agent.chat_history_received.connect(_on_history)
	agent.request_failed.connect(func(_error: String):
		_thinking(false)
		_rearm())

func _on_text(message: String) -> void:
	_add(message, true)
	agent.text_to_text(message)
	_thinking(true)

func _on_audio(audio: AudioStreamWAV) -> void:
	agent.audio_to_audio(audio)
	_thinking(true)
	if audio_input != null:
		audio_input.set_chat_state(false)

func _on_response(response: NeocortexChatResponse) -> void:
	if not response.name.is_empty():
		_character_name = response.name
	if agent.chat_lines_mode == NeocortexEnums.ChatLinesMode.OFF:
		_thinking(false)
		_add(response.message, false)
		_rearm()

func _on_history(history: Array) -> void:
	for entry in history:
		if entry is NeocortexChatHistoryEntry:
			_add(entry.content, entry.is_user(), entry.name)

func _rearm() -> void:
	if audio_input != null:
		audio_input.set_chat_state(true)
	if voice_input != null and not voice_input.use_push_to_talk:
		voice_input.start_microphone()

func _add(text: String, is_user: bool, sender: String = "") -> void:
	if text.strip_edges().is_empty() or chat_panel == null:
		return
	if sender.is_empty():
		sender = player_name if is_user else _speaker_name()
	chat_panel.add_message(text, is_user, sender)

func _speaker_name() -> String:
	if not _character_name.is_empty():
		return _character_name
	return str(agent.get_parent().name) if agent.get_parent() != null else str(agent.name)

func _thinking(visible_now: bool) -> void:
	if thinking_indicator != null:
		thinking_indicator.display(visible_now)

func _resolve_references() -> void:
	if agent == null:
		agent = NeocortexUiUtils.find_descendant(get_parent(), NeocortexSmartAgent)
	if chat_panel == null:
		chat_panel = NeocortexUiUtils.find_descendant(self, NeocortexChatPanel)
	if text_input == null:
		text_input = NeocortexUiUtils.find_descendant(self, NeocortexTextChatInput)
	if audio_input == null:
		audio_input = NeocortexUiUtils.find_descendant(self, NeocortexAudioChatInput)
	if thinking_indicator == null:
		thinking_indicator = NeocortexUiUtils.find_descendant(self, NeocortexThinkingIndicator)
	if voice_input == null:
		voice_input = NeocortexUiUtils.find_descendant(self, NeocortexAudioReceiverBase)
