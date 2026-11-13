extends Control

# The prompt bar on the Case Board: a few key glyphs just under the board, drawn like little paper
# keys with ink outlines (the same look as the cards). They only show what the player can do RIGHT NOW. It replaces the old line of key hints across the top.
#
# What it shows comes from data/ui/board_prompts.json (context id -> list of prompts), so the words
# can be translated later. The board tells it which context is active (set_context) and when the
# dialogue box is showing (set_suppressed). When the last input came from a gamepad it draws pad
# glyphs instead of keycaps.

# Which prompt file this bar reads. The case board and the dialogue box each have their own.
@export_file("*.json") var prompts_path: String = "res://data/ui/board_prompts.json"
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const PaperFx := preload("res://scripts/ui/PaperFx.gd")

const CAP_HEIGHT: float = 30.0
const CAP_MIN_WIDTH: float = 30.0
const ITEM_GAP: float = 22.0
const FADE_SECONDS: float = 0.15
const KEY_PAPER: Color = Color(0.965, 0.93, 0.84)
const KEY_SIDE: Color = Color(0.56, 0.44, 0.3)  # the front edge of the key, which gives it height
const KEY_INK: Color = Color(0.13, 0.09, 0.1)
const KEY_ACCENT: Color = Color(0.557, 0.169, 0.149)  # oxblood: the mouse button to press
const KEY_DEPTH: float = 3.0
const LABEL_COLOR: Color = Color(0.97, 0.93, 0.85, 0.92)
const LABEL_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.55)

# TODO(settings): "show control hints" switch. On by default.
var show_hints: bool = true
var context_id: String = "default"
var use_pad: bool = false

var _contexts: Dictionary = {}
var _suppressed: bool = false
var _fade_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_prompts()


func _load_prompts() -> void:
	if not FileAccess.file_exists(prompts_path):
		push_warning("PromptBar: missing %s" % prompts_path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(prompts_path))
	if parsed is Dictionary:
		_contexts = (parsed as Dictionary).get("contexts", {})
	else:
		push_warning("PromptBar: %s is not valid JSON" % prompts_path)


func set_context(id: String) -> void:
	if id == context_id:
		return
	context_id = id
	queue_redraw()


# Hides the bar while the dialogue box is showing, and brings it back afterwards.
func set_suppressed(value: bool) -> void:
	if value == _suppressed:
		return
	_suppressed = value
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0 if value else 1.0, FADE_SECONDS)


func is_suppressed() -> bool:
	return _suppressed


func prompts_for(id: String) -> Array:
	return _contexts.get(id, [])


# The prompts that are drawn right now (pad mode drops the ones without a pad button).
func visible_prompts() -> Array:
	var result: Array = []
	for prompt: Variant in prompts_for(context_id):
		var entry: Dictionary = prompt
		if use_pad and str(entry.get("pad", "")) == "":
			continue
		if not use_pad and str(entry.get("key", "")) == "" and str(entry.get("mouse", "")) == "":
			continue
		result.append(entry)
	return result


func _input(event: InputEvent) -> void:
	var pad_now: bool = use_pad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad_now = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad_now = false
	if pad_now != use_pad:
		use_pad = pad_now
		queue_redraw()


# ---------- drawing ----------

func _draw() -> void:
	if not show_hints:
		return
	var prompts: Array = visible_prompts()
	if prompts.is_empty():
		return
	# Measure first, then draw from the right edge so the bar stays right-aligned.
	var widths: Array[float] = []
	var total: float = 0.0
	for prompt: Variant in prompts:
		var width: float = _item_width(prompt)
		widths.append(width)
		total += width
	total += ITEM_GAP * float(prompts.size() - 1)
	var x: float = size.x - total
	var top: float = size.y - CAP_HEIGHT - 2.0
	for index: int in range(prompts.size()):
		_draw_item(prompts[index], Vector2(x, top))
		x += widths[index] + ITEM_GAP


func _glyph_width(entry: Dictionary) -> float:
	var width: float = 0.0
	if use_pad:
		var pad: String = str(entry.get("pad", ""))
		return 46.0 if (pad == "lb" or pad == "rb") else CAP_HEIGHT
	var mouse: String = str(entry.get("mouse", ""))
	var key: String = str(entry.get("key", ""))
	if mouse != "":
		width += 22.0
	if key != "":
		if mouse != "":
			width += 6.0
		width += maxf(CAP_MIN_WIDTH, FONT.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18.0)
	return width


