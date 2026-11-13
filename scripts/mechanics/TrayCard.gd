extends Control

# One handwritten entry on a page of James's notebook (Milestone 4.2).
# It holds a clue, a Lead or a Conclusion the player has but has not pinned to the board.
# It is two ruled lines tall (60 px): a small photo or paper scrap held by tape, and the name in ink.
#
# It only reports what the player did. The board decides what that means.
#   - press and drag: a ghost card follows the mouse; let go over the board to pin it
#   - click without dragging: "clicked" (the board only clears the red asterisk)
#   - Enter / A while it has focus: "activated" (the board pins it)

signal clicked(card: Control)
signal activated(card: Control)
signal drag_started(card: Control)
signal drag_moved(card: Control, global_mouse: Vector2)
signal drag_released(card: Control, global_mouse: Vector2)

const CARD_SIZE: Vector2 = Vector2(112.0, 134.0)
const DRAG_START_PX: float = 8.0
const OBJECT_CENTER: Vector2 = Vector2(56.0, 42.0)  # where the little object sits on the tile
const CAPTION_TOP: float = 80.0
const TEXT_WIDTH: float = 108.0
const NAME_SIZE: int = 12
const NAME_LINES: int = 3
const NAME_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

const INK: Color = Color(0.169, 0.114, 0.078)
const DARK_EDGE: Color = Color(0.1, 0.08, 0.17)
const PAPER: Color = Color(0.953, 0.918, 0.827)
const PAPER_EDGE: Color = Color(0.62, 0.52, 0.36)
const GOLD: Color = Color(0.85, 0.68, 0.3)
const GOLD_FOIL: Color = Color(0.851, 0.678, 0.302)
const RED_PENCIL: Color = Color(0.8, 0.2, 0.18)
const TAPE: Color = Color(0.98, 0.94, 0.8, 0.75)
const FOCUS_COLOR: Color = Color(1.0, 0.86, 0.5)

var item_id: String = ""
var display_name: String = ""
var card_style: String = "note"
var accent: Color = GOLD
var is_new: bool = false:
	set(value):
		is_new = value
		queue_redraw()
var hinted: bool = false:
	set(value):
		hinted = value
		set_process(value)
		queue_redraw()

var _pressing: bool = false
var _dragging: bool = false
var _press_global: Vector2 = Vector2.ZERO
var _focus_from_mouse: bool = false
var _time: float = 0.0
var _lift: float = 0.0
var _hover: bool = false
var _hover_tween: Tween
var _tween: Tween

var _glow_style: StyleBoxFlat
var _ring_style: StyleBoxFlat


func _ready() -> void:
	size = CARD_SIZE
	custom_minimum_size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_exited.connect(_on_focus_exited)
	focus_entered.connect(queue_redraw)
	set_process(false)


func setup(id: String, card_name: String, style: String, accent_color: Color, show_new: bool) -> void:
	item_id = id
	display_name = card_name
	card_style = style
	accent = accent_color
	_build_styles()
	is_new = show_new
	queue_redraw()


func shake() -> void:
	if _tween != null:
		_tween.kill()
	var home: float = position.x
	_tween = create_tween()
	for offset: float in [-9.0, 9.0, -5.0, 5.0, 0.0]:
		_tween.tween_property(self, "position:x", home + offset, 0.05)


func is_hovered() -> bool:
	return _hover


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		var global_mouse: Vector2 = get_global_transform() * button.position
		if button.pressed:
			_focus_from_mouse = true
			grab_focus()
			_pressing = true
			_dragging = false
			_press_global = global_mouse
		else:
			if _dragging:
				drag_released.emit(self, global_mouse)
			elif _pressing:
				clicked.emit(self)
			_pressing = false
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _pressing:
		var motion: InputEventMouseMotion = event
		var global_mouse: Vector2 = get_global_transform() * motion.position
		if not _dragging and global_mouse.distance_to(_press_global) >= DRAG_START_PX:
			_dragging = true
			drag_started.emit(self)
		if _dragging:
			drag_moved.emit(self, global_mouse)
		accept_event()
	elif (event is InputEventKey or event is InputEventJoypadButton) and _focus_from_mouse:
		_focus_from_mouse = false
		queue_redraw()
		if event.is_action_pressed("ui_accept") and not event.is_echo():
			activated.emit(self)
			accept_event()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		activated.emit(self)
		accept_event()


