extends Control

# A question on the Case Board, written in James's words, for example "Is the photo real?".
# It has two looks:
#   - open: a small paper slip with a "?" in the question list (top of the right column)
#   - solved: the same slip with an ink tick and the answer. The player can click it to read the answer again.
# When a question is answered it is ticked in ink and struck through by hand, then it turns into the solved slip.
#
# It only draws itself and reports a click. The board decides when a question appears and is answered.

signal clicked(question_id: String)

const OPEN_SIZE: Vector2 = Vector2(206.0, 54.0)
const CHIP_SIZE: Vector2 = Vector2(206.0, 54.0)
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

const INK: Color = Color(0.1, 0.08, 0.17)
const PAPER: Color = Color(0.99, 0.96, 0.87)
const OXBLOOD: Color = Color(0.557, 0.169, 0.149)
const IVORY: Color = Color(0.957, 0.914, 0.812)
const DARK_BORDER: Color = Color(0.231, 0.165, 0.118)
const CHIP_INK: Color = Color(0.169, 0.114, 0.078)
const GOLD: Color = Color(0.85, 0.68, 0.3)
const GOLD_SOFT: Color = Color(1.0, 0.9, 0.6)
const SEPIA: Color = Color(0.478, 0.384, 0.282)
const CHIP_PAPER: Color = Color(0.953, 0.918, 0.827)
const TICK_INK: Color = Color(0.11, 0.09, 0.16)

var question_id: String = ""
var question_text: String = ""
var solved_text: String = ""
var solved: bool = false

var _body_style: StyleBoxFlat
var _tick_progress: float = 0.0  # 0..1, the ink tick is drawn stroke by stroke
var _strike_progress: float = 0.0  # 0..1, the wavy line through the question text
var _tween: Tween
var _hover_tween: Tween


func _ready() -> void:
	pivot_offset = size * 0.5
	mouse_entered.connect(func() -> void: _hover(1.05))
	mouse_exited.connect(func() -> void: _hover(1.0))


# `answer_title` is the short name of the deduction, shown on the solved chip.
func setup(id: String, text: String, is_solved: bool, answer_title: String = "") -> void:
	question_id = id
	question_text = text
	solved_text = answer_title
	solved = is_solved
	size = CHIP_SIZE if solved else OPEN_SIZE
	custom_minimum_size = size
	pivot_offset = size * 0.5
	# Open questions are only for reading. Solved chips can be clicked.
	mouse_filter = Control.MOUSE_FILTER_STOP if solved else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if solved else Control.CURSOR_ARROW
	_body_style = StyleBoxFlat.new()
	_body_style.bg_color = CHIP_PAPER if solved else PAPER
	_body_style.border_color = DARK_BORDER
	_body_style.set_border_width_all(2)
	_body_style.set_corner_radius_all(8)
	_body_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	_body_style.shadow_size = 8
	_body_style.shadow_offset = Vector2(0.0, 4.0)
	_tick_progress = 0.0
	_strike_progress = 0.0
	rotation = 0.0
	queue_redraw()


# The question slip drops a few pixels into its place in the list.
func slide_in(delay: float) -> void:
	var rest_y: float = position.y
	position.y = rest_y - 14.0
	modulate.a = 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_property(self, "position:y", rest_y, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# The question is ticked in ink (a short stroke, then a long one, 0.3 s) and struck through by hand.
func tick_solved(delay: float) -> void:
	_tick_progress = 0.0
	_strike_progress = 0.0
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_callback(Audio.play.bind("ink_tick"))
	_tween.tween_method(
		func(amount: float) -> void:
			_tick_progress = amount
			queue_redraw(),
		0.0, 1.0, 0.3
	)
	_tween.tween_method(
		func(amount: float) -> void:
			_strike_progress = amount
			queue_redraw(),
		0.0, 1.0, 0.25
	)


# A chip drops into the solved strip.
func pop_in() -> void:
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)


func _gui_input(event: InputEvent) -> void:
	if not solved:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			clicked.emit(question_id)
			accept_event()


func _hover(target: float) -> void:
	if not solved:
		return
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(target, target), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if _body_style == null:
		return
	var whole: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(_body_style, whole)
	if solved:
		_draw_chip()
	else:
		_draw_open()


func _draw_open() -> void:
	# A small oxblood "?" badge, then the question in ink.
	var badge: Vector2 = Vector2(21.0, size.y * 0.5)
	draw_circle(badge + Vector2(1.0, 1.5), 13.0, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(badge, 13.0, INK)
	draw_circle(badge, 11.0, OXBLOOD)
	draw_arc(badge, 11.0, 0.0, TAU, 28, Color(GOLD, 0.9), 1.3, true)
	draw_string(FONT, badge + Vector2(-5.0, 6.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, GOLD_SOFT)
	var text_left: float = 42.0
	var text_width: float = size.x - text_left - 30.0
	var text_size: Vector2 = FONT.get_multiline_string_size(question_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, 14, 2)
	var top: float = (size.y - text_size.y) * 0.5
	draw_multiline_string(FONT, Vector2(text_left, top + FONT.get_ascent(14)), question_text, HORIZONTAL_ALIGNMENT_LEFT, text_width, 14, 2, INK)
	if _strike_progress > 0.0:
		var y: float = size.y * 0.5 + 1.0
		var length: float = (minf(text_size.x, text_width) + 6.0) * _strike_progress
		var points: PackedVector2Array = PackedVector2Array()
		var x: float = 0.0
		while x <= length:
			points.append(Vector2(text_left - 3.0 + x, y + sin(x * 0.11) * 1.6 - x * 0.012))
			x += 4.0
		if points.size() >= 2:
			draw_polyline(points, Color(TICK_INK, 0.85), 2.0, true)
	if _tick_progress > 0.0:
		_draw_tick(Vector2(size.x - 20.0, size.y * 0.5 + 1.0), 1.1, _tick_progress)


# A hand-drawn tick, stroke by stroke. `progress` 0..0.3 draws the short stroke, the rest the long one.
func _draw_tick(origin: Vector2, scale_factor: float, progress: float) -> void:
	var a: Vector2 = origin + Vector2(-9.0, -1.0) * scale_factor
	var b: Vector2 = origin + Vector2(-3.0, 8.0) * scale_factor
	var c: Vector2 = origin + Vector2(13.0, -12.0) * scale_factor
	var width: float = 3.2 if scale_factor > 1.0 else 2.2
	var short_part: float = clampf(progress / 0.3, 0.0, 1.0)
	draw_line(a, a.lerp(b, short_part), TICK_INK, width, true)
	if progress > 0.3:
		var long_part: float = clampf((progress - 0.3) / 0.7, 0.0, 1.0)
		draw_line(b, b.lerp(c, long_part), TICK_INK, width, true)


func _draw_chip() -> void:
	# Cream chip: a small ink tick, the question in small sepia text, the answer in ink.
	_draw_tick(Vector2(16.0, size.y * 0.5), 0.9, 1.0)
	draw_multiline_string(FONT, Vector2(34.0, 21.0), question_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 44.0, 12, 1, SEPIA)
	draw_multiline_string(FONT, Vector2(34.0, 42.0), solved_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 44.0, 15, 1, CHIP_INK)
