extends Control

# The black bars at the top and bottom of the screen during a cut-away (a scene the player sees
# and James does not), with an optional small caption such as "Meanwhile, Kingsport".

const FONT: Font = preload("res://assets/fonts/KleeOne-Regular.ttf")
const CREAM: Color = Color(0.96, 0.93, 0.84)
const BAR_HEIGHT: float = 110.0
const SLIDE_SECONDS: float = 0.35

var amount: float = 0.0:   # 0 = bars off screen, 1 = bars in place
	set(value):
		amount = value
		queue_redraw()
var caption: String = ""

var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func slide(target: float, new_caption: String = "") -> void:
	if target > 0.0:
		caption = new_caption
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "amount", target, SLIDE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _tween.finished
	if target == 0.0:
		caption = ""


func _draw() -> void:
	if amount <= 0.0:
		return
	var bar: float = BAR_HEIGHT * amount
	draw_rect(Rect2(0.0, 0.0, size.x, bar), Color.BLACK)
	draw_rect(Rect2(0.0, size.y - bar, size.x, bar), Color.BLACK)
	if caption != "":
		# In the top bar: the dialogue's dark shade covers the bottom one while someone is talking.
		draw_string(FONT, Vector2(48.0, bar - 40.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(CREAM, 0.7 * amount))
