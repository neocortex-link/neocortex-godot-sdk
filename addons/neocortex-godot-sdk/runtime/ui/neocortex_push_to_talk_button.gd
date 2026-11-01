class_name NeocortexPushToTalkButton
extends Button

## A button that reports press-and-hold state, for push-to-talk recording.

signal pushed
signal released

func _ready() -> void:
	button_down.connect(func(): pushed.emit())
	button_up.connect(func(): released.emit())
