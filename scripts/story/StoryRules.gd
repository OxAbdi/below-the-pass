extends RefCounted

# The one place that understands story conditions and story effects.
# Conversations, hotspots, maps and the chapter file all write them the same way, and all ask here.
#
#   StoryRules.check({ "flag": "ch01_met_mary", "phase": ["night1", "blackout"] })   -> true / false
#   StoryRules.apply({ "collect_evidence": "ch01_whisky" })
#
# A condition is an object. Every key must pass. A value may be one id or a list of ids
# (a list means all of them, except for "phase" and "on_map", where it means any one of them).
#
# An effect is an object with exactly one key. Simple effects change GameState on the spot.
# "Game" effects (moving James, a scene card, a cut-away...) need the screen, so they are handed
# to the running Game, which does them one after another.

const EvidenceCatalog := preload("res://scripts/data/EvidenceCatalog.gd")

const CONDITION_KEYS: Array[String] = ["has_evidence", "not_evidence", "flag", "not_flag", "link", "seen", "phase", "on_map"]
const STATE_EFFECTS: Array[String] = ["set_flag", "clear_flag", "collect_evidence", "add_trust", "unlock_proof_tier", "sound", "set_phase"]
const GAME_EFFECTS: Array[String] = ["move_player", "scene_card", "cutaway", "play", "notice", "autosave", "end_chapter", "cinematic", "cutscene"]

# The running Game scene, or null (the title screen, the test rooms, the tests).
static var host: Node = null


# ---------- conditions ----------

# `scope` is the id of the conversation asking, so "seen": "node" can mean a node of that
# conversation. From anywhere else, write "seen": "conversation_id:node".
static func check(condition: Variant, scope: String = "") -> bool:
	if not condition is Dictionary:
		return true
	var rules: Dictionary = condition
	for key: String in rules.keys():
		var values: Array[String] = as_list(rules[key])
		if key == "phase":
			if not values.has(GameState.phase):
				return false
		elif key == "on_map":
			if not values.has(str(GameState.location.get("map", ""))):
				return false
		else:
			for value: String in values:
				if not _check_one(key, value, scope):
					return false
	return true


static func _check_one(key: String, value: String, scope: String) -> bool:
	match key:
		"has_evidence":
			return GameState.has_evidence(value)
		"not_evidence":
			return not GameState.has_evidence(value)
		"flag":
			return GameState.has_flag(value)
		"not_flag":
			return not GameState.has_flag(value)
		"link":
			return GameState.has_link(value)
		"seen":
			return GameState.has_flag(seen_flag(value, scope))
	return false


# "node" inside a conversation, or "conversation_id:node" from anywhere.
static func seen_flag(value: String, scope: String) -> String:
	if value.contains(":"):
		return "seen:" + value
	return "seen:%s:%s" % [scope, value]


# A condition written as text (used by exports in the editor, which cannot hold an object).
static func parse_condition(text: String) -> Variant:
	if text.strip_edges() == "":
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_warning("StoryRules: this condition is not a JSON object: %s" % text)
	return null


# ---------- effects ----------

static func is_game_effect(effect: Dictionary) -> bool:
	for key: String in effect.keys():
		if GAME_EFFECTS.has(key):
			return true
	return false


# Applies one effect. `context` is the Game (leave it out to use the running one).
# With no Game, Game effects are skipped, so conversations still work in the test rooms.
static func apply(effect: Dictionary, context: Node = null) -> void:
	if is_game_effect(effect):
		var game: Node = context if context != null else host
		if game != null and is_instance_valid(game) and game.has_method("queue_effect"):
			game.queue_effect(effect)
		return
	apply_state_effect(effect)


