extends "res://addons/neocortex-godot-sdk/samples/scripts/chat_sample.gd"

## Sample 3 (actions). Ask the character to dance or jump: the reply carries a DANCE or
## JUMP action and the handler plays it. Handlers return a Signal, so stacked actions
## ("jump, then dance") play one after the other. Author the keywords on the character's
## Actions node.

func _ready() -> void:
	super()
	agent.register_action("DANCE", func(_action: NeocortexChatAction): return character.dance())
	agent.register_action("JUMP", func(_action: NeocortexChatAction): return character.jump())
