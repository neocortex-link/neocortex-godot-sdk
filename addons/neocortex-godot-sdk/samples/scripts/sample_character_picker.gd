class_name NeocortexSampleCharacterPicker
extends OptionButton

## The launcher's character and question set dropdowns: list your team's characters
## (or question sets) and remember the pick in user://. Every
## sample applies it as it loads (NeocortexSampleFrame calls apply_to_scene), so the
## samples talk to your characters without editing a scene. The scenes ship
## without character or question set ids.

const SAVE_PATH := "user://neocortex_samples.cfg"

## The character the samples use, or "" before the launcher has loaded your team.
static func get_saved_character_id() -> String:
	return str(_load().get_value("samples", "character_id", ""))

## Gives the saved picks to the agents in `scene`, before their _ready. The main
## agents get the picked character. In the group sample, the characters who join get
## your other characters in turn (a group sends each character once, so the same id
## everywhere would leave one speaker). Quiz agents get the picked question set.
static func apply_to_scene(scene: Node) -> void:
	var config := _load()
	var picked := str(config.get_value("samples", "character_id", ""))
	if picked.is_empty():
		return
	var others: Array = Array(config.get_value("samples", "other_character_ids", PackedStringArray()))
	var question_set := str(config.get_value("samples", "question_set_id", ""))

	var standing: Array = []
	for director in scene.find_children("*", "NeocortexGroupDirector", true, false):
		standing.append_array(director.agents)
	var guests := 0
	for agent in scene.find_children("*", "NeocortexSmartAgent", true, false):
		if standing.is_empty() or standing.has(agent):
			agent.character_id = picked
		else:
			agent.character_id = others[guests % others.size()] if not others.is_empty() else picked
			guests += 1
	for agent in scene.find_children("*", "NeocortexQuizAgent", true, false):
		agent.character_id = picked
		if not question_set.is_empty():
			agent.question_set_id = question_set

static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	return config

## What this dropdown picks: a character, or a question set for the quiz.
enum Kind { CHARACTERS, QUESTION_SETS }

@export var kind := Kind.CHARACTERS
var _items: Array = []

func _ready() -> void:
	clip_text = true
	fit_to_longest_item = false
	if kind == Kind.CHARACTERS:
		tooltip_text = "The character every sample uses"
	else:
		tooltip_text = "The question set the quiz uses"
	item_selected.connect(func(_index: int): _save())
	_load_team()

func _load_team() -> void:
	clear()
	disabled = true
	if NeocortexSettings.get_settings().api_key.is_empty():
		add_item("Add your API key first")
		return
	var characters := kind == Kind.CHARACTERS
	add_item("Loading your characters..." if characters else "Loading your question sets...")
	var request := ApiRequest.new()
	add_child(request)
	var items = null
	if characters:
		items = await request.get_characters()
	else:
		items = await request.get_question_sets()
	var error := request.last_error
	request.queue_free()
	clear()
	if items == null:
		add_item("Could not load your characters" if characters else "Could not load your question sets")
		tooltip_text = error
		return
	if items.is_empty():
		add_item("No characters" if characters else "No question sets")
		tooltip_text = "Create one in the Neocortex dashboard."
		if not characters:
			_store("question_set_id", "")
		return

	_items = items
	var key := "character_id" if characters else "question_set_id"
	var saved := str(_load().get_value("samples", key, ""))
	for item in items:
		add_item(item.name if characters else "%s (%d questions)" % [item.name, item.question_count])
		if item.id == saved:
			select(item_count - 1)
	if not items.any(func(item): return item.id == saved):
		select(0)
	disabled = false
	_save()

func _save() -> void:
	if selected < 0 or selected >= _items.size():
		return
	var picked: String = _items[selected].id
	if kind == Kind.QUESTION_SETS:
		_store("question_set_id", picked)
		return
	var others := PackedStringArray()
	for character in _items:
		if character.id != picked:
			others.append(character.id)
	var config := _load()
	config.set_value("samples", "character_id", picked)
	config.set_value("samples", "other_character_ids", others)
	config.save(SAVE_PATH)

static func _store(key: String, value: String) -> void:
	var config := _load()
	config.set_value("samples", key, value)
	config.save(SAVE_PATH)
