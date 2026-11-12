extends Control

# One evidence card on the case board, drawn in code in a clean anime / webtoon style:
# rounded corners, dark ink outline, flat colour with soft gradients and soft shadows.
# It is either a photo print or a paper note (the registry's "card_style"), and every clue
# has its own accent colour (the registry's "accent").
#
# It only handles its own input and reports what happened through signals.
# The board decides what a link means and where cards may stand.
#
#   - press on the card body and drag: move the card (it cannot overlap other cards)
#   - click the card without dragging: "clicked"
#   - press on the round pin and drag: start a link (the board draws the string)
#   - Enter / A while the card has focus: "activated" (keyboard and controller linking)

signal hovered(card: Control)
signal moved(card: Control)
signal move_finished(card: Control)
signal clicked(card: Control)
signal link_drag_started(card: Control)
signal link_drag_moved(card: Control, global_mouse: Vector2)
signal link_drag_released(card: Control, global_mouse: Vector2)
signal activated(card: Control)

enum Mode { NONE, MOVING, LINKING }

const CARD_SIZE: Vector2 = Vector2(260.0, 190.0)
const PIN_CENTER: Vector2 = Vector2(130.0, 20.0)
const PIN_GRAB_RADIUS: float = 26.0
const MOVE_STEP_PX: float = 16.0
const CLICK_MAX_TRAVEL_PX: float = 6.0
const CORNER_RADIUS: int = 14
const HOVER_SCALE: float = 1.035
const STYLE_PHOTO: String = "photo"
const STYLE_NOTE: String = "note"

const INK: Color = Color(0.1, 0.08, 0.17)
const CREAM: Color = Color(0.98, 0.95, 0.89)
const PARCHMENT: Color = Color(0.99, 0.95, 0.84)
const CAPTION_INK: Color = Color(0.13, 0.1, 0.22)
const FOCUS_COLOR: Color = Color(1.0, 0.86, 0.5)
const TARGET_COLOR: Color = Color(1.0, 1.0, 1.0)

var evidence_id: String = ""
var display_name: String = ""
var description: String = ""
var card_style: String = STYLE_NOTE
var accent: Color = Color(0.85, 0.68, 0.3)
# The area (in the same coordinates as `position`) the card may be dragged inside.
var bounds: Rect2 = Rect2()
# Set by the board: func(card, rect) -> bool. The rect is in the same coordinates as `position`.
# Returns true if the card may stand there.
var placement_check: Callable = Callable()
# The card the player is about to drop a string on.
var highlighted: bool = false:
	set(value):
		highlighted = value
		queue_redraw()
# The card belongs to the link the player is reading. It glows.
var selected: bool = false:
	set(value):
		selected = value
		set_process(value)
		queue_redraw()

var _mode: Mode = Mode.NONE
var _grab_mouse: Vector2 = Vector2.ZERO  # mouse position when the drag began, in parent coordinates
var _grab_start: Vector2 = Vector2.ZERO  # card position when the drag began
var _linking: bool = false
# True when the mouse gave the card focus. The gold keyboard ring is only for keyboard / pad focus.
var _focus_from_mouse: bool = false
var _glow_time: float = 0.0
var _tween: Tween
var _hover_tween: Tween

var _body_style: StyleBoxFlat
var _glow_style: StyleBoxFlat
var _ring_style: StyleBoxFlat
var _photo_frame_style: StyleBoxFlat
var _note_header_style: StyleBoxFlat

@onready var margin: MarginContainer = $Margin
@onready var name_label: Label = $Margin/Name
@onready var pin: Control = $Pin


func _ready() -> void:
	size = CARD_SIZE
	pivot_offset = CARD_SIZE * 0.5
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pin.draw.connect(_draw_pin)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	set_process(false)


func setup(id: String, card_name: String, card_description: String, style: String, accent_color: Color) -> void:
	evidence_id = id
	display_name = card_name
	description = card_description
	card_style = style if style == STYLE_PHOTO else STYLE_NOTE
	accent = accent_color
	name_label.text = card_name
	_apply_text_layout()
	_build_styles()
	# A very small fixed tilt per card (about -1.5 to +1.5 degrees) so the board feels hand-pinned.
	rotation = deg_to_rad(float(posmod(hash(id), 5) - 2) * 0.75)
	queue_redraw()


