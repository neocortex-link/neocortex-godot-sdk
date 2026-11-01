extends "res://addons/neocortex-godot-sdk/samples/scripts/chat_sample.gd"

## Sample 4 (interactables). Three tagged shapes are in the scene; every message carries
## them as metadata, so the character knows what is where. Say "go to the blue square,
## then the red one": the reply stacks GO_TO_LOCATION actions whose target_id names an
## interactable, and the character walks to each in turn.

@export var move_speed: float = 2.0
@export var stop_distance: float = 0.1

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
		var to_target := target.global_position - character.global_position
		to_target.y = 0.0
		if to_target.length() <= stop_distance + 0.6:
			break
		character.face(target.global_position)
		character.global_position += to_target.normalized() * move_speed * get_process_delta_time()
		await get_tree().process_frame
	character.walking = false

func _find_interactable(id: String) -> NeocortexInteractable:
	for node in get_tree().get_nodes_in_group(NeocortexInteractable.GROUP):
		if node is NeocortexInteractable and node.get_id() == id:
			return node
	return null
