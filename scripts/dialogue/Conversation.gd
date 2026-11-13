extends RefCounted

# The rules of one conversation, read from data/dialogue/<id>.json.
#
# This script has no pictures and no input. The dialogue box asks it questions:
#   "where do we start?"            entry_node()
#   "what is in this node?"         node(id)
#   "which topics can be asked?"    visible_choices(id)
#   "he was shown this. What now?"  present(evidence_id)
# and tells it what happened (begin_node, note_statement). Everything it has to remember between
# visits is written to GameState.flags, so this object can be thrown away after every talk.
#
# Flags it writes:
#   said:<statement>                 a statement is on record
#   caught:<statement>               that lie has been caught (each one only once)
#   seen:<conversation_id>:<node>    the node has played at least once

const EvidenceCatalog := preload("res://scripts/data/EvidenceCatalog.gd")

const END: String = "end"
const CONDITION_KEYS: Array[String] = ["has_evidence", "not_evidence", "flag", "not_flag", "link", "seen"]
const EFFECT_KEYS: Array[String] = ["set_flag", "clear_flag", "collect_evidence", "add_trust", "unlock_proof_tier", "sound"]

var conversation_id: String = ""
var path: String = ""
var data: Dictionary = {}
var nodes: Dictionary = {}

# Which group of "wrong evidence" lines comes next. Only for this one talk, never saved.
var _wrong_index: int = 0


# Reads the file. Returns false when it is missing or is not valid JSON.
func load_from(file_path: String) -> bool:
	path = file_path
	data = {}
	nodes = {}
	if not FileAccess.file_exists(file_path):
		push_error("Conversation: missing file %s" % file_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not parsed is Dictionary:
		push_error("Conversation: %s is not valid JSON" % file_path)
		return false
	data = parsed
	nodes = data.get("nodes", {})
	conversation_id = str(data.get("conversation_id", data.get("dialogue_id", file_path.get_file().get_basename())))
	return true


# A file with "nodes" is a conversation. A file with only "lines" is plain dialogue.
func is_conversation() -> bool:
	return data.has("nodes")


# ---------- questions the dialogue box asks ----------

# The first entry whose condition passes decides where the talk starts.
func entry_node() -> String:
	for entry: Variant in data.get("entries", []):
		var item: Dictionary = entry
		if not item.has("if") or check(item["if"]):
			return str(item.get("node", ""))
	if nodes.has("intro"):
		return "intro"
	return END


func node(node_id: String) -> Dictionary:
	return nodes.get(node_id, {})


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)


func next_of(node_id: String) -> String:
	return str(node(node_id).get("next", END))


func can_present(node_id: String) -> bool:
	return not bool(node(node_id).get("no_present", false))


