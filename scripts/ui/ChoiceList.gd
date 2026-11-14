extends Control

# The topics the player can pick in a conversation, drawn as paper slips stacked above the text.
#
# It only shows slips and reports which one was picked. It knows nothing about the story:
# the dialogue box gives it a list of { "text", "done" } and listens for `choice_picked`.
#
# Pick with the mouse, the number keys 1-6, or arrows / d-pad and Enter / A.

signal choice_picked(index: int)

const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

const MAX_SLIPS: int = 6
const SLIP_SIZE: Vector2 = Vector2(560.0, 50.0)
const SLIP_GAP: float = 10.0
const SLIDE_PX: float = 10.0
const RISE_PX: float = 12.0
const APPEAR_STAGGER: float = 0.05
const APPEAR_SECONDS: float = 0.16
const TICK_SECONDS: float = 0.18
const FADE_SECONDS: float = 0.15
const NUMBER_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]

const PAPER: Color = Color(0.965, 0.933, 0.839)
const INK: Color = Color(0.169, 0.114, 0.078)
const SEPIA: Color = Color(0.478, 0.384, 0.282)

var items: Array[Dictionary] = []
var selected: int = 0
var is_showing: bool = false
var tag: String = ""  # a short pencil label above the slips, for example "Briggs is testing you"

var _hover: Array[float] = []  # 0..1 per slip: how far it has slid out
var _time: float = 0.0  # seconds since the slips appeared
var _picked: int = -1
var _pick_time: float = 0.0
var _slip_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	set_process(false)
	_slip_style = StyleBoxFlat.new()
	_slip_style.bg_color = PAPER
	_slip_style.border_color = INK
	_slip_style.set_border_width_all(2)
	_slip_style.set_corner_radius_all(5)
	_slip_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	_slip_style.shadow_size = 7
	_slip_style.shadow_offset = Vector2(1.0, 4.0)


# `new_items`: [{ "text": String, "done": bool }, ...]. Only the first six are shown.
func show_choices(new_items: Array, new_tag: String = "") -> void:
	tag = new_tag
	items.clear()
	_hover.clear()
	for item: Variant in new_items:
		if items.size() >= MAX_SLIPS:
			break
		items.append(item)
		_hover.append(0.0)
	# Start on the first topic that has not been asked yet.
	selected = 0
	for index: int in range(items.size()):
		if not bool(items[index].get("done", false)):
			selected = index
			break
	_picked = -1
	_time = 0.0
	is_showing = true
	visible = true
	modulate.a = 1.0
	set_process(true)
	queue_redraw()


func hide_choices() -> void:
	is_showing = false
	visible = false
	set_process(false)


# Keyboard and controller. Returns true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if not is_showing or _picked >= 0:
		return is_showing
	if event is InputEventKey and event.pressed and not event.echo:
		var number: int = NUMBER_KEYS.find((event as InputEventKey).keycode)
		if number < 0:
			number = NUMBER_KEYS.find((event as InputEventKey).physical_keycode)
		if number >= 0:
			if number < items.size():
				_pick(number)
			return true
	if event.is_action_pressed("ui_up"):
		_select(posmod(selected - 1, items.size()))
		return true
	if event.is_action_pressed("ui_down"):
		_select(posmod(selected + 1, items.size()))
		return true
	if UiInput.is_accept(event):
		_pick(selected)
		return true
	return false


func slip_rect(index: int) -> Rect2:
	var top: float = size.y - float(items.size() - index) * (SLIP_SIZE.y + SLIP_GAP) + SLIP_GAP
	return Rect2(Vector2(0.0, top), SLIP_SIZE)


func _has_point(point: Vector2) -> bool:
	return _slip_at(point) >= 0


func _slip_at(point: Vector2) -> int:
	for index: int in range(items.size()):
		if slip_rect(index).grow_individual(0.0, SLIP_GAP * 0.5, SLIDE_PX, SLIP_GAP * 0.5).has_point(point):
			return index
	return -1


func _gui_input(event: InputEvent) -> void:
	if not is_showing or _picked >= 0:
		return
	if event is InputEventMouseMotion:
		var over: int = _slip_at((event as InputEventMouseMotion).position)
		if over >= 0:
			_select(over)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var over: int = _slip_at(button.position)
			if over >= 0:
				accept_event()
				_pick(over)


func _select(index: int) -> void:
	if index == selected:
		return
	selected = index
	Audio.play("choice_hover", 0.08)
	queue_redraw()


func _pick(index: int) -> void:
	selected = index
	_picked = index
	_pick_time = 0.0
	Audio.play("choice_pick")


func _process(delta: float) -> void:
	_time += delta
	for index: int in range(items.size()):
		var target: float = 1.0 if index == selected else 0.0
		_hover[index] = move_toward(_hover[index], target, delta / 0.12)
	if _picked >= 0:
		_pick_time += delta
		if _pick_time >= TICK_SECONDS + FADE_SECONDS * 2.0:
			var index: int = _picked
			hide_choices()
			choice_picked.emit(index)
			return
	queue_redraw()


