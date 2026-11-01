class_name NeocortexSampleCharacter
extends Node3D

## Cora, the character every sample uses, with her animations (idle, talking, thinking,
## walking, dance, jump). Set `talking`, `thinking` and `walking` each frame; dance()
## and jump() play once and return a Signal that fires when they end, so they work as
## action handlers. Flags blend in over 0.25 s (talking out over 0.5 s), one shots
## return to idle when done.

const CORA := preload("res://addons/neocortex-godot-sdk/samples/cora/cora.fbx")
const ANIMATIONS := preload("res://addons/neocortex-godot-sdk/samples/cora/cora_animations.res")
const LIBRARY := "cora"
const BLEND := 0.25

## Raised when a one shot (dance, jump) has finished.
signal action_finished

@export var display_name: String = "Cora":
	set(value):
		display_name = value
		if _tag != null:
			_tag.text = value
## Show the name above her head.
@export var show_name_tag: bool = false

var talking := false
var thinking := false
var walking := false

var _model: Node3D
var _player: AnimationPlayer
var _tag: Label3D
var _current := ""
var _one_shot := ""

func _ready() -> void:
	_model = CORA.instantiate()
	_model.name = "Cora"
	add_child(_model)

	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_model.add_child(_player)
	_player.root_node = NodePath("..")
	_player.add_animation_library(LIBRARY, ANIMATIONS)
	_player.animation_finished.connect(_on_animation_finished)
	_play("idle", 0.0)

	_tag = _label(display_name, 1.95)
	_tag.visible = show_name_tag

## The model's root, for a NeocortexFaceAnimator to find the face meshes under.
func get_model() -> Node3D:
	return _model

func _label(text: String, height: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = height
	label.font_size = 26
	label.outline_size = 6
	add_child(label)
	return label

func _process(_delta: float) -> void:
	# Walking overrides a one shot; otherwise a one shot plays to its end.
	if walking:
		_one_shot = ""
	elif not _one_shot.is_empty():
		return

	var wanted := "idle"
	if walking:
		wanted = "walking"
	elif talking:
		wanted = "talking"
	elif thinking:
		wanted = "thinking"
	if wanted != _current:
		_play(wanted, 0.5 if _current == "talking" else BLEND)

## Plays the dance once.
func dance() -> Signal:
	return _play_once("dance")

## Plays the jump once.
func jump() -> Signal:
	return _play_once("jump")

## Turns to face a point on the floor.
func face(point: Vector3) -> void:
	var flat := Vector3(point.x, global_position.y, point.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat, Vector3.UP, true)

func _play_once(animation: String) -> Signal:
	_one_shot = animation
	_play(animation, BLEND)
	return action_finished

func _play(animation: String, blend: float) -> void:
	_current = animation
	_player.play("%s/%s" % [LIBRARY, animation], blend)

func _on_animation_finished(animation: StringName) -> void:
	if String(animation).ends_with("/" + _one_shot) and not _one_shot.is_empty():
		_one_shot = ""
		_play("idle", BLEND)
		action_finished.emit()
