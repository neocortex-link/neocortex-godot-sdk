class_name NeocortexThinkingIndicator
extends Control

## A pill with the character's avatar and three pulsing dots, shown while the character
## is thinking.

const _FADE_SECONDS := 0.2

@onready var _dots: Node = get_node_or_null("Row/Dots")

var _time := 0.0
var _shown := false
var _tween: Tween

func _ready() -> void:
	visible = false
	set_process(false)

func display(is_visible: bool) -> void:
	if is_visible == _shown:
		return
	_shown = is_visible
	if _tween:
		_tween.kill()
	if is_visible:
		_time = 0.0
		visible = true
		modulate.a = 0.0
		set_process(true)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if is_visible else 0.0, _FADE_SECONDS)
	if not is_visible:
		_tween.tween_callback(func():
			visible = false
			set_process(false))

func _process(delta: float) -> void:
	_time += delta
	if _dots == null:
		return
	for i in _dots.get_child_count():
		_dots.get_child(i).modulate.a = 0.3 + 0.7 * maxf(0.0, sin(_time * 5.0 - i * 0.9))
