@tool
extends RefCounted

## The Neocortex editor tooling, started by plugin.gd once the addon is in place:
## - the Neocortex dock and the Settings window (Project > Tools > Neocortex > Settings),
##   which opens by itself the first time a project has no API key
## - Project > Tools > Neocortex: complete chat rigs and single widgets (and, in the SDK's
##   own repository only, the local server switch)
## - inspector help and pickers on the Neocortex nodes
## - Debugger > Neocortex: live microphone levels and agent state while the game runs

const DOCK_SCENE := preload("res://addons/neocortex-godot-sdk/dock.tscn")
const InspectorPlugin := preload("res://addons/neocortex-godot-sdk/editor/neocortex_id_inspector_plugin.gd")
const DebuggerPlugin := preload("res://addons/neocortex-godot-sdk/editor/neocortex_debugger_plugin.gd")
const SettingsWindow := preload("res://addons/neocortex-godot-sdk/editor/neocortex_settings_window.gd")

const MENU := "Neocortex"
const SHOWN_KEY := "settings_window_shown"
const LOCAL_SERVER_URL := "http://localhost:3000/api/v3"

enum Item { SETTINGS, TEXT_CHAT, VOICE_CHAT, CHAT_PANEL, TEXT_INPUT, AUDIO_INPUT, MIC_DROPDOWN, THINKING, LOCAL_SERVER, SAMPLES, DOCS }

const WIDGETS := {
	Item.CHAT_PANEL: ["ChatPanel", "res://addons/neocortex-godot-sdk/nodes/NeocortexChatPanel.tscn"],
	Item.TEXT_INPUT: ["TextChatInput", "res://addons/neocortex-godot-sdk/nodes/NeocortexTextChatInput.tscn"],
	Item.AUDIO_INPUT: ["AudioChatInput", "res://addons/neocortex-godot-sdk/nodes/NeocortexAudioChatInput.tscn"],
	Item.MIC_DROPDOWN: ["MicrophoneDropdown", "res://addons/neocortex-godot-sdk/nodes/NeocortexMicrophoneDropdown.tscn"],
	Item.THINKING: ["ThinkingIndicator", "res://addons/neocortex-godot-sdk/nodes/NeocortexThinkingIndicator.tscn"],
}

var _plugin: EditorPlugin
var _dock: Control
var _inspector: EditorInspectorPlugin
var _debugger: EditorDebuggerPlugin
var _window: Window
var _menu: PopupMenu

func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin

func enter() -> void:
	_dock = DOCK_SCENE.instantiate()
	_dock.editor_interface = _plugin.get_editor_interface()
	_plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

	_window = SettingsWindow.new()
	_window.visible = false
	_plugin.get_editor_interface().get_base_control().add_child(_window)
	_window.setup(_plugin.get_editor_interface())

	_inspector = InspectorPlugin.new(open_settings)
	_plugin.add_inspector_plugin(_inspector)

	_debugger = DebuggerPlugin.new()
	_plugin.add_debugger_plugin(_debugger)

	_menu = PopupMenu.new()
	_menu.add_item("Settings...", Item.SETTINGS)
	_menu.add_separator("Add to the open scene")
	_menu.add_item("Complete Text Chat", Item.TEXT_CHAT)
	_menu.add_item("Complete Voice Chat", Item.VOICE_CHAT)
	_menu.add_item("Chat Panel", Item.CHAT_PANEL)
	_menu.add_item("Text Chat Input", Item.TEXT_INPUT)
	_menu.add_item("Audio Chat Input", Item.AUDIO_INPUT)
	_menu.add_item("Microphone Dropdown", Item.MIC_DROPDOWN)
	_menu.add_item("Thinking Indicator", Item.THINKING)
	if _dock.developer_tools_enabled():
		_menu.add_separator("Developer")
		_menu.add_check_item("Use Local Server", Item.LOCAL_SERVER)
	_menu.add_separator()
	_menu.add_item("Open Samples", Item.SAMPLES)
	_menu.add_item("Documentation", Item.DOCS)
	_menu.id_pressed.connect(_on_menu)
	_menu.about_to_popup.connect(_sync_menu)
	_plugin.add_tool_submenu_item(MENU, _menu)

	_first_run.call_deferred()

func exit() -> void:
	_plugin.remove_tool_menu_item(MENU)
	_menu = null
	if _debugger != null:
		_plugin.remove_debugger_plugin(_debugger)
		_debugger = null
	if _inspector != null:
		_plugin.remove_inspector_plugin(_inspector)
		_inspector = null
	if _window != null:
		_window.queue_free()
		_window = null
	if _dock != null:
		_plugin.remove_control_from_docks(_dock)
		_dock.free()
		_dock = null

## Opens the Settings window.
func open_settings() -> void:
	if _window != null:
		_window.open()

# The Settings window opens once per project when there is no key yet.
func _first_run() -> void:
	var editor_settings := _plugin.get_editor_interface().get_editor_settings()
	if editor_settings.get_project_metadata(MENU, SHOWN_KEY, false):
		return
	editor_settings.set_project_metadata(MENU, SHOWN_KEY, true)
	if NeocortexSettings.get_settings().api_key.strip_edges().is_empty():
		open_settings()

func _sync_menu() -> void:
	var index := _menu.get_item_index(Item.LOCAL_SERVER)
	if index >= 0:
		_menu.set_item_checked(index, NeocortexSettings.get_settings().base_url_override == LOCAL_SERVER_URL)

func _on_menu(id: int) -> void:
	match id:
		Item.SETTINGS:
			open_settings()
		Item.TEXT_CHAT:
			_scaffold(false)
		Item.VOICE_CHAT:
			_scaffold(true)
		Item.LOCAL_SERVER:
			var settings := NeocortexSettings.get_settings()
			settings.base_url_override = "" if settings.base_url_override == LOCAL_SERVER_URL else LOCAL_SERVER_URL
			settings.save_settings()
			_dock.reload()
			print("[Neocortex] Requests from the editor go to %s" % ApiRequest.get_base_url())
		Item.SAMPLES:
			_plugin.get_editor_interface().open_scene_from_path("res://addons/neocortex-godot-sdk/samples/neocortex_samples.tscn")
		Item.DOCS:
			OS.shell_open("https://docs.neocortex.link/integrations/godot/quick-start")
		_:
			if WIDGETS.has(id):
				_add_widget(WIDGETS[id][0], load(WIDGETS[id][1]))

# Adds a wired chat rig to the open scene and selects its agent.
func _scaffold(voice: bool) -> void:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("[Neocortex] Open a scene first, then add the chat to it.")
		return
	var chat := NeocortexSceneBuilder.build_chat(root, root, voice)
	_select(chat.agent)
	print("[Neocortex] Added %s. Pick a character on the selected agent." % chat.name)

# Adds one widget under the selected Control, or under a CanvasLayer at the scene root.
func _add_widget(widget_name: String, scene: PackedScene) -> void:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("[Neocortex] Open a scene first, then add the widget to it.")
		return
	var parent: Node = null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if node is Control or node is CanvasLayer:
			parent = node
			break
	if parent == null:
		parent = root.get_node_or_null("NeocortexUI")
		if parent == null:
			parent = CanvasLayer.new()
			parent.name = "NeocortexUI"
			root.add_child(parent)
			parent.owner = root
	var node := NeocortexSceneBuilder.add_scene(parent, scene, root, widget_name)
	_select(node)

func _select(node: Node) -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	_plugin.get_editor_interface().mark_scene_as_unsaved()
