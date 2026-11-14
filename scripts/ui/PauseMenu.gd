extends Control

# The pause menu, "frost on the glass".
#
# The game stops and the moment freezes: the picture behind (the map, and a conversation with its
# portrait if there is one) goes soft, cold and dark, frost grows in down the left side, and the title
# screen's quiet menu is written over the frost. Behind the chosen word a patch of frost melts and the
# warm light shows through, like breath on a window.
#
# Layers, back to front (all children of this node):
#   Blur      reads the screen under it and blurs / darkens it      (shaders/pause_blur.gdshader)
#   Shade     a dark left side and soft dark edges
#   Frost     the frost band and the melted patch                   (shaders/pause_frost.gdshader)
#   Snow      slow flakes drifting over everything
#   Text      chapter, title, place, lead, description, hints, play time (PauseText.gd)
#   menu      the six words and the warm light (TitleMenu.gd, the same as on the title screen)
#   slots     the save / load cards (they cover the whole screen while open)
#   Wash      a dark veil behind the question
#   confirm   "Return to the title?" (FrostConfirm.gd)
#   Black     only used to fade out when quitting to the title
#
# While it is open the whole game is paused (get_tree().paused), so a conversation underneath simply
# waits. This node keeps running because its process mode is "always".
#
# It only reports what the player picked. The Game does the work.
#
# Everything eases in and out: no flash, no blink, no pop. Words only fade (slow-moving big text
# shimmers, see art-direction.md). Settings is greyed out until Milestone 8.

signal resumed
signal board_requested
signal load_requested(slot: int)
signal quit_requested

