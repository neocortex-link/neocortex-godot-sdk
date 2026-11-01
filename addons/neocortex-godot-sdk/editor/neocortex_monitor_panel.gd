@tool
extends VBoxContainer

## Debugger > Neocortex: live microphone levels and agent state from the running game.
## Shows the receiver's state, an input bar with the threshold marker and the silence
## countdown, plus a row per agent.

var _receivers := {} # instance id -> { row, meter, state }
var _agents := {} # instance id -> { row, label }
var _receiver_box: VBoxContainer
var _agent_box: VBoxContainer
var _empty: Label

func _init() -> void:
	name = "Neocortex"
	add_theme_constant_override("separation", 6)
	_empty = Label.new()
	_empty.text = "Run a scene with Neocortex nodes to see live microphone levels and agent state here."
	_empty.modulate = Color(1, 1, 1, 0.6)
	add_child(_empty)
	add_child(_heading("Microphones"))
	_receiver_box = VBoxContainer.new()
	add_child(_receiver_box)
	add_child(_heading("Agents"))
	_agent_box = VBoxContainer.new()
	add_child(_agent_box)

## Clears everything (a new run started or the old one stopped).
func reset() -> void:
	for entry in _receivers.values():
		entry.row.queue_free()
	for entry in _agents.values():
		entry.row.queue_free()
	_receivers.clear()
	_agents.clear()
	_empty.visible = true

func on_message(kind: String, data: Array) -> void:
	match kind:
		"receiver":
			_update_receiver(data[0])
		"agent":
			_update_agent(data[0])
		"forget":
			_forget(int(data[0]))

func _update_receiver(state: Dictionary) -> void:
	_empty.visible = false
	var id := int(state.id)
	if not _receivers.has(id):
		var row := HBoxContainer.new()
		var title := Label.new()
		title.custom_minimum_size.x = 180
		title.text = state.name
		title.tooltip_text = state.path
		row.add_child(title)
		var meter := _Meter.new()
		meter.custom_minimum_size = Vector2(260, 18)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(meter)
		var label := Label.new()
		label.custom_minimum_size.x = 320
		row.add_child(label)
		_receiver_box.add_child(row)
		_receivers[id] = { "row": row, "meter": meter, "state": label }
	var entry: Dictionary = _receivers[id]
	var meter: _Meter = entry.meter
	# The same scale the voice input bar uses: five times the raw amplitude.
	meter.level = clampf(float(state.amplitude) * 5.0, 0.0, 1.0)
	meter.threshold = clampf(float(state.threshold) * 5.0, 0.0, 1.0)
	meter.active = state.listening
	meter.queue_redraw()
	var status := "Waiting for user input"
	if not state.listening:
		status = "Busy (mic closed)"
	elif state.speaking:
		var left := maxf(0.0, float(state.max_wait) - float(state.wait))
		status = "Recording, ends in %.1fs of silence" % left if float(state.wait) > 0.0 else "Recording"
	if state.push_to_talk:
		status += " [push to talk]"
	entry.state.text = "%s  |  %s" % [status, state.device]

func _update_agent(state: Dictionary) -> void:
	_empty.visible = false
	var id := int(state.id)
	if not _agents.has(id):
		var row := VBoxContainer.new()
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		row.add_child(HSeparator.new())
		_agent_box.add_child(row)
		_agents[id] = { "row": row, "label": label }
	var lines := PackedStringArray([
		"%s  (%s)  %s, %s%s" % [state.name, state.character_id if not str(state.character_id).is_empty() else "no character", state.mode,
			str(state.state).to_lower().replace("_", " "), (", %d queued" % state.queued) if int(state.queued) > 0 else ""],
	])
	if not str(state.line).is_empty():
		lines.append("  Last line: %s" % state.line)
	if not str(state.error).is_empty():
		lines.append("  Last error: %s" % state.error)
	if not str(state.session).is_empty():
		lines.append("  Session: %s" % state.session)
	_agents[id].label.text = "\n".join(lines)

func _forget(id: int) -> void:
	for table in [_receivers, _agents]:
		if table.has(id):
			table[id].row.queue_free()
			table.erase(id)

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderSmall"
	return label

## The input bar with a marker at the speech threshold.
class _Meter extends Control:
	var level := 0.0
	var threshold := 0.5
	var active := false

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.12, 0.13, 0.16))
		var fill := Color("#5CC98F") if level >= threshold else Color("#3B82F6")
		if not active:
			fill = Color(0.4, 0.4, 0.45)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * level, size.y)), fill)
		var x := size.x * threshold
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color("#EE6B6B"), 2.0)
