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

#
# Conditions ("if") and effects are understood by StoryRules.gd, the same as everywhere else.

const EvidenceCatalog := preload("res://scripts/data/EvidenceCatalog.gd")
const StoryRules := preload("res://scripts/story/StoryRules.gd")

const END: String = "end"
const LINE_STYLES: Array[String] = ["", "thought", "action", "voice"]

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


# Where the talk goes after this node's lines. "next_if" is tried first: the first entry whose
# condition passes wins. Otherwise "next".
func next_of(node_id: String) -> String:
	for branch: Variant in node(node_id).get("next_if", []):
		var item: Dictionary = branch
		if check(item.get("if", null)):
			return str(item.get("node", END))
	return str(node(node_id).get("next", END))


# A node with no lines and no topics: it only runs its effects and moves on, showing nothing.
func is_silent(node_id: String) -> bool:
	var content: Dictionary = node(node_id)
	return (content.get("lines", []) as Array).is_empty() and (content.get("choices", []) as Array).is_empty()


# The short pencil label above the topics, for example "Briggs is testing you".
func choice_tag(node_id: String) -> String:
	return str(node(node_id).get("choice_tag", ""))


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


func check(condition: Variant) -> bool:
	return StoryRules.check(condition, conversation_id)


# ---------- things the dialogue box reports ----------

# Call when a node starts playing. Its effects happen the first time only, so reading an answer
# again never gives a clue or changes trust twice.
func begin_node(node_id: String) -> void:
	var flag: String = _seen_flag(node_id)
	if GameState.has_flag(flag):
		return
	GameState.set_flag(flag)
	for effect: Variant in node(node_id).get("effects", []):
		StoryRules.apply(effect)


# Call when a line is shown. A line marked as a statement goes on record.
func note_statement(line: Dictionary) -> void:
	var statement: String = str(line.get("statement", ""))
	if statement != "":
		GameState.set_flag("said:" + statement)


# James shows a piece of evidence. Returns:
#   { "caught": node_id }    it contradicts something this person said (each lie only once)
#   { "reaction": node_id }  this person has something to say about it (every time; no lie caught)
#   { "wrong": lines }       anything else
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
	for reaction: Variant in data.get("reactions", []):
		if str((reaction as Dictionary).get("evidence", "")) == evidence_id:
			return { "reaction": str((reaction as Dictionary).get("goto", END)) }
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
		_validate_target(str(item.get("node", "")), "entries", errors, true)
		_validate_condition(item.get("if", null), "entries", errors)
	for node_id: String in nodes.keys():
		var content: Dictionary = nodes[node_id]
		var where: String = "node '%s'" % node_id
		for line: Variant in content.get("lines", []):
			_validate_line(line, where, portraits, errors)
		for effect: Variant in content.get("effects", []):
			StoryRules.validate_effect(effect, where, errors)
		for branch: Variant in content.get("next_if", []):
			_validate_target(str((branch as Dictionary).get("node", "")), "\"next_if\" in %s" % where, errors, true)
			_validate_condition((branch as Dictionary).get("if", null), "\"next_if\" in %s" % where, errors)
		var choices: Array = content.get("choices", [])
		for choice: Variant in choices:
			var option: Dictionary = choice
			if str(option.get("text", "")) == "":
				errors.append("A choice in %s has no text." % where)
			_validate_target(str(option.get("goto", "")), "a choice in %s" % where, errors, true)
			_validate_condition(option.get("if", null), "a choice in %s" % where, errors)
		if choices.is_empty():
			if not content.has("next"):
				errors.append("%s has no \"next\" and no \"choices\", so the talk would get stuck there." % StoryRules.cap(where))
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
	for reaction: Variant in data.get("reactions", []):
		var evidence_id: String = str((reaction as Dictionary).get("evidence", ""))
		if not EvidenceCatalog.exists(evidence_id):
			errors.append("A reaction uses evidence '%s', which is not in the evidence registry." % evidence_id)
		_validate_target(str((reaction as Dictionary).get("goto", "")), "a reaction", errors, false)
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
		errors.append("%s points to node '%s', which does not exist." % [StoryRules.cap(where), target])


func _validate_line(line: Variant, where: String, portraits: Dictionary, errors: Array[String]) -> void:
	var item: Dictionary = line
	var speaker: String = str(item.get("speaker", ""))
	var style: String = str(item.get("style", ""))
	if str(item.get("text", "")) == "":
		errors.append("A line in %s has no text." % where)
	if not LINE_STYLES.has(style):
		errors.append("A line in %s uses style '%s'. Known styles: thought, action, voice." % [where, style])
	if style == "action":
		return
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
	StoryRules.validate_condition(condition, where, errors, nodes)


# Every effect in the file, as [{ "effect": {...}, "where": "node 'x'" }]. Used by the wider checks
# (does that map exist, does that conversation exist), which need more than this one file.
func all_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node_id: String in nodes.keys():
		for effect: Variant in (nodes[node_id] as Dictionary).get("effects", []):
			if effect is Dictionary:
				result.append({ "effect": effect, "where": "node '%s'" % node_id })
	return result


# ---------- helpers ----------

func _seen_flag(node_id: String) -> String:
	return "seen:%s:%s" % [conversation_id, node_id]
