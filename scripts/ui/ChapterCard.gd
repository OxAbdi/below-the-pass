extends Control

# The card at the end of a chapter: the screen goes black, then "Chapter 1", the chapter's
# title and "End of chapter" fade in one after another. It holds for 3 seconds or until a press.

signal finished

const UiInput := preload("res://scripts/ui/UiInput.gd")
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const FONT_BODY: Font = preload("res://assets/fonts/KleeOne-Regular.ttf")
const CREAM: Color = Color(0.96, 0.93, 0.84)
const BLACK_SECONDS: float = 1.0
const HOLD_SECONDS: float = 3.0

var is_open: bool = false
var number_text: String = ""
var title_text: String = ""
var end_text: String = ""

var black: float = 0.0:
	set(value):
		black = value
		queue_redraw()
var number_alpha: float = 0.0:
	set(value):
		number_alpha = value
		queue_redraw()
var title_alpha: float = 0.0:
	set(value):
		title_alpha = value
		queue_redraw()
var end_alpha: float = 0.0:
	set(value):
		end_alpha = value
		queue_redraw()

var _holding: bool = false
var _hold: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


# Plays the whole card and waits until it has been read. The screen is left black.
func play(number: String, title: String, end_line: String) -> void:
	number_text = number
	title_text = title
	end_text = end_line
	number_alpha = 0.0
	title_alpha = 0.0
	end_alpha = 0.0
	is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tween: Tween = create_tween()
	tween.tween_property(self, "black", 1.0, BLACK_SECONDS)
	tween.tween_property(self, "number_alpha", 1.0, 0.6)
	tween.tween_property(self, "title_alpha", 1.0, 0.8)
	tween.tween_property(self, "end_alpha", 1.0, 0.6)
	await tween.finished
	_holding = true
	_hold = create_tween()
	_hold.tween_interval(HOLD_SECONDS)
	_hold.tween_callback(_end_hold)
	await finished
	var out: Tween = create_tween().set_parallel(true)
	out.tween_property(self, "number_alpha", 0.0, 0.5)
	out.tween_property(self, "title_alpha", 0.0, 0.5)
	out.tween_property(self, "end_alpha", 0.0, 0.5)
	await out.finished
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _end_hold() -> void:
	if not _holding:
		return
	_holding = false
	if _hold != null:
		_hold.kill()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if _holding and (UiInput.is_accept(event) or (event is InputEventMouseButton and event.pressed)):
		get_viewport().set_input_as_handled()
		_end_hold()


func _gui_input(event: InputEvent) -> void:
	if _holding and event is InputEventMouseButton and event.pressed:
		accept_event()
		_end_hold()


func _draw() -> void:
	if black <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, black))
	_centered(FONT, number_text, 28, size.y * 0.5 - 70.0, Color(CREAM, 0.6 * number_alpha))
	_centered(FONT, title_text, 56, size.y * 0.5 + 10.0, Color(CREAM, title_alpha))
	_centered(FONT_BODY, end_text, 22, size.y * 0.5 + 70.0, Color(CREAM, 0.6 * end_alpha))


func _centered(font: Font, text: String, font_size: int, y: float, color: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - width) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
