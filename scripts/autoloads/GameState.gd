extends Node

# GameState.gd - global autoload for "Below the Pass".
# Every flag, trust counter, proof tier and piece of evidence lives here.
# Scenes read and change this state, but never keep persistent state themselves.

signal evidence_added(evidence_id: String)
signal trust_changed(character: String, new_value: int)
signal proof_tier_unlocked(tier: int)
signal choice_made(choice_id: String, value: Variant)
signal link_made(link_id: String)
signal state_reset

const TRUST_MIN: int = 0
const TRUST_MAX: int = 5

var current_chapter: int = 1
var current_scene_id: String = ""

# Trust counters (0-5). Repeated trust in Brandt or Priya can lead to Ending D.
var trust: Dictionary = {
	"brandt": 0,
	"priya": 0,
	"silas": 0,
	"jonah": 0,
}

# Proof tiers decide the ending: 1 = Staging, 2 = Deaths, 3 = Present Cover-Up.
var proof_tiers: Dictionary = {
	1: false,
	2: false,
	3: false,
}

# evidence_id -> true. IDs match /data/evidence/evidence_registry.json.
var evidence_collected: Dictionary = {}

# puzzle_id -> true. IDs match /data/puzzles/*.json.
var puzzles_solved: Dictionary = {}

# Story choices, e.g. "ch02_negatives" -> "priya". Added as the story needs them.
var choices: Dictionary = {}

# Case Board. link_id -> true. IDs match the "links" in /data/puzzles/*_board.json.
var board_links: Dictionary = {}

# Case Board card positions. evidence_id -> [x, y] (an array, so it saves to JSON cleanly).
var board_layout: Dictionary = {}


func collect_evidence(evidence_id: String) -> void:
	if evidence_collected.has(evidence_id):
		return
	evidence_collected[evidence_id] = true
	evidence_added.emit(evidence_id)


func has_evidence(evidence_id: String) -> bool:
	return evidence_collected.get(evidence_id, false)


func add_trust(character: String, amount: int) -> void:
	if not trust.has(character):
		push_warning("GameState: unknown character '%s'" % character)
		return
	trust[character] = clampi(trust[character] + amount, TRUST_MIN, TRUST_MAX)
	trust_changed.emit(character, trust[character])


func get_trust(character: String) -> int:
	return trust.get(character, 0)


func unlock_proof_tier(tier: int) -> void:
	if not proof_tiers.has(tier):
		push_warning("GameState: unknown proof tier %d" % tier)
		return
	if proof_tiers[tier]:
		return
	proof_tiers[tier] = true
	proof_tier_unlocked.emit(tier)


func has_proof_tier(tier: int) -> bool:
	return proof_tiers.get(tier, false)


func get_proof_tiers_held() -> Array[int]:
	var held: Array[int] = []
	for tier: int in proof_tiers:
		if proof_tiers[tier]:
			held.append(tier)
	return held


func mark_puzzle_solved(puzzle_id: String) -> void:
	puzzles_solved[puzzle_id] = true


func is_puzzle_solved(puzzle_id: String) -> bool:
	return puzzles_solved.get(puzzle_id, false)


func set_choice(choice_id: String, value: Variant) -> void:
	choices[choice_id] = value
	choice_made.emit(choice_id, value)


func get_choice(choice_id: String, default_value: Variant = null) -> Variant:
	return choices.get(choice_id, default_value)


func add_link(link_id: String) -> void:
	if board_links.has(link_id):
		return
	board_links[link_id] = true
	link_made.emit(link_id)


func has_link(link_id: String) -> bool:
	return board_links.get(link_id, false)


func set_card_position(evidence_id: String, pos: Vector2) -> void:
	board_layout[evidence_id] = [pos.x, pos.y]


func get_card_position(evidence_id: String, fallback: Vector2) -> Vector2:
	var stored: Variant = board_layout.get(evidence_id)
	if stored is Array and stored.size() == 2:
		return Vector2(float(stored[0]), float(stored[1]))
	return fallback


func reset() -> void:
	current_chapter = 1
	current_scene_id = ""
	for character: String in trust:
		trust[character] = 0
	for tier: int in proof_tiers:
		proof_tiers[tier] = false
	evidence_collected.clear()
	puzzles_solved.clear()
	choices.clear()
	board_links.clear()
	board_layout.clear()
	state_reset.emit()


# Save/load only convert state to and from a plain Dictionary.
# SaveManager.gd (later) will write that Dictionary to a JSON file.
# JSON turns whole numbers into floats and dictionary keys into strings,
# so load_save_data converts them back.
func get_save_data() -> Dictionary:
	return {
		"current_chapter": current_chapter,
		"current_scene_id": current_scene_id,
		"trust": trust.duplicate(),
		"proof_tiers": proof_tiers.duplicate(),
		"evidence_collected": evidence_collected.duplicate(),
		"puzzles_solved": puzzles_solved.duplicate(),
		"choices": choices.duplicate(),
		"board_links": board_links.duplicate(),
		"board_layout": board_layout.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	reset()
	current_chapter = int(data.get("current_chapter", 1))
	current_scene_id = str(data.get("current_scene_id", ""))

	var saved_trust: Dictionary = data.get("trust", {})
	for character: String in saved_trust:
		if trust.has(character):
			trust[character] = clampi(int(saved_trust[character]), TRUST_MIN, TRUST_MAX)

	var saved_tiers: Dictionary = data.get("proof_tiers", {})
	for tier_key: Variant in saved_tiers:
		var tier: int = int(tier_key)
		if proof_tiers.has(tier):
			proof_tiers[tier] = bool(saved_tiers[tier_key])

	evidence_collected = data.get("evidence_collected", {}).duplicate()
	puzzles_solved = data.get("puzzles_solved", {}).duplicate()
	choices = data.get("choices", {}).duplicate()
	board_links = data.get("board_links", {}).duplicate()
	board_layout = data.get("board_layout", {}).duplicate(true)