func _draw() -> void:
	for index: int in range(items.size()):
		_draw_slip(index)
	draw_set_transform(Vector2.ZERO)
	if tag != "" and not items.is_empty() and _picked < 0:
		var alpha: float = clampf((_time - 0.1) / 0.25, 0.0, 1.0)
		var at: Vector2 = slip_rect(0).position + Vector2(6.0, -14.0)
		draw_string(FONT, at + Vector2(1.0, 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(0.0, 0.0, 0.0, 0.7 * alpha))
		draw_string(FONT, at, tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(PAPER, 0.9 * alpha))
		var width: float = FONT.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		PaperFx.draw_wavy(self, at + Vector2(0.0, 7.0), width, Color(PAPER, 0.6 * alpha), 1.5, alpha)


func _draw_slip(index: int) -> void:
	var item: Dictionary = items[index]
	var done: bool = bool(item.get("done", false))
	var rect: Rect2 = slip_rect(index)
	# Slips rise and fade in one after another, the bottom one first.
	var delay: float = float(items.size() - 1 - index) * APPEAR_STAGGER
	var appear: float = clampf((_time - delay) / APPEAR_SECONDS, 0.0, 1.0)
	var alpha: float = appear
	if _picked >= 0:
		if index == _picked:
			alpha *= 1.0 - clampf((_pick_time - TICK_SECONDS - FADE_SECONDS) / FADE_SECONDS, 0.0, 1.0)
		else:
			alpha *= 1.0 - clampf(_pick_time / FADE_SECONDS, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var slide: float = 1.0 - pow(1.0 - _hover[index], 2.0)  # ease-out
	var offset: Vector2 = Vector2(slide * SLIDE_PX, (1.0 - appear) * RISE_PX)
	var tilt: float = deg_to_rad(float(posmod(hash(str(item.get("text", ""))), 3) - 1) * 0.5)
	draw_set_transform(rect.get_center() + offset, tilt)
	var local: Rect2 = Rect2(-SLIP_SIZE * 0.5, SLIP_SIZE)
	var tint: Color = Color(1.0, 1.0, 1.0, alpha)

	_slip_style.bg_color = Color(PAPER, alpha)
	_slip_style.border_color = Color(INK, alpha)
	_slip_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4 * alpha)
	draw_style_box(_slip_style, local)
	draw_texture_rect(PaperFx.grain(), local.grow(-3.0), true, Color(0.45, 0.32, 0.18, 0.1 * alpha))

	# The number key on the left.
	var key: Rect2 = Rect2(local.position + Vector2(12.0, 10.0), Vector2(28.0, 25.0))
	draw_set_transform(rect.get_center() + offset, tilt)
	if alpha > 0.95:
		PaperFx.draw_key(self, key, 6)
	var number: String = str(index + 1)
	var number_width: float = FONT.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(FONT, key.position + Vector2((key.size.x - number_width) * 0.5, 18.5), number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(PaperFx.KEY_INK, alpha))

	# The topic. One already asked is written in faded sepia and keeps its tick.
	var text: String = str(item.get("text", ""))
	var text_color: Color = Color(SEPIA, 0.65 * alpha) if done else Color(INK, alpha)
	var text_at: Vector2 = local.position + Vector2(54.0, 32.0)
	draw_string(FONT, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, SLIP_SIZE.x - 54.0 - 46.0, 19, text_color)
	if _hover[index] > 0.0:
		var text_width: float = minf(FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x, SLIP_SIZE.x - 100.0)
		PaperFx.draw_wavy(self, text_at + Vector2(0.0, 7.0), text_width, Color(INK, 0.7 * alpha), 1.5, _hover[index])

	var tick: float = 0.0
	if done:
		tick = 1.0
	if index == _picked:
		tick = clampf(_pick_time / TICK_SECONDS, 0.0, 1.0)
	if tick > 0.0:
		_draw_tick(local.position + Vector2(SLIP_SIZE.x - 26.0, SLIP_SIZE.y * 0.5 + 1.0), tick, Color(INK, (0.6 if done and index != _picked else 1.0) * tint.a))


# A hand-drawn tick: the short stroke first, then the long one.
func _draw_tick(origin: Vector2, progress: float, color: Color) -> void:
	var a: Vector2 = origin + Vector2(-8.0, -1.0)
	var b: Vector2 = origin + Vector2(-3.0, 7.0)
	var c: Vector2 = origin + Vector2(11.0, -10.0)
	draw_line(a, a.lerp(b, clampf(progress / 0.3, 0.0, 1.0)), color, 2.4, true)
	if progress > 0.3:
		draw_line(b, b.lerp(c, clampf((progress - 0.3) / 0.7, 0.0, 1.0)), color, 2.4, true)
