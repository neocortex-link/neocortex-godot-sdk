class_name NeocortexFaceAnimator
extends Node

## Lip sync for a character's face, driven by the words being spoken rather than by
## audio analysis, and timed to each clip. Works with ARKit style blend shapes (jawOpen,
## mouthFunnel, mouthPucker...) on MeshInstance3D nodes.
##
## Add it under (or beside) a NeocortexSmartAgent, or set `quiz_agent` to follow a quiz
## host. Meshes default to every MeshInstance3D with blend shapes under the agent's body
## (or its parent).

## The agent whose speech this face follows. Defaults to the parent or a sibling.
@export var agent: NeocortexSmartAgent
## A quiz host whose lines this face follows, instead of an agent. Defaults to the
## parent or a sibling when there is no agent.
@export var quiz_agent: NeocortexQuizAgent
## The node the face meshes are under. Empty: the agent's body, else its parent.
@export var face_root: Node
## The meshes to animate. Empty: every MeshInstance3D with blend shapes under face_root.
@export var meshes: Array[MeshInstance3D] = []
## How fast the mouth moves toward each shape.
@export var blend_speed: float = 10.0

enum Viseme { A, E, I, O, U, M_B_P, F_V, CH_J_SH, W_Q, L_N_T_D, R, REST }

const VISEME_SHAPES := {
	Viseme.A: { "jawopen": 0.4, "mouthlowerdownleft": 0.3, "mouthlowerdownright": 0.3 },
	Viseme.E: { "jawopen": 0.15, "mouthsmileleft": 0.3, "mouthsmileright": 0.3, "mouthstretchleft": 0.4, "mouthstretchright": 0.4 },
	Viseme.I: { "jawopen": 0.1, "mouthsmileleft": 0.4, "mouthsmileright": 0.4, "mouthdimpleleft": 0.2, "mouthdimpleright": 0.2 },
	Viseme.O: { "jawopen": 0.3, "mouthfunnel": 0.8 },
	Viseme.U: { "jawopen": 0.15, "mouthpucker": 0.8 },
	Viseme.M_B_P: { "mouthclose": 0.2, "mouthpressleft": 0.2, "mouthpressright": 0.2, "mouthrolllower": 0.1, "mouthrollupper": 0.1 },
	Viseme.F_V: { "jawopen": 0.1, "mouthrolllower": 0.6, "mouthshrugupper": 0.2 },
	Viseme.CH_J_SH: { "jawopen": 0.1, "mouthfunnel": 0.3, "mouthshrugupper": 0.2, "mouthshruglower": 0.2 },
	Viseme.W_Q: { "jawopen": 0.1, "mouthpucker": 0.9 },
	Viseme.L_N_T_D: { "mouthstretchleft": 0.3, "mouthstretchright": 0.3 },
	Viseme.R: { "jawopen": 0.1, "mouthfunnel": 0.2, "mouthpucker": 0.2, "mouthstretchleft": 0.1, "mouthstretchright": 0.1 },
	Viseme.REST: {},
}

const CHAR_VISEMES := {
	"a": Viseme.A, "e": Viseme.E, "i": Viseme.I, "y": Viseme.I, "o": Viseme.O, "u": Viseme.U,
	"m": Viseme.M_B_P, "b": Viseme.M_B_P, "p": Viseme.M_B_P,
	"f": Viseme.F_V, "v": Viseme.F_V,
	"c": Viseme.CH_J_SH, "j": Viseme.CH_J_SH, "q": Viseme.CH_J_SH, "x": Viseme.CH_J_SH, "s": Viseme.CH_J_SH, "h": Viseme.CH_J_SH,
	"w": Viseme.W_Q, "z": Viseme.W_Q,
	"l": Viseme.L_N_T_D, "n": Viseme.L_N_T_D, "t": Viseme.L_N_T_D, "d": Viseme.L_N_T_D,
	"r": Viseme.R, "g": Viseme.R,
}

# [{ mesh, index, canonical name }]
var _shapes: Array[Dictionary] = []
var _targets: Dictionary = {} # canonical name -> weight 0..1
var _timeline: Array = [] # [{ at, viseme }]
var _timeline_start_ms: int = -1
var _timeline_length_ms: int = 0
var _reply_text: String = ""
var _line_text: String = ""
var _expression: Dictionary = {}
var _random_talk := false
var _next_random_ms := 0
var _audio_started := false

