extends "res://addons/neocortex-godot-sdk/samples/scripts/chat_sample.gd"

## Sample 4 (interactables). Three tagged shapes are in the scene; every message carries
## them as metadata, so the character knows what is where. Say "go to the blue square,
## then the red one": the reply stacks GO_TO_LOCATION actions whose target_id names an
## interactable, and the character walks to each in turn.

## Matches Cora's walk cycle, so her feet stay planted instead of sliding.
@export var move_speed: float = 1.6
## How far from the object's centre she stops. 0 stops exactly on it.
@export var stop_distance: float = 0.0

func _ready() -> void:
	super()
	# Each run starts clean, so the character perceives the scene afresh.
	agent.clean_session_id()
	agent.register_action("GO_TO_LOCATION", _go_to_location)

func _go_to_location(action: NeocortexChatAction) -> void:
	var target := _find_interactable(action.target_id)
	if target == null:
		push_warning("[Neocortex] GO_TO_LOCATION names '%s', which is not in the scene." % action.target_id)
		return

	character.walking = true
	while is_inside_tree():
		# Measured on the floor, so she walks onto the object's centre.
		var to_target := target.global_position - character.global_position
		to_target.y = 0.0
		if to_target.length() <= maxf(stop_distance, 0.001):
			break
		character.face(target.global_position)
		var step := minf(move_speed * get_process_delta_time(), to_target.length())
		character.global_position += to_target.normalized() * step
		await get_tree().process_frame
	character.walking = false

func _find_interactable(id: String) -> NeocortexInteractable:
	for node in get_tree().get_nodes_in_group(NeocortexInteractable.GROUP):
		if node is NeocortexInteractable and node.get_id() == id:
			return node
	return null