static func apply_state_effect(effect: Dictionary) -> void:
	if effect.has("set_flag"):
		GameState.set_flag(str(effect["set_flag"]))
	elif effect.has("clear_flag"):
		GameState.clear_flag(str(effect["clear_flag"]))
	elif effect.has("collect_evidence"):
		GameState.collect_evidence(str(effect["collect_evidence"]))
	elif effect.has("add_trust"):
		var trust: Dictionary = effect["add_trust"]
		GameState.add_trust(str(trust.get("character", "")), int(trust.get("amount", 0)))
	elif effect.has("unlock_proof_tier"):
		GameState.unlock_proof_tier(int(effect["unlock_proof_tier"]))
	elif effect.has("sound"):
		Audio.play(str(effect["sound"]))
	elif effect.has("set_phase"):
		GameState.set_phase(str(effect["set_phase"]))


# ---------- checking for mistakes ----------

# `nodes` is the conversation's own nodes (leave empty when checking from outside a conversation).
static func validate_condition(condition: Variant, where: String, errors: Array[String], nodes: Dictionary = {}) -> void:
	if condition == null:
		return
	if not condition is Dictionary:
		errors.append("The condition in %s must be an object." % where)
		return
	var rules: Dictionary = condition
	for key: String in rules.keys():
		if not CONDITION_KEYS.has(key):
			errors.append("The condition in %s uses '%s', which is not a known condition." % [where, key])
			continue
		for value: String in as_list(rules[key]):
			if (key == "has_evidence" or key == "not_evidence") and not EvidenceCatalog.exists(value):
				errors.append("The condition in %s checks evidence '%s', which is not in the evidence registry." % [where, value])
			if key == "seen" and not value.contains(":"):
				if nodes.is_empty():
					errors.append("The condition in %s checks \"seen\": \"%s\". Outside a conversation it must be written \"conversation_id:node\"." % [where, value])
				elif not nodes.has(value):
					errors.append("The condition in %s checks node '%s', which does not exist." % [where, value])


static func validate_effect(effect: Variant, where: String, errors: Array[String]) -> void:
	if not effect is Dictionary or (effect as Dictionary).size() != 1:
		errors.append("An effect in %s must be an object with exactly one key." % where)
		return
	var key: String = str((effect as Dictionary).keys()[0])
	var value: Variant = effect[key]
	if not STATE_EFFECTS.has(key) and not GAME_EFFECTS.has(key):
		errors.append("An effect in %s uses '%s', which is not a known effect." % [where, key])
		return
	match key:
		"collect_evidence":
			if not EvidenceCatalog.exists(str(value)):
				errors.append("An effect in %s collects evidence '%s', which is not in the evidence registry." % [where, str(value)])
		"add_trust":
			if not value is Dictionary or not GameState.trust.has(str((value as Dictionary).get("character", ""))):
				errors.append("An effect in %s adds trust for a character GameState does not know." % where)
		"move_player":
			if not value is Dictionary or not (value as Dictionary).has("map") or not (value as Dictionary).has("spawn"):
				errors.append("\"move_player\" in %s needs a \"map\" and a \"spawn\"." % where)
		"scene_card":
			if not value is Dictionary or str((value as Dictionary).get("text", "")) == "":
				errors.append("\"scene_card\" in %s needs a \"text\"." % where)
		"cutaway":
			if not value is Dictionary or str((value as Dictionary).get("conversation", "")) == "":
				errors.append("\"cutaway\" in %s needs a \"conversation\"." % where)
		"notice":
			if not value is Dictionary or str((value as Dictionary).get("text", "")) == "":
				errors.append("\"notice\" in %s needs a \"text\"." % where)
		"cinematic", "cutscene":
			if str(value) == "":
				errors.append("\"%s\" in %s needs the id of a file." % [key, where])
		"end_chapter":
			if not value is Dictionary:
				errors.append("\"end_chapter\" in %s must be an object, for example { \"chapter\": 1 }." % where)


# ---------- helpers ----------

static func as_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(str(item))
	else:
		result.append(str(value))
	return result


# "beat 'b1'" -> "Beat 'b1'". (String.capitalize() would also change the words inside.)
static func cap(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}