func _item_width(entry: Dictionary) -> float:
	var label: String = str(entry.get("label", ""))
	return _glyph_width(entry) + 8.0 + FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x


func _draw_item(entry: Dictionary, origin: Vector2) -> void:
	var x: float = origin.x
	if use_pad:
		_draw_pad_glyph(str(entry.get("pad", "")), Vector2(x, origin.y))
	else:
		var mouse: String = str(entry.get("mouse", ""))
		var key: String = str(entry.get("key", ""))
		if mouse != "":
			_draw_mouse(mouse, Vector2(x, origin.y + 1.0))
			x += 28.0
		if key != "":
			_draw_keycap(key, Vector2(x, origin.y))
	var label: String = str(entry.get("label", ""))
	var label_x: float = origin.x + _glyph_width(entry) + 8.0
	draw_string(FONT, Vector2(label_x + 1.0, origin.y + 22.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, LABEL_SHADOW)
	draw_string(FONT, Vector2(label_x, origin.y + 21.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, LABEL_COLOR)


func _key_shape(rect: Rect2, radius: int) -> void:
	PaperFx.draw_key(self, rect, radius)


func _draw_keycap(text: String, origin: Vector2) -> void:
	var width: float = maxf(CAP_MIN_WIDTH, FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18.0)
	_key_shape(Rect2(origin, Vector2(width, CAP_HEIGHT - KEY_DEPTH)), 7)
	var text_width: float = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(FONT, origin + Vector2((width - text_width) * 0.5, 19.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, KEY_INK)


# A small paper mouse. The left button is inked in oxblood; "drag" and "pin" add a little arrow.
func _draw_mouse(kind: String, origin: Vector2) -> void:
	var body: Rect2 = Rect2(origin, Vector2(20.0, 27.0))
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	draw_style_box(style, Rect2(body.position + Vector2(1.0, 3.0), body.size))
	style.bg_color = KEY_PAPER
	style.border_color = KEY_INK
	style.set_border_width_all(2)
	draw_style_box(style, body)
	var filled: PackedVector2Array = PackedVector2Array([origin + Vector2(3.0, 12.0), origin + Vector2(3.0, 8.0), origin + Vector2(5.0, 4.5), origin + Vector2(9.0, 3.0), origin + Vector2(9.0, 12.0)])
	draw_colored_polygon(filled, KEY_ACCENT)
	draw_line(origin + Vector2(10.0, 2.0), origin + Vector2(10.0, 13.0), KEY_INK, 1.5)
	draw_line(origin + Vector2(2.0, 13.0), origin + Vector2(18.0, 13.0), KEY_INK, 1.5)
	if kind == "drag" or kind == "pin":
		var tip: Vector2 = origin + Vector2(23.0, 14.0)
		for offset: Vector2 in [Vector2(1.0, 1.5), Vector2.ZERO]:
			var color: Color = LABEL_SHADOW if offset != Vector2.ZERO else LABEL_COLOR
			draw_line(tip + offset, tip + offset + Vector2(5.0, 0.0), color, 1.8, true)
			draw_line(tip + offset + Vector2(5.0, 0.0), tip + offset + Vector2(2.0, -3.0), color, 1.8, true)
			draw_line(tip + offset + Vector2(5.0, 0.0), tip + offset + Vector2(2.0, 3.0), color, 1.8, true)


func _draw_pad_glyph(pad: String, origin: Vector2) -> void:
	var shoulder: bool = pad == "lb" or pad == "rb"
	var text: String = pad.to_upper()
	if shoulder:
		var rect: Rect2 = Rect2(origin + Vector2(0.0, 2.0), Vector2(46.0, 23.0))
		_key_shape(rect, 11)
		var text_width: float = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(FONT, rect.position + Vector2((46.0 - text_width) * 0.5, 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, KEY_INK)
	else:
		var radius: float = (CAP_HEIGHT - KEY_DEPTH) * 0.5
		var center: Vector2 = origin + Vector2(CAP_HEIGHT * 0.5, radius)
		draw_circle(center + Vector2(1.0, KEY_DEPTH + 2.0), radius, Color(0.0, 0.0, 0.0, 0.35))
		draw_circle(center + Vector2(0.0, KEY_DEPTH), radius, KEY_INK)
		draw_circle(center + Vector2(0.0, KEY_DEPTH), radius - 2.0, KEY_SIDE)
		draw_circle(center, radius, KEY_INK)
		draw_circle(center, radius - 2.0, KEY_PAPER)
		var text_width: float = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(FONT, center + Vector2(-text_width * 0.5, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, KEY_INK)
