extends Control

# The curtain: a black sheet over the whole game that fades in and out between maps.
# A "scene card" is big handwritten text shown on the black, such as "Morning" or "11:42".

const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const CREAM: Color = Color(0.96, 0.93, 0.84)
const CARD_IN: float = 0.4
const CARD_HOLD: float = 1.6
const CARD_OUT: float = 0.4

var amount: float = 0.0:   # 0 = clear, 1 = black
	set(value):
		amount = value
		queue_redraw()
var card_text: String = ""
var card_alpha: float = 0.0:
	set(value):
		card_alpha = value
		queue_redraw()

var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_black() -> bool:
	return amount >= 0.999


func set_black(black: bool) -> void:
	if _tween != null:
		_tween.kill()
	amount = 1.0 if black else 0.0


# Fades to black (or back). Wait for it with `await fade.fade_to(1.0, 0.3)`.
func fade_to(target: float, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	if is_equal_approx(amount, target) or seconds <= 0.0:
		amount = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "amount", target, seconds)
	await _tween.finished


# Shows the text on black: in 0.4 s, hold 1.6 s, out 0.4 s. The screen stays black underneath.
func show_card(text: String) -> void:
	card_text = text
	card_alpha = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "card_alpha", 1.0, CARD_IN)
	tween.tween_interval(CARD_HOLD)
	tween.tween_property(self, "card_alpha", 0.0, CARD_OUT)
	await tween.finished
	card_text = ""


func _draw() -> void:
	if amount > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, amount))
	if card_text != "" and card_alpha > 0.0:
		var width: float = FONT.get_string_size(card_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		draw_string(FONT, Vector2((size.x - width) * 0.5, size.y * 0.5 + 20.0), card_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 64, Color(CREAM, card_alpha))
