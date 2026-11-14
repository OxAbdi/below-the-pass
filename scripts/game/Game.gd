extends Node
## The Game scene: the one scene that stays loaded the whole time you play. It swaps only the map
## inside it, like a theatre that keeps its stage and curtains and changes the scenery between acts.
##
## What it does:
##   - loads one map at a time into World and puts James in it
##   - runs the camera, the fades, scene cards and cut-aways
##   - opens the case board, the loupe and the pause menu
##   - does story effects one after another (the "queue")
##   - starts the conversations the story asks for
##
## What it does NOT do: remember anything. Flags, evidence, the time of day, where James stands and
## the play time all live in GameState. The chapter's order lives in the Director.

const StoryRules := preload("res://scripts/story/StoryRules.gd")
const StoryCheck := preload("res://scripts/story/StoryCheck.gd")
const RuntimeSetup := preload("res://scripts/ui/RuntimeSetup.gd")
const MapBaseScript := preload("res://scripts/game/MapBase.gd")
const DirectorScript := preload("res://scripts/game/ChapterDirector.gd")
const PlayerScript := preload("res://scripts/world/Player.gd")
const HotspotScript := preload("res://scripts/world/Hotspot.gd")
const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")
const FadeScript := preload("res://scripts/ui/FadeLayer.gd")
const LetterboxScript := preload("res://scripts/ui/Letterbox.gd")
const ChapterCardScript := preload("res://scripts/ui/ChapterCard.gd")
const PauseMenuScript := preload("res://scripts/ui/PauseMenu.gd")
const MenuSlipsScript := preload("res://scripts/ui/menu/MenuSlips.gd")
const CaseBoardScript := preload("res://scripts/mechanics/CaseBoard.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const KeyGlyphs := preload("res://scripts/ui/KeyGlyphs.gd")
const CinematicScript := preload("res://scripts/ui/cinema/Cinematic.gd")
const ControlsHintScript := preload("res://scripts/ui/ControlsHint.gd")

const PlayerScene: PackedScene = preload("res://scenes/world/player.tscn")
const BoardScene: PackedScene = preload("res://scenes/mechanics/case_board.tscn")
const LoupeScene: PackedScene = preload("res://scenes/mechanics/loupe_examination.tscn")

const START_PATH: String = "res://data/chapters/start.json"
const MAPS_PATH: String = "res://data/maps/maps.json"
const MENUS_PATH: String = "res://data/ui/menus.json"
const DIALOGUE_FOLDER: String = "res://data/dialogue/"
const CUTSCENE_FOLDER: String = "res://data/cutscenes/"
const PUZZLE_FOLDER: String = "res://data/puzzles/"
const DEFAULT_BOARD: String = "res://data/puzzles/ch01_board.json"
const TITLE_SCENE: String = "res://scenes/ui/title.tscn"
const GAME_SCENE: String = "res://scenes/game/game.tscn"

const TRAVEL_FADE: float = 0.3
const START_FADE: float = 0.6
const CUTAWAY_GLIDE: float = 0.6
const CAMERA_FOLLOW_SPEED: float = 9.0
const CAMERA_HEIGHT_OFFSET: Vector2 = Vector2(0.0, -60.0)
const PAUSE_ACTION: String = "pause"

@onready var world: Node2D = $World
@onready var camera: Camera2D = $Camera2D
@onready var director: DirectorScript = $Director
@onready var board_layer: CanvasLayer = $Board
@onready var loupe_layer: CanvasLayer = $Loupe
@onready var overlay_layer: CanvasLayer = $Overlay
@onready var letterbox: LetterboxScript = $Letterbox/Bars
@onready var chapter_card: ChapterCardScript = $ChapterCard/Card
@onready var fade: FadeScript = $Fade/Curtain
@onready var dialogue: DialogueBoxScript = $Dialogue/DialogueBox
@onready var pause: PauseMenuScript = $Pause/PauseMenu
@onready var cinematic: CinematicScript = $Cinema/Film
@onready var hint: ControlsHintScript = $Hint/Controls

var maps: Dictionary = {}
var menus: Dictionary = {}
var map: MapBaseScript = null
var player: PlayerScript = null
var board: CaseBoardScript = null
var loupe: Control = null
var overlay: Control = null

var started: bool = false
var in_cutaway: bool = false
var in_cutscene: bool = false
var ending: bool = false

var _queue: Array[Dictionary] = []
var _running: bool = false          # true while the queue is doing effects
var _camera_free: bool = false      # true while a cut-away moves the camera itself
var _stashed_map: MapBaseScript = null
var _jump_list: Control = null


func _ready() -> void:
	process_priority = 10   # run AFTER James has moved this frame, so the camera never lags a frame behind
	RuntimeSetup.apply(get_tree())
	StoryRules.host = self
	get_tree().paused = false
	_ensure_pause_action()
	maps = StoryRules.read_json(MAPS_PATH).get("maps", {})
	menus = StoryRules.read_json(MENUS_PATH)
	$SaveIndicator/Saving.text = str(menus.get("saving", "Saving…"))
	hint.texts = menus.get("hints", {})
	var chapter_file: String = str(StoryRules.read_json(START_PATH).get("chapter_file", ""))
	director.load_chapter(chapter_file)
	director.beat_completed.connect(_on_beat_completed)

	player = PlayerScene.instantiate()
	board = BoardScene.instantiate()
	board.board_path = str(director.chapter.get("board", DEFAULT_BOARD))
	board_layer.add_child(board)

	camera.make_current()
	camera.set("limit_enabled", false)
	camera.position_smoothing_enabled = false

	SaveManager.before_save = sync_location
	SaveManager.summary_provider = save_summary
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.link_made.connect(func(_link_id: String) -> void: SaveManager.request_autosave())
	pause.board_requested.connect(open_board)
	pause.load_requested.connect(_on_load_requested)
	pause.quit_requested.connect(_on_quit_requested)

	if OS.is_debug_build():
		var problems: Dictionary = StoryCheck.validate_all(chapter_file, false)
		for file_name: String in problems.keys():
			for problem: String in problems[file_name]:
				push_warning("Story data, %s: %s" % [file_name, problem])
	_begin()


func _exit_tree() -> void:
	if StoryRules.host == self:
		StoryRules.host = null
	if SaveManager.before_save.is_valid() and SaveManager.before_save.get_object() == self:
		SaveManager.before_save = Callable()
		SaveManager.summary_provider = Callable()
	# James may be outside the tree (a cut-away on another map was showing): free him by hand.
	if _stashed_map != null and is_instance_valid(_stashed_map):
		_stashed_map.queue_free()


# A new game starts at the chapter's start. A loaded save continues exactly where it stopped.
func _begin() -> void:
	_running = true
	fade.set_black(true)
	if str(GameState.location.get("map", "")) == "":
		var start: Dictionary = director.start()
		GameState.current_chapter = director.chapter_number()
		GameState.set_phase(str(start.get("phase", "")))
		_load_map(str(start.get("map", "")))
		_place_at_spawn(str(start.get("spawn", "")))
		# The opening plays on black, before the first picture: a conversation, or a list of effects
		# (usually a cinematic).
		var opening: Variant = start.get("opening", "")
		if opening is Array:
			for effect: Variant in opening:
				if effect is Dictionary:
					await _run_effect(effect)
		elif str(opening) != "":
			await _play(str(opening))
		await fade.fade_to(0.0, START_FADE)
	else:
		_load_map(str(GameState.location["map"]))
		player.global_position = GameState.location_position()
		player.set_facing_name(str(GameState.location.get("facing", "S")))
		_snap_camera()
		await fade.fade_to(0.0, TRAVEL_FADE)
	_running = false
	started = true
	director.queue_check()


# ---------- every frame ----------

func _process(delta: float) -> void:
	if started and not ending:
		GameState.play_seconds += delta
	_pump()
	if player != null:
		player.set_frozen(not player_in_control())
		hint.track(player.global_position, player_in_control(), delta)
	_follow_camera(delta)


# Starts whatever is waiting, when the screen is free for it.
func _pump() -> void:
	if not started or _running or ending:
		return
	if not _queue.is_empty():
		if _screen_is_free():
			_run_queue()
		return
	if not player_in_control():
		return
	# The current beat may want to start a conversation by itself on this map.
	var auto: Dictionary = director.take_auto_play(current_map_id())
	if not auto.is_empty():
		queue_effect(auto)
		return
	# An autosave that was asked for waits until this safe moment.
	if SaveManager.autosave_pending:
		if SaveManager.active_slot > 0:
			SaveManager.save_now()
		else:
			SaveManager.autosave_pending = false   # started without a slot (F6 on this scene): nothing to save into


## True when James can walk: nothing is open, nothing is fading, nothing is playing.
func player_in_control() -> bool:
	return started and not _running and not ending and _screen_is_free() and not pause.is_open and _jump_list == null


# True when no full-screen thing is open (a short notice at the bottom does not count).
func _screen_is_free() -> bool:
	if dialogue.is_open and dialogue.blocking:
		return false
	return not board.visible and loupe == null and overlay == null and not chapter_card.is_open and not in_cutaway \
		and not in_cutscene and not cinematic.is_playing


func current_map_id() -> String:
	return map.map_id if map != null else ""


# ---------- the queue: story effects, one after another ----------

## Adds one effect to the end of the queue. StoryRules sends Game effects here.
func queue_effect(effect: Dictionary) -> void:
	_queue.append(effect)


## Adds a list of effects, in order (a beat's "on_complete").
func run_effects(effects: Array) -> void:
	for effect: Variant in effects:
		if effect is Dictionary:
			_queue.append(effect)


func _on_beat_completed(_beat_id: String, effects: Array) -> void:
	run_effects(effects)


func _run_queue() -> void:
	_running = true
	while not _queue.is_empty() and not ending:
		var effect: Dictionary = _queue.pop_front()
		await _run_effect(effect)
	# Never leave the player looking at black.
	if fade.is_black() and not ending:
		await fade.fade_to(0.0, TRAVEL_FADE)
	_running = false


func _run_effect(effect: Dictionary) -> void:
	if not StoryRules.is_game_effect(effect):
		StoryRules.apply_state_effect(effect)
	elif effect.has("move_player"):
		var move: Dictionary = effect["move_player"]
		await _travel(str(move.get("map", "")), str(move.get("spawn", "")))
	elif effect.has("scene_card"):
		if not fade.is_black():
			await fade.fade_to(1.0, 0.4)
		await fade.show_card(str((effect["scene_card"] as Dictionary).get("text", "")))
	elif effect.has("cutaway"):
		await _cutaway(effect["cutaway"])
	elif effect.has("play"):
		await _play(str(effect["play"]))
	elif effect.has("notice"):
		var notice: Dictionary = effect["notice"]
		dialogue.show_notice(str(notice.get("name", "")), str(notice.get("text", "")))
	elif effect.has("autosave"):
		SaveManager.request_autosave()
	elif effect.has("end_chapter"):
		await _end_chapter(effect["end_chapter"])
	elif effect.has("cinematic"):
		await _cinematic(str(effect["cinematic"]))
	elif effect.has("cutscene"):
		await _cutscene(str(effect["cutscene"]))


# Plays a conversation and waits until it is closed. A conversation with nothing to say right
# now (a map's "enter" talk on a second visit) simply does nothing.
func _play(conversation_id: String) -> void:
	if not FileAccess.file_exists(DIALOGUE_FOLDER + conversation_id + ".json"):
		push_warning("Game: there is no conversation '%s' in %s" % [conversation_id, DIALOGUE_FOLDER])
		return
	dialogue.play_conversation(conversation_id)
	if not dialogue.is_open:
		return
	await dialogue.dialogue_finished


# ---------- maps ----------

func _load_map(map_id: String) -> void:
	if map != null:
		if player.get_parent() != null:
			player.get_parent().remove_child(player)
		map.queue_free()
		world.remove_child(map)
		map = null
	map = _instantiate_map(map_id)
	if map == null:
		return
	world.add_child(map)
	map.actors.add_child(player)
	_connect_map(map)
	_apply_phase_to(map, true)


func _instantiate_map(map_id: String) -> MapBaseScript:
	var info: Dictionary = maps.get(map_id, {})
	var scene_path: String = str(info.get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("Game: map '%s' is not in %s, or its scene is missing." % [map_id, MAPS_PATH])
		return null
	var instance: MapBaseScript = (load(scene_path) as PackedScene).instantiate()
	instance.map_id = map_id
	return instance


func _connect_map(target: MapBaseScript) -> void:
	for node: Node in get_tree().get_nodes_in_group("hotspots"):
		if target.is_ancestor_of(node) and node.has_signal("used") and not node.used.is_connected(_on_hotspot_used):
			node.used.connect(_on_hotspot_used)
	for node: Node in get_tree().get_nodes_in_group("exits"):
		if target.is_ancestor_of(node) and not node.entered.is_connected(_on_exit_entered):
			node.entered.connect(_on_exit_entered)
	for node: Node in get_tree().get_nodes_in_group("blockers"):
		if target.is_ancestor_of(node) and not node.bumped.is_connected(_on_blocker_bumped):
			node.bumped.connect(_on_blocker_bumped)


func _place_at_spawn(spawn_id: String) -> void:
	if map == null:
		return
	player.global_position = map.get_spawn(spawn_id)
	player.velocity = Vector2.ZERO
	player.set_facing_name(map.get_spawn_facing(spawn_id))
	GameState.set_location(map.map_id, spawn_id, player.global_position, player.facing_name())
	_snap_camera()


# Fade out, change the scenery, fade in. Then the map's "enter" conversation, if it has one.
func _travel(map_id: String, spawn_id: String) -> void:
	if not maps.has(map_id):
		push_warning("Game: cannot go to map '%s': it is not in %s" % [map_id, MAPS_PATH])
		return
	if not fade.is_black():
		Audio.play("travel_out")
		await fade.fade_to(1.0, TRAVEL_FADE)
	if map_id != current_map_id():
		_load_map(map_id)
	_place_at_spawn(spawn_id)
	await get_tree().process_frame
	# If more is still to happen on black (a scene card right after), stay black for it.
	if _queue.is_empty() or not (_queue[0] as Dictionary).has("scene_card"):
		Audio.play("travel_in")
		await fade.fade_to(0.0, TRAVEL_FADE)
	var enter: String = str((maps[map_id] as Dictionary).get("enter", ""))
	if enter != "":
		await _play(enter)


func _on_hotspot_used(hotspot: Node) -> void:
	if not player_in_control():
		return
	var spot: HotspotScript = hotspot
	match spot.action:
		"conversation":
			queue_effect({ "play": spot.target })
		"door":
			if spot.is_open():
				queue_effect({ "move_player": { "map": spot.to_map, "spawn": spot.to_spawn } })
			elif spot.locked_conversation != "":
				queue_effect({ "play": spot.locked_conversation })
		"board":
			open_board()
		"loupe":
			open_loupe(spot.target)
		"overlay":
			open_overlay(spot.target)


func _on_exit_entered(exit: Node) -> void:
	if player_in_control():
		queue_effect({ "move_player": { "map": str(exit.to_map), "spawn": str(exit.to_spawn) } })


func _on_blocker_bumped(blocker: Node) -> void:
	if player_in_control() and str(blocker.conversation) != "":
		queue_effect({ "play": str(blocker.conversation) })
	else:
		blocker.reset_gap()   # he did not get to say it: let the next touch speak


# ---------- time of day ----------

func _on_phase_changed(_phase: String) -> void:
	if map != null:
		_apply_phase_to(map, fade.is_black())


func _apply_phase_to(target: MapBaseScript, instant: bool) -> void:
	var info: Dictionary = maps.get(target.map_id, {})
	target.apply_phase(director.phase_info(GameState.phase), map_tint(target.map_id, GameState.phase), bool(info.get("exterior", false)), instant)


## The colour a map is tinted with at a time of day (from maps.json; white when nothing is set).
func map_tint(map_id: String, phase: String) -> Color:
	var tints: Dictionary = (maps.get(map_id, {}) as Dictionary).get("tint", {})
	return Color.html(str(tints.get(phase, tints.get("default", "#ffffff"))))


# ---------- camera ----------

func _follow_camera(delta: float) -> void:
	if _camera_free or map == null or player == null or not player.is_inside_tree():
		return
	var target: Vector2 = player.global_position + CAMERA_HEIGHT_OFFSET
	var weight: float = 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta)
	camera.global_position = _clamp_camera(camera.global_position.lerp(target, weight), map)


func _snap_camera() -> void:
	if map != null and player != null:
		camera.global_position = _clamp_camera(player.global_position + CAMERA_HEIGHT_OFFSET, map)


# Keeps the camera's centre far enough from the map's edges that nothing outside it shows.
func _clamp_camera(wanted: Vector2, target: MapBaseScript) -> Vector2:
	var bounds: Rect2 = target.camera_bounds()
	var half: Vector2 = get_viewport().get_visible_rect().size / camera.zoom / 2.0
	var result: Vector2 = wanted
	if bounds.size.x <= half.x * 2.0:
		result.x = bounds.get_center().x
	else:
		result.x = clampf(wanted.x, bounds.position.x + half.x, bounds.end.x - half.x)
	if bounds.size.y <= half.y * 2.0:
		result.y = bounds.get_center().y
	else:
		result.y = clampf(wanted.y, bounds.position.y + half.y, bounds.end.y - half.y)
	return result


# ---------- cut-aways: scenes the player sees and James does not ----------

func _cutaway(cut: Dictionary) -> void:
	in_cutaway = true
	if fade.is_black():
		await fade.fade_to(0.0, TRAVEL_FADE)
	var stage_id: String = str(cut.get("map", ""))
	var other_map: bool = stage_id != "" and stage_id != current_map_id()
	var focus_id: String = str(cut.get("focus", ""))
	var camera_home: Vector2 = camera.global_position
	await letterbox.slide(1.0, str(cut.get("caption", "")))
	_camera_free = true
	if other_map:
		# Put the real map (with James in it) aside, untouched, and show the other one as a stage.
		await fade.fade_to(1.0, TRAVEL_FADE)
		_stashed_map = map
		world.remove_child(map)
		map = _instantiate_map(stage_id)
		if map != null:
			world.add_child(map)
			_apply_phase_to(map, true)
			camera.global_position = _clamp_camera(map.get_focus(focus_id), map)
		await fade.fade_to(0.0, TRAVEL_FADE)
	else:
		player.visible = false
		var glide: Tween = create_tween()
		glide.tween_property(camera, "global_position", _clamp_camera(map.get_focus(focus_id), map), CUTAWAY_GLIDE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await glide.finished

	await _play(str(cut.get("conversation", "")))

	# Put everything back exactly as it was.
	if other_map:
		await fade.fade_to(1.0, TRAVEL_FADE)
		if map != null:
			world.remove_child(map)
			map.queue_free()
		map = _stashed_map
		_stashed_map = null
		world.add_child(map)
		_apply_phase_to(map, true)   # in case the time of day changed while it was put aside
		camera.global_position = camera_home
		await fade.fade_to(0.0, TRAVEL_FADE)
	else:
		var back: Tween = create_tween()
		back.tween_property(camera, "global_position", camera_home, CUTAWAY_GLIDE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await back.finished
		player.visible = true
	_camera_free = false
	await letterbox.slide(0.0)
	in_cutaway = false


# ---------- cinematics: short films of paintings ----------

func _cinematic(id: String) -> void:
	if not CinematicScript.exists(id):
		push_warning("Game: there is no cinematic '%s' in data/cinematics/." % id)
		return
	# The film always starts and ends on black, so whatever was on screen fades out first.
	if not fade.is_black():
		await fade.fade_to(1.0, 0.6)
	await cinematic.play(id, dialogue)


# ---------- cutscenes: the story moves James and the others by itself ----------
#
# A cutscene is a list of steps in data/cutscenes/<id>.json, played one after another:
#   { "walk": { "who": "james" or a person on the map, "to": a spawn or focus point, "speed": 240, "wait": true } }
#   { "face": { "who": "james", "dir": "N" } }
#   { "camera": { "focus": a spawn or focus point, or "james" to follow him again, "seconds": 0.8 } }
#   { "wait": 1.0 }
#   { "play": "conversation_id" }
#   { "effects": [ ...any story effects... ] }
#   { "sound": "id" }
# "bars": true slides the black cut-away bars in for the whole cutscene.

func _cutscene(id: String) -> void:
	var data: Dictionary = StoryRules.read_json(CUTSCENE_FOLDER + id + ".json")
	if data.is_empty():
		push_warning("Game: there is no cutscene '%s' in %s" % [id, CUTSCENE_FOLDER])
		return
	if str(data.get("map", "")) != "" and str(data["map"]) != current_map_id():
		push_warning("Game: cutscene '%s' is for map '%s', but James is on '%s'." % [id, str(data["map"]), current_map_id()])
	in_cutscene = true
	if fade.is_black():
		await fade.fade_to(0.0, TRAVEL_FADE)
	var bars: bool = bool(data.get("bars", true))
	if bars:
		await letterbox.slide(1.0, str(data.get("caption", "")))
	for step: Variant in data.get("steps", []):
		if step is Dictionary and map != null:
			await _cutscene_step(step)
	if _camera_free:
		await _glide_camera(player.global_position + CAMERA_HEIGHT_OFFSET, 0.6)
		_camera_free = false
	if bars:
		await letterbox.slide(0.0)
	GameState.set_location(map.map_id, str(GameState.location.get("spawn", "")), player.global_position, player.facing_name())
	in_cutscene = false


func _cutscene_step(step: Dictionary) -> void:
	if step.has("walk"):
		var walk: Dictionary = step["walk"]
		var who: Node = _actor(str(walk.get("who", "")))
		if who == null or not who.has_method("walk_to"):
			return
		var walking: Callable = who.walk_to.bind(_mark(str(walk.get("to", ""))), float(walk.get("speed", 280.0 if who == player else 240.0)))
		if bool(walk.get("wait", true)):
			await walking.call()
		else:
			walking.call()
	elif step.has("face"):
		var face: Dictionary = step["face"]
		var who: Node = _actor(str(face.get("who", "james")))
		if who == player:
			player.set_facing_name(str(face.get("dir", "S")))
	elif step.has("camera"):
		var shot: Dictionary = step["camera"]
		var focus: String = str(shot.get("focus", "james"))
		var seconds: float = float(shot.get("seconds", 0.8))
		if focus == "james":
			_camera_free = true
			await _glide_camera(player.global_position + CAMERA_HEIGHT_OFFSET, seconds)
			_camera_free = false
		else:
			_camera_free = true
			await _glide_camera(_mark(focus), seconds)
	elif step.has("wait"):
		await get_tree().create_timer(float(step["wait"]), false).timeout
	elif step.has("play"):
		await _play(str(step["play"]))
	elif step.has("effects"):
		for effect: Variant in step["effects"]:
			if effect is Dictionary:
				await _run_effect(effect)
	elif step.has("sound"):
		Audio.play(str(step["sound"]))


func _glide_camera(target: Vector2, seconds: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(camera, "global_position", _clamp_camera(target, map), maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


# "james", or the name of a person (a node under the map's Actors).
func _actor(who: String) -> Node:
	if who == "james":
		return player
	var node: Node = map.actors.get_node_or_null(who)
	if node == null:
		push_warning("Game: map '%s' has nobody called '%s' under Actors." % [map.map_id, who])
	return node


# A place on the map: a focus point, or else a spawn point.
func _mark(mark_id: String) -> Vector2:
	if map.has_focus(mark_id):
		return map.get_focus(mark_id)
	return map.get_spawn(mark_id)


# ---------- board, loupe, overlays ----------

func open_board() -> void:
	if player_in_control():
		board.open()


func open_loupe(puzzle_id: String) -> void:
	var path: String = PUZZLE_FOLDER + puzzle_id + ".json"
	if not player_in_control() or not FileAccess.file_exists(path):
		return
	loupe = LoupeScene.instantiate()
	loupe.puzzle_path = path
	loupe.show_debug_hotspots = false
	loupe_layer.add_child(loupe)
	loupe.closed.connect(close_loupe)


func close_loupe() -> void:
	if loupe != null:
		loupe.queue_free()
		loupe = null


## Full-screen views such as the darkroom print line arrive in Milestone 6 part B.
func open_overlay(overlay_id: String) -> void:
	push_warning("Game: there is no overlay '%s' yet (overlays arrive in Milestone 6 part B)." % overlay_id)


# ---------- input: pause, board key, debug jumper ----------

func _input(event: InputEvent) -> void:
	KeyGlyphs.note(event)


func _unhandled_input(event: InputEvent) -> void:
	if not started or ending or event is InputEventMouse:
		return
	if _jump_list != null:
		get_viewport().set_input_as_handled()
		if UiInput.is_cancel(event) or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F9):
			_close_jump_list()
		else:
			(_jump_list.get_node("Slips") as MenuSlipsScript).handle_input(event)
		return
	if event.is_action_pressed(PAUSE_ACTION) and not event.is_echo():
		if _can_pause():
			get_viewport().set_input_as_handled()
			pause.open(menus, director.chapter_number(), director.chapter_title(), director.current_lead(), player_in_control(), _pause_place())
	elif event.is_action_pressed("toggle_board") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if board.visible:
			board.request_close()
		else:
			open_board()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F9:
		if player_in_control():
			get_viewport().set_input_as_handled()
			_open_jump_list()


# The pause menu can open over a conversation (it simply waits). The board and the loupe use
# Esc to close themselves instead.
func _can_pause() -> bool:
	return not board.visible and loupe == null and overlay == null and not chapter_card.is_open and not pause.is_open \
		and not cinematic.is_playing


# "Graves Studio · Night": the map and the time of day, the same words a save card shows.
func _pause_place() -> String:
	var summary: Dictionary = save_summary()
	var parts: Array[String] = []
	for key: String in ["map_name", "phase_name"]:
		if str(summary.get(key, "")) != "":
			parts.append(str(summary[key]))
	if parts.size() == 2:
		return str((menus.get("pause", {}) as Dictionary).get("place", "%s · %s")) % parts
	return parts[0] if parts.size() == 1 else ""


# Esc on the keyboard, Start on a controller. Normally set in project.godot; added here if missing.
func _ensure_pause_action() -> void:
	if InputMap.has_action(PAUSE_ACTION):
		return
	InputMap.add_action(PAUSE_ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event(PAUSE_ACTION, key)
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_START
	InputMap.action_add_event(PAUSE_ACTION, button)


func _on_load_requested(slot: int) -> void:
	if SaveManager.load_slot(slot):
		get_tree().paused = false
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		pause.slots.refresh()


func _on_quit_requested() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


# ---------- saving ----------

## Writes James's exact position into GameState. SaveManager calls this just before every save.
func sync_location() -> void:
	if map == null or player == null or in_cutaway:
		return
	GameState.set_location(map.map_id, str(GameState.location.get("spawn", "")), player.global_position, player.facing_name())


## The few words shown on a save card.
func save_summary() -> Dictionary:
	return {
		"chapter": director.chapter_number(),
		"chapter_title": director.chapter_title(),
		"map_name": str((maps.get(str(GameState.location.get("map", "")), {}) as Dictionary).get("name", "")),
		"phase_name": director.phase_name(GameState.phase),
		"lead": director.current_lead(),
		"play_seconds": GameState.play_seconds,
	}


# ---------- the end of a chapter ----------

func _end_chapter(value: Variant) -> void:
	ending = true
	var end: Dictionary = value if value is Dictionary else {}
	var words: Dictionary = menus.get("chapter_card", {})
	var number: int = int(end.get("chapter", director.chapter_number()))
	await chapter_card.play(str(words.get("chapter", "Chapter %d")) % number, director.chapter_title(), str(words.get("end", "End of chapter")))
	# The epilogue: a last line or two over black.
	var epilogue: Array = end.get("epilogue", [])
	if not epilogue.is_empty():
		dialogue.play_lines(epilogue, true)
		await dialogue.dialogue_finished
	if SaveManager.active_slot > 0:
		SaveManager.save_now()
		await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file(TITLE_SCENE)


# ---------- debug: jump to a beat (F9, debug builds only) ----------

func _open_jump_list() -> void:
	_jump_list = Control.new()
	_jump_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade: ColorRect = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.7)
	_jump_list.add_child(shade)
	var heading: Label = Label.new()
	heading.text = str((menus.get("debug", {}) as Dictionary).get("jump_heading", "Jump to a beat (debug)"))
	heading.position = Vector2(120.0, 60.0)
	heading.add_theme_font_size_override("font_size", 30)
	_jump_list.add_child(heading)
	var slips: MenuSlipsScript = MenuSlipsScript.new()
	slips.name = "Slips"
	slips.slip_size = Vector2(900.0, 44.0)
	slips.position = Vector2(120.0, 130.0)
	_jump_list.add_child(slips)
	var items: Array = []
	for index: int in range(director.beats.size()):
		var beat: Dictionary = director.beats[index]
		items.append({ "id": str(index), "text": "%s   %s" % [str(beat.get("id", "")), str(beat.get("lead", ""))] })
	slips.set_items(items)
	slips.picked.connect(func(id: String) -> void: jump_to_beat(int(id)))
	pause.get_parent().add_child(_jump_list)


func _close_jump_list() -> void:
	if _jump_list != null:
		_jump_list.queue_free()
		_jump_list = null


## Puts the game in the state of a player who has just reached beat `index`.
func jump_to_beat(index: int) -> void:
	_close_jump_list()
	_queue.clear()
	var place: Dictionary = director.grant_up_to(index)
	board.rebuild()
	queue_effect({ "move_player": { "map": str(place["map"]), "spawn": str(place["spawn"]) } })
