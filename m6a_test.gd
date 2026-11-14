extends SceneTree
# Milestone 6 part A acceptance checks: the game frame.
# Numbers in the labels match section A14 of docs/milestone-6.md.

const TITLE := "res://scenes/ui/title.tscn"
const BOOT := "res://scenes/ui/boot.tscn"
const GAME := "res://scenes/game/game.tscn"
const SAVES := "user://saves_m6a"
# Loaded when the test runs (not preloaded): these scripts use the GameState autoload, which does
# not exist yet while this file is being compiled.
var StoryRules: GDScript
var StoryCheck: GDScript

var passed: int = 0
var failed: int = 0
var gs: Node
var sm: Node
var g: Node          # the Game scene
var d: Control       # its dialogue box
var save_count: int = 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label, "  ", extra)

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/home/claude/shots/m6a_%s.png" % n)

func secs(s: float) -> void:
	await create_timer(s).timeout

func frames(n: int) -> void:
	for i in n:
		await process_frame

func key(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = p
		root.push_input(e)

func pad(button: int) -> void:
	for p in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = p
		root.push_input(e)

# Waits until `test` is true (or gives up after `timeout` seconds). Returns whether it became true.
func until(test: Callable, timeout: float = 6.0) -> bool:
	var waited: float = 0.0
	while waited < timeout:
		if test.call():
			return true
		await secs(0.05)
		waited += 0.05
	return bool(test.call())

# Reads the open conversation to its end (or until topics show).
func read_on(max_lines: int = 14) -> void:
	for i in max_lines:
		if not d.is_open or not d.blocking or d.mode != d.Mode.READING:
			return
		if d.typing:
			key(KEY_SPACE)
			await frames(2)
		key(KEY_SPACE)
		await secs(0.12)
		if d.mode == d.Mode.CHOOSING:
			await secs(0.6)
			return
	await secs(0.2)

# Reads every conversation that comes up until James is free again (a whole cutscene).
func play_through(timeout: float = 20.0) -> void:
	var waited: float = 0.0
	await secs(0.3)
	while waited < timeout and not control():
		if d.is_open and d.blocking and d.mode == d.Mode.READING:
			await read_on()
		await secs(0.1)
		waited += 0.1


func finish_line() -> void:
	if d.typing:
		key(KEY_SPACE)
		await frames(2)

# Starts the Game scene fresh and waits for it to exist.
func open_game() -> void:
	change_scene_to_file(GAME)
	await frames(3)
	g = current_scene
	d = g.dialogue

func control() -> bool:
	return g.player_in_control()

func spot(name: String) -> Node:
	return g.map.get_node("Actors/" + name)

func slot_file(slot: int) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sm.slot_path(slot)))
	return parsed if parsed is Dictionary else {}