func _ready() -> void:
	if agent == null:
		agent = _find_agent()
	# Deferred, so a character that builds its model in its own _ready has done so.
	_find_meshes.call_deferred()

	if agent != null:
		agent.chat_response_received.connect(func(r: NeocortexChatResponse):
			_reply_text = r.spoken_message if not r.spoken_message.is_empty() else r.message)
		agent.chat_line_started.connect(_on_line_started)
		agent.audio_response_received.connect(_on_audio)
		agent.reply_finished.connect(rest)
	elif quiz_agent == null:
		quiz_agent = _find_quiz_agent()
	if agent == null and quiz_agent != null:
		# Each host line is raised as it becomes audible; the mouth rests when the voice stops.
		quiz_agent.host_line.connect(func(line: NeocortexQuizLine): _on_host_line.call_deferred(line))
		quiz_agent.host_finished.connect(rest)

## Moves the mouth through the visemes of `text` over `duration` seconds.
func play_text(text: String, duration: float) -> void:
	_random_talk = false
	_timeline = _build_timeline(text)
	_timeline_length_ms = int(duration * 1000.0)
	_timeline_start_ms = Time.get_ticks_msec()
	_audio_started = false

## Random mouth movement, for speech you have no text for.
func start_speaking() -> void:
	_timeline.clear()
	_random_talk = true
	_next_random_ms = 0

## Closes the mouth.
func rest() -> void:
	_timeline.clear()
	_random_talk = false
	_targets.clear()

## Holds a blend shape (any ARKit style name, any casing) at a weight on top of speech.
func play_expression(shape_name: String, weight: float = 1.0) -> void:
	_expression[_canonical(shape_name)] = clampf(weight, 0.0, 1.0)

func clear_expressions() -> void:
	_expression.clear()

## Seconds of speech per character, for timing a streamed line before its length is known.
const SECONDS_PER_CHARACTER := 0.065

# A streamed line is heard before its clip exists, so the mouth starts with the line
# on an estimated length and rests when the voice stops.
func _on_line_started(line: NeocortexChatLine) -> void:
	_line_text = line.speech_text()
	var voiced := agent.chat_lines_mode == NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO 		or agent.chat_lines_mode == NeocortexEnums.ChatLinesMode.SINGLE_AUDIO
	if voiced and agent.stream_speech and ApiRequest.streamed_speech_supported:
		var per_line := agent.chat_lines_mode == NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO
		# One clip voices the whole reply: the mouth starts with its first line only.
		if not per_line and not _timeline.is_empty():
			return
		var text := _line_text if per_line else _reply_text
		play_text(text, maxf(0.5, text.length() * SECONDS_PER_CHARACTER))

func _on_audio(clip: AudioStream) -> void:
	if clip == null:
		return
	var per_line := agent.chat_lines_mode == NeocortexEnums.ChatLinesMode.PER_LINE_AUDIO
	var text := _line_text if per_line and not _line_text.is_empty() else _reply_text
	# A streamed line arrives as a clip once it has already been heard; nothing to sync.
	if clip is AudioStreamWAV and is_instance_valid(agent.audio_player) and agent.audio_player.stream is AudioStreamGenerator:
		return
	play_text(text, clip.get_length())

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var wanted := {}

	if _random_talk:
		if now >= _next_random_ms:
			_next_random_ms = now + randi_range(50, 200)
			_targets = VISEME_SHAPES[randi() % Viseme.REST].duplicate()
		wanted = _targets
	elif not _timeline.is_empty():
		var elapsed := now - _timeline_start_ms
		var player = _voice()
		if is_instance_valid(player) and player.playing:
			_audio_started = true
		# Once the voice has started and stopped, the mouth rests with it.
		var audio_done: bool = _audio_started and is_instance_valid(player) and not player.playing
		if elapsed >= _timeline_length_ms or audio_done:
			_timeline.clear()
		else:
			var position := float(elapsed) / maxf(1.0, _timeline_length_ms)
			var current: int = Viseme.REST
			for step in _timeline:
				if step.at <= position:
					current = step.viseme
				else:
					break
			wanted = VISEME_SHAPES[current]

	var alpha := minf(1.0, delta * blend_speed)
	for shape in _shapes:
		var mesh: MeshInstance3D = shape.mesh
		if not is_instance_valid(mesh):
			continue
		var target := float(wanted.get(shape.name, 0.0))
		target = maxf(target, float(_expression.get(shape.name, 0.0)))
		var value := mesh.get_blend_shape_value(shape.index)
		mesh.set_blend_shape_value(shape.index, lerpf(value, target, alpha))

