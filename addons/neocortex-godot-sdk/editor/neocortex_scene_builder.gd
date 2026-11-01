@tool
class_name NeocortexSceneBuilder
extends RefCounted

## Builds ready wired chat rigs from the SDK's nodes. Used by the editor's
## Project > Tools > Neocortex menu (Complete Text Chat, Complete Voice Chat).

const CHAT_PANEL := preload("res://addons/neocortex-godot-sdk/nodes/NeocortexChatPanel.tscn")
const TEXT_INPUT := preload("res://addons/neocortex-godot-sdk/nodes/NeocortexTextChatInput.tscn")
const AUDIO_INPUT := preload("res://addons/neocortex-godot-sdk/nodes/NeocortexAudioChatInput.tscn")
const THINKING := preload("res://addons/neocortex-godot-sdk/nodes/NeocortexThinkingIndicator.tscn")
const MIC_DROPDOWN := preload("res://addons/neocortex-godot-sdk/nodes/NeocortexMicrophoneDropdown.tscn")

## A NeocortexChatUI with a panel, an input (typed or voice), a thinking indicator and
## the agent it drives, wired together. `owner` is the scene root the nodes are saved
## under (the edited scene, or null for runtime use). Returns the NeocortexChatUI.
static func build_chat(parent: Node, owner: Node, voice: bool, character_id: String = "", side_panel: bool = false) -> NeocortexChatUI:
	var chat := NeocortexChatUI.new()
	chat.name = "NeocortexVoiceChat" if voice else "NeocortexTextChat"
	_add(parent, chat, owner)

	var agent := add_agent(chat, owner, "Character", character_id,
		NeocortexEnums.ChatLinesMode.SINGLE_AUDIO if voice else NeocortexEnums.ChatLinesMode.TEXT)
	chat.agent = agent

	var column := add_ui_column(chat, owner, "UI", side_panel)
	chat.chat_panel = add_scene(column, CHAT_PANEL, owner, "ChatPanel")
	chat.chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.thinking_indicator = add_scene(column, THINKING, owner, "ThinkingIndicator")

	if voice:
		var receiver := NeocortexAudioReceiver.new()
		receiver.name = "Microphone"
		_add(chat, receiver, owner)
		chat.voice_input = receiver
		chat.audio_input = add_scene(column, AUDIO_INPUT, owner, "AudioChatInput")
		chat.audio_input.audio_receiver = receiver
		# At the top, so the device picker is never pushed off a small window.
		var dropdown := add_scene(column, MIC_DROPDOWN, owner, "MicrophoneDropdown")
		column.move_child(dropdown, 0)
	else:
		chat.text_input = add_scene(column, TEXT_INPUT, owner, "TextChatInput")
	return chat

## A NeocortexSmartAgent with its own AudioStreamPlayer.
static func add_agent(parent: Node, owner: Node, agent_name: String, character_id: String,
		mode: NeocortexEnums.ChatLinesMode) -> NeocortexSmartAgent:
	var agent := NeocortexSmartAgent.new()
	agent.name = agent_name
	agent.character_id = character_id
	agent.chat_lines_mode = mode
	_add(parent, agent, owner)
	var voice := AudioStreamPlayer.new()
	voice.name = "Voice"
	_add(agent, voice, owner)
	agent.audio_player = voice
	return agent

## A CanvasLayer holding a padded VBoxContainer: full screen, or the right 45% of the
## screen with `side_panel` (so a character stays visible on the left). Returns the column.
static func add_ui_column(parent: Node, owner: Node, layer_name: String = "UI", side_panel: bool = false) -> VBoxContainer:
	var layer := CanvasLayer.new()
	layer.name = layer_name
	_add(parent, layer, owner)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if side_panel:
		margin.anchor_left = 0.55
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_add(layer, margin, owner)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	_add(margin, column, owner)
	return column

## Instances an SDK scene under `parent`.
static func add_scene(parent: Node, scene: PackedScene, owner: Node, node_name: String) -> Node:
	var node := scene.instantiate()
	node.name = node_name
	_add(parent, node, owner)
	return node

static func _add(parent: Node, node: Node, owner: Node) -> void:
	parent.add_child(node)
	if owner != null:
		node.owner = owner