func _run() -> void:
	gs = root.get_node("GameState")
	sm = root.get_node("SaveManager")
	StoryRules = load("res://scripts/story/StoryRules.gd")
	StoryCheck = load("res://scripts/story/StoryCheck.gd")
	sm.saves_dir = SAVES
	for s in [1, 2, 3]:
		sm.delete_slot(s)
	sm.saved.connect(func(_slot: int) -> void: save_count += 1)
	gs.reset()

	# ---- 18. every data file fits together ----
	var problems: Dictionary = StoryCheck.validate_all("res://data/chapters/dev_chapter.json")
	check("18 dialogue, maps and chapter files all validate", problems.is_empty(), str(problems))
	var bad: Dictionary = {
		"chapter": 1, "title": "Bad", "phases": { "day": {} },
		"start": { "map": "nowhere", "spawn": "x", "phase": "noon" },
		"beats": [{ "id": "b1", "complete_when": { "wibble": "x", "has_evidence": "no_such_clue" },
			"on_complete": [{ "move_player": { "map": "dev_a", "spawn": "roof" } }, { "play": "no_such_talk" }, { "set_phase": "dusk" }, { "explode": true },
				{ "cutaway": { "map": "dev_b", "focus": "moon", "conversation": "dev_cutaway" } }],
			"auto_play": { "map": "narnia", "conversation": "dev_welcome" } }]
	}
	var bad_file := FileAccess.open("user://m6a_bad_chapter.json", FileAccess.WRITE)
	bad_file.store_string(JSON.stringify(bad))
	bad_file.close()
	var bad_text: String = "\n".join(PackedStringArray(StoryCheck.validate_all("user://m6a_bad_chapter.json").get("m6a_bad_chapter.json", [])))
	for needle: String in ["map 'nowhere'", "phase 'noon'", "'wibble'", "'no_such_clue'", "spawn 'roof'", "'no_such_talk'", "phase 'dusk'", "'explode'", "'moon'", "'narnia'"]:
		check("18 a bad chapter file is reported in plain words: %s" % needle, bad_text.contains(needle), bad_text)

	# ---- B. boot screens ----
	change_scene_to_file(BOOT)
	await until(func() -> bool: return current_scene != null and current_scene.name == "Boot" and current_scene.current_id() == "studio" and current_scene.card_alpha > 0.9, 3.0)
	var boot: Node = current_scene
	check("B the first boot card is the studio", boot.current_id() == "studio")
	await shot("00a_boot_studio")
	key(KEY_SPACE)
	await until(func() -> bool: return boot.current_id() == "engine" and boot.card_alpha > 0.9, 3.0)
	check("B a press moves on to the engine card", boot.current_id() == "engine")
	key(KEY_SPACE)
	await until(func() -> bool: return boot.current_id() == "advisory" and boot.card_alpha > 0.9, 3.0)
	key(KEY_SPACE)
	await secs(0.3)
	check("B the advisory cannot be skipped in its first moments", boot.current_id() == "advisory")
	await shot("00b_boot_advisory")
	await secs(1.5)
	key(KEY_SPACE)
	await until(func() -> bool: return boot.current_id() == "autosave" and boot.card_alpha > 0.9, 3.0)
	check("B the autosave notice comes last", boot.current_id() == "autosave")
	await shot("00c_boot_autosave")
	key(KEY_ESCAPE)
	await until(func() -> bool: return current_scene != null and current_scene.name == "Title", 3.0)
	check("B Esc skips the rest and opens the title", current_scene.name == "Title")

	# ---- 1. title with no saves ----
	var title: Node = current_scene
	check("T the title begins in pitch black", title.dark > 0.95)
	await until(func() -> bool: return title._press_alpha > 0.6, 30.0)
	check("T the first visit waits for a press, with the menu hidden", title.waiting_for_press and not title.menu.visible)
	await shot("01a_press_any")
	key(KEY_SPACE)
	await secs(1.4)
	check("T a press reveals the menu", not title.waiting_for_press and title.menu.visible and title.menu.reveal > 0.99)
	check("1 Continue is hidden with no saves", not title.has_continue())
	check("T each item has a description", title.menu.selected_description() != "", title.menu.selected_description())
	await shot("01_title")

	# ---- 2. New Game into an empty slot ----
	key(KEY_ENTER)                     # New Game
	await secs(0.3)
	check("2 New Game opens the slot cards", title.slots.is_open and title.slots.mode == "new" and title.slots.selected == 1)
	await shot("02_slots_empty")
	key(KEY_ENTER)                     # slot 1
	await secs(0.2)
	check("2 an empty slot starts at once (no question)", sm.active_slot == 1)
	check("2 New Game fades the whole title to black first", title._leaving)
	await until(func() -> bool: return current_scene != null and current_scene.name == "Game", 12.0)
	g = current_scene
	d = g.dialogue
	await until(func() -> bool: return g.cinematic.is_playing and g.cinematic.caption_alpha > 0.95, 14.0)
	check("2 a new game opens with the chapter's film", g.cinematic.is_playing and g.cinematic.film_id == "ch01_intro")
	check("2 the film opens on the 'Winter, 1986' card, on black", g.cinematic.caption.begins_with("Winter, 1986.") and g.cinematic.black > 0.99, g.cinematic.caption)
	check("2 nobody speaks before the first picture", not d.is_open)
	check("2 the start map is already loaded behind the film", g.current_map_id() == "dev_a" and gs.phase == "day")
	check("6 James is frozen during the film", g.player.frozen)
	await shot("03_film_caption")
	await until(func() -> bool: return g.cinematic.shot_index == 1 and g.cinematic.black < 0.05, 8.0)
	check("C a painting that does not exist yet shows a stand-in with its brief", g.cinematic.current.get("texture") == null and str(g.cinematic.current["shot"].get("brief", "")) != "")
	await secs(1.0)
	await shot("03c_film_standin")
	key(KEY_SPACE)
	await secs(0.2)
	check("C a press shows 'Hold to skip'", g.cinematic.prompt_left > 0.0)
	Input.action_press("pause")
	await secs(0.5)
	check("C holding fills the ring, and nothing is skipped yet", g.cinematic.hold > 0.3 and g.cinematic.is_playing and not g.cinematic.skipped)
	await shot("03d_film_hold_to_skip")
	await secs(0.8)
	Input.action_release("pause")
	check("C holding for a second skips the film", g.cinematic.skipped)
	await until(func() -> bool: return not g.cinematic.is_playing, 3.0)
	check("C the skipped film ends, nothing is left open", not g.cinematic.is_playing and not d.is_open and not g.pause.is_open)

	# ---- 9. auto_play: the arrival cutscene ----
	await until(func() -> bool: return g.in_cutscene, 4.0)
	check("9 auto_play starts the beat's cutscene on its map", g.in_cutscene and gs.has_flag("auto:dev_b1"))
	check("S the bars slide in for the cutscene", await until(func() -> bool: return g.letterbox.amount > 0.99, 2.0))
	await until(func() -> bool: return d.is_open, 4.0)
	check("2 the cutscene begins with James thinking about Kessler", d._line_style == "thought" and d.text_label.text.begins_with("The box hasn't moved"), d.text_label.text)
	await finish_line()
	key(KEY_SPACE)
	await until(func() -> bool: return d._line_style == "voice", 2.0)
	await finish_line()
	check("10 Kessler's remembered words are a 'voice' line: her name, no portrait", d._line_style == "voice" and not d.portrait.visible and d.name_label.text == "Kessler" and d.text_label.text.begins_with("It's a box, Flint"), d.text_label.text)
	await shot("03_kessler_memory")
	key(KEY_SPACE)
	await until(func() -> bool: return d._line_style == "thought", 2.0)
	await finish_line()
	check("2 then James answers her in his head", d.text_label.text.begins_with("Try not to solve anything. Two months a detective"), d.text_label.text)
	await read_on()
	await until(func() -> bool: return gs.has_flag("dev_conductor_here"), 3.0)
	var conductor: Node = spot("Conductor")
	var conductor_start: Vector2 = conductor.global_position
	await secs(1.2)
	check("S the conductor appears and walks by himself", conductor.shown and conductor.global_position.distance_to(conductor_start) > 100.0)
	check("6 James is frozen during a cutscene", g.player.frozen)
	await until(func() -> bool: return d.is_open, 6.0)
	check("S he arrives beside James, and the cutscene talks", conductor.global_position.distance_to(Vector2(560, 790)) < 1.0 and d.text_label.text.begins_with("Last stop, sir"), d.text_label.text)
	check("S his talk hotspot walked with him", spot("ConductorSpot").global_position.distance_to(Vector2(560, 790)) < 1.0)
	check("S James turned to face him", g.player.facing_name() == "E")
	await finish_line()
	await shot("04a_cutscene_talk")
	await read_on()
	await secs(0.6)
	check("S then James walks by himself", g.player.auto_walking)
	await until(func() -> bool: return d.is_open, 6.0)
	check("S James reached the desk and faces it", g.player.global_position.distance_to(Vector2(600, 640)) < 1.0 and g.player.facing_name() == "N")
	check("10 a 'thought' line: pencil '(thinking)' name with James's portrait", d._line_style == "thought" and d.name_label.text == "James Flint (thinking)" and d.portrait.visible)
	await finish_line()
	await shot("04_thought_line")
	await read_on()
	await until(control, 4.0)
	check("S after the cutscene: bars gone, the conductor has left, James is free", g.letterbox.amount < 0.01 and not conductor.shown and control() and not g.player.frozen)
	check("S GameState.location follows where the cutscene left James", gs.location_position().distance_to(Vector2(600, 640)) < 1.0)
	await secs(0.9)
	check("H the controls hint shows the first time James is free", g.hint.showing and not gs.has_flag("hint:controls"))
	await shot("04b_controls_hint")
	await secs(0.5)
	check("9 auto_play does not start a second time", not d.is_open and not g.in_cutscene)

	# ---- 5. time of day, live ----
	var lamp: Node = spot("Lamp")
	var candle: Node = spot("Candle")
	var clerk: Node = spot("Clerk")
	var lights: Node = g.map.get_node("PhaseLights")
	check("5 day: mains on, candles off, the clerk is here, the bed cannot be used", lamp.visible and not candle.visible and clerk.shown and spot("ClerkSpot").shown and not spot("BedSpot").shown)
	check("5 day tint comes from maps.json", lights.current_tint().is_equal_approx(Color.html("#ffe9c9")), str(lights.current_tint()))
	await shot("05_phase_day")
	StoryRules.apply({ "set_phase": "night" })
	await frames(2)
	check("5 night: mains off, candles on", not lamp.visible and candle.visible)
	check("5 night: the clerk leaves and the bed can be used", not clerk.shown and not spot("ClerkSpot").shown and spot("ClerkSpot").collision_layer == 0 and spot("BedSpot").shown)
	check("5 a phase marked 'instant' cuts the tint at once", lights.current_tint().is_equal_approx(Color.html("#55608a")), str(lights.current_tint()))
	await secs(0.8)
	check("5 the clerk fades out", not clerk.visible)
	await shot("06_phase_night")
	StoryRules.apply({ "set_phase": "day" })
	await secs(0.5)
	var mid: Color = lights.current_tint()
	check("5 a normal phase change cross-fades the tint (1 s)", not mid.is_equal_approx(Color.html("#ffe9c9")) and not mid.is_equal_approx(Color.html("#55608a")), str(mid))
	await secs(0.8)
	check("5 back to day", lamp.visible and clerk.shown and lights.current_tint().is_equal_approx(Color.html("#ffe9c9")))

	# ---- 10. conversation features, and beat 1 ----
	spot("DeskSpot").interact()
	await until(func() -> bool: return d.is_open, 2.0)
	await read_on()
	check("10 choice_tag shows above the topics", d.mode == d.Mode.CHOOSING and d.choices.tag == "The desk is testing you", d.choices.tag)
	await shot("07_choice_tag")
	key(KEY_1)
	await secs(0.8)
	check("10 the picked answer plays", d.text_label.text == "Detective work. It's a gift.", d.text_label.text)
	await finish_line()
	key(KEY_SPACE)
	await secs(0.3)
	check("10 a silent node runs its effects and shows nothing; next_if picks the branch", gs.has_flag("dev_desk_seen") and d.text_label.text.begins_with("Kessler would be so proud"), d.text_label.text)
	check("9 the lead changes as soon as the beat is done", g.director.current_lead() == "Go outside and talk to the stranger.", g.director.current_lead())
	sm.request_autosave()
	var saves_before: int = save_count
	await secs(0.4)
	check("11 a save asked for during a conversation waits", save_count == saves_before and sm.autosave_pending)
	await read_on()
	await until(func() -> bool: return save_count > saves_before, 3.0)
	check("11 autosave after the beat, once James is back in control", save_count == saves_before + 1 and not sm.autosave_pending, str(save_count - saves_before))
	check("7 the beat's notice plays (a short line, no portrait, James stays free)", d.is_open and not d.blocking and d.text_label.text.begins_with("One desk, examined"), d.text_label.text)
	await secs(0.3)
	await shot("08_save_indicator")
	check("11 the save indicator showed", g.get_node("SaveIndicator/Saving").show_count >= 1)
	var file: Dictionary = slot_file(1)
	var summary: Dictionary = file.get("summary", {})
	check("12 the save file has version, saved_at, summary and state", int(file.get("version", 0)) == 1 and int(file.get("saved_at", 0)) > 0 and file.get("state") is Dictionary)
	check("12 the summary names the chapter, place, phase and lead", str(summary.get("chapter_title")) == "Test Chapter" and str(summary.get("map_name")) == "Dev room" and str(summary.get("phase_name")) == "Day" and str(summary.get("lead")) == "Go outside and talk to the stranger.", str(summary))
	check("12 no .tmp file is left behind", not FileAccess.file_exists(sm.slot_path(1) + ".tmp"))
	g.director.check()
	await frames(3)
	check("9 a finished beat never completes again", g._queue.is_empty() and gs.has_flag("beat:dev_b1"))
	await secs(3.2)

	# reactions: showing evidence that is not a lie
	spot("ClerkSpot").interact()
	await until(func() -> bool: return d.is_open, 2.0)
	await finish_line()
	for round in 2:
		key(KEY_Q)
		await secs(0.5)
		key(KEY_ENTER)
		await secs(1.6)
		check("10 a reaction plays when that evidence is shown (time %d)" % (round + 1), d.text_label.text.begins_with("That's the leaflet from the desk"), d.text_label.text)
		check("10 a reaction catches no lie", not d._interlude)
		await finish_line()
		if round == 0:
			# go back to a line that can be presented on: the talk ended, start again
			key(KEY_SPACE)
			await secs(0.6)
			spot("ClerkSpot").interact()
			await until(func() -> bool: return d.is_open, 2.0)
			await finish_line()
	await read_on()
	await until(control, 2.0)

	# ---- 6. board and loupe freeze James ----
	spot("BoardSpot").interact()
	await secs(0.4)
	check("6 the board hotspot opens the board, and James is frozen", g.board.visible and g.player.frozen)
	key(KEY_ESCAPE)
	await secs(0.3)
	check("14 Esc closes the board, not the pause menu", not g.board.visible and not g.pause.is_open)
	g.open_loupe("ch01_loupe")
	await secs(0.3)
	check("6 the loupe opens as an overlay, and James is frozen", g.loupe != null and g.player.frozen)
	key(KEY_ESCAPE)
	await secs(0.3)
	check("6 Esc closes the loupe and gives James back", g.loupe == null and not g.pause.is_open and control())

	# ---- 3. doors ----
	spot("LockedSpot").interact()
	await until(func() -> bool: return d.is_open, 2.0)
	check("3 a shut door plays its locked conversation", d.text_label.text.begins_with("Locked."), d.text_label.text)
	await read_on()
	await until(control, 2.0)
	check("3 and James stays where he is", g.current_map_id() == "dev_a")
	var locked: Node = spot("LockedSpot")
	gs.set_flag("dev_key")
	check("3 the door opens once its flag is on", locked.is_open())
	locked.open_if = "{\"has_evidence\": \"ch01_cctv_thursday\"}"
	check("3 a door can also wait for a condition (open_if)", not locked.is_open())
	gs.collect_evidence("ch01_cctv_thursday")
	check("3 and opens when the condition passes", locked.is_open())
	locked.open_if = ""
	gs.clear_flag("dev_key")
	spot("DoorSpot").interact()
	await secs(0.15)
	check("6 James is frozen during a fade", g.player.frozen and g.fade.amount > 0.0)
	await until(func() -> bool: return g.current_map_id() == "dev_b", 2.0)
	await until(func() -> bool: return d.is_open, 2.0)
	check("3 the door fades out and in and puts James at the spawn", g.current_map_id() == "dev_b" and g.player.global_position.distance_to(Vector2(400, 440)) < 1.0, str(g.player.global_position))
	check("3 GameState.location is updated", str(gs.location["map"]) == "dev_b" and str(gs.location["spawn"]) == "door" and gs.location_position().distance_to(Vector2(400, 440)) < 1.0, str(gs.location))
	check("3 the map's enter conversation plays", d.text_label.text.begins_with("Snow. Of course"), d.text_label.text)
	await read_on()
	await until(control, 2.0)
	var snow_light: int = g.map.get_node("PhaseLights").snow_amount()
	check("5 an outside map has light snow by day", snow_light > 60 and snow_light < 120, str(snow_light))
	await shot("09_street_day")

	# ---- 4. blockers ----
	var drift: Node = spot("Drift")
	g.player.global_position = Vector2(2284, 700)
	await until(func() -> bool: return d.is_open, 2.0)
	check("4 walking into a blocker plays its line", d.is_open and d.text_label.text.begins_with("Snow to the knees"), d.text_label.text)
	g.player.global_position = Vector2(2284, 700)
	await frames(3)
	check("4 the blocker stops James", g.player.global_position.x < 2300.0)
	await read_on()
	await until(control, 2.0)
	g.player.global_position = Vector2(1800, 700)
	await secs(0.3)
	g.player.global_position = Vector2(2284, 700)
	await secs(0.6)
	check("4 it does not speak again within 8 seconds", not d.is_open)
	g.player.global_position = Vector2(1800, 700)
	await secs(0.3)
	drift.reset_gap()
	g.player.global_position = Vector2(2284, 700)
	await until(func() -> bool: return d.is_open, 2.0)
	check("4 after the gap it speaks again", d.is_open)
	await read_on()
	await until(control, 2.0)

	# ---- 8. cut-aways ----
	g.player.global_position = Vector2(1800, 700)
	g.player.set_facing_name("W")
	await secs(1.0)
	var before_pos: Vector2 = g.player.global_position
	var before_cam: Vector2 = g.camera.global_position
	g.sync_location()
	var before_location: Dictionary = gs.location.duplicate(true)
	g.queue_effect({ "cutaway": { "map": "", "focus": "lamp", "caption": "Meanwhile, by the lamp", "conversation": "dev_cutaway" } })
	await until(func() -> bool: return d.is_open, 3.0)
	check("8 same map: bars and caption are up", g.letterbox.amount > 0.99 and g.letterbox.caption == "Meanwhile, by the lamp")
	check("8 same map: James is hidden and the camera has moved to the focus", not g.player.visible and g.camera.global_position.distance_to(before_cam) > 100.0 and absf(g.camera.global_position.x - 960.0) < 1.0, str(g.camera.global_position))
	check("6 James is frozen during a cut-away", g.player.frozen and g.in_cutaway)
	await finish_line()
	await secs(0.6)
	await shot("10_cutaway_same_map")
	sm.request_autosave()
	var saves_mid: int = save_count
	await read_on()
	await until(control, 4.0)
	check("8 same map: everything is back exactly", g.player.visible and g.player.global_position == before_pos and g.camera.global_position.distance_to(before_cam) < 1.0 and g.player.facing_name() == "W" and g.letterbox.amount < 0.01)
	check("8 GameState.location was never touched", gs.location == before_location, str(gs.location))
	await until(func() -> bool: return save_count > saves_mid, 2.0)
	check("11 a save asked for during a cut-away waited until it was over", save_count == saves_mid + 1)

	g.queue_effect({ "cutaway": { "map": "dev_a", "focus": "corner", "caption": "Meanwhile, indoors", "conversation": "dev_cutaway" } })
	await until(func() -> bool: return d.is_open, 4.0)
	check("8 other map: the other map is on stage with no James in it", g.current_map_id() == "dev_a" and not g.player.is_inside_tree() and g.letterbox.amount > 0.99)
	check("8 other map: GameState.location still says where James really is", gs.location == before_location)
	check("10 an 'action' line shows no name and no portrait", d._line_style == "action" and not d.name_label.visible and not d.portrait.visible, d.name_label.text)
	await finish_line()
	await shot("11_cutaway_other_map")
	await read_on()
	await until(control, 4.0)
	check("8 other map: back on the real map, exactly as before", g.current_map_id() == "dev_b" and g.player.is_inside_tree() and g.player.global_position == before_pos and g.camera.global_position.distance_to(before_cam) < 1.0 and gs.location == before_location)

	# ---- 3. exits ----
	g.player.global_position = Vector2(60, 660)
	await until(func() -> bool: return g.current_map_id() == "dev_a" and control(), 3.0)
	check("3 walking into an exit moves James to the other map's spawn", g.current_map_id() == "dev_a" and g.player.global_position.distance_to(Vector2(400, 800)) < 1.0 and str(gs.location["spawn"]) == "start")
	spot("DoorSpot").interact()
	await until(func() -> bool: return g.current_map_id() == "dev_b" and control(), 3.0)
	await secs(0.4)
	check("3 the enter conversation has nothing to say the second time", not d.is_open)

	# ---- 14, 17. pause ----
	var played: float = gs.play_seconds
	check("17 play time has been counting", played > 5.0, str(played))
	key(KEY_ESCAPE)
	await secs(0.5)
	check("14 Esc opens the pause menu and stops the game", g.pause.is_open and paused)
	check("14 the pause menu shows the current lead", g.pause.lead == "Go outside and talk to the stranger.", g.pause.lead)
	await shot("12_pause_menu")
	var at_pause: float = gs.play_seconds
	await secs(0.6)
	check("17 play time does not count while paused", gs.play_seconds == at_pause)
	key(KEY_ESCAPE)
	await secs(0.4)
	check("14 Esc closes it again", not g.pause.is_open and not paused)
	pad(JOY_BUTTON_START)
	await secs(0.4)
	check("14 Start opens it", g.pause.is_open)
	pad(JOY_BUTTON_START)
	await secs(0.4)
	check("14 Start closes it", not g.pause.is_open)
	key(KEY_ESCAPE)
	await secs(0.4)
	key(KEY_DOWN)                      # Case board
	key(KEY_ENTER)
	await secs(0.5)
	check("14 'Case board' opens the board", g.board.visible and not g.pause.is_open)
	key(KEY_ESCAPE)
	await secs(0.3)
	key(KEY_ESCAPE)
	await secs(0.4)
	key(KEY_UP)                        # wraps to Quit to title
	key(KEY_ENTER)
	await secs(0.3)
	check("14 'Quit to title' asks first", g.pause.confirm.is_open and current_scene == g)
	key(KEY_ENTER)                     # it starts on No
	await secs(0.3)
	check("14 answering No stays in the game", not g.pause.confirm.is_open and g.pause.is_open and current_scene == g)
	# Save into another slot (no question for an empty one), then again (asks to overwrite).
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_DOWN)                      # Save
	key(KEY_ENTER)
	await secs(0.3)
	check("12 Save opens the slot cards on the active slot", g.pause.slots.is_open and g.pause.slots.mode == "save" and g.pause.slots.selected == 1)
	key(KEY_RIGHT)
	key(KEY_ENTER)
	await secs(0.3)
	check("12 a manual save into an empty slot writes it", str(sm.slot_info(2)["status"]) == "ok" and not g.pause.slots.is_open)
	key(KEY_ENTER)                     # Save again
	await secs(0.3)
	key(KEY_RIGHT)
	key(KEY_ENTER)
	await secs(0.3)
	check("14 overwriting another slot asks first", g.pause.slots._confirm.is_open)
	key(KEY_UP)
	key(KEY_ENTER)                     # Yes
	await secs(0.3)
	check("12 the old save is kept as .bak", FileAccess.file_exists(sm.slot_path(2) + ".bak") and str(sm.slot_info(2)["status"]) == "ok")
	key(KEY_ESCAPE)
	await secs(0.4)

	# pause over a conversation
	spot("DoorSpot").interact()
	await until(func() -> bool: return g.current_map_id() == "dev_a" and control(), 3.0)
	spot("LockedSpot").interact()
	await until(func() -> bool: return d.is_open, 2.0)
	var line_before: String = d.text_label.text
	key(KEY_ESCAPE)
	await secs(0.4)
	check("14 the pause menu can open over a conversation", g.pause.is_open and d.is_open)
	check("14 the conversation and its portrait stay on screen behind the menu (blurred, not hidden)", g.get_node("Dialogue").visible and d.portrait.visible)
	var items: Array = g.pause.menu.items
	check("14 Save is greyed out while a conversation is open", bool(items[2].get("disabled", false)))
	key(KEY_ESCAPE)
	await secs(0.4)
	check("14 the conversation is still there afterwards", d.is_open and not g.pause.is_open)
	check("14 the conversation is untouched afterwards (same line showing)", d.text_label.text == line_before and g.get_node("Dialogue").visible)
	await read_on()
	await until(control, 2.0)

	# ---- 7. the effect queue, in order (beat 2) ----
	spot("DoorSpot").interact()
	await until(func() -> bool: return g.current_map_id() == "dev_b" and control(), 3.0)
	spot("StrangerSpot").interact()
	await until(func() -> bool: return d.is_open, 2.0)
	await read_on()
	await until(func() -> bool: return g.in_cutaway and d.is_open, 5.0)
	check("7 first: the cut-away", g.in_cutaway and gs.phase == "day" and str(gs.location["map"]) == "dev_b")
	await read_on()
	await until(func() -> bool: return g.fade.card_text == "Night" and g.fade.card_alpha > 0.9, 5.0)
	check("7 then: the scene card, on black, before anything changes", g.fade.is_black() and gs.phase == "day" and g.current_map_id() == "dev_b", gs.phase)
	await shot("13_scene_card")
	await until(func() -> bool: return d.is_open and d.blocking, 6.0)
	check("7 then: the phase, the move, and the conversation", gs.phase == "night" and g.current_map_id() == "dev_a" and g.player.global_position.distance_to(Vector2(400, 800)) < 1.0 and d.text_label.text.begins_with("Dark already"), d.text_label.text)
	check("7 the fade is clear again when the conversation starts", not g.fade.is_black())
	var saves_b2: int = save_count
	await read_on()
	await until(func() -> bool: return save_count > saves_b2, 3.0)
	check("11 autosave after beat 2", save_count == saves_b2 + 1)
	check("9 the lead is now beat 3", g.director.current_lead() == "Get some sleep.")

	# ---- 11. autosave after a board link ----
	saves_b2 = save_count
	gs.add_link("ch01_link_staged")
	await until(func() -> bool: return save_count > saves_b2, 2.0)
	check("11 autosave after a board link", save_count == saves_b2 + 1)

	# ---- 12. load restores everything ----
	g.player.global_position = Vector2(777, 888)
	g.player.set_facing_name("W")
	gs.add_trust("mary", 2)
	gs.set_counter("film:test", 7)
	await frames(3)
	check("12 a manual save through the API", sm.save_now(3))
	var saved_seconds: float = gs.play_seconds
	gs.reset()
	g._on_load_requested(3)
	await frames(4)
	g = current_scene
	d = g.dialogue
	await until(func() -> bool: return g.started, 3.0)
	check("12 load: map, exact position and facing", g.current_map_id() == "dev_a" and g.player.global_position.distance_to(Vector2(777, 888)) < 0.5 and g.player.facing_name() == "W", str(g.player.global_position))
	check("12 load: phase, and the map shows it", gs.phase == "night" and spot("Candle").visible and not spot("Lamp").visible and not spot("Clerk").shown)
	check("12 load: flags, evidence, links, trust, counters", gs.has_flag("dev_desk_seen") and gs.has_flag("dev_talked") and gs.has_evidence("ch01_anniversary_leaflet") and gs.has_link("ch01_link_staged") and gs.get_trust("mary") == 2 and gs.get_counter("film:test") == 7)
	check("12 load: play time", absf(gs.play_seconds - saved_seconds) < 1.0, "%s vs %s" % [gs.play_seconds, saved_seconds])
	check("12 load makes that slot the active one", sm.active_slot == 3)
	await secs(1.0)
	check("9 after a load no beat completes twice and nothing replays", g._queue.is_empty() and not d.is_open and g.director.current_lead() == "Get some sleep.")

	# ---- H, I. the controls hint went away; the save icon sits in the safe area ----
	check("H the controls hint was dismissed once James walked, and is remembered", gs.has_flag("hint:controls") and not g.hint.showing)
	var icon: Vector2 = g.get_node("SaveIndicator/Saving").ICON_CENTER
	check("I the saving icon sits inside the safe area (5% from the edges)", icon.x + 20.0 <= 1920.0 * 0.95 and icon.y + 20.0 <= 1080.0 * 0.95, str(icon))

	# ---- C. a whole film, start to end ----
	g.queue_effect({ "cinematic": "dev_short" })
	await until(func() -> bool: return g.cinematic.caption_alpha > 0.95, 10.0)
	check("C film: the caption shows on black", g.cinematic.caption == "Test caption.\nSecond line." and g.cinematic.is_playing)
	await until(func() -> bool: return g.cinematic.title_alpha > 0.9, 6.0)
	check("C film: the title appears over the painting", str(g.cinematic.title.get("title", "")) == "Test Title" and g.cinematic.shot_index == 1)
	check("C film: the shot's snow falls", g.cinematic._snow.emitting)
	await shot("05_film_title")
	await until(func() -> bool: return d.is_open, 6.0)
	check("C film: a real picture is used when it exists, with its line over it", g.cinematic.current.get("texture") != null and d.text_label.text == "A line over a real picture.")
	await finish_line()
	await shot("05b_film_real_picture")
	await read_on()
	await until(func() -> bool: return not g.cinematic.is_playing, 6.0)
	check("C film: it ends by itself", not g.cinematic.is_playing and not g.cinematic.skipped)
	await until(control, 3.0)
	check("C film: the map fades back in and James is free", control() and not g.fade.is_black())

	# ---- 16. debug jumper ----
	key(KEY_F9)
	await secs(0.3)
	check("16 F9 opens the beat list", g._jump_list != null)
	key(KEY_ESCAPE)
	await secs(0.3)
	check("16 Esc closes it (and does not open the pause menu)", g._jump_list == null and not g.pause.is_open)
	g.jump_to_beat(0)
	await secs(0.2)
	await until(func() -> bool: return g.current_map_id() == "dev_a" and not g.fade.is_black(), 3.0)
	check("16 jump to beat 1: nothing held, day, start", not gs.has_flag("dev_desk_seen") and gs.evidence_collected.is_empty() and gs.phase == "day" and g.current_map_id() == "dev_a" and g.director.current_lead() == "Look at the desk.")
	await play_through()
	g.jump_to_beat(1)
	await secs(0.2)
	await until(func() -> bool: return control(), 3.0)
	check("16 jump to beat 2: desk done, leaflet held, at the door", gs.has_flag("dev_desk_seen") and gs.has_flag("beat:dev_b1") and gs.has_evidence("ch01_anniversary_leaflet") and gs.phase == "day" and g.player.global_position.distance_to(Vector2(1500, 440)) < 1.0 and g.director.current_lead() == "Go outside and talk to the stranger.")
	await secs(0.5)
	check("16 a jump plays no notices, cut-aways or conversations", not d.is_open and not g.in_cutaway)
	g.jump_to_beat(2)
	await secs(0.2)
	await until(func() -> bool: return control(), 3.0)
	check("16 jump to beat 3: night, both flags", gs.has_flag("dev_talked") and gs.phase == "night" and gs.has_flag("beat:dev_b2") and g.director.current_lead() == "Get some sleep." and spot("BedSpot").shown)

	# ---- 15. the chapter card ----
	sm.active_slot = 3
	var saves_end: int = save_count
	spot("BedSpot").interact()
	await until(func() -> bool: return d.is_open, 2.0)
	await read_on()
	await until(func() -> bool: return g.chapter_card.is_open, 3.0)
	check("15 the chapter card opens", g.chapter_card.is_open and g.ending)
	await until(func() -> bool: return g.chapter_card.end_alpha > 0.95, 5.0)
	check("15 it shows the chapter number, title and 'End of chapter'", g.chapter_card.number_text == "Chapter 1" and g.chapter_card.title_text == "Test Chapter" and g.chapter_card.end_text == "End of chapter" and g.chapter_card.black > 0.99)
	await shot("14_chapter_card")
	key(KEY_SPACE)
	await until(func() -> bool: return d.is_open, 3.0)
	check("15 then the epilogue plays on black", d.is_open and d.text_label.text.begins_with("One day, somebody will want to know") and d._line_style == "voice", d.text_label.text)
	await finish_line()
	await shot("15_epilogue")
	key(KEY_SPACE)
	await until(func() -> bool: return save_count > saves_end, 3.0)
	check("15 then it autosaves", save_count == saves_end + 1)
	await until(func() -> bool: return current_scene != null and current_scene.name == "Title", 4.0)
	check("15 and returns to the title", current_scene.name == "Title")
	await secs(0.8)

	# ---- 1, 13, 14. title with saves ----
	title = current_scene
	check("1 Continue is shown once a save exists", title.has_continue())
	# damage slot 2: its backup is good
	var broken := FileAccess.open(sm.slot_path(2), FileAccess.WRITE)
	broken.store_string("{ this is not json")
	broken.close()
	check("13 a damaged file is reported, with its backup", str(sm.slot_info(2)["status"]) == "damaged" and bool(sm.slot_info(2)["has_backup"]))
	key(KEY_DOWN)
	key(KEY_DOWN)                      # Load
	key(KEY_ENTER)
	await secs(0.4)
	check("13 Load opens the slot cards on the newest save", title.slots.is_open and title.slots.mode == "load" and title.slots.selected == 3, str(title.slots.selected))
	await shot("16_slots_damaged")
	key(KEY_LEFT)                      # slot 2, damaged
	key(KEY_ENTER)
	await secs(0.3)
	check("13 choosing a damaged save offers to restore the backup", title.slots._confirm.is_open and current_scene == title)
	key(KEY_UP)
	key(KEY_ENTER)                     # Yes
	await secs(0.3)
	check("13 the backup is restored and nothing crashed", str(sm.slot_info(2)["status"]) == "ok" and str(title.slots.infos[2]["status"]) == "ok")
	key(KEY_DELETE)
	await secs(0.3)
	check("14 Delete asks first", title.slots._confirm.is_open)
	key(KEY_ENTER)                     # No
	await secs(0.3)
	check("14 answering No keeps the save", str(sm.slot_info(2)["status"]) == "ok")
	pad(JOY_BUTTON_X)
	await secs(0.3)
	key(KEY_UP)
	key(KEY_ENTER)                     # Yes
	await secs(0.3)
	check("14 answering Yes deletes it", str(sm.slot_info(2)["status"]) == "empty" and not FileAccess.file_exists(sm.slot_path(2) + ".bak"))
	await shot("17_slots_one_empty")
	key(KEY_ESCAPE)
	await secs(0.3)
	key(KEY_UP)                        # New Game
	key(KEY_ENTER)
	await secs(0.3)
	check("14 New Game starts on the first empty slot", title.slots.mode == "new" and title.slots.selected == 2)
	key(KEY_LEFT)                      # slot 1: filled
	key(KEY_ENTER)
	await secs(0.3)
	check("14 New Game on a filled slot asks before overwriting", title.slots._confirm.is_open and current_scene == title)
	key(KEY_ENTER)                     # No
	await secs(0.3)
	check("14 answering No starts nothing", current_scene == title and str(sm.slot_info(1)["status"]) == "ok")
	key(KEY_ESCAPE)
	await secs(0.3)

	# ---- 1. Continue loads the newest ----
	key(KEY_UP)                        # Continue
	check("1 the menu is back on Continue", title.menu.selected_id() == "continue", title.menu.selected_id())
	key(KEY_ENTER)
	await until(func() -> bool: return current_scene != null and current_scene.name == "Game", 3.0)
	g = current_scene
	await until(func() -> bool: return g.started, 3.0)
	check("1 Continue loads the newest save", sm.active_slot == 3 and gs.has_flag("beat:dev_b3") and g.current_map_id() == "dev_a")
	check("17 play time did not count on the title screen", absf(gs.play_seconds - float(slot_file(3)["state"]["play_seconds"])) < 1.5)

	# ---- 13. a slot that is only garbage, with no backup ----
	var junk := FileAccess.open(sm.slot_path(2), FileAccess.WRITE)
	junk.store_string("[1, 2, 3]")
	junk.close()
	check("13 a save with no 'state' is damaged, not a crash", str(sm.slot_info(2)["status"]) == "damaged" and not sm.load_slot(2) and sm.newest_slot() == 3)

	for s in [1, 2, 3]:
		sm.delete_slot(s)
	print("\nM6A RESULT: %d passed, %d failed" % [passed, failed])
	quit()
