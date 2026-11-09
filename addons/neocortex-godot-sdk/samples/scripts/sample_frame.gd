class_name NeocortexSampleFrame
extends Control

## The samples' screen: everything under it is laid out on a 1920 x 1080 canvas and
## scaled to the window (width and height weighed by `match_width_or_height`), so the
## samples keep their proportions at any window size.

const REFERENCE := Vector2(1920, 1080)

## 0 scales with the window's width, 1 with its height, 0.5 with both equally.
@export_range(0.0, 1.0) var match_width_or_height: float = 0.5

func _enter_tree() -> void:
	# Every sample has a frame, so this is where the launcher's character pick reaches
	# the sample's agents, before their _ready, however the sample was started.
	var scene: Node = self
	while scene.get_parent() != null and scene.get_parent() != get_tree().root:
		scene = scene.get_parent()
	NeocortexSampleCharacterPicker.apply_to_scene(scene)

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var by_width := log(screen.x / REFERENCE.x) / log(2.0)
	var by_height := log(screen.y / REFERENCE.y) / log(2.0)
	var factor := pow(2.0, lerpf(by_width, by_height, match_width_or_height))
	position = Vector2.ZERO
	scale = Vector2(factor, factor)
	size = screen / factor