# Where the pin is, in global coordinates (the board attaches strings here).
func get_pin_global() -> Vector2:
	return get_global_transform() * PIN_CENTER


func set_linking(value: bool) -> void:
	_linking = value
	pin.queue_redraw()


func shake() -> void:
	var home: float = position.x
	_restart_tween()
	for offset: float in [-10.0, 10.0, -6.0, 6.0, 0.0]:
		_tween.tween_property(self, "position:x", home + offset, 0.05)


func pulse() -> void:
	_restart_tween()
	_tween.tween_property(self, "scale", Vector2(1.07, 1.07), 0.12)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.18)


func _process(delta: float) -> void:
	_glow_time += delta
	queue_redraw()


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_on_press(button.position)
		else:
			_on_release(button.position)
		accept_event()
	elif event is InputEventMouseMotion and _mode != Mode.NONE:
		var motion: InputEventMouseMotion = event
		_on_motion(motion.position)
		accept_event()
	elif (event is InputEventKey or event is InputEventJoypadButton) and _focus_from_mouse:
		# The player switched to keyboard / pad: show where the focus is.
		_focus_from_mouse = false
		queue_redraw()
		if event.is_action_pressed("ui_accept") and not event.is_echo():
			activated.emit(self)
			accept_event()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		activated.emit(self)
		accept_event()


func _on_press(local_pos: Vector2) -> void:
	_focus_from_mouse = true
	grab_focus()
	if local_pos.distance_to(PIN_CENTER) <= PIN_GRAB_RADIUS:
		_mode = Mode.LINKING
		link_drag_started.emit(self)
	else:
		_mode = Mode.MOVING
		_grab_mouse = _to_parent_space(get_global_transform() * local_pos)
		_grab_start = position
		move_to_front()


func _on_motion(local_pos: Vector2) -> void:
	var global_mouse: Vector2 = get_global_transform() * local_pos
	if _mode == Mode.MOVING:
		_slide_towards(_clamp_to_bounds(_grab_start + (_to_parent_space(global_mouse) - _grab_mouse)))
		moved.emit(self)
	elif _mode == Mode.LINKING:
		link_drag_moved.emit(self, global_mouse)


func _on_release(local_pos: Vector2) -> void:
	var global_mouse: Vector2 = get_global_transform() * local_pos
	var finished_mode: Mode = _mode
	_mode = Mode.NONE
	if finished_mode == Mode.MOVING:
		var travel: float = (_to_parent_space(global_mouse) - _grab_mouse).length()
		if travel < CLICK_MAX_TRAVEL_PX:
			clicked.emit(self)
		else:
			move_finished.emit(self)
	elif finished_mode == Mode.LINKING:
		link_drag_released.emit(self, global_mouse)


# Walks the card toward the target in small steps. If a step would overlap another card,
# the card slides along that card (x only, then y only) or stops. It can never jump over one.
func _slide_towards(target: Vector2) -> void:
	var start: Vector2 = position
	var steps: int = maxi(1, ceili(start.distance_to(target) / MOVE_STEP_PX))
	var current: Vector2 = start
	for i: int in range(1, steps + 1):
		var wanted: Vector2 = start.lerp(target, float(i) / float(steps))
		if _is_free(wanted):
			current = wanted
		elif _is_free(Vector2(wanted.x, current.y)):
			current = Vector2(wanted.x, current.y)
		elif _is_free(Vector2(current.x, wanted.y)):
			current = Vector2(current.x, wanted.y)
		else:
			break
	position = current


# A tilted card's global_position is not its top-left corner, so all movement and collision
# maths uses `position` (parent coordinates) instead.
func _to_parent_space(global_point: Vector2) -> Vector2:
	var parent_item: CanvasItem = get_parent() as CanvasItem
	if parent_item == null:
		return global_point
	return parent_item.get_global_transform().affine_inverse() * global_point


func _is_free(top_left: Vector2) -> bool:
	if not placement_check.is_valid():
		return true
	return placement_check.call(self, Rect2(top_left, size))


