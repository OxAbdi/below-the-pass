extends Control

# The "Saving" mark in the bottom-right corner: a camera shutter that turns while the game saves.
# It shows by itself every time SaveManager finishes a save: in 0.25 s, stays 1.4 s, out 0.4 s.
# It sits well inside the screen's safe area, where TVs and the Steam Deck never crop it.

const Typo := preload("res://scripts/ui/Typo.gd")

const ICON_CENTER: Vector2 = Vector2(1792.0, 990.0)
const ICON_RADIUS: float = 19.0
const BLADES: int = 6

var text: String = "Saving…"
var show_count: int = 0   # how many times it has shown (used by tests)

var _angle: float = 0.0
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	SaveManager.saved.connect(func(_slot: int) -> void: show_saving())


func show_saving() -> void:
	show_count += 1
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.tween_interval(1.4)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	if modulate.a <= 0.0:
		return
	_angle += delta * 2.4
	queue_redraw()


func _draw() -> void:
	draw_icon(self, ICON_CENTER, ICON_RADIUS, _angle, 1.0)
	var font: Font = Typo.sans(400, 4)
	var word: String = text.to_upper()
	var width: float = font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var at: Vector2 = Vector2(ICON_CENTER.x - ICON_RADIUS - 18.0 - width, ICON_CENTER.y + 7.0)
	draw_string(font, at + Vector2(1, 2), word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0, 0, 0, 0.6))
	draw_string(font, at, word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(Typo.CREAM, 0.9))


# A camera's iris: a ring and six blades around a small opening. Also used on the boot screen.
static func draw_icon(item: CanvasItem, center: Vector2, radius: float, angle: float, alpha: float) -> void:
	item.draw_circle(center + Vector2(1, 2), radius + 2.0, Color(0, 0, 0, 0.35 * alpha))
	item.draw_arc(center, radius, 0.0, TAU, 40, Color(Typo.CREAM, 0.9 * alpha), 2.0, true)
	var inner: float = radius * 0.34
	for blade: int in range(BLADES):
		var a: float = angle + TAU * blade / float(BLADES)
		var b: float = a + TAU / float(BLADES)
		var p1: Vector2 = center + Vector2.from_angle(a) * inner
		var p2: Vector2 = center + Vector2.from_angle(a + 0.9) * (radius - 3.0)
		var p3: Vector2 = center + Vector2.from_angle(b + 0.9) * (radius - 3.0)
		var p4: Vector2 = center + Vector2.from_angle(b) * inner
		var shade: float = 0.55 + 0.25 * float(blade % 2)
		item.draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), Color(Typo.CREAM, shade * alpha))
		item.draw_line(p1, p2, Color(0.1, 0.08, 0.08, 0.7 * alpha), 1.2, true)
