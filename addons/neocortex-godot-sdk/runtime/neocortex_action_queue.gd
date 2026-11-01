class_name NeocortexActionQueue
extends Node

## Runs the ordered ChatResponse.actions stack returned by the agent one at a time,
## waiting for each registered handler to finish before starting the next.
##
## Kept for projects built on SDK 0.1. New code should call
## NeocortexSmartAgent.register_action() instead, which honours the agent's
## action_trigger. Handlers here receive the NeocortexChatAction (name and target_id)
## and the NeocortexChatResponse.
##
## Godot handler contract (register_action):
##   - Instant handler: a Callable that returns nothing.
##   - Timed handler:   a coroutine, or a Callable that returns a Signal the queue awaits before
##                      advancing, e.g. `return get_tree().create_timer(2.0).timeout`
##                      or a custom "finished" signal on your own object.
##
## Example:
##   queue.register_action("DANCE", func(action, response): return _play_dance()) # a Signal
##   queue.register_action("JUMP", func(action, response): animator.travel("Jump")) # instant

signal unhandled_action(keyword: String)
signal queue_completed

## Agent whose responses drive the queue. Falls back to a sibling/parent agent if unset.
@export var agent: NeocortexSmartAgent

var _handlers: Dictionary = {} # keyword -> Callable
var _queue: Array = [] # [{ action, response }]
var _running: bool = false

## True while an action sequence is currently being processed.
var is_running: bool:
	get:
		return _running

func _ready() -> void:
	if agent == null:
		agent = get_parent() as NeocortexSmartAgent
	if agent == null:
		agent = _find_agent()

	if agent == null:
		push_error("[Neocortex] NeocortexActionQueue has no agent assigned.")
		return

	agent.chat_response_received.connect(_enqueue)

func _exit_tree() -> void:
	if agent != null and agent.chat_response_received.is_connected(_enqueue):
		agent.chat_response_received.disconnect(_enqueue)

## Registers a handler for an action keyword. See the class docs for the contract.
func register_action(keyword: String, handler: Callable) -> void:
	_handlers[keyword] = handler

func unregister_action(keyword: String) -> void:
	_handlers.erase(keyword)

func _enqueue(response: NeocortexChatResponse) -> void:
	if response == null:
		return

	for action in response.actions:
		if action != null and not action.name.is_empty():
			_queue.append({ "action": action, "response": response })

	if not _running and not _queue.is_empty():
		_process_queue()

func _process_queue() -> void:
	_running = true

	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var action: NeocortexChatAction = item["action"]
		var keyword := action.name

		if _handlers.has(keyword):
			var handler: Callable = _handlers[keyword]
			var result = await handler.call(action, item["response"])
			if result is Signal:
				await result
		else:
			unhandled_action.emit(keyword)
			push_warning("[Neocortex] No handler registered for action '%s'. Skipping." % keyword)

	_running = false
	queue_completed.emit()

func _find_agent() -> NeocortexSmartAgent:
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is NeocortexSmartAgent:
			return sibling
	return null