func _on_focus_exited() -> void:
	_focus_from_mouse = false
	queue_redraw()


# The photo lifts 2 px on hover.
func _set_hover(value: bool) -> void:
	_hover = value
	if _dragging:
		return
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_method(_set_lift, _lift, -4.0 if value else 0.0, 0.12)


func _set_lift(value: float) -> void:
	_lift = value
	queue_redraw()


# ---------- drawing ----------

func _make_box(fill: Color, outline: Color, outline_width: int, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_border_width_all(outline_width)
	box.set_corner_radius_all(radius)
	return box


func _build_styles() -> void:
	_glow_style = _make_box(Color(accent, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 6)
	_glow_style.shadow_offset = Vector2.ZERO
	_ring_style = _make_box(Color(1.0, 1.0, 1.0, 0.18), Color(INK, 0.55), 2, 9)


# A small fixed tilt between -3 and +3 degrees, the same for the same clue every time.
func _tilt() -> float:
	return deg_to_rad(float(posmod(item_id.hash(), 7)) - 3.0)


func _draw() -> void:
	if _glow_style == null:
		return
	var whole: Rect2 = Rect2(Vector2.ZERO, size)
	if hinted:
		var soft: float = 0.5 + 0.5 * sin(_time * 2.2)
		_glow_style.shadow_color = Color(1.0, 0.85, 0.4, 0.6 + 0.3 * soft)
		_glow_style.shadow_size = 14 + int(8.0 * soft)
		draw_style_box(_glow_style, Rect2(OBJECT_CENTER - Vector2(34.0, 26.0), Vector2(68.0, 52.0)))
	_draw_object()
	draw_set_transform(Vector2.ZERO)
	# The caption, written under the object by hand.
	var text_size: Vector2 = NAME_FONT.get_multiline_string_size(display_name, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, NAME_SIZE, NAME_LINES)
	var baseline: float = CAPTION_TOP + NAME_FONT.get_ascent(NAME_SIZE)
	draw_multiline_string(NAME_FONT, Vector2((size.x - TEXT_WIDTH) * 0.5, baseline), display_name, HORIZONTAL_ALIGNMENT_CENTER, TEXT_WIDTH, NAME_SIZE, NAME_LINES, INK)
	if _hover or (has_focus() and not _focus_from_mouse):
		var line_width: float = minf(text_size.x, TEXT_WIDTH) * 0.7
		_draw_wavy_underline(Vector2((size.x - line_width) * 0.5, CAPTION_TOP + text_size.y + 2.0), line_width)
	if is_new:
		_draw_asterisk()
	if has_focus() and not _focus_from_mouse:
		draw_style_box(_ring_style, whole.grow(-1.0))


# A short wavy line in ink, like a pen underline.
func _draw_wavy_underline(start: Vector2, length: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var x: float = 0.0
	while x <= length:
		points.append(start + Vector2(x, sin(x * 0.45) * 1.4))
		x += 3.0
	if points.size() >= 2:
		draw_polyline(points, Color(INK, 0.75), 1.5, true)


# A red-pencil asterisk beside the object: something here has not been looked at yet.
func _draw_asterisk() -> void:
	var center: Vector2 = Vector2(11.0, 12.0)
	for index: int in range(3):
		var direction: Vector2 = Vector2.from_angle(float(index) * PI / 3.0 + 0.2) * 6.0
		draw_line(center - direction, center + direction, RED_PENCIL, 2.2, true)


# Every kind of evidence is kept in the journal the way a reporter would keep the real thing:
# a photo is taped in, a note is paper-clipped, an old document is tucked in, a Lead is a torn page,
# a Conclusion is a finished card. `card_style` in the evidence registry picks the look.
func _draw_object() -> void:
	var center: Vector2 = OBJECT_CENTER + Vector2(0.0, _lift)
	var tilt: float = _tilt() * (0.4 if _hover else 1.0)
	draw_set_transform(center, tilt)
	if card_style == "photo":
		_draw_photo(Rect2(-41.0, -31.0, 82.0, 62.0))
		_draw_tape(Vector2(-33.0, -29.0), -38.0)
		_draw_tape(Vector2(33.0, -29.0), 38.0)
	elif card_style == "lead":
		_draw_lead(Rect2(-36.0, -31.0, 72.0, 62.0))
	elif card_style == "conclusion":
		_draw_conclusion(Rect2(-40.0, -28.0, 80.0, 56.0))
	elif card_style == "parchment" or card_style == "document":
		_draw_parchment(Rect2(-33.0, -33.0, 66.0, 66.0))
	else:
		_draw_note(Rect2(-36.0, -30.0, 72.0, 60.0))
		_draw_paperclip(Vector2(-22.0, -30.0))


func _soft_shadow(rect: Rect2) -> void:
	for step: int in range(3):
		draw_rect(Rect2(rect.position + Vector2(1.0, 2.0 + float(step)), rect.size).grow(float(step)), Color(0.15, 0.08, 0.02, 0.09))


func _draw_tape(at: Vector2, degrees: float) -> void:
	var rect: Rect2 = Rect2(Vector2(-13.0, -5.0), Vector2(26.0, 10.0))
	var corners: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		corners.append(at + corner.rotated(deg_to_rad(degrees)))
	draw_colored_polygon(corners, TAPE)
	corners.append(corners[0])
	draw_polyline(corners, Color(PAPER_EDGE, 0.4), 1.0, true)


# A steel paper clip holding a note to the page.
func _draw_paperclip(at: Vector2) -> void:
	var steel: Color = Color(0.42, 0.42, 0.45)
	var shine: Color = Color(0.85, 0.86, 0.9)
	draw_arc(at + Vector2(0.0, 0.0), 5.0, PI, TAU, 10, steel, 2.0, true)
	draw_line(at + Vector2(-5.0, 0.0), at + Vector2(-5.0, 16.0), steel, 2.0, true)
	draw_line(at + Vector2(5.0, 0.0), at + Vector2(5.0, 12.0), steel, 2.0, true)
	draw_arc(at + Vector2(0.0, 0.0), 2.4, PI, TAU, 8, shine, 1.4, true)
	draw_line(at + Vector2(-2.4, 0.0), at + Vector2(-2.4, 9.0), shine, 1.4, true)


func _draw_photo(rect: Rect2) -> void:
	_soft_shadow(rect)
	draw_rect(rect, Color(1.0, 0.995, 0.97))
	draw_rect(rect, Color(DARK_EDGE, 0.85), false, 1.5)
	var inner: Rect2 = Rect2(rect.position + Vector2(5.0, 5.0), Vector2(rect.size.x - 10.0, rect.size.y - 17.0))
	var sky_top: Color = Color(0.1, 0.1, 0.29).lerp(accent, 0.12)
	var sky_mid: Color = Color(0.35, 0.22, 0.54).lerp(accent, 0.45)
	var sky_low: Color = accent.lerp(Color.WHITE, 0.4)
	var mid_y: float = inner.position.y + inner.size.y * 0.55
	draw_polygon(
		PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.end.x, mid_y), Vector2(inner.position.x, mid_y)]),
		PackedColorArray([sky_top, sky_top, sky_mid, sky_mid])
	)
	draw_polygon(
		PackedVector2Array([Vector2(inner.position.x, mid_y), Vector2(inner.end.x, mid_y), inner.end, Vector2(inner.position.x, inner.end.y)]),
		PackedColorArray([sky_mid, sky_mid, sky_low, sky_low])
	)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(item_id)
	var left: float = inner.position.x
	var top: float = inner.position.y
	var far: PackedVector2Array = PackedVector2Array([Vector2(left, inner.end.y)])
	var near: PackedVector2Array = PackedVector2Array([Vector2(left, inner.end.y)])
	for step: int in range(7):
		var x: float = left + inner.size.x * float(step) / 6.0
		far.append(Vector2(x, top + inner.size.y * rng.randf_range(0.35, 0.62)))
		near.append(Vector2(x, top + inner.size.y * rng.randf_range(0.66, 0.86)))
	far.append(inner.end)
	near.append(inner.end)
	draw_colored_polygon(far, Color(0.2, 0.16, 0.4).lerp(accent, 0.18))
	draw_colored_polygon(near, Color(0.09, 0.08, 0.22))
	var moon: Vector2 = Vector2(left + inner.size.x * rng.randf_range(0.6, 0.85), top + 9.0)
	draw_circle(moon, 6.0, Color(1.0, 1.0, 1.0, 0.18))
	draw_circle(moon, 2.6, Color(1.0, 1.0, 0.95, 0.95))
	for star: int in range(5):
		draw_circle(Vector2(left + rng.randf() * inner.size.x, top + 3.0 + rng.randf() * 12.0), 0.8, Color(1.0, 1.0, 1.0, 0.8))
	# Gloss: a pale band across the print.
	draw_colored_polygon(PackedVector2Array([inner.position, inner.position + Vector2(26.0, 0.0), inner.position + Vector2(8.0, inner.size.y), Vector2(inner.position.x, inner.end.y)]), Color(1.0, 1.0, 1.0, 0.1))
	draw_rect(inner, Color(DARK_EDGE, 0.55), false, 1.0)


