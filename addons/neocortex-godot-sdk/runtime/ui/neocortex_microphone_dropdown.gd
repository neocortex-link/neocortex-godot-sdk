class_name NeocortexMicrophoneDropdown
extends OptionButton

## Lists the input devices and remembers the player's choice (NeocortexMicrophone, saved
## in user://).

func _ready() -> void:
	clear()
	for device in NeocortexMicrophone.devices():
		add_item(device)

	var saved := NeocortexMicrophone.get_selected_index()
	if item_count > 0:
		select(saved if saved >= 0 and saved < item_count else 0)

	item_selected.connect(NeocortexMicrophone.set_selected_index)