# The topics the player may pick now. Each one is { "text", "goto", "done" }.
# "done" means it was a `once` topic and has been asked already (it stays, greyed and ticked).
func visible_choices(node_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for choice: Variant in node(node_id).get("choices", []):
		var item: Dictionary = choice
		if item.has("if") and not check(item["if"]):
			continue
		var target: String = str(item.get("goto", END))
		result.append({
			"text": str(item.get("text", "")),
			"goto": target,
			"done": bool(item.get("once", false)) and GameState.has_flag(_seen_flag(target)),
		})
	return result


# Every key must pass. A value may be one id or a list of ids (then all of them must pass).
func check(condition: Variant) -> bool:
	if not condition is Dictionary:
		return true
	var rules: Dictionary = condition
	for key: String in rules.keys():
		for value: String in _as_list(rules[key]):
			if not _check_one(key, value):
				return false
	return true


func _check_one(key: String, value: String) -> bool:
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
			return GameState.has_flag(_seen_flag(value))
	return false


# ---------- things the dialogue box reports ----------

# Call when a node starts playing. Its effects happen the first time only, so reading an answer
# again never gives a clue or changes trust twice.
func begin_node(node_id: String) -> void:
	var flag: String = _seen_flag(node_id)
	if GameState.has_flag(flag):
		return
	GameState.set_flag(flag)
	for effect: Variant in node(node_id).get("effects", []):
		_apply_effect(effect)


func _apply_effect(effect: Dictionary) -> void:
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


# Call when a line is shown. A line marked as a statement goes on record.
func note_statement(line: Dictionary) -> void:
	var statement: String = str(line.get("statement", ""))
	if statement != "":
		GameState.set_flag("said:" + statement)


# James shows a piece of evidence. Returns { "caught": node_id } when it contradicts something
# this person has said and has not been caught on yet, otherwise { "wrong": lines }.
func present(evidence_id: String) -> Dictionary:
	for contradiction: Variant in data.get("contradictions", []):
		var item: Dictionary = contradiction
		var statement: String = str(item.get("statement", ""))
		if str(item.get("evidence", "")) != evidence_id:
			continue
		if not GameState.has_flag("said:" + statement) or GameState.has_flag("caught:" + statement):
			continue
		GameState.set_flag("caught:" + statement)
		return { "caught": str(item.get("goto", END)) }
	var groups: Array = data.get("wrong_present", [])
	if groups.is_empty():
		return { "wrong": [] }
	var lines: Array = groups[_wrong_index % groups.size()]
	_wrong_index += 1
	return { "wrong": lines }


# ---------- checking a file for mistakes ----------

# Returns one plain sentence per problem. An empty list means the file is fine.
# `portraits` is the "portraits" object from data/characters/portraits.json.
func validate(portraits: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not is_conversation():
		for line: Variant in data.get("lines", []):
			_validate_line(line, "lines", portraits, errors)
		return errors
	if nodes.is_empty():
		errors.append("There are no nodes.")
	for entry: Variant in data.get("entries", []):
		var item: Dictionary = entry
		_validate_target(str(item.get("node", "")), "entries", errors, false)
		_validate_condition(item.get("if", null), "entries", errors)
	for node_id: String in nodes.keys():
		var content: Dictionary = nodes[node_id]
		var where: String = "node '%s'" % node_id
		for line: Variant in content.get("lines", []):
			_validate_line(line, where, portraits, errors)
		for effect: Variant in content.get("effects", []):
			_validate_effect(effect, where, errors)
		var choices: Array = content.get("choices", [])
		for choice: Variant in choices:
			var option: Dictionary = choice
			if str(option.get("text", "")) == "":
				errors.append("A choice in %s has no text." % where)
			_validate_target(str(option.get("goto", "")), "a choice in %s" % where, errors, true)
			_validate_condition(option.get("if", null), "a choice in %s" % where, errors)
		if choices.is_empty():
			if not content.has("next"):
				errors.append("%s has no \"next\" and no \"choices\", so the talk would get stuck there." % where.capitalize())
			else:
				_validate_target(str(content["next"]), where, errors, true)
	for contradiction: Variant in data.get("contradictions", []):
		var item: Dictionary = contradiction
		var evidence_id: String = str(item.get("evidence", ""))
		if not EvidenceCatalog.exists(evidence_id):
			errors.append("A contradiction uses evidence '%s', which is not in the evidence registry." % evidence_id)
		if not _statement_exists(str(item.get("statement", ""))):
			errors.append("A contradiction answers statement '%s', but no line makes that statement." % str(item.get("statement", "")))
		_validate_target(str(item.get("goto", "")), "a contradiction", errors, false)
	for group: Variant in data.get("wrong_present", []):
		for line: Variant in group:
			_validate_line(line, "wrong_present", portraits, errors)
	return errors


func _statement_exists(statement: String) -> bool:
	for node_id: String in nodes.keys():
		for line: Variant in (nodes[node_id] as Dictionary).get("lines", []):
			if str((line as Dictionary).get("statement", "")) == statement:
				return true
	return false


func _validate_target(target: String, where: String, errors: Array[String], end_allowed: bool) -> void:
	if target == END and end_allowed:
		return
	if not nodes.has(target):
		errors.append("%s points to node '%s', which does not exist." % [where.capitalize(), target])


func _validate_line(line: Variant, where: String, portraits: Dictionary, errors: Array[String]) -> void:
	var item: Dictionary = line
	var speaker: String = str(item.get("speaker", ""))
	if str(item.get("text", "")) == "":
		errors.append("A line in %s has no text." % where)
	if speaker == "":
		if not item.has("name"):
			errors.append("A line in %s has no speaker." % where)
		return
	if not portraits.has(speaker):
		errors.append("A line in %s uses speaker '%s', who is not in portraits.json." % [where, speaker])
		return
	var expression: String = str(item.get("expression", "neutral"))
	var known: Dictionary = (portraits[speaker] as Dictionary).get("expressions", {})
	if expression != "neutral" and not known.has(expression):
		errors.append("A line in %s uses expression '%s', which '%s' does not have in portraits.json." % [where, expression, speaker])


func _validate_condition(condition: Variant, where: String, errors: Array[String]) -> void:
	if condition == null:
		return
	if not condition is Dictionary:
		errors.append("The \"if\" in %s must be an object." % where)
		return
	var rules: Dictionary = condition
	for key: String in rules.keys():
		if not CONDITION_KEYS.has(key):
			errors.append("The \"if\" in %s uses '%s', which is not a known condition." % [where, key])
			continue
		for value: String in _as_list(rules[key]):
			if (key == "has_evidence" or key == "not_evidence") and not EvidenceCatalog.exists(value):
				errors.append("The \"if\" in %s checks evidence '%s', which is not in the evidence registry." % [where, value])
			if key == "seen" and not nodes.has(value):
				errors.append("The \"if\" in %s checks node '%s', which does not exist." % [where, value])


func _validate_effect(effect: Variant, where: String, errors: Array[String]) -> void:
	if not effect is Dictionary or (effect as Dictionary).size() != 1:
		errors.append("An effect in %s must be an object with exactly one key." % where)
		return
	var key: String = str((effect as Dictionary).keys()[0])
	if not EFFECT_KEYS.has(key):
		errors.append("An effect in %s uses '%s', which is not a known effect." % [where, key])
	elif key == "collect_evidence" and not EvidenceCatalog.exists(str(effect[key])):
		errors.append("An effect in %s collects evidence '%s', which is not in the evidence registry." % [where, str(effect[key])])


# ---------- helpers ----------

func _seen_flag(node_id: String) -> String:
	return "seen:%s:%s" % [conversation_id, node_id]


func _as_list(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(str(item))
	else:
		result.append(str(value))
	return result
