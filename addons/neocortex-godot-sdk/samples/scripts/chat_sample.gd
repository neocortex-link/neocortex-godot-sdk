extends Node

## Samples 1 and 2 (text and voice chat). The NeocortexChatUI does the talking; this
## script only animates the character (talking while a line plays, thinking while a
## reply is on its way) and starts a fresh conversation on the New Chat button.

@export var chat_ui: NeocortexChatUI
@export var character: NeocortexSampleCharacter
@export var new_session_button: Button
## Switches the microphone between voice detection and push to talk (voice samples).
@export var push_to_talk_toggle: Button

var agent: NeocortexSmartAgent
var _talking := false

func _ready() -> void:
	agent = chat_ui.agent
	agent.chat_line_started.connect(func(_line): _talking = true)
	agent.reply_finished.connect(func(): _talking = false)
	agent.request_failed.connect(func(_error): _talking = false)
	if new_session_button != null:
		new_session_button.pressed.connect(start_new_session)
	if push_to_talk_toggle != null and chat_ui.voice_input != null:
		push_to_talk_toggle.set_pressed_no_signal(chat_ui.voice_input.use_push_to_talk)
		push_to_talk_toggle.toggled.connect(func(on: bool): chat_ui.voice_input.use_push_to_talk = on)

func _process(_delta: float) -> void:
	if character == null:
		return
	character.talking = _talking
	character.thinking = agent.is_speaking and not _talking

## Forgets the conversation and clears the panel.
func start_new_session() -> void:
	agent.clean_session_id()
	chat_ui.chat_panel.clear_messages()
