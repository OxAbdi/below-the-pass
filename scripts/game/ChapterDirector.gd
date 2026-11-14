extends Node
## Knows the chapter's story order. It reads data/chapters/<chapter>.json and answers:
##   "which beat are we on?"   current_beat()
##   "what is the lead?"       current_lead()   (shown in the pause menu only: no quest markers)
## and, each time GameState changes, checks whether the current beat is now complete.
##
## It keeps no state of its own. A finished beat is remembered as the flag "beat:<id>" in GameState,
## so a beat can never complete twice, even after loading a save.

signal beat_completed(beat_id: String, effects: Array)

const StoryRules := preload("res://scripts/story/StoryRules.gd")

var path: String = ""
var chapter: Dictionary = {}
var beats: Array = []

var _check_queued: bool = false


func load_chapter(chapter_path: String) -> bool:
	path = chapter_path
	chapter = StoryRules.read_json(chapter_path)
	beats = chapter.get("beats", [])
	if chapter.is_empty():
		push_error("ChapterDirector: %s is missing or is not valid JSON." % chapter_path)
		return false
	return true


func _ready() -> void:
	GameState.flag_changed.connect(func(_id: String, _on: bool) -> void: queue_check())
	GameState.evidence_added.connect(func(_id: String) -> void: queue_check())
	GameState.link_made.connect(func(_id: String) -> void: queue_check())
	GameState.phase_changed.connect(func(_phase: String) -> void: queue_check())
	GameState.counter_changed.connect(func(_id: String, _value: int) -> void: queue_check())


# ---------- questions ----------

func chapter_number() -> int:
	return int(chapter.get("chapter", 1))


func chapter_title() -> String:
	return str(chapter.get("title", ""))


func start() -> Dictionary:
	return chapter.get("start", {})


func phase_info(phase_id: String) -> Dictionary:
	return (chapter.get("phases", {}) as Dictionary).get(phase_id, {})


func phase_name(phase_id: String) -> String:
	return str(phase_info(phase_id).get("name", ""))


static func beat_flag(beat_id: String) -> String:
	return "beat:" + beat_id


static func auto_flag(beat_id: String) -> String:
	return "auto:" + beat_id


# The first beat that is not finished yet. Empty when the chapter is over.
func current_beat() -> Dictionary:
	for beat: Variant in beats:
		if not GameState.has_flag(beat_flag(str((beat as Dictionary).get("id", "")))):
			return beat
	return {}


func current_lead() -> String:
	return str(current_beat().get("lead", ""))


# What the current beat wants to start by itself on this map, as an effect:
# { "play": conversation } or { "cutscene": id }, or {} for nothing.
# Asking marks it as played, so it only ever starts once.
func take_auto_play(map_id: String) -> Dictionary:
	var beat: Dictionary = current_beat()
	var auto: Dictionary = beat.get("auto_play", {})
	if auto.is_empty() or str(auto.get("map", "")) != map_id:
		return {}
	var flag: String = auto_flag(str(beat.get("id", "")))
	if GameState.has_flag(flag):
		return {}
	GameState.set_flag(flag)
	if auto.has("cutscene"):
		return { "cutscene": str(auto["cutscene"]) }
	return { "play": str(auto.get("conversation", "")) }


# ---------- completing beats ----------

func queue_check() -> void:
	if _check_queued:
		return
	_check_queued = true
	check.call_deferred()


# Completes the current beat if its condition passes, then looks at the next one, and so on.
func check() -> void:
	_check_queued = false
	while true:
		var beat: Dictionary = current_beat()
		if beat.is_empty() or not StoryRules.check(beat.get("complete_when", null)):
			return
		var beat_id: String = str(beat.get("id", ""))
		GameState.set_flag(beat_flag(beat_id))
		beat_completed.emit(beat_id, beat.get("on_complete", []))


# ---------- debug: jump to a beat ----------

# Gives GameState what a player who had just reached beat `index` would hold.
# Returns where James should stand: { "map", "spawn" }.
func grant_up_to(index: int) -> Dictionary:
	GameState.reset()
	for i: int in range(mini(index, beats.size())):
		var earlier: Dictionary = beats[i]
		_grant(earlier.get("debug_grant", {}))
		GameState.set_flag(beat_flag(str(earlier.get("id", ""))))
		if earlier.has("auto_play"):
			GameState.set_flag(auto_flag(str(earlier.get("id", ""))))
		for effect: Variant in earlier.get("on_complete", []):
			if effect is Dictionary and not StoryRules.is_game_effect(effect) and not (effect as Dictionary).has("sound"):
				StoryRules.apply_state_effect(effect)
	var grant: Dictionary = (beats[index] as Dictionary).get("debug_grant", {}) if index < beats.size() else {}
	_grant(grant)
	if grant.has("phase"):
		GameState.set_phase(str(grant["phase"]))
	elif GameState.phase == "":
		GameState.set_phase(str(start().get("phase", "")))
	return { "map": str(grant.get("map", start().get("map", ""))), "spawn": str(grant.get("spawn", start().get("spawn", ""))) }


func _grant(grant: Dictionary) -> void:
	for flag: Variant in grant.get("flags", []):
		GameState.set_flag(str(flag))
	for evidence: Variant in grant.get("evidence", []):
		GameState.collect_evidence(str(evidence))
	for link: Variant in grant.get("links", []):
		GameState.add_link(str(link))