func _build_timeline(text: String) -> Array:
	var steps: Array = []
	var total := 0.0
	var words := RegEx.create_from_string("[a-z]+").search_all(text.to_lower())
	var syllable := RegEx.create_from_string("[^aeiouy]*[aeiouy]+(?:[^aeiouy]*$|[^aeiouy](?=[^aeiouy]))?")
	for word_match in words:
		var word := word_match.get_string()
		var parts := syllable.search_all(word)
		var chunks: PackedStringArray = []
		for part in parts:
			chunks.append(part.get_string())
		if chunks.is_empty():
			chunks.append(word)
		for chunk in chunks:
			for c in chunk:
				var viseme: int = CHAR_VISEMES.get(c, Viseme.REST)
				var weight := 3.0 if "aeiouy".contains(c) else 1.0
				steps.append({ "viseme": viseme, "weight": weight })
				total += weight
		steps.append({ "viseme": Viseme.REST, "weight": 2.0 })
		total += 2.0

	var timeline: Array = []
	var at := 0.0
	for step in steps:
		timeline.append({ "at": at / maxf(total, 1.0), "viseme": step.viseme })
		at += step.weight
	return timeline

func _find_meshes() -> void:
	if meshes.is_empty():
		_collect_meshes(_mesh_root())
	_index_shapes()

# Where the face lives: face_root, else the agent's body, else the agent's parent.
func _mesh_root() -> Node:
	if face_root != null:
		return face_root
	if agent != null and agent.body != null:
		return agent.body
	if agent != null and agent.get_parent() != null:
		return agent.get_parent()
	return get_parent()

# Deferred, so a whole clip is already on the player and gives the line its length; a
# streamed line has none yet and is timed on an estimate.
func _on_host_line(line: NeocortexQuizLine) -> void:
	var text := line.speech_text()
	var duration := maxf(0.5, text.length() * SECONDS_PER_CHARACTER)
	var player = _voice()
	if is_instance_valid(player) and player.stream != null and not (player.stream is AudioStreamGenerator):
		duration = maxf(0.5, player.stream.get_length())
	play_text(text, duration)

# The player the voice comes out of, to rest the mouth when it stops.
func _voice() -> Node:
	if agent != null:
		return agent.audio_player
	if quiz_agent != null:
		return quiz_agent.audio_player
	return null

func _find_quiz_agent() -> NeocortexQuizAgent:
	if get_parent() is NeocortexQuizAgent:
		return get_parent()
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is NeocortexQuizAgent:
				return sibling
	return null

func _find_agent() -> NeocortexSmartAgent:
	if get_parent() is NeocortexSmartAgent:
		return get_parent()
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is NeocortexSmartAgent:
				return sibling
	return null

func _collect_meshes(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D and child.mesh != null and child.get_blend_shape_count() > 0:
			meshes.append(child)
		_collect_meshes(child)

func _index_shapes() -> void:
	_shapes.clear()
	for mesh in meshes:
		if mesh == null or mesh.mesh == null:
			continue
		for i in mesh.get_blend_shape_count():
			var shape_name := str(mesh.mesh.get_blend_shape_name(i)) if mesh.mesh is ArrayMesh else ""
			_shapes.append({ "mesh": mesh, "index": i, "name": _canonical(shape_name) })

# "Head.mouthSmile_L", "MouthSmileLeft" and "mouthSmileLeft" all become "mouthsmileleft".
static func _canonical(shape_name: String) -> String:
	var out := shape_name.get_slice(".", shape_name.get_slice_count(".") - 1).to_lower()
	if out.ends_with("_l"):
		out = out.left(-2) + "left"
	elif out.ends_with("_r"):
		out = out.left(-2) + "right"
	return out.replace("_", "")
