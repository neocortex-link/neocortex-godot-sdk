@tool
extends EditorPlugin

## Starts the Neocortex editor tools (editor/neocortex_editor_tools.gd): the Neocortex dock
## and Settings window, Project > Tools > Neocortex, inspector help, and the Debugger tab.
##
## The addon's files find each other at res://addons/neocortex-godot-sdk/, so the addon has
## to live there. Installed anywhere else, this says where to move it instead of failing,
## which is why this script loads nothing else until it has checked.

const HOME := "res://addons/neocortex-godot-sdk"

var _tools: RefCounted

func _enter_tree() -> void:
	var here := (get_script() as Script).resource_path.get_base_dir()
	if here != HOME:
		_explain_location(here)
		return
	_tools = load(HOME + "/editor/neocortex_editor_tools.gd").new(self)
	_tools.enter()

func _exit_tree() -> void:
	if _tools != null:
		_tools.exit()
		_tools = null

## Opens the Settings window.
func open_settings() -> void:
	if _tools != null:
		_tools.open_settings()

func _explain_location(here: String) -> void:
	var message := ("The Neocortex addon is in %s/, but it has to be in %s/.\n\n"
		+ "Move the neocortex-godot-sdk folder into your project's addons folder, then enable "
		+ "Neocortex in Project > Project Settings > Plugins.") % [here, HOME]
	push_error("[Neocortex] " + message.replace("\n\n", " "))
	var dialog := AcceptDialog.new()
	dialog.title = "Neocortex"
	dialog.dialog_text = message
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered.call_deferred()
