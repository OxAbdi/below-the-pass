extends Control

# The title screen: a slow, moving picture, the game's name, and a quiet menu down the left.
#
#   first visit:   "Press any button" under the name, then the menu fades in word by word
#   Continue       loads the newest save (only shown when there is one)
#   New Game       pick a slot, then the chapter starts
#   Load           pick a save
#
# The words live in data/ui/menus.json; the picture and the music in data/ui/title.json.
# It keeps no state. Saves are read through SaveManager; the story lives in GameState.

const StoryRules := preload("res://scripts/story/StoryRules.gd")
const TitleMenuScript := preload("res://scripts/ui/menu/TitleMenu.gd")
const SlotListScript := preload("res://scripts/ui/menu/SlotList.gd")
const BackdropScript := preload("res://scripts/ui/cinema/TitleBackdrop.gd")
const KeyGlyphs := preload("res://scripts/ui/KeyGlyphs.gd")
const Typo := preload("res://scripts/ui/Typo.gd")
const LogoScript := preload("res://scripts/ui/TitleLogo.gd")
const RuntimeSetup := preload("res://scripts/ui/RuntimeSetup.gd")

const MENUS_PATH: String = "res://data/ui/menus.json"
const TITLE_PATH: String = "res://data/ui/title.json"
const GAME_SCENE: String = "res://scenes/game/game.tscn"
const LEFT: float = 144.0
const LOGO_Y: float = 170.0       # the baseline of the small line of the name; the lockup hangs below it
const MENU_Y: float = 400.0

# The entrance, in seconds from the moment the title scene starts. It begins in pitch black.
const BLACK_HOLD: float = 0.8     # nothing but black (the picture is drawn and its shader compiled out of sight)
const PICTURE_IN: float = 3.6     # the picture rises out of the black
const WAKE_TIME: float = 6.0      # the snow and the cloth stir from still to full
const LOGO_START: float = 2.8
const LOGO_TIME: float = 3.4
const MENU_START: float = 5.4
const CALM_LIMIT: float = 2.0     # the longest the black waits for steady frames

# The "Press any button" screen shows once per run of the game, not every time you quit to the title.
static var pressed_once: bool = false

var texts: Dictionary = {}
var setup: Dictionary = {}
var backdrop: BackdropScript
var menu: TitleMenuScript
var slots: SlotListScript
var waiting_for_press: bool = false

var _overlay: Control        # the shade, the name, the description and the prompts
var _logo: LogoScript
var _veil: ColorRect         # a black sheet over everything; the entrance and the exit are its fade
var dark: float = 1.0:       # 1 = pitch black, 0 = clear
	set(value):
		dark = value
		if _veil != null:
			_veil.color = Color(0, 0, 0, value)
var _press_alpha: float = 0.0
var _desc_alpha: float = 0.0
var _time: float = 0.0
var _leaving: bool = false
var _preload_asked: bool = false
var _description_text: String = ""
var _description_paragraph: TextParagraph


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RuntimeSetup.apply(get_tree())
	get_tree().paused = false
	texts = StoryRules.read_json(MENUS_PATH)
	setup = StoryRules.read_json(TITLE_PATH)
	backdrop = BackdropScript.new()
	add_child(backdrop)
	backdrop.use_layers(_load_layers())
	backdrop.use_painting(setup.get("painting", {}))
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_logo = LogoScript.new()
	_logo.position = Vector2(LEFT, LOGO_Y)
	_logo.title = str((texts.get("title", {}) as Dictionary).get("game_title", "Below the Pass"))
	_logo.reveal = 0.0
	add_child(_logo)
	menu = TitleMenuScript.new()
	menu.position = Vector2(LEFT, MENU_Y)
	add_child(menu)
	menu.picked.connect(_on_menu_picked)
	menu.selection_changed.connect(func(_id: String) -> void: _flash_description())
	slots = SlotListScript.new()
	add_child(slots)
	slots.chosen.connect(_on_slot_chosen)
	slots.cancelled.connect(_on_slots_closed)
	refresh_menu()
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	dark = 1.0
	Audio.play_music(str(setup.get("music", "")), 2.5)
	_play_intro()


