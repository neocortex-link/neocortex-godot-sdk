class_name NeocortexQuizUI
extends Node

## Wires a NeocortexQuizAgent to a chat panel and a text input: the host's lines come in
## as bubbles, typed answers go to the host, and the input is only open while the host
## is waiting for something.

@export var agent: NeocortexQuizAgent
@export var player_name: String = "You"
@export var chat_panel: NeocortexChatPanel
@export var text_input: NeocortexTextChatInput
@export var thinking_indicator: NeocortexThinkingIndicator

func _ready() -> void:
	if agent == null:
		agent = NeocortexUiUtils.find_descendant(get_parent(), NeocortexQuizAgent)
	if chat_panel == null:
		chat_panel = NeocortexUiUtils.find_descendant(self, NeocortexChatPanel)
	if text_input == null:
		text_input = NeocortexUiUtils.find_descendant(self, NeocortexTextChatInput)
	if thinking_indicator == null:
		thinking_indicator = NeocortexUiUtils.find_descendant(self, NeocortexThinkingIndicator)
	if agent == null:
		push_warning("[Neocortex] NeocortexQuizUI has no quiz agent.")
		return

	agent.host_line.connect(func(line: NeocortexQuizLine): _add(line.text, false))
	if text_input != null:
		text_input.visible = false
		text_input.send_submitted.connect(func(message: String):
			_add(message, true)
			agent.say(message, true))
	agent.busy_changed.connect(func(busy: bool):
		if thinking_indicator != null:
			thinking_indicator.display(busy))
	agent.expecting_changed.connect(func(expecting: NeocortexEnums.QuizExpecting):
		if text_input != null:
			text_input.visible = expecting != NeocortexEnums.QuizExpecting.NOTHING)
	agent.quiz_finished.connect(func(_board: Array):
		if text_input != null:
			text_input.visible = false)
	agent.input_dropped.connect(_on_dropped)
	agent.request_failed.connect(func(error: String): _add(error, false))

func _on_dropped(_text: String, reason: NeocortexEnums.QuizInputDropReason) -> void:
	match reason:
		NeocortexEnums.QuizInputDropReason.SUPERSEDED:
			return
		NeocortexEnums.QuizInputDropReason.EXPIRED, NeocortexEnums.QuizInputDropReason.BUSY:
			_add("Sorry, I missed that. Say it again?", false)
		NeocortexEnums.QuizInputDropReason.FINISHED:
			_add("That is the end of the quiz.", false)
		NeocortexEnums.QuizInputDropReason.NO_SESSION:
			_add("The quiz has not started yet.", false)
		_:
			_add("Sorry, that did not reach me. Say it again?", false)

func _add(text: String, is_user: bool) -> void:
	if chat_panel == null or text.strip_edges().is_empty():
		return
	var host_name := str(agent.get_parent().name) if agent.get_parent() != null else "Host"
	chat_panel.add_message(text, is_user, player_name if is_user else host_name)