func _clamp_to_bounds(top_left: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return top_left
	return Vector2(
		clampf(top_left.x, bounds.position.x, bounds.end.x - size.x),
		clampf(top_left.y, bounds.position.y, bounds.end.y - size.y)
	)


func _on_focus_exited() -> void:
	_focus_from_mouse = false
	queue_redraw()


func _on_focus_entered() -> void:
	queue_redraw()
	hovered.emit(self)


func _on_mouse_entered() -> void:
	hovered.emit(self)
	_animate_hover(HOVER_SCALE)


func _on_mouse_exited() -> void:
	_animate_hover(1.0)


func _animate_hover(target_scale: float) -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(target_scale, target_scale), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---------- text layout ----------

func _apply_text_layout() -> void:
	name_label.add_theme_color_override("font_color", CAPTION_INK)
	if card_style == STYLE_PHOTO:
		# Caption strip under the photo.
		margin.add_theme_constant_override("margin_top", 124)
		margin.add_theme_constant_override("margin_bottom", 6)
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_right", 18)
		name_label.add_theme_font_size_override("font_size", 20)
	else:
		margin.add_theme_constant_override("margin_top", 46)
		margin.add_theme_constant_override("margin_bottom", 18)
		margin.add_theme_constant_override("margin_left", 22)
		margin.add_theme_constant_override("margin_right", 22)
		name_label.add_theme_font_size_override("font_size", 24)


# ---------- styles ----------

func _make_box(fill: Color, outline: Color, outline_width: int, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_border_width_all(outline_width)
	box.set_corner_radius_all(radius)
	return box


func _build_styles() -> void:
	var paper: Color = CREAM if card_style == STYLE_PHOTO else PARCHMENT
	_body_style = _make_box(paper, INK, 3, CORNER_RADIUS)
	_body_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	_body_style.shadow_size = 16
	_body_style.shadow_offset = Vector2(0.0, 8.0)
	_glow_style = _make_box(Color(accent, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, CORNER_RADIUS)
	_glow_style.shadow_offset = Vector2.ZERO
	_ring_style = _make_box(Color(0.0, 0.0, 0.0, 0.0), FOCUS_COLOR, 3, CORNER_RADIUS + 5)
	_photo_frame_style = _make_box(Color(0.0, 0.0, 0.0, 0.0), INK, 3, 5)
	_note_header_style = _make_box(accent, Color(0.0, 0.0, 0.0, 0.0), 0, 0)
	_note_header_style.corner_radius_top_left = CORNER_RADIUS - 3
	_note_header_style.corner_radius_top_right = CORNER_RADIUS - 3


# ---------- drawing ----------

func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(evidence_id)
	return rng


func _draw() -> void:
	if _body_style == null:
		return
	var whole: Rect2 = Rect2(Vector2.ZERO, size)
	if selected:
		var beat: float = 0.5 + 0.5 * sin(_glow_time * 3.2)
		_glow_style.shadow_color = Color(accent.lerp(Color.WHITE, 0.25), 0.5 + 0.3 * beat)
		_glow_style.shadow_size = 22 + int(10.0 * beat)
		draw_style_box(_glow_style, whole)
	draw_style_box(_body_style, whole)
	if card_style == STYLE_PHOTO:
		_draw_photo()
	else:
		_draw_note()
	if highlighted:
		_ring_style.border_color = TARGET_COLOR
		draw_style_box(_ring_style, whole.grow(6.0))
	elif has_focus() and not _focus_from_mouse:
		_ring_style.border_color = FOCUS_COLOR
		draw_style_box(_ring_style, whole.grow(6.0))


func _draw_note() -> void:
	# Coloured header strip like a notepad, with the pin on it.
	draw_style_box(_note_header_style, Rect2(Vector2(3.0, 3.0), Vector2(size.x - 6.0, 32.0)))
	draw_line(Vector2(3.0, 35.0), Vector2(size.x - 3.0, 35.0), Color(0.0, 0.0, 0.0, 0.18), 2.0, true)
	draw_line(Vector2(3.0, 33.0), Vector2(size.x - 3.0, 33.0), Color(1.0, 1.0, 1.0, 0.25), 1.5, true)
	# Soft ruled lines.
	for line_y: float in [152.0, 172.0]:
		draw_line(Vector2(18.0, line_y), Vector2(size.x - 72.0, line_y), Color(0.45, 0.55, 0.85, 0.2), 1.5, true)
	# A faint rubber stamp in the corner.
	var stamp: Vector2 = Vector2(size.x - 40.0, size.y - 38.0)
	draw_arc(stamp, 20.0, 0.0, TAU, 48, Color(accent, 0.5), 2.5, true)
	draw_arc(stamp, 14.0, 0.0, TAU, 40, Color(accent, 0.35), 1.5, true)
	draw_circle(stamp, 4.0, Color(accent, 0.45))
	# Soft light across the top of the paper.
	draw_polygon(
		PackedVector2Array([Vector2(3.0, 36.0), Vector2(size.x - 3.0, 36.0), Vector2(size.x - 3.0, 80.0), Vector2(3.0, 80.0)]),
		PackedColorArray([Color(1.0, 1.0, 1.0, 0.28), Color(1.0, 1.0, 1.0, 0.28), Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.0)])
	)


func _draw_photo() -> void:
	var rng: RandomNumberGenerator = _rng()
	var photo: Rect2 = Rect2(Vector2(16.0, 36.0), Vector2(228.0, 84.0))
	var left: float = photo.position.x
	var right: float = photo.end.x
	var top: float = photo.position.y
	var bottom: float = photo.end.y

	# Sky: deep night at the top, glowing in the clue's colour near the horizon.
	var sky_top: Color = Color(0.1, 0.1, 0.29).lerp(accent, 0.12)
	var sky_mid: Color = Color(0.35, 0.22, 0.54).lerp(accent, 0.45)
	var sky_low: Color = accent.lerp(Color.WHITE, 0.4)
	var mid_y: float = top + photo.size.y * 0.55
	draw_polygon(
		PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, mid_y), Vector2(left, mid_y)]),
		PackedColorArray([sky_top, sky_top, sky_mid, sky_mid])
	)
	draw_polygon(
		PackedVector2Array([Vector2(left, mid_y), Vector2(right, mid_y), Vector2(right, bottom), Vector2(left, bottom)]),
		PackedColorArray([sky_mid, sky_mid, sky_low, sky_low])
	)

	# Moon / sun glow and a few sparkles.
	var glow_center: Vector2 = Vector2(left + photo.size.x * rng.randf_range(0.55, 0.8), top + photo.size.y * 0.46)
	for i: int in range(6):
		draw_circle(glow_center, 26.0 - float(i) * 4.0, Color(sky_low.lerp(Color.WHITE, 0.4), 0.08 + 0.05 * float(i)))
	draw_circle(glow_center, 5.0, Color(1.0, 1.0, 1.0, 0.95))
	for i: int in range(7):
		var star: Vector2 = Vector2(left + rng.randf() * photo.size.x, top + 4.0 + rng.randf() * photo.size.y * 0.4)
		var reach: float = rng.randf_range(1.6, 3.2)
		draw_line(star - Vector2(reach, 0.0), star + Vector2(reach, 0.0), Color(1.0, 1.0, 1.0, 0.75), 1.2, true)
		draw_line(star - Vector2(0.0, reach), star + Vector2(0.0, reach), Color(1.0, 1.0, 1.0, 0.75), 1.2, true)

	# Three layers of mountains, hazy far away and dark in front.
	var far: PackedVector2Array = _ridge(rng, photo, 0.42, 0.10)
	_fill_ridge(far, photo, Color(0.3, 0.27, 0.58).lerp(accent, 0.18))
	for i: int in range(far.size() - 1):
		if far[i].y < top + photo.size.y * 0.37:
			draw_line(far[i], far[i + 1], Color(1.0, 1.0, 1.0, 0.85), 2.5, true)
	draw_polygon(
		PackedVector2Array([Vector2(left, top + photo.size.y * 0.45), Vector2(right, top + photo.size.y * 0.45), Vector2(right, top + photo.size.y * 0.72), Vector2(left, top + photo.size.y * 0.72)]),
		PackedColorArray([Color(sky_low, 0.0), Color(sky_low, 0.0), Color(sky_low, 0.45), Color(sky_low, 0.45)])
	)
	var middle: PackedVector2Array = _ridge(rng, photo, 0.6, 0.11)
	_fill_ridge(middle, photo, Color(0.18, 0.16, 0.42).lerp(accent, 0.08))
	draw_polyline(middle, Color(accent.lerp(Color.WHITE, 0.6), 0.55), 1.6, true)
	var near: PackedVector2Array = _ridge(rng, photo, 0.8, 0.07)
	_fill_ridge(near, photo, Color(0.08, 0.07, 0.22))
	draw_polyline(near, Color(accent.lerp(Color.WHITE, 0.5), 0.4), 1.4, true)
	# A tiny lit window on the near hill.
	var window: Vector2 = near[near.size() / 3] + Vector2(0.0, 6.0)
	draw_circle(window, 6.0, Color(1.0, 0.8, 0.4, 0.25))
	draw_circle(window, 2.2, Color(1.0, 0.88, 0.55))

	# Glossy sheen and outline.
	draw_polygon(
		PackedVector2Array([Vector2(left + 38.0, top), Vector2(left + 86.0, top), Vector2(left + 50.0, bottom), Vector2(left + 2.0, bottom)]),
		PackedColorArray([Color(1.0, 1.0, 1.0, 0.14), Color(1.0, 1.0, 1.0, 0.14), Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.0)])
	)
	draw_style_box(_photo_frame_style, photo.grow(1.5))

	# Washi tape on the top corners, in the clue's colour.
	for side: float in [-1.0, 1.0]:
		var corner: Vector2 = Vector2(size.x * 0.5 + side * 108.0, 14.0)
		draw_set_transform(corner, deg_to_rad(side * -34.0))
		draw_rect(Rect2(Vector2(-27.0, -9.0), Vector2(54.0, 18.0)), Color(accent, 0.88))
		draw_rect(Rect2(Vector2(-27.0, -3.0), Vector2(54.0, 3.0)), Color(1.0, 1.0, 1.0, 0.35))
		draw_rect(Rect2(Vector2(-27.0, 3.0), Vector2(54.0, 3.0)), Color(1.0, 1.0, 1.0, 0.2))
		draw_set_transform(Vector2.ZERO)


