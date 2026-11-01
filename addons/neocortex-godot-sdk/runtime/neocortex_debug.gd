class_name NeocortexDebug
extends RefCounted

## Sends live state to the editor's Debugger > Neocortex tab while the game runs from
## the editor (microphone levels, what each agent is doing, the last error). Does
## nothing in an exported game.

const PREFIX := "neocortex"

## True when an editor is listening.
static func is_active() -> bool:
	return EngineDebugger.is_active()

## Reports one node's state. `kind` is "receiver" or "agent".
static func report(kind: String, node: Node, state: Dictionary) -> void:
	if not EngineDebugger.is_active() or node == null:
		return
	state["id"] = node.get_instance_id()
	state["name"] = str(node.name)
	state["path"] = str(node.get_path()) if node.is_inside_tree() else str(node.name)
	EngineDebugger.send_message("%s:%s" % [PREFIX, kind], [state])

## Tells the editor a node is gone.
static func forget(node: Node) -> void:
	if EngineDebugger.is_active() and node != null:
		EngineDebugger.send_message("%s:forget" % PREFIX, [node.get_instance_id()])