const TitleMenuScript := preload("res://scripts/ui/menu/TitleMenu.gd")
const SlotListScript := preload("res://scripts/ui/menu/SlotList.gd")
const FrostConfirmScript := preload("res://scripts/ui/menu/FrostConfirm.gd")
const PauseTextScript := preload("res://scripts/ui/menu/PauseText.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const BLUR_SHADER: Shader = preload("res://shaders/pause_blur.gdshader")
const FROST_SHADER: Shader = preload("res://shaders/pause_frost.gdshader")

const LEFT: float = 144.0
const MENU_Y: float = 470.0

const OPEN_BLUR: float = 0.75       # the picture goes soft, cold and dark
const OPEN_FROST: float = 1.1       # the frost grows in from the left
const OPEN_FROST_DELAY: float = 0.05
const OPEN_FROST_FADE: float = 0.4
const OPEN_WORD: float = 0.6        # each piece of text fades in this long
const OPEN_MENU_DELAY: float = 0.42
const OPEN_MENU_REVEAL: float = 0.7
const CLOSE_SECONDS: float = 0.4
const QUESTION_SECONDS: float = 0.3
const QUIT_FADE: float = 1.2
const DIMMED: float = 0.18          # how faint the menu gets while the question is up

# When each piece of text starts fading in (seconds after opening), in PauseText.Part order.
const WORD_DELAYS: Array[float] = [0.10, 0.16, 0.24, 0.28, 0.34, 0.38, 0.70, 0.75, 0.75]

var is_open: bool = false
var texts: Dictionary = {}
var chapter_number: int = 1
var chapter_title: String = ""
var lead: String = ""
var place: String = ""

var menu: TitleMenuScript
var slots: SlotListScript
var confirm: FrostConfirmScript

# Kept public so tests and the look can be checked from outside.
var blur: ColorRect
var shade: Control
var frost: ColorRect
var snow: CPUParticles2D
var words: PauseTextScript
var wash: ColorRect
var black: ColorRect

var _blur_material: ShaderMaterial
var _frost_material: ShaderMaterial
var _open_tween: Tween
var _close_tween: Tween
var _look_tween: Tween
var _breath: float = 0.0
var _quitting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	blur = _full_rect(ColorRect.new()) as ColorRect
	_blur_material = ShaderMaterial.new()
	_blur_material.shader = BLUR_SHADER
	_blur_material.set_shader_parameter("amount", 0.0)
	blur.material = _blur_material
	add_child(blur)

	shade = _full_rect(ShadeLayer.new())
	shade.modulate.a = 0.0
	add_child(shade)

	frost = _full_rect(ColorRect.new()) as ColorRect
	_frost_material = ShaderMaterial.new()
	_frost_material.shader = FROST_SHADER
	_frost_material.set_shader_parameter("bloom_tex", _make_noise(0.02, 4, 7))
	_frost_material.set_shader_parameter("grain_tex", _make_noise(0.4, 2, 3))
	_frost_material.set_shader_parameter("strength", 0.0)
	_frost_material.set_shader_parameter("grow", 0.0)
	frost.material = _frost_material
	add_child(frost)

	snow = _make_snow()
	snow.modulate.a = 0.0
	add_child(snow)

	words = PauseTextScript.new()
	add_child(words)

	menu = TitleMenuScript.new()
	menu.position = Vector2(LEFT, MENU_Y)
	add_child(menu)
	menu.picked.connect(_on_menu_picked)
	menu.selection_changed.connect(func(_id: String) -> void: words.show_description(menu.selected_description()))

	slots = SlotListScript.new()
	add_child(slots)
	slots.chosen.connect(_on_slot_chosen)
	slots.cancelled.connect(_on_slots_cancelled)

	wash = _full_rect(ColorRect.new()) as ColorRect
	wash.color = Color(0.047, 0.063, 0.11, 0.5)
	wash.modulate.a = 0.0
	add_child(wash)

	confirm = FrostConfirmScript.new()
	add_child(confirm)

	black = _full_rect(ColorRect.new()) as ColorRect
	black.color = Color.BLACK
	black.modulate.a = 0.0
	add_child(black)


func _full_rect(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


# Frost is made of two pictures of noise: big soft blooms and fine grain. They are made once, here,
# so nothing has to be made at the moment the menu opens.
func _make_noise(frequency: float, octaves: int, noise_seed: int) -> ImageTexture:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return ImageTexture.create_from_image(noise.get_seamless_image(512, 512))


# About 42 slow flakes. They fade in and out at the ends of their fall, so none ever pops.
func _make_snow() -> CPUParticles2D:
	var flakes: CPUParticles2D = CPUParticles2D.new()
	var dot: Gradient = Gradient.new()
	dot.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	dot.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	var dot_texture: GradientTexture2D = GradientTexture2D.new()
	dot_texture.gradient = dot
	dot_texture.fill = GradientTexture2D.FILL_RADIAL
	dot_texture.fill_from = Vector2(0.5, 0.5)
	dot_texture.fill_to = Vector2(1.0, 0.5)
	dot_texture.width = 16
	dot_texture.height = 16
	flakes.texture = dot_texture
	flakes.amount = 42
	flakes.lifetime = 32.0
	flakes.lifetime_randomness = 0.5
	flakes.preprocess = 32.0
	flakes.emitting = false
	flakes.position = Vector2(1100.0, -24.0)
	flakes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flakes.emission_rect_extents = Vector2(1100.0, 1.0)
	flakes.direction = Vector2(-0.15, 1.0)
	flakes.spread = 4.0
	flakes.gravity = Vector2.ZERO
	flakes.initial_velocity_min = 38.0
	flakes.initial_velocity_max = 60.0
	flakes.scale_amount_min = 0.25
	flakes.scale_amount_max = 0.7
	flakes.color = Color(0.91, 0.933, 0.969)
	var strength: Gradient = Gradient.new()
	strength.colors = PackedColorArray([Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.75)])
	strength.offsets = PackedFloat32Array([0.0, 1.0])
	flakes.color_initial_ramp = strength
	var life: Gradient = Gradient.new()
	life.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	life.offsets = PackedFloat32Array([0.0, 0.08, 0.85, 1.0])
	flakes.color_ramp = life
	return flakes


# `menu_texts` is the whole menus.json object. `can_save` is false at moments a save would be
# unsafe (in the middle of a conversation): Case board and Save are then greyed out.
# `current_place` is the small line under the chapter title ("Graves Studio · Night"); leave it empty to skip it.
func open(menu_texts: Dictionary, number: int, title: String, current_lead: String, can_save: bool, current_place: String = "") -> void:
	texts = menu_texts
	chapter_number = number
	chapter_title = title
	lead = current_lead
	place = current_place
	var pause_words: Dictionary = texts.get("pause", {})
	confirm.yes_text = str((texts.get("confirm", {}) as Dictionary).get("yes", "Yes"))
	confirm.no_text = str((texts.get("confirm", {}) as Dictionary).get("no", "No"))
	confirm.heading = str(pause_words.get("quit_question", ""))
	menu.set_items([
		{ "id": "resume", "text": str(pause_words.get("resume", "Resume")), "group": 0, "description": str(pause_words.get("desc_resume", "")) },
		{ "id": "board", "text": str(pause_words.get("case_board", "Case board")), "group": 0, "disabled": not can_save, "description": str(pause_words.get("desc_case_board", "")) },
		{ "id": "save", "text": str(pause_words.get("save", "Save")), "group": 1, "disabled": not can_save, "description": str(pause_words.get("desc_save", "")) },
		{ "id": "load", "text": str(pause_words.get("load", "Load")), "group": 1, "description": str(pause_words.get("desc_load", "")) },
		{ "id": "settings", "text": str(pause_words.get("settings", "Settings")), "group": 2, "disabled": true, "description": str(pause_words.get("desc_settings", "")) },
		{ "id": "quit", "text": str(pause_words.get("quit_to_title", "Quit to title")), "group": 2, "description": str(pause_words.get("desc_quit", "")) },
	])
	words.words = pause_words
	words.slot_words = texts.get("slots", {})
	words.chapter_number = number
	words.chapter_title = title
	words.lead = current_lead
	words.place = current_place
	words.set_description_now(menu.selected_description())

	_kill_tweens()
	_quitting = false
	var fresh: bool = not visible
	if fresh:
		_blur_material.set_shader_parameter("amount", 0.0)
		_frost_material.set_shader_parameter("strength", 0.0)
		_frost_material.set_shader_parameter("grow", 0.0)
		_frost_material.set_shader_parameter("widen", 0.0)
		_frost_material.set_shader_parameter("breath_strength", 0.0)
		_breath = 0.0
		shade.modulate.a = 0.0
		snow.modulate.a = 0.0
		words.set_all_alphas(0.0)
		words.fade = 1.0
		words.dim = 1.0
		menu.reveal = 0.0
		menu.modulate.a = 1.0
		wash.modulate.a = 0.0
		black.modulate.a = 0.0
		snow.restart()
	menu.visible = true
	menu.active = true
	confirm.visible = false
	is_open = true
	visible = true
	words.visible = true
	get_tree().paused = true
	Audio.play("menu_open")
	_play_open()


func _play_open() -> void:
	var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_blur_material, "shader_parameter/amount", 1.0, OPEN_BLUR).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_open_tween.tween_property(shade, "modulate:a", 1.0, OPEN_BLUR).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_open_tween.tween_property(snow, "modulate:a", 1.0, OPEN_BLUR).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_open_tween.tween_property(_frost_material, "shader_parameter/grow", 1.0, OPEN_FROST).set_delay(OPEN_FROST_DELAY).set_trans(Tween.TRANS_CUBIC).set_ease(ease_type)
	_open_tween.tween_property(_frost_material, "shader_parameter/strength", 1.0, OPEN_FROST_FADE).set_delay(OPEN_FROST_DELAY).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_open_tween.tween_property(words, "fade", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_open_tween.tween_property(menu, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	for part: int in range(WORD_DELAYS.size()):
		_open_tween.tween_method(words.set_alpha.bind(part), words.get_alpha(part), 1.0, OPEN_WORD).set_delay(WORD_DELAYS[part]).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_open_tween.tween_property(menu, "reveal", 1.0, OPEN_MENU_REVEAL).set_delay(OPEN_MENU_DELAY)


func close() -> void:
	if not is_open:
		return
	is_open = false
	slots.close()
	if confirm.is_open:
		confirm.handle_input(_cancel_event())
	get_tree().paused = false
	Audio.play("menu_close")
	_kill_tweens()
	var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
	_close_tween = create_tween().set_parallel(true)
	_close_tween.tween_property(_blur_material, "shader_parameter/amount", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.tween_property(shade, "modulate:a", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.tween_property(snow, "modulate:a", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.tween_property(_frost_material, "shader_parameter/strength", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.tween_property(words, "fade", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.tween_property(menu, "modulate:a", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.tween_property(wash, "modulate:a", 0.0, CLOSE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(ease_type)
	_close_tween.chain().tween_callback(_finish_close)
	resumed.emit()


func _finish_close() -> void:
	visible = false
	snow.emitting = false


func _cancel_event() -> InputEvent:
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	return event


func _kill_tweens() -> void:
	for tween: Tween in [_open_tween, _close_tween, _look_tween]:
		if tween != null:
			tween.kill()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or event is InputEventMouse:
		return
	get_viewport().set_input_as_handled()
	if _quitting:
		return
	if confirm.handle_input(event) or slots.handle_input(event):
		return
	if UiInput.is_cancel(event) or _is_start(event):
		close()
	else:
		menu.handle_input(event)


func _is_start(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START


func _on_menu_picked(id: String) -> void:
	match id:
		"resume":
			close()
		"board":
			close()
			board_requested.emit()
		"save":
			_open_slots("save")
		"load":
			_open_slots("load")
		"quit":
			await _ask_to_quit()


# The question is written on the frost: the menu goes faint, the frost spreads over the whole screen
# at half strength and a dark veil comes in. "No" brings everything back; "Yes" fades to black first,
# so the title screen (which also starts black) replaces the game without a visible cut.
func _ask_to_quit() -> void:
	menu.active = false
	_set_question_look(true)
	var sure: bool = await confirm.ask(str((texts.get("pause", {}) as Dictionary).get("quit_confirm", "")))
	if sure:
		_quitting = true
		var tween: Tween = create_tween()
		tween.tween_property(black, "modulate:a", 1.0, QUIT_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
		quit_requested.emit()
	elif is_open:
		_set_question_look(false)
		menu.active = true


func _set_question_look(on: bool) -> void:
	if _look_tween != null:
		_look_tween.kill()
	var target: float = 1.0 if on else 0.0
	var text_level: float = DIMMED if on else 1.0
	_look_tween = create_tween().set_parallel(true)
	_look_tween.tween_property(_frost_material, "shader_parameter/widen", target, QUESTION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_property(wash, "modulate:a", target, QUESTION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_property(menu, "modulate:a", text_level, QUESTION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_property(words, "dim", text_level, QUESTION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# The slot cards cover the whole screen, so the menu steps aside while they are open (as on the title screen).
func _open_slots(mode: String) -> void:
	menu.active = false
	menu.visible = false
	words.visible = false
	slots.open(mode, texts)


func _on_slots_cancelled() -> void:
	_bring_menu_back()


# The menu and its words come back with a short fade, not all at once.
func _bring_menu_back() -> void:
	menu.visible = true
	menu.active = true
	words.visible = true
	menu.modulate.a = 0.0
	words.fade = 0.0
	if _look_tween != null:
		_look_tween.kill()
	_look_tween = create_tween().set_parallel(true)
	_look_tween.tween_property(menu, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_look_tween.tween_property(words, "fade", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_slot_chosen(slot: int) -> void:
	if slots.mode == "save":
		if SaveManager.save_now(slot):
			words.saved_flash = 1.0
		slots.close()
		_bring_menu_back()
	else:
		load_requested.emit(slot)


func _process(delta: float) -> void:
	if not visible:
		return
	# The melted patch follows the warm light behind the chosen word, and fades while the menu is not in use.
	var light: Vector2 = menu.light_position()
	if light.y >= 0.0:
		_frost_material.set_shader_parameter("breath_center", menu.position + light)
	var wanted: float = 1.0 if (menu.active and menu.visible) else 0.0
	_breath = move_toward(_breath, wanted, delta / 0.3)
	_frost_material.set_shader_parameter("breath_strength", _breath * clampf(menu.reveal * 2.0, 0.0, 1.0))


# The dark left side and soft dark edges, laid over the blurred picture and under the frost.
class ShadeLayer extends Control:
	var _vignette: GradientTexture2D

	func _ready() -> void:
		var gradient: Gradient = Gradient.new()
		gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)])
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		_vignette = GradientTexture2D.new()
		_vignette.gradient = gradient
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.5)
		_vignette.fill_to = Vector2(1.0, 0.5)
		_vignette.width = 256
		_vignette.height = 256

	func _draw() -> void:
		var dark: Color = Color(0.0235, 0.031, 0.055, 0.6)
		var half: Color = Color(0.0235, 0.031, 0.055, 0.3)
		var clear: Color = Color(0.0235, 0.031, 0.055, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(560, 0), Vector2(560, size.y), Vector2(0, size.y)]), PackedColorArray([dark, half, half, dark]))
		draw_polygon(PackedVector2Array([Vector2(560, 0), Vector2(820, 0), Vector2(820, size.y), Vector2(560, size.y)]), PackedColorArray([half, clear, clear, half]))
		# An oval, 75% of the width by 70% of the height around a point a little right of the middle.
		var middle: Vector2 = Vector2(size.x * 0.55, size.y * 0.5)
		var reach: Vector2 = Vector2(size.x * 0.75, size.y * 0.7)
		draw_texture_rect(_vignette, Rect2(middle - reach, reach * 2.0), false)
