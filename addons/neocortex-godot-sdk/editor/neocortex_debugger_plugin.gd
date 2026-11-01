@tool
extends EditorDebuggerPlugin

## Receives the running game's NeocortexDebug messages and shows them in a Neocortex
## tab of the Debugger panel, one per debug session.

const MonitorPanel := preload("res://addons/neocortex-godot-sdk/editor/neocortex_monitor_panel.gd")

var _panels := {} # session id -> panel

func _has_capture(capture: String) -> bool:
	return capture == NeocortexDebug.PREFIX

func _capture(message: String, data: Array, session_id: int) -> bool:
	var panel = _panels.get(session_id)
	if panel == null:
		return false
	panel.on_message(message.trim_prefix(NeocortexDebug.PREFIX + ":"), data)
	return true

func _setup_session(session_id: int) -> void:
	var panel := MonitorPanel.new()
	_panels[session_id] = panel
	var session := get_session(session_id)
	session.started.connect(panel.reset)
	session.add_session_tab(panel)
