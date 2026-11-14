extends RefCounted

# Checks the story data for mistakes that only show when the files are read together:
# a door that leads to a map that does not exist, a beat that starts a conversation nobody
# wrote, a spawn point that is not in the map.
#
#   var problems: Dictionary = StoryCheck.validate_all("res://data/chapters/chapter_01.json")
#   # { "chapter_01.json": ["Beat 'ch01_b02' moves James to spawn 'frontdoor', which map 'hotel_lobby' does not have."] }
#
# An empty result means everything fits. The Game runs this once at start in debug builds and
# prints each problem as a warning, in plain words.

const StoryRules := preload("res://scripts/story/StoryRules.gd")
const ConversationScript := preload("res://scripts/dialogue/Conversation.gd")
const EvidenceCatalog := preload("res://scripts/data/EvidenceCatalog.gd")

const MAPS_PATH: String = "res://data/maps/maps.json"
const PORTRAITS_PATH: String = "res://data/characters/portraits.json"
const DIALOGUE_FOLDER: String = "res://data/dialogue/"
const CINEMATIC_FOLDER: String = "res://data/cinematics/"
const CUTSCENE_FOLDER: String = "res://data/cutscenes/"
const CUTSCENE_STEPS: Array[String] = ["walk", "face", "camera", "wait", "play", "effects", "sound"]


