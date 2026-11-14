extends SceneTree
# The pause menu's look and feel ("frost on the glass"), see docs/pause-menu-build.md.
# Takes screenshots into /home/claude/shots/ (pz_*.png) and checks the rules the director asked for.
# Run:  godot --path . -s m6p_test.gd      (needs a display: xvfb-run on a server)

const TITLE := "res://scenes/ui/title.tscn"
const GAME := "res://scenes/game/game.tscn"
const SAVES := "user://saves_m6p"
const SHOTS := "/home/claude/shots/"

var passed: int = 0
var failed: int = 0
var gs: Node
var sm: Node
var g: Node
var d: Control


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label, "  ", extra)


func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func shot(n: String) -> Image:
	var img: Image = await grab()
	img.save_png(SHOTS + "pz_%s.png" % n)
	return img


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


func until(test: Callable, timeout: float = 6.0) -> bool:
	var waited: float = 0.0
	while waited < timeout:
		if test.call():
			return true
		await secs(0.05)
		waited += 0.05
	return bool(test.call())


func finish_line() -> void:
	if d.typing:
		key(KEY_SPACE)
		await frames(2)


# Average brightness of a picture, in two parts: the whole screen and its right half
# (the right half has no frost and no words, only the blurred game and the snow).
func brightness(img: Image) -> Array:
	var small: Image = img.duplicate() as Image
	small.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var whole: float = 0.0
	var right: float = 0.0
	var right_count: int = 0
	for y: int in range(36):
		for x: int in range(64):
			var c: Color = small.get_pixel(x, y)
			var l: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			whole += l
			if x >= 32:
				right += l
				right_count += 1
	return [whole / float(64 * 36), right / float(right_count)]


# Takes pictures for `seconds` of real time, as fast as the screen draws. Returns [[whole, right], ...].
# The game clock runs slowly meanwhile (`slow`), so a short animation is caught in many pictures:
# a blink or a pop that lasted only a moment could not hide between two of them.
func record(seconds: float, press: Callable = Callable(), slow: float = 0.2) -> Array:
	var series: Array = []
	var started: int = Time.get_ticks_msec()
	var pressed: bool = not press.is_valid()
	Engine.time_scale = slow
	while float(Time.get_ticks_msec() - started) / 1000.0 < seconds:
		if not pressed and series.size() >= 2:
			press.call()
			pressed = true
		series.append(brightness(await grab()))
	Engine.time_scale = 1.0
	return series


# Returns the biggest move AGAINST the wanted direction (0.0 = it only ever moves the wanted way).
func wrong_way(series: Array, index: int, want_down: bool) -> float:
	var worst: float = 0.0
	for i: int in range(1, series.size()):
		var delta: float = float(series[i][index]) - float(series[i - 1][index])
		worst = maxf(worst, delta if want_down else -delta)
	return worst


func biggest_step(series: Array, index: int) -> float:
	var worst: float = 0.0
	for i: int in range(1, series.size()):
		worst = maxf(worst, absf(float(series[i][index]) - float(series[i - 1][index])))
	return worst