# From pitch black, slowly: the picture rises out of the dark and the storm stirs awake,
# then the name blooms in, then the menu (or "Press any button").
func _play_intro() -> void:
	dark = 1.0
	if backdrop.painting != null:
		backdrop.painting.wake = 0.0
	# Everything starts hidden, and stays hidden (and deaf to the keyboard) until its moment in the entrance.
	if pressed_once:
		menu.reveal = 0.0
	else:
		waiting_for_press = true
		menu.visible = false
		menu.active = false
	# The first frames are heavy (the painting and its shader are prepared for the graphics card), and an animation
	# that starts in the middle of that jumps ahead. So the black waits until frames come at a steady pace.
	var calm: int = 0
	var waited: float = 0.0
	while calm < 4 and waited < CALM_LIMIT:
		await get_tree().process_frame
		var step: float = get_process_delta_time()
		waited += step
		calm = calm + 1 if step < 0.03 else 0
	var intro: Tween = create_tween()
	intro.set_parallel(true)
	intro.tween_property(self, "dark", 0.0, PICTURE_IN).set_delay(BLACK_HOLD).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if backdrop.painting != null:
		intro.tween_property(backdrop.painting, "wake", 1.0, WAKE_TIME).set_delay(BLACK_HOLD).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	intro.tween_property(_logo, "reveal", 1.0, LOGO_TIME).set_delay(BLACK_HOLD + LOGO_START)
	if pressed_once:
		intro.tween_property(menu, "reveal", 1.0, 0.9).set_delay(BLACK_HOLD + MENU_START)
		intro.tween_method(func(v: float) -> void: _desc_alpha = v, 0.0, 1.0, 0.6).set_delay(BLACK_HOLD + MENU_START + 0.6)
	else:
		intro.tween_method(func(v: float) -> void: _press_alpha = v, 0.0, 1.0, 0.9).set_delay(BLACK_HOLD + MENU_START)


func _load_layers() -> Array:
	var result: Array = []
	for layer: Variant in setup.get("layers", []):
		var path: String = str((layer as Dictionary).get("texture", ""))
		if path != "" and ResourceLoader.exists(path):
			result.append({ "texture": load(path), "depth": float((layer as Dictionary).get("depth", 0.5)) })
	return result


func refresh_menu() -> void:
	var words: Dictionary = texts.get("title", {})
	var items: Array = []
	if SaveManager.has_any_save():
		items.append({ "id": "continue", "text": str(words.get("continue", "Continue")), "group": 0, "description": _continue_description() })
	items.append({ "id": "new", "text": str(words.get("new_game", "New Game")), "group": 0, "description": str(words.get("desc_new", "")) })
	items.append({ "id": "load", "text": str(words.get("load", "Load")), "group": 0, "disabled": not _any_slot_used(), "description": str(words.get("desc_load", "")) })
	items.append({ "id": "settings", "text": str(words.get("settings", "Settings")), "group": 1, "disabled": true, "description": str(words.get("desc_settings", "")) })
	items.append({ "id": "quit", "text": str(words.get("quit", "Quit")), "group": 2, "description": str(words.get("desc_quit", "")) })
	var keep: String = menu.selected_id()
	for item: Dictionary in items:
		if str(item["id"]) == keep and not bool(item.get("disabled", false)):
			menu.set_items(items, keep)
			return
	menu.set_items(items)


# "Graves Studio, Morning. Chapter 1, 0:35 played."
func _continue_description() -> String:
	var info: Dictionary = SaveManager.slot_info(SaveManager.newest_slot())
	var summary: Dictionary = info.get("summary", {})
	var words: Dictionary = texts.get("title", {})
	var place: String = str(summary.get("map_name", ""))
	if str(summary.get("phase_name", "")) != "":
		place += ", " + str(summary.get("phase_name", ""))
	return str(words.get("desc_continue", "%s. Chapter %d, %s played.")) % [place, int(summary.get("chapter", 1)), SlotListScript.format_play_time(float(summary.get("play_seconds", 0.0)))]


func has_continue() -> bool:
	for item: Dictionary in menu.items:
		if str(item.get("id", "")) == "continue":
			return true
	return false


func _any_slot_used() -> bool:
	for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
		if str(SaveManager.slot_info(slot)["status"]) != "empty":
			return true
	return false


# ---------- input ----------

func _input(event: InputEvent) -> void:
	KeyGlyphs.note(event)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if waiting_for_press:
		if _is_press(event) and _press_alpha > 0.05:
			get_viewport().set_input_as_handled()
			_dismiss_press()
		return
	if event is InputEventMouse:
		return
	if slots.handle_input(event) or menu.handle_input(event):
		get_viewport().set_input_as_handled()


func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		return event.is_pressed() and not event.is_echo()
	return false


func _dismiss_press() -> void:
	waiting_for_press = false
	pressed_once = true
	Audio.play("choice_pick")
	menu.visible = true
	menu.active = true
	menu.reveal = 0.0
	var tween: Tween = create_tween()
	tween.tween_method(func(v: float) -> void: _press_alpha = v, _press_alpha, 0.0, 0.3)
	tween.tween_property(menu, "reveal", 1.0, 0.9)
	tween.parallel().tween_method(func(v: float) -> void: _desc_alpha = v, 0.0, 1.0, 0.5).set_delay(0.5)