func _draw_note(rect: Rect2) -> void:
	_soft_shadow(rect)
	draw_rect(rect, Color(0.995, 0.975, 0.9))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 11.0)), accent.lerp(Color.WHITE, 0.15))
	draw_line(rect.position + Vector2(0.0, 11.0), rect.position + Vector2(rect.size.x, 11.0), Color(DARK_EDGE, 0.5), 1.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(item_id) + 3
	var line_y: float = rect.position.y + 21.0
	while line_y < rect.end.y - 6.0:
		draw_line(Vector2(rect.position.x + 7.0, line_y), Vector2(rect.end.x - 7.0 - rng.randf_range(0.0, 24.0), line_y), Color(0.25, 0.2, 0.3, 0.55), 1.4, true)
		line_y += 8.0
	draw_rect(rect, Color(DARK_EDGE, 0.85), false, 1.5)


# An old document: tan paper, darker at the edges, with a wavy outline and faded writing.
func _draw_parchment(rect: Rect2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(item_id) + 9
	var outline: PackedVector2Array = PackedVector2Array()
	var steps: int = 7
	for index: int in range(steps + 1):
		outline.append(Vector2(rect.position.x + rect.size.x * float(index) / float(steps), rect.position.y + rng.randf_range(-1.5, 1.5)))
	for index: int in range(1, steps + 1):
		outline.append(Vector2(rect.end.x + rng.randf_range(-1.5, 1.5), rect.position.y + rect.size.y * float(index) / float(steps)))
	for index: int in range(1, steps + 1):
		outline.append(Vector2(rect.end.x - rect.size.x * float(index) / float(steps), rect.end.y + rng.randf_range(-1.5, 1.5)))
	for index: int in range(1, steps):
		outline.append(Vector2(rect.position.x + rng.randf_range(-1.5, 1.5), rect.end.y - rect.size.y * float(index) / float(steps)))
	var shadow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in outline:
		shadow.append(point + Vector2(1.5, 3.0))
	draw_colored_polygon(shadow, Color(0.15, 0.08, 0.02, 0.22))
	draw_colored_polygon(outline, Color(0.87, 0.76, 0.56))
	draw_rect(rect.grow(-7.0), Color(0.93, 0.84, 0.66, 0.8))
	var line_y: float = rect.position.y + 14.0
	while line_y < rect.end.y - 16.0:
		draw_line(Vector2(rect.position.x + 10.0, line_y), Vector2(rect.end.x - 10.0 - rng.randf_range(0.0, 14.0), line_y), Color(0.33, 0.2, 0.1, 0.5), 1.3, true)
		line_y += 7.0
	draw_circle(Vector2(rect.end.x - 15.0, rect.end.y - 13.0), 5.5, Color(accent, 0.9))
	draw_arc(Vector2(rect.end.x - 15.0, rect.end.y - 13.0), 5.5, 0.0, TAU, 16, Color(DARK_EDGE, 0.7), 1.0, true)
	outline.append(outline[0])
	draw_polyline(outline, Color(0.3, 0.18, 0.08, 0.9), 1.5, true)


# A Lead is a page torn out of this notebook, held by a pin in the link's colour.
func _draw_lead(rect: Rect2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(item_id)
	var points: PackedVector2Array = PackedVector2Array()
	var teeth: int = 10
	for index: int in range(teeth + 1):
		var x: float = rect.position.x + rect.size.x * float(index) / float(teeth)
		points.append(Vector2(x, rect.position.y + 2.0 + rng.randf_range(-2.5, 3.0)))
	points.append(rect.end)
	points.append(Vector2(rect.position.x, rect.end.y))
	var shadow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		shadow.append(point + Vector2(1.5, 3.0))
	draw_colored_polygon(shadow, Color(0.15, 0.08, 0.02, 0.22))
	draw_colored_polygon(points, Color(0.985, 0.955, 0.87))
	var line_y: float = rect.position.y + 16.0
	while line_y < rect.end.y - 4.0:
		draw_line(Vector2(rect.position.x + 3.0, line_y), Vector2(rect.end.x - 3.0, line_y), Color(0.55, 0.45, 0.3, 0.4), 1.0, true)
		line_y += 9.0
	draw_line(Vector2(rect.position.x + 12.0, rect.position.y + 6.0), Vector2(rect.position.x + 12.0, rect.end.y - 1.0), Color(0.56, 0.17, 0.15, 0.45), 1.0, true)
	# Pencil writing.
	for row: int in range(2):
		var y: float = rect.position.y + 22.0 + float(row) * 9.0
		var points_row: PackedVector2Array = PackedVector2Array()
		var x: float = rect.position.x + 17.0
		while x < rect.end.x - 8.0 - float(row) * 16.0:
			points_row.append(Vector2(x, y + sin(x * 1.3) * 1.6))
			x += 2.5
		draw_polyline(points_row, Color(0.2, 0.17, 0.2, 0.75), 1.2, true)
	points.append(points[0])
	draw_polyline(points, Color(DARK_EDGE, 0.8), 1.3, true)
	draw_circle(Vector2(0.0, rect.position.y + 9.0) + Vector2(1.0, 1.5), 4.5, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(Vector2(0.0, rect.position.y + 9.0), 4.5, DARK_EDGE)
	draw_circle(Vector2(0.0, rect.position.y + 9.0), 3.3, accent)
	draw_circle(Vector2(-1.0, rect.position.y + 8.0), 1.1, Color(1.0, 1.0, 1.0, 0.7))


# A Conclusion is a finished ivory card with a gold foil corner.
func _draw_conclusion(rect: Rect2) -> void:
	_soft_shadow(rect)
	draw_rect(rect, Color(0.97, 0.935, 0.84))
	draw_rect(rect.grow(-4.0), Color(GOLD_FOIL, 0.85), false, 1.2)
	draw_colored_polygon(PackedVector2Array([Vector2(rect.end.x - 20.0, rect.position.y), Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + 20.0)]), GOLD_FOIL)
	draw_line(Vector2(rect.end.x - 13.0, rect.position.y + 1.0), Vector2(rect.end.x - 1.0, rect.position.y + 13.0), Color(1.0, 1.0, 0.85, 0.5), 1.2, true)
	for row: int in range(2):
		var y: float = rect.position.y + 22.0 + float(row) * 10.0
		draw_line(Vector2(rect.position.x + 12.0 + float(row) * 8.0, y), Vector2(rect.end.x - 12.0 - float(row) * 8.0, y), Color(0.2, 0.14, 0.1, 0.7), 1.6, true)
	draw_rect(rect, Color(DARK_EDGE, 0.9), false, 1.5)
