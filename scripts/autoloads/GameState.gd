extends Node

# GameState.gd - global autoload for "Below the Pass".
# Every flag, trust counter, proof tier and piece of evidence lives here.
# Scenes read and change this state, but never keep persistent state themselves.

signal evidence_added(evidence_id: String)
signal trust_changed(character: String, new_value: int)
signal proof_tier_unlocked(tier: int)
signal choice_made(choice_id: String, value: Variant)
signal link_made(link_id: String)
signal card_pinned(card_id: String)
signal card_unpinned(card_id: String)
signal question_answered(question_id: String)
signal flag_changed(flag_id: String, on: bool)
signal phase_changed(phase: String)
signal counter_changed(counter_id: String, value: int)
signal state_reset

const TRUST_MIN: int = -5  # trust can go below zero when James catches someone lying
const TRUST_MAX: int = 5

var current_chapter: int = 1
var current_scene_id: String = ""

# Hidden bonds (-5 to +5). They change later lines, who helps James, and the endings.
# Never shown to the player as numbers.
# "jonah" is only for the old test room's conversation. Milestone 6 part C removes it.
var trust: Dictionary = {
	"mary": 0,
	"katherine": 0,
	"briggs": 0,
	"ruby": 0,
	"kessler": 0,
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

# Case Board v2. Ids (clues and deductions) currently pinned on the board, in pin order.
var board_pinned: Array[String] = []

# Case Board. id -> true once the player has looked at that card or question (removes the "new" dot,
# and stops a question from sliding in a second time).
var board_seen: Dictionary = {}

# Case Board soft hint. question_id -> number of wrong links tried while that question was the oldest open one.
var board_wrong_tries: Dictionary = {}

# Case Board. True once James has said the "how to use the board" intro lines (once per save).
var board_intro_seen: bool = false

# Story flags: small yes/no facts, such as "Jonah has said he last saw her on Tuesday".
# Conversations write and read these. A flag that is not in here is off.
var flags: Dictionary = {}

# The time of day, for example "night1" or "blackout". The chapter file lists the phases.
var phase: String = ""

# Where James is. "position" is [x, y] (an array, so it saves to JSON cleanly). An empty "map"
# means a new game that has not started yet.
var location: Dictionary = { "map": "", "spawn": "", "position": [0.0, 0.0], "facing": "S" }

# Seconds played in this save (not counting the title screen or the pause menu).
var play_seconds: float = 0.0

# Small whole numbers the story needs to remember, for example frames of film left.
var counters: Dictionary = {}


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


func pin_card(card_id: String) -> void:
	if board_pinned.has(card_id):
		return
	board_pinned.append(card_id)
	card_pinned.emit(card_id)


func unpin_card(card_id: String) -> void:
	if not board_pinned.has(card_id):
		return
	board_pinned.erase(card_id)
	card_unpinned.emit(card_id)


func is_pinned(card_id: String) -> bool:
	return board_pinned.has(card_id)


func mark_seen(id: String) -> void:
	board_seen[id] = true


func has_seen(id: String) -> bool:
	return board_seen.get(id, false)


func add_wrong_try(question_id: String) -> int:
	board_wrong_tries[question_id] = get_wrong_tries(question_id) + 1
	return board_wrong_tries[question_id]


func get_wrong_tries(question_id: String) -> int:
	return int(board_wrong_tries.get(question_id, 0))


# Tells the rest of the game a question was answered. The board calls this once, at the moment the
# answering link locks. Which questions are answered is worked out from board_links, not stored.
func announce_question_answered(question_id: String) -> void:
	question_answered.emit(question_id)


func set_flag(flag_id: String) -> void:
	if flags.has(flag_id):
		return
	flags[flag_id] = true
	flag_changed.emit(flag_id, true)


func clear_flag(flag_id: String) -> void:
	if not flags.has(flag_id):
		return
	flags.erase(flag_id)
	flag_changed.emit(flag_id, false)


func has_flag(flag_id: String) -> bool:
	return flags.has(flag_id)


func set_phase(new_phase: String) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(phase)


func set_counter(counter_id: String, value: int) -> void:
	if counters.has(counter_id) and int(counters[counter_id]) == value:
		return
	counters[counter_id] = value
	counter_changed.emit(counter_id, value)


func get_counter(counter_id: String, default_value: int = 0) -> int:
	return int(counters.get(counter_id, default_value))


func set_location(map_id: String, spawn_id: String, position: Vector2, facing: String) -> void:
	location = { "map": map_id, "spawn": spawn_id, "position": [position.x, position.y], "facing": facing }


func location_position() -> Vector2:
	var stored: Variant = location.get("position", [0.0, 0.0])
	if stored is Array and (stored as Array).size() == 2:
		return Vector2(float(stored[0]), float(stored[1]))
	return Vector2.ZERO


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
	board_pinned.clear()
	board_seen.clear()
	board_wrong_tries.clear()
	board_intro_seen = false
	flags.clear()
	phase = ""
	location = { "map": "", "spawn": "", "position": [0.0, 0.0], "facing": "S" }
	play_seconds = 0.0
	counters.clear()
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
		"board_pinned": board_pinned.duplicate(),
		"board_seen": board_seen.duplicate(),
		"board_wrong_tries": board_wrong_tries.duplicate(),
		"board_intro_seen": board_intro_seen,
		"flags": flags.duplicate(),
		"phase": phase,
		"location": location.duplicate(true),
		"play_seconds": play_seconds,
		"counters": counters.duplicate(),
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
	board_pinned.assign(data.get("board_pinned", []))
	board_seen = data.get("board_seen", {}).duplicate()
	board_intro_seen = bool(data.get("board_intro_seen", false))
	flags.clear()
	for flag_id: Variant in (data.get("flags", {}) as Dictionary):
		flags[str(flag_id)] = true
	var saved_tries: Dictionary = data.get("board_wrong_tries", {})
	for question_id: Variant in saved_tries:
		board_wrong_tries[str(question_id)] = int(saved_tries[question_id])
	phase = str(data.get("phase", ""))
	var saved_location: Dictionary = data.get("location", {})
	var saved_position: Variant = saved_location.get("position", [0.0, 0.0])
	var x: float = 0.0
	var y: float = 0.0
	if saved_position is Array and (saved_position as Array).size() == 2:
		x = float(saved_position[0])
		y = float(saved_position[1])
	location = {
		"map": str(saved_location.get("map", "")),
		"spawn": str(saved_location.get("spawn", "")),
		"position": [x, y],
		"facing": str(saved_location.get("facing", "S")),
	}
	play_seconds = float(data.get("play_seconds", 0.0))
	var saved_counters: Dictionary = data.get("counters", {})
	for counter_id: Variant in saved_counters:
		counters[str(counter_id)] = int(saved_counters[counter_id])