func _flash_description() -> void:
	_desc_alpha = 0.0
	create_tween().tween_method(func(v: float) -> void: _desc_alpha = v, 0.0, 1.0, 0.35)


func _on_menu_picked(id: String) -> void:
	if _leaving:
		return
	match id:
		"continue":
			_preload_game()
			if SaveManager.load_slot(SaveManager.newest_slot()):
				_start_game()
		"new":
			_open_slots("new")
		"load":
			_open_slots("load")
		"quit":
			get_tree().quit()


func _open_slots(mode: String) -> void:
	# The player is about to start a game: begin loading it now, while they choose a slot.
	_preload_game()
	menu.active = false
	menu.visible = false
	slots.open(mode, texts)


func _on_slots_closed() -> void:
	menu.active = true
	menu.visible = true
	refresh_menu()


func _on_slot_chosen(slot: int) -> void:
	if slots.mode == "new":
		# A new game in this slot: the old save (if any) is gone, as the player was asked.
		SaveManager.delete_slot(slot)
		GameState.reset()
		SaveManager.active_slot = slot
		SaveManager.autosave_pending = false
		SaveManager.last_saved_at = 0
		_start_game()
	elif SaveManager.load_slot(slot):
		_start_game()
	else:
		slots.refresh()


func _start_game() -> void:
	_leaving = true
	slots.close()
	Audio.stop_music(1.8)
	# Slowly into black: the picture, the name and the menu all go dark together.
	var fade: Tween = create_tween()
	fade.tween_property(self, "dark", 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade.finished
	# The game has been loading in the background since the title appeared; wait for it if it is not done.
	_preload_game()
	while ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed: Variant = ResourceLoader.load_threaded_get(GAME_SCENE)
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(GAME_SCENE)


# Starts loading the game scene (and everything it needs) on other threads. Safe to call twice.
func _preload_game() -> void:
	if _preload_asked:
		return
	_preload_asked = true
	ResourceLoader.load_threaded_request(GAME_SCENE)


# ---------- drawing ----------

# The line under the menu. It is shaped once per sentence, not once per frame.
func _description() -> TextParagraph:
	var text: String = menu.selected_description()
	if _description_paragraph == null or text != _description_text:
		_description_text = text
		_description_paragraph = TextParagraph.new()
		_description_paragraph.width = 560.0
		_description_paragraph.max_lines_visible = 3
		_description_paragraph.add_string(text, Typo.hand(), 21)
	return _description_paragraph


func _process(delta: float) -> void:
	_time += delta
	_logo.visible = not slots.is_open
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	var c: Control = _overlay
	# The painting's left side is already dark. A light shade keeps the words readable over any art,
	# and the edges darken like an old lens.
	var dark: Color = Color(0.02, 0.015, 0.02, 0.5)
	var clear: Color = Color(0.02, 0.015, 0.02, 0.0)
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(900, 0), Vector2(900, 1080), Vector2(0, 1080)]), PackedColorArray([dark, clear, clear, dark]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1920, 0), Vector2(1920, 120), Vector2(0, 120)]), PackedColorArray([Color(0, 0, 0, 0.4), Color(0, 0, 0, 0.4), clear, clear]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 920), Vector2(1920, 920), Vector2(1920, 1080), Vector2(0, 1080)]), PackedColorArray([clear, clear, Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.5)]))
	if slots.is_open:
		return
	var words: Dictionary = texts.get("title", {})
	# "Press any button", breathing.
	if _press_alpha > 0.0:
		var pulse: float = 0.55 + 0.45 * sin(_time * 2.2)
		c.draw_string(Typo.sans(400, 6), Vector2(LEFT + 2, MENU_Y + 40), str(words.get("press_any", "Press any button")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color(Typo.CREAM, 0.8 * pulse * _press_alpha))
		return
	# What the chosen item does.
	if menu.visible:
		var desc_y: float = MENU_Y + menu.size.y + 56.0
		_description().draw(c.get_canvas_item(), Vector2(LEFT, desc_y - Typo.hand().get_ascent(21)), Color(Typo.CREAM, 0.55 * _desc_alpha * menu.reveal))
		KeyGlyphs.draw(c, Vector2(LEFT, 1002), "accept", str((texts.get("slots", {}) as Dictionary).get("hint_choose", "Select")), 0.8 * menu.reveal)
