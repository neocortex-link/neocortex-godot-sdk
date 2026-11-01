class_name NeocortexSampleCharacterPicker
extends OptionButton

## The launcher's character dropdown: lists your team's characters and remembers the
## pick, with your team's other characters and question sets (in user://). Every
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
## everywhere would leave one speaker). Quiz agents get your first question set.
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

var _characters: Array = []
var _question_set_id := ""

func _ready() -> void:
	clip_text = true
	fit_to_longest_item = false
	tooltip_text = "The character every sample uses"
	item_selected.connect(func(_index: int): _save())
	_load_team()

func _load_team() -> void:
	disabled = true
	if NeocortexSettings.get_settings().api_key.is_empty():
		add_item("Add your API key first")
		return
	add_item("Loading your characters...")
	var request := ApiRequest.new()
	add_child(request)
	var characters = await request.get_characters()
	var question_sets = await request.get_question_sets() if characters != null else null
	var error := request.last_error
	request.queue_free()
	clear()
	if characters == null or characters.is_empty():
		add_item("No characters" if characters != null else "Could not load your characters")
		tooltip_text = error if characters == null else "Create a character in the Neocortex dashboard."
		return

	_characters = characters
	_question_set_id = question_sets[0].id if question_sets != null and not question_sets.is_empty() else ""
	var saved := get_saved_character_id()
	for character in characters:
		add_item(character.name)
		if character.id == saved:
			select(item_count - 1)
	if not characters.any(func(c): return c.id == saved):
		select(0)
	disabled = false
	_save()

func _save() -> void:
	if selected < 0 or selected >= _characters.size():
		return
	var picked: String = _characters[selected].id
	var others := PackedStringArray()
	for character in _characters:
		if character.id != picked:
			others.append(character.id)
	var config := _load()
	config.set_value("samples", "character_id", picked)
	config.set_value("samples", "other_character_ids", others)
	config.set_value("samples", "question_set_id", _question_set_id)
	config.save(SAVE_PATH)
