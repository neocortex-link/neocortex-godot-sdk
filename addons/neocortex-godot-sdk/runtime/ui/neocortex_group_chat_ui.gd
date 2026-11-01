class_name NeocortexGroupChatUI
extends Node

## Wires a NeocortexGroupDirector to a chat panel, a text input and a voice input: the
## player talks to the whole cast and every speaker's turn comes back as a named bubble.

@export var director: NeocortexGroupDirector
@export var player_name: String = "You"
@export var chat_panel: NeocortexChatPanel
@export var text_input: NeocortexTextChatInput
@export var audio_input: NeocortexAudioChatInput
@export var thinking_indicator: NeocortexThinkingIndicator
@export var voice_input: NeocortexAudioReceiverBase

func _ready() -> void:
	if director == null:
		director = NeocortexUiUtils.find_descendant(get_parent(), NeocortexGroupDirector)
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

	if director == null:
		push_warning("[Neocortex] NeocortexGroupChatUI has no director.")
		return
	if audio_input != null and voice_input != null:
		audio_input.set_audio_receiver(voice_input)

	if text_input != null:
		text_input.send_submitted.connect(func(message: String):
			_add(message, true, player_name)
			director.send(message))
	if voice_input != null:
		voice_input.audio_recorded.connect(director.send_audio)

	director.player_speech.connect(func(text: String): _add(text, true, player_name))
	director.speaker.connect(func(message: NeocortexGroupMessage):
		var text := ""
		for line in message.lines:
			text += line.text
		_add(text, false, message.name))
	director.turn_started.connect(func():
		_thinking(true)
		if audio_input != null:
			audio_input.set_chat_state(false))
	director.turn_finished.connect(func():
		_thinking(false)
		_rearm())
	director.history_received.connect(func(history: Array):
		for entry in history:
			if entry is NeocortexChatHistoryEntry:
				_add(entry.content, entry.is_user(), player_name if entry.is_user() else entry.name))
	director.request_failed.connect(func(_error: String): _thinking(false))

func _rearm() -> void:
	if audio_input != null:
		audio_input.set_chat_state(true)
	if voice_input != null and not voice_input.use_push_to_talk:
		voice_input.start_microphone()

func _add(text: String, is_user: bool, sender: String) -> void:
	if chat_panel != null and not text.strip_edges().is_empty():
		chat_panel.add_message(text, is_user, sender)

func _thinking(visible_now: bool) -> void:
	if thinking_indicator != null:
		thinking_indicator.display(visible_now)
