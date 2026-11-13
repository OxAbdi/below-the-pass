extends RefCounted

# One place that knows what every piece of evidence looks like and what James holds.
# The case board, the notebook and the "present evidence" picker all ask here, so a clue has the
# same name, colour and look everywhere.
#
# It reads two kinds of data file and remembers them:
#   data/evidence/evidence_registry.json   - the clues
#   data/puzzles/*_board.json              - the links, which create deductions (Leads and Conclusions)

const REGISTRY_PATH: String = "res://data/evidence/evidence_registry.json"
const PUZZLES_FOLDER: String = "res://data/puzzles/"
const DEFAULT_ACCENT: String = "#d9ad4d"
const GOLD: Color = Color(0.98, 0.8, 0.36)

static var _loaded: bool = false
static var _evidence: Dictionary = {}  # evidence_id -> its registry entry
static var _evidence_order: Array[String] = []
static var _deduction_link: Dictionary = {}  # deduction_id -> the link that makes it
static var _deduction_order: Array[String] = []
static var _lead_ids: Dictionary = {}  # deduction_id -> true when another link builds on it


# Forget everything and read the files again (used by tests and after data edits).
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_evidence.clear()
	_evidence_order.clear()
	_deduction_link.clear()
	_deduction_order.clear()
	_lead_ids.clear()
	_evidence = _read_json(REGISTRY_PATH).get("evidence", {})
	for id: String in _evidence.keys():
		_evidence_order.append(id)
	var folder: DirAccess = DirAccess.open(PUZZLES_FOLDER)
	if folder == null:
		return
	var files: Array[String] = []
	for file_name: String in folder.get_files():
		if file_name.ends_with("_board.json"):
			files.append(file_name)
	files.sort()
	for file_name: String in files:
		for link: Variant in _read_json(PUZZLES_FOLDER + file_name).get("links", []):
			var deduction_id: String = str((link as Dictionary).get("deduction_id", ""))
			if deduction_id != "":
				_deduction_link[deduction_id] = link
				_deduction_order.append(deduction_id)
	for deduction_id: String in _deduction_order:
		for part: Variant in (_deduction_link[deduction_id] as Dictionary).get("pair", []):
			if _deduction_link.has(str(part)):
				_lead_ids[str(part)] = true


static func exists(id: String) -> bool:
	_ensure_loaded()
	return _evidence.has(id) or _deduction_link.has(id)


static func is_deduction(id: String) -> bool:
	_ensure_loaded()
	return _deduction_link.has(id)


# A Lead is a deduction that another link still builds on. Otherwise it is a Conclusion.
static func is_lead(id: String) -> bool:
	_ensure_loaded()
	return _lead_ids.has(id)


# What to show for a clue or a deduction: { name, description, style, accent }.
static func item_info(id: String) -> Dictionary:
	_ensure_loaded()
	if _deduction_link.has(id):
		var link: Dictionary = _deduction_link[id]
		var lead: bool = _lead_ids.has(id)
		return {
			"name": str(link.get("deduction", id)),
			"description": str(link.get("deduction_text", "")),
			"style": "lead" if lead else "conclusion",
			# A Lead carries the blended colour of the link it came from.
			"accent": blend_accent(id) if lead else GOLD,
		}
	var info: Dictionary = _evidence.get(id, {})
	return {
		"name": str(info.get("name", id)),
		"description": str(info.get("description", "")),
		"style": str(info.get("card_style", "note")),
		"accent": accent_for(id),
	}


static func accent_for(evidence_id: String) -> Color:
	_ensure_loaded()
	var info: Dictionary = _evidence.get(evidence_id, {})
	return Color.html(str(info.get("accent", DEFAULT_ACCENT)))


# The colour of a clue, or for a deduction the mix of the clues it was built from.
static func blend_accent(id: String) -> Color:
	_ensure_loaded()
	if _deduction_link.has(id):
		var pair: Array = (_deduction_link[id] as Dictionary).get("pair", [])
		if pair.size() == 2:
			return blend_accent(str(pair[0])).lerp(blend_accent(str(pair[1])), 0.5)
		return GOLD
	return accent_for(id)


# Everything James can show someone, in notebook order: clues, then Leads, then Conclusions.
# Nothing is stored here: it is worked out from GameState every time.
static func held_items(state: Node) -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for id: String in _evidence_order:
		if state.has_evidence(id):
			result.append(id)
	var conclusions: Array[String] = []
	for deduction_id: String in _deduction_order:
		var link_id: String = str((_deduction_link[deduction_id] as Dictionary).get("link_id", ""))
		if not state.has_link(link_id):
			continue
		if _lead_ids.has(deduction_id):
			result.append(deduction_id)
		else:
			conclusions.append(deduction_id)
	result.append_array(conclusions)
	return result


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("EvidenceCatalog: missing file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("EvidenceCatalog: %s is not valid JSON" % path)
	return {}