# How different two pictures are in one strip of columns (0 = identical, 1 = black against white).
func strip_difference(a: Image, b: Image, x_from: int, x_to: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for x: int in range(x_from, mini(x_to, a.get_width()), 2):
		for y: int in range(0, a.get_height(), 6):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			count += 1
	return total / float(maxi(1, count))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	gs = root.get_node("GameState")
	sm = root.get_node("SaveManager")
	sm.saves_dir = SAVES
	for s in [1, 2, 3]:
		sm.delete_slot(s)
	gs.reset()
	sm.active_slot = 1
	change_scene_to_file(GAME)
	await frames(3)
	g = current_scene
	d = g.dialogue
	# Skip the opening film, then wait for the first conversation.
	await until(func() -> bool: return g.cinematic.is_playing and g.cinematic.caption_alpha > 0.95, 14.0)
	key(KEY_SPACE)
	await secs(0.2)
	Input.action_press("pause")
	await secs(1.4)
	Input.action_release("pause")
	await until(func() -> bool: return not g.cinematic.is_playing, 3.0)
	await until(func() -> bool: return d.is_open, 8.0)
	await finish_line()
	await secs(0.6)

	# ---- 1. over a conversation: it opens smoothly, the conversation stays, the frost is where it should be ----
	var open_series: Array = await record(9.0, func() -> void: key(KEY_ESCAPE))
	check("1 Esc opens the pause menu over the conversation and stops the game", g.pause.is_open and paused)
	await secs(2.5)                    # let the opening finish before looking at it
	await shot("talk")
	check("1 the conversation box and its portrait stay on screen behind the menu", g.get_node("Dialogue").visible and d.portrait.visible and d.is_open)
	check("1 the place line is filled in from the map and the time of day", g.pause.place.contains(" · "), g.pause.place)

	# No flash: the right half of the screen only ever gets darker while opening.
	var worse: float = wrong_way(open_series, 1, true)
	check("3 opening never flashes: the picture behind only gets darker", worse < 0.002, "moved the wrong way by %.4f over %d frames" % [worse, open_series.size()])
	var step: float = biggest_step(open_series, 0)
	check("3 opening has no sudden jump (biggest brightness step between frames is small)", step < 0.02, "biggest step %.4f" % step)
	print("   open: %d frames, whole %.3f -> %.3f, right half %.3f -> %.3f" % [open_series.size(), open_series[0][0], open_series[-1][0], open_series[0][1], open_series[-1][1]])

	# The frost: about 30% of the screen, none past 780 px, none in the right corners.
	g.pause.snow.visible = false
	var with_frost: Image = await grab()
	g.pause.frost.visible = false
	var without_frost: Image = await grab()
	g.pause.frost.visible = true
	var with_frost_again: Image = await grab()
	g.pause.snow.visible = true
	# Two pictures with the frost on are the baseline: anything on screen that moves by itself
	# (the conversation box idles a little) shows up there too, and is not frost.
	var idle: float = strip_difference(with_frost, with_frost_again, 800, 1920)
	var beyond: float = strip_difference(with_frost, without_frost, 800, 1920)
	check("2 there is frost at the left edge", strip_difference(with_frost, without_frost, 0, 300) > 0.03, "%.4f" % strip_difference(with_frost, without_frost, 0, 300))
	check("2 there is NO frost at x = 900 (and none further right, corners included)", beyond <= idle + 0.0003, "difference %.5f, picture-to-picture baseline %.5f" % [beyond, idle])
	var reach: int = 0
	for x: int in range(0, 1920, 20):
		if strip_difference(with_frost, without_frost, x, x + 20) > 0.004:
			reach = x + 20
	check("2 the frost covers about 30% of the screen (reaches 450 to 800 px)", reach >= 450 and reach <= 800, "reaches %d px" % reach)

	# ---- 4. closing: Esc, Start and Resume all close it at once, and smoothly ----
	var close_series: Array = await record(4.0, func() -> void: key(KEY_ESCAPE))
	check("4 Esc closes it at once and the game runs again", not g.pause.is_open and not paused)
	var close_worse: float = wrong_way(close_series, 1, false)
	check("4 closing never flashes: the picture only gets brighter", close_worse < 0.002, "moved the wrong way by %.4f" % close_worse)
	check("4 closing has no sudden jump", biggest_step(close_series, 0) < 0.02, "biggest step %.4f" % biggest_step(close_series, 0))
	await until(func() -> bool: return not g.pause.visible, 3.0)
	check("4 the menu is hidden when the fade ends", not g.pause.visible)
	check("4 the conversation is still open and untouched", d.is_open and g.get_node("Dialogue").visible)

	pad(JOY_BUTTON_START)
	await secs(0.3)
	check("4 Start opens it", g.pause.is_open)
	pad(JOY_BUTTON_START)
	await frames(2)
	check("4 Start closes it at once", not g.pause.is_open and not paused)
	await secs(0.6)
	key(KEY_ESCAPE)
	await secs(0.5)
	key(KEY_ENTER)                     # Resume is the first word
	await frames(2)
	check("4 the Resume word closes it at once", not g.pause.is_open and not paused)
	await secs(0.6)

	# Back to free roam: read the conversation to its end.
	for i in 80:
		if g.player_in_control():
			break
		if d.is_open:
			await finish_line()
			key(KEY_SPACE)
		await secs(0.4)
	await secs(0.8)

	# ---- 5. walking: the menu words and Settings ----
	key(KEY_ESCAPE)
	await secs(2.0)
	await shot("walk")
	var items: Array = g.pause.menu.items
	check("5 the menu has the six words in order", items.size() == 6 and str(items[0]["id"]) == "resume" and str(items[1]["id"]) == "board" and str(items[2]["id"]) == "save" and str(items[3]["id"]) == "load" and str(items[4]["id"]) == "settings" and str(items[5]["id"]) == "quit")
	check("5 Case board and Save are available while walking", not bool(items[1].get("disabled", false)) and not bool(items[2].get("disabled", false)))
	check("5 Settings is greyed out", bool(items[4].get("disabled", false)))
	check("5 every word has a description from menus.json", str(items[0]["description"]) == "Back to Northvale." and str(items[5]["description"]) == "Quit to the title screen.")
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_DOWN)
	await secs(0.2)
	check("5 three Downs reach Load", g.pause.menu.selected_id() == "load", g.pause.menu.selected_id())
	key(KEY_DOWN)
	await secs(0.2)
	check("5 Down from Load skips Settings and lands on Quit to title", g.pause.menu.selected_id() == "quit", g.pause.menu.selected_id())
	await secs(0.5)
	await shot("walk_quit_chosen")

	# ---- 6. the question on the frost ----
	key(KEY_ENTER)
	await secs(0.6)
	check("6 Quit to title asks first (and the game has not left)", g.pause.confirm.is_open and current_scene == g)
	check("6 the question starts on NO", g.pause.confirm._choice == 0)
	check("6 the question reads 'Return to the title?'", g.pause.confirm.heading == "Return to the title?", g.pause.confirm.heading)
	await shot("quit_question")
	key(KEY_RIGHT)
	await secs(0.5)
	await shot("quit_question_yes")
	key(KEY_LEFT)
	await secs(0.2)
	key(KEY_ENTER)                     # NO
	await secs(0.6)
	check("6 No brings the menu back", not g.pause.confirm.is_open and g.pause.is_open and g.pause.menu.active and current_scene == g)
	await shot("quit_declined")
	key(KEY_ESCAPE)
	await secs(0.5)
	check("6 Esc closed the menu again", not g.pause.is_open)

	# Yes: black sheet over 1.2 s, then the title screen.
	await secs(0.6)
	key(KEY_ESCAPE)
	await secs(1.8)
	key(KEY_UP)                        # wraps to Quit to title
	key(KEY_ENTER)
	await secs(0.5)
	key(KEY_RIGHT)
	key(KEY_ENTER)                     # YES
	var seen: Array[float] = []
	var left_game_at: float = -1.0
	var started: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - started) / 1000.0 < 10.0:
		await process_frame
		if current_scene != g:
			left_game_at = float(Time.get_ticks_msec() - started) / 1000.0
			break
		seen.append(g.pause.black.modulate.a)
		if seen.size() == 12:
			key(KEY_ESCAPE)            # pressing Esc during the fade must do nothing
	var rising: bool = true
	for i: int in range(1, seen.size()):
		if seen[i] < seen[i - 1] - 0.0001:
			rising = false
	check("6 Yes fades to black over about a second", seen.size() > 4 and rising and seen[-1] > 0.9, "last black %.2f after %d frames" % [seen[-1] if seen.size() > 0 else -1.0, seen.size()])
	check("6 it only leaves the game once the screen is black", left_game_at >= 1.0 and seen[-1] > 0.9, "left after %.2f s, black %.2f" % [left_game_at, seen[-1] if seen.size() > 0 else -1.0])
	await secs(0.8)
	check("6 the title screen is loaded", current_scene != null and current_scene.scene_file_path == TITLE, str(current_scene.scene_file_path if current_scene != null else "none"))

	# ---- 7. static checks: only Klee One, no leftover placeholder fonts in the pause menu files ----
	var files: Array[String] = [
		"res://scripts/ui/PauseMenu.gd", "res://scripts/ui/menu/PauseText.gd", "res://scripts/ui/menu/FrostConfirm.gd",
		"res://shaders/pause_blur.gdshader", "res://shaders/pause_frost.gdshader",
	]
	var clean: bool = true
	var dirty: String = ""
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		for bad: String in ["fallback_font", "Josefin", "Quicksand"]:
			if text.contains(bad):
				clean = false
				dirty += "%s has %s; " % [path, bad]
	check("7 no pause menu file uses fallback_font, Josefin or Quicksand", clean, dirty)
	var menus: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/menus.json"))
	var pause_words: Dictionary = menus.get("pause", {})
	check("7 the new words live in menus.json", str(pause_words.get("quit_question", "")) == "Return to the title?" and str(pause_words.get("desc_quit", "")) == "Quit to the title screen.")

	for s in [1, 2, 3]:
		sm.delete_slot(s)
	print("\nM6P RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