# `dialogue_basics`: also run each conversation's own checks (speakers, node names). The dialogue
# box already prints those once, so the Game leaves them out to avoid saying everything twice.
static func validate_all(chapter_path: String, dialogue_basics: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var context: Dictionary = _build_context(chapter_path)
	_add(result, MAPS_PATH.get_file(), _check_maps(context))
	_add(result, chapter_path.get_file(), _check_chapter(chapter_path, context))
	for cutscene_id: String in context["cutscenes"].keys():
		_add(result, cutscene_id + ".json", _check_cutscene(cutscene_id, context))
	var portraits: Dictionary = StoryRules.read_json(PORTRAITS_PATH).get("portraits", {})
	for file_name: String in context["conversations"].keys():
		var conversation: ConversationScript = ConversationScript.new()
		var errors: Array[String] = []
		if not conversation.load_from(DIALOGUE_FOLDER + file_name + ".json"):
			errors.append("The file is not valid JSON.")
		else:
			if dialogue_basics:
				errors.append_array(conversation.validate(portraits))
			for item: Dictionary in conversation.all_effects():
				_check_effect(item["effect"], item["where"], context, errors)
		_add(result, file_name + ".json", errors)
	return result


static func _add(result: Dictionary, file_name: String, errors: Array[String]) -> void:
	if not errors.is_empty():
		result[file_name] = errors


# Everything the checks need to look things up: maps, their spawn and focus points, the chapter's
# phases, and which conversations exist.
static func _build_context(chapter_path: String) -> Dictionary:
	var maps: Dictionary = StoryRules.read_json(MAPS_PATH).get("maps", {})
	var spawns: Dictionary = {}
	var focus: Dictionary = {}
	for map_id: String in maps.keys():
		spawns[map_id] = _children_of(str((maps[map_id] as Dictionary).get("scene", "")), "Spawns")
		focus[map_id] = _children_of(str((maps[map_id] as Dictionary).get("scene", "")), "Focus")
	var conversations: Dictionary = {}
	var folder: DirAccess = DirAccess.open(DIALOGUE_FOLDER)
	if folder != null:
		for file_name: String in folder.get_files():
			if file_name.ends_with(".json"):
				conversations[file_name.get_basename()] = true
	var actors: Dictionary = {}
	for map_id: String in maps.keys():
		actors[map_id] = _children_of(str((maps[map_id] as Dictionary).get("scene", "")), "Actors")
	var chapter: Dictionary = StoryRules.read_json(chapter_path)
	return { "maps": maps, "spawns": spawns, "focus": focus, "actors": actors, "conversations": conversations,
		"cinematics": _ids_in(CINEMATIC_FOLDER), "cutscenes": _ids_in(CUTSCENE_FOLDER), "phases": chapter.get("phases", {}) }


static func _ids_in(folder_path: String) -> Dictionary:
	var ids: Dictionary = {}
	var folder: DirAccess = DirAccess.open(folder_path)
	if folder != null:
		for file_name: String in folder.get_files():
			if file_name.ends_with(".json"):
				ids[file_name.get_basename()] = true
	return ids


# The names of the nodes directly under `parent_name` in a scene file, read without building the scene.
static func _children_of(scene_path: String, parent_name: String) -> Array[String]:
	var names: Array[String] = []
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return names
	var state: SceneState = (load(scene_path) as PackedScene).get_state()
	for index: int in range(state.get_node_count()):
		var parts: PackedStringArray = str(state.get_node_path(index)).trim_prefix("./").split("/")
		if parts.size() == 2 and parts[0] == parent_name:
			names.append(parts[1])
	return names


static func _check_maps(context: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var maps: Dictionary = context["maps"]
	if maps.is_empty():
		errors.append("There are no maps.")
	for map_id: String in maps.keys():
		var info: Dictionary = maps[map_id]
		var scene_path: String = str(info.get("scene", ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			errors.append("Map '%s' points to the scene '%s', which does not exist." % [map_id, scene_path])
		elif (context["spawns"][map_id] as Array).is_empty():
			errors.append("Map '%s' has no spawn points (it needs a \"Spawns\" node with at least one marker)." % map_id)
		var enter: String = str(info.get("enter", ""))
		if enter != "" and not context["conversations"].has(enter):
			errors.append("Map '%s' plays the conversation '%s' on arrival, which does not exist." % [map_id, enter])
		for phase: String in (info.get("tint", {}) as Dictionary).keys():
			if phase != "default" and not context["phases"].has(phase):
				errors.append("Map '%s' has a tint for the phase '%s', which the chapter does not have." % [map_id, phase])
	return errors


static func _check_chapter(chapter_path: String, context: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var chapter: Dictionary = StoryRules.read_json(chapter_path)
	if chapter.is_empty():
		errors.append("The file is missing or is not valid JSON.")
		return errors
	if (chapter.get("phases", {}) as Dictionary).is_empty():
		errors.append("The chapter has no \"phases\".")
	var start: Dictionary = chapter.get("start", {})
	_check_place(str(start.get("map", "")), str(start.get("spawn", "")), "\"start\"", context, errors)
	_check_phase(str(start.get("phase", "")), "\"start\"", context, errors)
	var opening: Variant = start.get("opening", "")
	if opening is Array:
		for effect: Variant in opening:
			StoryRules.validate_effect(effect, "the \"start\" opening", errors)
			if effect is Dictionary:
				_check_effect(effect, "the \"start\" opening", context, errors)
	elif str(opening) != "":
		_check_conversation(str(opening), "\"start\" opening", context, errors)
	var seen_ids: Dictionary = {}
	for beat: Variant in chapter.get("beats", []):
		var item: Dictionary = beat
		var beat_id: String = str(item.get("id", ""))
		var where: String = "beat '%s'" % beat_id
		if beat_id == "" or seen_ids.has(beat_id):
			errors.append("A beat has no id, or the id '%s' is used twice." % beat_id)
		seen_ids[beat_id] = true
		if not item.has("complete_when"):
			errors.append("%s has no \"complete_when\", so it would finish at once." % StoryRules.cap(where))
		StoryRules.validate_condition(item.get("complete_when", null), where, errors)
		for effect: Variant in item.get("on_complete", []):
			StoryRules.validate_effect(effect, where, errors)
			if effect is Dictionary:
				_check_effect(effect, where, context, errors)
		var auto: Dictionary = item.get("auto_play", {})
		if not auto.is_empty():
			if not context["maps"].has(str(auto.get("map", ""))):
				errors.append("The \"auto_play\" of %s names the map '%s', which does not exist." % [where, str(auto.get("map", ""))])
			if auto.has("cutscene"):
				_check_cutscene_id(str(auto["cutscene"]), "the \"auto_play\" of %s" % where, context, errors)
			else:
				_check_conversation(str(auto.get("conversation", "")), "the \"auto_play\" of %s" % where, context, errors)
		var grant: Dictionary = item.get("debug_grant", {})
		if grant.has("map"):
			_check_place(str(grant["map"]), str(grant.get("spawn", "")), "the \"debug_grant\" of %s" % where, context, errors)
		if grant.has("phase"):
			_check_phase(str(grant["phase"]), "the \"debug_grant\" of %s" % where, context, errors)
		for evidence: Variant in grant.get("evidence", []):
			if not EvidenceCatalog.exists(str(evidence)):
				errors.append("The \"debug_grant\" of %s gives evidence '%s', which is not in the evidence registry." % [where, str(evidence)])
	return errors


# The parts of an effect that point at other files.
static func _check_effect(effect: Dictionary, where: String, context: Dictionary, errors: Array[String]) -> void:
	if effect.has("set_phase"):
		_check_phase(str(effect["set_phase"]), "\"set_phase\" in %s" % where, context, errors)
	elif effect.has("move_player") and effect["move_player"] is Dictionary:
		var move: Dictionary = effect["move_player"]
		_check_place(str(move.get("map", "")), str(move.get("spawn", "")), "\"move_player\" in %s" % where, context, errors)
	elif effect.has("play"):
		_check_conversation(str(effect["play"]), "\"play\" in %s" % where, context, errors)
	elif effect.has("cinematic"):
		if not context["cinematics"].has(str(effect["cinematic"])):
			errors.append("\"cinematic\" in %s names '%s', which is not in data/cinematics/." % [where, str(effect["cinematic"])])
	elif effect.has("cutscene"):
		_check_cutscene_id(str(effect["cutscene"]), "\"cutscene\" in %s" % where, context, errors)
	elif effect.has("cutaway") and effect["cutaway"] is Dictionary:
		var cut: Dictionary = effect["cutaway"]
		_check_conversation(str(cut.get("conversation", "")), "\"cutaway\" in %s" % where, context, errors)
		var map_id: String = str(cut.get("map", ""))
		if map_id != "":
			if not context["maps"].has(map_id):
				errors.append("\"cutaway\" in %s names the map '%s', which does not exist." % [where, map_id])
			elif not (context["focus"][map_id] as Array).has(str(cut.get("focus", ""))):
				errors.append("\"cutaway\" in %s looks at '%s', which map '%s' does not have under its \"Focus\" node." % [where, str(cut.get("focus", "")), map_id])


static func _check_place(map_id: String, spawn_id: String, where: String, context: Dictionary, errors: Array[String]) -> void:
	if not context["maps"].has(map_id):
		errors.append("%s names the map '%s', which does not exist." % [StoryRules.cap(where), map_id])
	elif not (context["spawns"][map_id] as Array).has(spawn_id):
		errors.append("%s names the spawn '%s', which map '%s' does not have." % [StoryRules.cap(where), spawn_id, map_id])


static func _check_phase(phase: String, where: String, context: Dictionary, errors: Array[String]) -> void:
	if not context["phases"].has(phase):
		errors.append("%s names the phase '%s', which the chapter does not have." % [StoryRules.cap(where), phase])


static func _check_conversation(conversation_id: String, where: String, context: Dictionary, errors: Array[String]) -> void:
	if not context["conversations"].has(conversation_id):
		errors.append("%s names the conversation '%s', which does not exist in data/dialogue/." % [StoryRules.cap(where), conversation_id])


static func _check_cutscene_id(cutscene_id: String, where: String, context: Dictionary, errors: Array[String]) -> void:
	if not context["cutscenes"].has(cutscene_id):
		errors.append("%s names the cutscene '%s', which is not in data/cutscenes/." % [StoryRules.cap(where), cutscene_id])


# A cutscene: its map exists, every step is known, and everyone and everywhere it names is on that map.
static func _check_cutscene(cutscene_id: String, context: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var data: Dictionary = StoryRules.read_json(CUTSCENE_FOLDER + cutscene_id + ".json")
	var map_id: String = str(data.get("map", ""))
	if not context["maps"].has(map_id):
		errors.append("The cutscene's \"map\" is '%s', which does not exist." % map_id)
		return errors
	var marks: Array = (context["spawns"][map_id] as Array) + (context["focus"][map_id] as Array)
	var actors: Array = context["actors"][map_id]
	var steps: Array = data.get("steps", [])
	if steps.is_empty():
		errors.append("The cutscene has no steps.")
	for index: int in range(steps.size()):
		var step: Dictionary = steps[index] if steps[index] is Dictionary else {}
		var where: String = "step %d" % (index + 1)
		if step.size() != 1 or not CUTSCENE_STEPS.has(str(step.keys()[0])):
			errors.append("%s must be one of: %s." % [StoryRules.cap(where), ", ".join(CUTSCENE_STEPS)])
			continue
		var key: String = str(step.keys()[0])
		var value: Variant = step[key]
		match key:
			"walk", "face":
				var who: String = str((value as Dictionary).get("who", ""))
				if who != "james" and not actors.has(who):
					errors.append("%s moves '%s', who is not in map '%s' (a node under \"Actors\", or \"james\")." % [StoryRules.cap(where), who, map_id])
				if key == "walk" and not marks.has(str((value as Dictionary).get("to", ""))):
					errors.append("%s walks to '%s', which map '%s' has under neither \"Spawns\" nor \"Focus\"." % [StoryRules.cap(where), str((value as Dictionary).get("to", "")), map_id])
			"camera":
				var focus: String = str((value as Dictionary).get("focus", ""))
				if focus != "james" and not marks.has(focus):
					errors.append("%s points the camera at '%s', which map '%s' does not have." % [StoryRules.cap(where), focus, map_id])
			"play":
				_check_conversation(str(value), where, context, errors)
			"effects":
				for effect: Variant in value:
					StoryRules.validate_effect(effect, where, errors)
	return errors
