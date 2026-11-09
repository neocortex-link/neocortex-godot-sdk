extends Node

## Sample 5 (group chat). Characters share one conversation through a
## NeocortexGroupDirector: the player talks to the group and the director decides who
## answers. Characters in `director.agents` stay for the whole scene; each cast member
## below can join or leave with its toggle: it walks to its seat or offstage, and the
## characters present react with an ambient turn (continue_scene()). Needs a Pro or Team
## API key.

@export var director: NeocortexGroupDirector
## The characters that can join and leave. The arrays below line up by index.
@export var members: Array[NeocortexSmartAgent] = []
@export var seats: Array[Node3D] = []
@export var offstage: Array[Node3D] = []
@export var starts_present: Array[bool] = []
@export var toggles: Array[Button] = []
## What seated characters turn to face, usually the camera.
@export var face_target: Node3D
## Matches Cora's walk cycle, so her feet stay planted instead of sliding.
@export var move_speed: float = 1.6

var _present: Array[bool] = []

func _ready() -> void:
	for i in members.size():
		var present := starts_present[i] if i < starts_present.size() else true
		_present.append(present)
		var body := _body(members[i])
		body.global_position = (seats[i] if present else offstage[i]).global_position
		_face_front(body)
		if present:
			director.add_agent(members[i])
		else:
			director.remove_agent(members[i])
		if i < toggles.size() and toggles[i] != null:
			toggles[i].set_pressed_no_signal(present)
			toggles[i].toggled.connect(_on_toggle.bind(i))
	var everyone: Array[NeocortexSmartAgent] = director.agents.duplicate()
	for agent in members:
		if not everyone.has(agent):
			everyone.append(agent)
	for agent in everyone:
		_face_front(_body(agent))
		agent.reply_finished.connect(_stop_talking.bind(agent))

	director.turn_started.connect(func():
		_set_toggles_enabled(false)
		for agent in director.agents:
			_body(agent).talking = false
			_body(agent).thinking = true)
	director.turn_finished.connect(func():
		_set_toggles_enabled(true)
		for agent in director.agents:
			_body(agent).talking = false
			_body(agent).thinking = false)
	director.speaker.connect(func(message: NeocortexGroupMessage):
		for agent in director.agents:
			var speaking := agent.character_id == message.character_id
			_body(agent).talking = speaking
			_body(agent).thinking = false)

func _stop_talking(agent: NeocortexSmartAgent) -> void:
	_body(agent).talking = false

func _on_toggle(on: bool, index: int) -> void:
	if director.is_busy or on == _present[index]:
		toggles[index].set_pressed_no_signal(_present[index])
		return
	if on:
		_join(index)
	else:
		_leave(index)

func _join(index: int) -> void:
	_set_toggles_enabled(false)
	var body := _body(members[index])
	await _walk(body, seats[index].global_position)
	_face_front(body)
	_present[index] = true
	director.add_agent(members[index])
	_set_toggles_enabled(true)
	# An ambient turn: the cast notices the newcomer.
	director.continue_scene()

func _leave(index: int) -> void:
	_set_toggles_enabled(false)
	_present[index] = false
	director.remove_agent(members[index])
	await _walk(_body(members[index]), offstage[index].global_position)
	_set_toggles_enabled(true)
	director.continue_scene()

func _walk(body: NeocortexSampleCharacter, point: Vector3) -> void:
	body.walking = true
	while is_inside_tree():
		var step := point - body.global_position
		step.y = 0.0
		if step.length() < 0.05:
			break
		body.face(point)
		body.global_position += step.normalized() * minf(step.length(), move_speed * get_process_delta_time())
		await get_tree().process_frame
	body.walking = false

func _face_front(body: NeocortexSampleCharacter) -> void:
	if face_target != null:
		body.face(face_target.global_position)

func _body(agent: NeocortexSmartAgent) -> NeocortexSampleCharacter:
	return agent.get_parent() as NeocortexSampleCharacter

func _set_toggles_enabled(enabled: bool) -> void:
	for toggle in toggles:
		if toggle != null:
			toggle.disabled = not enabled