# A smooth rolling ridge line across the photo, made from three sine waves.
func _ridge(rng: RandomNumberGenerator, area: Rect2, base: float, amplitude: float) -> PackedVector2Array:
	var phase_a: float = rng.randf() * TAU
	var phase_b: float = rng.randf() * TAU
	var phase_c: float = rng.randf() * TAU
	var points: PackedVector2Array = PackedVector2Array()
	var x: float = 0.0
	while x <= area.size.x + 0.01:
		var wave: float = 0.6 * sin(0.045 * x + phase_a) + 0.3 * sin(0.11 * x + phase_b) + 0.1 * sin(0.23 * x + phase_c)
		var height: float = clampf(base + amplitude * wave, 0.05, 0.98)
		points.append(Vector2(area.position.x + x, area.position.y + area.size.y * height))
		x += 4.0
	return points


func _fill_ridge(ridge: PackedVector2Array, area: Rect2, color: Color) -> void:
	var shape: PackedVector2Array = ridge.duplicate()
	shape.append(area.end)
	shape.append(Vector2(area.position.x, area.end.y))
	draw_colored_polygon(shape, color)


func _draw_pin() -> void:
	var center: Vector2 = pin.size * 0.5
	pin.draw_circle(center + Vector2(2.0, 4.0), 11.0, Color(0.0, 0.0, 0.0, 0.35))
	if _linking:
		pin.draw_circle(center, 15.0, Color(1.0, 1.0, 1.0, 0.9))
	pin.draw_circle(center, 11.5, INK)
	pin.draw_circle(center, 9.5, accent.darkened(0.25))
	pin.draw_circle(center + Vector2(-1.0, -1.0), 7.5, accent)
	pin.draw_circle(center + Vector2(-3.0, -3.5), 3.0, Color(1.0, 1.0, 1.0, 0.9))


func _restart_tween() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
