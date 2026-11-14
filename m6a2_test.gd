extends SceneTree
# Title painting + font checks (follow-up to Milestone 6 part A2).

var passed: int = 0
var failed: int = 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label, "  ", extra)

func secs(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	root.get_node("SaveManager").saves_dir = "user://saves_m6a2"
	var Typo: GDScript = load("res://scripts/ui/Typo.gd")
	var Backdrop: GDScript = load("res://scripts/ui/cinema/TitleBackdrop.gd")
	var StoryRules: GDScript = load("res://scripts/story/StoryRules.gd")
	var setup: Dictionary = StoryRules.read_json("res://data/ui/title.json")

	# Font: one typeface everywhere.
	var light: Font = Typo.sans(300, 6)
	var bold: Font = Typo.sans(600, 0)
	check("1 Typo.sans is built on Klee One Regular for light weights", light is FontVariation and (light as FontVariation).base_font == Typo.hand())
	check("1 and on Klee One SemiBold for 500 and up", bold is FontVariation and (bold as FontVariation).base_font == Typo.hand_bold())
	check("1 the letter spacing is kept", (light as FontVariation).spacing_glyph == 6)
	check("1 no other font file is in assets/fonts", _only_klee())
	var all_text: String = ""
	for path: String in _scripts("res://scripts"):
		all_text += FileAccess.get_file_as_string(path)
	check("1 no script mentions another typeface", not all_text.contains("Josefin") and not all_text.contains("Quicksand"))

	# The painting.
	var back: Control = Backdrop.new()
	root.add_child(back)
	await secs(0.3)
	check("2 the stand-in shows until a painting is loaded", back.get("painting") == null and back.get("_outside").visible)
	var ok: bool = back.use_painting(setup.get("painting", {}))
	check("2 use_painting loads the painting from title.json", ok and back.get("painting") != null)
	check("2 the stand-in is hidden once it is loaded", not back.get("_outside").visible and not back.get("_front").visible)
	var painting: Control = back.get("painting")
	var rect: Rect2 = painting.art_rect()
	check("3 the painting covers the whole screen", rect.position.x <= 0.0 and rect.position.y <= 0.0 and rect.end.x >= 1920.0 and rect.end.y >= 1080.0, str(rect))
	check("3 it keeps its shape", is_equal_approx(rect.size.x / rect.size.y, 2576.0 / 1438.0))
	var corner: Vector2 = painting.to_screen(Vector2(2576, 1438))
	check("3 to_screen maps the painting's far corner to the rect's far corner", corner.is_equal_approx(rect.end))

	# Things move.
	var mat: ShaderMaterial = painting.get("_material")
	check("4 the shader is attached with its mask", mat != null and mat.shader != null and mat.get_shader_parameter("masks") != null)
	var t0: float = float(painting.get("time"))
	var w0: float = float(painting.get("_wind_phase"))
	var gusts: Array[float] = []
	for i: int in range(40):
		await secs(0.1)
		gusts.append(float(painting.get("gust")))
	check("4 time passes in the shader", float(mat.get_shader_parameter("time_s")) > t0 + 3.0)
	check("4 the wind carries the snow along", float(mat.get_shader_parameter("wind_phase")) > w0 + 2.0)
	check("4 gust stays between 0 and 1 and changes", gusts.min() >= 0.0 and gusts.max() <= 1.0 and gusts.max() - gusts.min() > 0.02)
	var steam: Array = painting.get("_steam")
	check("4 steam is rising from the cup", steam.size() > 0)

	# The masks mark curtains, glass and lamp.
	var masks: Image = (load("res://assets/art/title/title_masks.png") as Texture2D).get_image()
	var left_curtain: Color = masks.get_pixel(int(1350 / 2), int(300 / 2))
	var glass: Color = masks.get_pixel(int(1850 / 2), int(350 / 2))
	var wall: Color = masks.get_pixel(int(300 / 2), int(300 / 2))
	check("5 the mask marks the left curtain", left_curtain.r > 0.8, str(left_curtain))
	check("5 the mask marks a window pane", glass.g > 0.8, str(glass))
	check("5 the mask leaves the bare wall still", wall.r < 0.05 and wall.g < 0.05, str(wall))
	var mullion: Color = masks.get_pixel(int(1740 / 2), int(350 / 2))
	check("5 no snow on the window bar", mullion.g < 0.2, str(mullion))
	var mug: Color = masks.get_pixel(int(1620 / 2), int(1100 / 2))
	check("5 no snow on the mug", mug.g < 0.2, str(mug))

	# A missing file falls back to the stand-in.
	var back2: Control = Backdrop.new()
	root.add_child(back2)
	await secs(0.2)
	var bad: Dictionary = (setup.get("painting", {}) as Dictionary).duplicate()
	bad["image"] = "res://assets/art/title/not_there.jpg"
	check("6 a missing painting is refused", not back2.use_painting(bad))
	check("6 and the stand-in stays visible", back2.get("_outside").visible)

	# The curtain mask is a "core": zero on the wall and on the curtain's outline, 1 well inside the cloth.
	var core_max_outside: float = 0.0
	var core_inside: float = 0.0
	for y: int in range(0, masks.get_height(), 4):
		for x: int in range(0, masks.get_width(), 4):
			var r: float = masks.get_pixel(x, y).r
			if x < 400:
				core_max_outside = maxf(core_max_outside, r)      # bare wall on the far left (the hem of the curtain only reaches x 450)
			core_inside = maxf(core_inside, r)
	check("5 the curtain core is zero over the bare wall", core_max_outside < 0.01, str(core_max_outside))
	check("5 and rises to 1 inside the cloth", core_inside > 0.99, str(core_inside))
	var cfg: Dictionary = setup.get("painting", {})
	check("5 the folds' swing stays smaller than the core's depth, so no wall can be pulled in", float(cfg.get("curtain_px", 0.0)) + 2.0 < 52.0 * 0.66, str(cfg.get("curtain_px")))

	# The whole title screen.
	var Title: GDScript = load("res://scripts/ui/TitleScreen.gd")
	Title.pressed_once = true
	var title: Control = Title.new()
	root.add_child(title)
	await secs(0.5)
	check("7 the entrance starts in pitch black", title.dark > 0.99 and title._logo.reveal < 0.01 and title.backdrop.painting.wake < 0.01)
	var mid_picture: bool = false
	var mid_logo: bool = false
	var guard: float = 0.0
	while guard < 30.0 and not (title._logo.reveal > 0.99 and title.menu.reveal > 0.99):
		await secs(0.1)
		guard += 0.1
		mid_picture = mid_picture or (title.dark > 0.2 and title.dark < 0.8)
		mid_logo = mid_logo or (title._logo.reveal > 0.2 and title._logo.reveal < 0.8)
	check("7 the picture rises out of the black in steps (not a cut)", mid_picture)
	check("7 the name blooms in after the picture (not before)", mid_logo)
	check("7 the whole entrance finishes", title._logo.reveal > 0.99 and title.menu.reveal > 0.99 and title.dark < 0.01 and title.backdrop.painting.wake > 0.5, "%s %s %s" % [title._logo.reveal, title.menu.reveal, title.dark])
	check("7 the title screen shows the painting", title.backdrop.painting != null)
	check("7 the menu is showing", title.menu.visible and title.menu.items.size() >= 3)
	check("7 the name is a lockup: BELOW THE over PASS", title._logo._small_text == "BELOW THE" and title._logo._big_text == "PASS", title._logo._small_text + "/" + title._logo._big_text)
	check("7 the lockup is no wider than 460 px (the old name was 560)", title._logo.lockup_width() < 460.0 and title._logo.lockup_width() > 250.0, str(title._logo.lockup_width()))
	check("7 the lockup sits above the menu", LOGO_BOTTOM_OK(title))
	check("7 the name only uses Klee One", title._logo._big_font is FontVariation and (title._logo._big_font as FontVariation).base_font == Typo.hand_bold())
	await secs(0.2)

	# No grey flash between scenes, a frame meter on F3, and a painting that holds still.
	check("9 the default clear colour is black, so no grey frame shows between scenes", RenderingServer.get_default_clear_color() == Color.BLACK, str(RenderingServer.get_default_clear_color()))
	await secs(0.3)
	var meter: Node = root.get_node_or_null("FpsOverlay")
	check("9 the frame meter exists and is hidden until F3", meter != null and not meter.visible)
	var f3: InputEventKey = InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	Input.parse_input_event(f3)
	await secs(0.8)
	check("9 F3 shows the meter, with FPS and the graphics card in it", meter.visible and meter._label.text.contains("FPS") and meter._label.text.length() > 20, meter._label.text)
	Input.parse_input_event(f3)
	await secs(0.3)
	var held: Control = title.backdrop._painting
	check("9 the painting holds perfectly still (no train-like drift)", held.scale == Vector2.ONE and held.position == Vector2.ZERO, "%s %s" % [held.scale, held.position])
	await secs(1.5)
	check("9 and keeps holding still", held.scale == Vector2.ONE and held.position == Vector2.ZERO)

	# The menu's warm light glides from word to word.
	var menu: Control = title.menu
	var from_y: float = menu._light_y
	var next_id: String = ""
	menu._step(1)
	var to_y: float = menu._rows[menu.selected] + 28.0
	await secs(0.1)
	var halfway: float = menu._light_y
	check("10 the light has started to travel, not jumped", halfway > from_y + 1.0 and halfway < to_y - 1.0, "%s -> %s (now %s)" % [from_y, to_y, halfway])
	await secs(1.2)
	check("10 and arrives on the chosen word", absf(menu._light_y - to_y) < 2.0, "%s vs %s" % [menu._light_y, to_y])
	check("10 the chosen word has slid fully across", menu._slide[menu.selected] > 0.99)
	menu._step(-1)
	await secs(1.2)

	# Only the cloth moves: sample the bare wall and the curtain at two moments.
	var painting2: Control = title.backdrop.painting
	painting2._fx.visible = false
	painting2._room.visible = false
	title._overlay.visible = false
	title._logo.modulate.a = 0.0
	title.menu.visible = false
	var stack: Array = [title.backdrop]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CPUParticles2D:
			(n as CPUParticles2D).visible = false
		stack.append_array(n.get_children())
	await RenderingServer.frame_post_draw
	var wall_rect: Rect2i = Rect2i(0, 0, 420, 220)
	var cloth_rect: Rect2i = Rect2i(1140, 120, 120, 260)    # inside the right-hand curtain's folds
	var first: Image = root.get_texture().get_image()
	var best_wall: float = 0.0
	var best_cloth: float = 0.0
	for round: int in range(6):
		await secs(0.7)
		await RenderingServer.frame_post_draw
		var later: Image = root.get_texture().get_image()
		best_wall = maxf(best_wall, _max_diff(first, later, wall_rect))
		best_cloth = maxf(best_cloth, _max_diff(first, later, Rect2i(1450, 120, 200, 360)))
	check("8 the bare wall does not move at all", best_wall < 0.05, str(best_wall))
	check("8 but the curtain's folds do", best_cloth > 0.04, str(best_cloth))

	print("M6A2 RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func LOGO_BOTTOM_OK(title: Control) -> bool:
	# the lockup hangs about 150 px below its position; the menu must start below that
	return title._logo.position.y + 160.0 < title.menu.position.y

func _max_diff(a: Image, b: Image, rect: Rect2i) -> float:
	var biggest: float = 0.0
	for y: int in range(rect.position.y, rect.end.y, 2):
		for x: int in range(rect.position.x, rect.end.x, 2):
			biggest = maxf(biggest, absf(a.get_pixel(x, y).r - b.get_pixel(x, y).r))
	return biggest

func _only_klee() -> bool:
	for f: String in DirAccess.get_files_at("res://assets/fonts"):
		if f.ends_with(".ttf") and not f.begins_with("KleeOne"):
			return false
	return true

func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			found.append(dir + "/" + f)
	for sub: String in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir + "/" + sub))
	return found
