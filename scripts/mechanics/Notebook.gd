extends Control

# James's pocket notebook on the left of the Case Board (Milestone 4.2).
# A top-bound reporter's notebook. It is either SET DOWN (closed, small, tilted, with an elastic band)
# or HELD UP (open, bigger, showing a ruled page with one handwritten entry per clue, Lead or Conclusion).
#
# It draws itself from four floats that an AnimationPlayer moves (see _build_animations):
#   lift  0 = set down, 1 = held up        (position, size and tilt blend)
#   band  0 = elastic on, 1 = elastic off
#   flip  cover angle, 0..180 degrees      (the cover swings up over the binding)
#   page  0..1                             (heading fades in, then entries cascade in)
# Method tracks on the same animations call play_sound(id) at exact times, so picture and sound match.
#
# This script only shows entries and reports what the player did. The board decides what it means.

signal toggled(is_open: bool)
signal entry_clicked(card: Control)
signal entry_activated(card: Control)
signal entry_drag_started(card: Control)
signal entry_drag_moved(card: Control, global_mouse: Vector2)
signal entry_drag_released(card: Control, global_mouse: Vector2)

const TrayCardScript := preload("res://scripts/mechanics/TrayCard.gd")
const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

# Sizes and places, in this node's coordinates (the column starts at screen x 40, y 56).
const CLOSED_SIZE: Vector2 = Vector2(190.0, 300.0)
const OPEN_SIZE: Vector2 = Vector2(260.0, 480.0)
const CLOSED_CENTER: Vector2 = Vector2(158.0, 544.0)  # screen (198, 600)
const OPEN_CENTER: Vector2 = Vector2(158.0, 314.0)  # screen top y = 130
const CLOSED_ROTATION_DEG: float = -5.0
const HOVER_LIFT_PX: float = 4.0
const BINDING_HEIGHT: float = 24.0
const LOOP_COUNT: int = 13

# The entries live on the open page.
const ITEMS_OFFSET: Vector2 = Vector2(12.0, 96.0)
const ITEMS_SIZE: Vector2 = Vector2(236.0, 368.0)
const ROW_HEIGHT: float = 136.0  # one row of the scrapbook grid
const COLUMNS: int = 2
const COLUMN_STEP: float = 124.0
const HEADER_HEIGHT: float = 34.0
const SCROLL_STEP: float = 60.0
const CASCADE_RISE_PX: float = 6.0

const OPEN_SECONDS: float = 0.62
const CLOSE_SECONDS: float = 0.48

const COVER: Color = Color(0.231, 0.122, 0.094)  # #3b1f18
const COVER_INSIDE: Color = Color(0.353, 0.227, 0.173)  # #5a3a2c
const STEEL: Color = Color(0.353, 0.341, 0.322)  # #5a5752
const STEEL_LIGHT: Color = Color(0.659, 0.639, 0.604)  # #a8a39a
const BAND: Color = Color(0.078, 0.063, 0.071)  # #141012
const PENCIL_BODY: Color = Color(0.788, 0.604, 0.235)  # #c99a3c
const RIBBON: Color = Color(0.557, 0.169, 0.149)  # #8e2b26
const GOLD: Color = Color(0.85, 0.68, 0.3)
const PAPER_TOP: Color = Color(0.953, 0.918, 0.827)  # #f3ead3
const PAPER_BOTTOM: Color = Color(0.925, 0.878, 0.769)  # #ece0c4
const RULE: Color = Color(0.796, 0.714, 0.561, 0.5)  # #cbb68f at 50%
const MARGIN_RED: Color = Color(0.557, 0.169, 0.149, 0.35)
const INK: Color = Color(0.169, 0.114, 0.078)  # #2b1d14
const SEPIA: Color = Color(0.478, 0.384, 0.282)  # #7a6248
const GRAPHITE: Color = Color(0.3, 0.27, 0.25)

var lift: float = 0.0:
	set(value):
		lift = value
		_on_state_changed()
var band: float = 0.0:
	set(value):
		band = value
		queue_redraw()
var flip: float = 0.0:
	set(value):
		flip = value
		queue_redraw()
var page: float = 0.0:
	set(value):
		page = value
		_layout_rows()
		queue_redraw()

var is_open: bool = false
var rows: Dictionary = {}  # id -> TrayCard
var order: Array[String] = []  # ids in page order
var empty_text: String = ""
# TODO(settings): "Reduce motion" sets this to true. Both animations then jump straight to the end.
var animations_instant: bool = false

var _anim: AnimationPlayer
var _entries: Array[Dictionary] = []  # { "node": Control, "height": float }
var _scroll: float = 0.0
var _content_size: float = 0.0
var _hover: float = 0.0
var _hover_tween: Tween
var _hot: bool = false
var _binding_hover: bool = false
var _pending_open: int = -1  # a toggle that arrived while an animation was running
var _tab_wiggle: float = 0.0  # degrees
var _tab_tween: Tween
var _summary: String = ""
var _grain: PackedVector2Array = PackedVector2Array()
var _body_style: StyleBoxFlat
var _shadow_style: StyleBoxFlat
var _paper_style: StyleBoxFlat
var _hot_style: StyleBoxFlat

@onready var items: Control = $Items
@onready var front: Control = $Front


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	items.clip_contents = true
	items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items.position = OPEN_CENTER - OPEN_SIZE * 0.5 + ITEMS_OFFSET
	items.size = ITEMS_SIZE
	items.visible = false
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.draw.connect(_draw_overlay)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for index: int in range(80):
		_grain.append(Vector2(rng.randf(), rng.randf()))
	_body_style = _flat(COVER, Color(0.0, 0.0, 0.0, 0.35), 1, 10)
	_shadow_style = _flat(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 10)
	_shadow_style.shadow_offset = Vector2(4.0, 8.0)
	_paper_style = _flat(PAPER_TOP, Color(0.55, 0.45, 0.3, 0.6), 1, 6)
	_hot_style = _flat(Color(1.0, 0.9, 0.55, 0.06), Color(1.0, 0.88, 0.45, 0.95), 3, 10)
	_build_animations()
	mouse_exited.connect(_on_mouse_exited)
	_on_state_changed()


func _flat(fill: Color, outline: Color, outline_width: int, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_border_width_all(outline_width)
	box.set_corner_radius_all(radius)
	return box


# ---------- animations (built in code, like DialogueBox.gd) ----------

func _build_animations() -> void:
	_anim = AnimationPlayer.new()
	_anim.name = "NotebookAnimation"
	add_child(_anim)
	var library: AnimationLibrary = AnimationLibrary.new()

	var open_anim: Animation = Animation.new()
	open_anim.length = OPEN_SECONDS
	# Picked up: a tiny overshoot, then settles.
	_add_value_track(open_anim, ".:lift", [[0.0, 0.0], [0.15, 1.04], [0.20, 1.0]], 2.0)
	_add_value_track(open_anim, ".:band", [[0.0, 0.0], [0.12, 0.0], [0.22, 1.0]])
	_add_value_track(open_anim, ".:flip", [[0.0, 0.0], [0.20, 0.0], [0.48, 180.0]])
	_add_value_track(open_anim, ".:page", [[0.0, 0.0], [0.40, 0.0], [0.62, 1.0]])
	_add_sound_track(open_anim, [[0.00, "notebook_pickup"], [0.14, "band_snap"], [0.20, "cover_open"], [0.42, "page_settle"]])
	library.add_animation("open", open_anim)

	var close_anim: Animation = Animation.new()
	close_anim.length = CLOSE_SECONDS
	_add_value_track(close_anim, ".:page", [[0.0, 1.0], [0.08, 0.0], [CLOSE_SECONDS, 0.0]])
	_add_value_track(close_anim, ".:flip", [[0.0, 180.0], [0.08, 180.0], [0.30, 0.0]])
	_add_value_track(close_anim, ".:band", [[0.0, 1.0], [0.30, 1.0], [0.38, 0.0]])
	_add_value_track(close_anim, ".:lift", [[0.0, 1.0], [0.34, 1.0], [CLOSE_SECONDS, 0.0]])
	_add_sound_track(close_anim, [[0.30, "cover_close"], [CLOSE_SECONDS - 0.01, "notebook_down"]])
	library.add_animation("close", close_anim)

	_anim.add_animation_library("", library)
	_anim.animation_finished.connect(_on_animation_finished)


# keys: [[time, value], ...]. `transition` 1.0 is a straight line; 2.0 starts fast and settles softly.
func _add_value_track(animation: Animation, path: String, keys: Array, transition: float = 1.0) -> void:
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	for key: Array in keys:
		animation.track_insert_key(track, float(key[0]), float(key[1]), transition)


# keys: [[time, sound id], ...]. A method track calls play_sound(id) on this node at that time.
func _add_sound_track(animation: Animation, keys: Array) -> void:
	var track: int = animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(track, NodePath("."))
	for key: Array in keys:
		animation.track_insert_key(track, float(key[0]), { "method": &"play_sound", "args": [str(key[1])] })


func play_sound(id: String) -> void:
	Audio.play(id)


func is_animating() -> bool:
	return _anim != null and _anim.is_playing()


func _on_animation_finished(animation_name: StringName) -> void:
	_snap_to_state()
	var wanted: int = _pending_open
	_pending_open = -1
	if wanted >= 0 and (wanted == 1) != is_open:
		set_open(wanted == 1, true)
	else:
		toggled.emit(is_open)


# ---------- open and close ----------

# Opens or closes the notebook. With `animate` false it jumps straight to the end state.
func set_open(value: bool, animate: bool) -> void:
	if is_animating():
		if animate:
			_pending_open = 1 if value else 0
			return
		_anim.stop()
	is_open = value
	_set_row_focus()
	if animate and not animations_instant and value != (lift > 0.5 and flip > 90.0):
		if value:
			items.visible = true
		_anim.play("open" if value else "close")
	else:
		_snap_to_state()
		toggled.emit(is_open)


func toggle() -> bool:
	if is_animating():
		_pending_open = 0 if (_pending_open == 1 or (_pending_open < 0 and is_open)) else 1
		return _pending_open == 1
	set_open(not is_open, true)
	return is_open


func _snap_to_state() -> void:
	var target: float = 1.0 if is_open else 0.0
	lift = target
	band = target
	flip = 180.0 * target
	page = target
	items.visible = is_open
	_set_row_focus()
	_layout_rows()
	queue_redraw()
	front.queue_redraw()


func _set_row_focus() -> void:
	for row: TrayCardScript in rows.values():
		row.focus_mode = Control.FOCUS_ALL if is_open else Control.FOCUS_NONE


# ---------- entries ----------

# entries: [{ id, name, style, accent, section ("clue" / "lead" / "proven"), is_new }]
func set_entries(entries: Array, empty_notebook_text: String) -> void:
	empty_text = empty_notebook_text
	for child: Node in items.get_children():
		items.remove_child(child)
		child.queue_free()
	rows.clear()
	order.clear()
	_entries.clear()
	_content_size = 0.0
	var counts: Dictionary = { "clue": 0, "lead": 0, "proven": 0 }
	var current: String = ""
	var cursor_y: float = 0.0  # where the next row starts, in page space
	var column: int = 0
	for entry: Dictionary in entries:
		var section: String = str(entry.get("section", "clue"))
		counts[section] = int(counts.get(section, 0)) + 1
		if section != current:
			current = section
			if column > 0:
				cursor_y += ROW_HEIGHT
				column = 0
			var header: Control = Control.new()
			header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			header.size = Vector2(ITEMS_SIZE.x, HEADER_HEIGHT)
			items.add_child(header)
			header.draw.connect(_draw_header.bind(header, _section_title(section)))
			_entries.append({ "node": header, "at": Vector2(0.0, cursor_y) })
			cursor_y += HEADER_HEIGHT
		var card: TrayCardScript = TrayCardScript.new()
		items.add_child(card)
		card.setup(str(entry["id"]), str(entry["name"]), str(entry["style"]), entry["accent"], bool(entry.get("is_new", false)))
		card.mouse_filter = Control.MOUSE_FILTER_PASS  # wheel events reach the page
		card.focus_mode = Control.FOCUS_ALL if is_open else Control.FOCUS_NONE
		card.clicked.connect(func(c: Control) -> void: entry_clicked.emit(c))
		card.activated.connect(func(c: Control) -> void: entry_activated.emit(c))
		card.drag_started.connect(func(c: Control) -> void: entry_drag_started.emit(c))
		card.drag_moved.connect(func(c: Control, p: Vector2) -> void: entry_drag_moved.emit(c, p))
		card.drag_released.connect(func(c: Control, p: Vector2) -> void: entry_drag_released.emit(c, p))
		card.focus_entered.connect(_ensure_visible.bind(card))
		rows[str(entry["id"])] = card
		order.append(str(entry["id"]))
		_entries.append({ "node": card, "at": Vector2(float(column) * COLUMN_STEP, cursor_y) })
		column += 1
		if column >= COLUMNS:
			column = 0
			cursor_y += ROW_HEIGHT
	if column > 0:
		cursor_y += ROW_HEIGHT
	_content_size = cursor_y
	_summary = _make_summary(counts)
	_layout_rows()
	queue_redraw()
	front.queue_redraw()


func _section_title(section: String) -> String:
	if section == "lead":
		return "Leads"
	if section == "proven":
		return "Proven"
	return "Clues"


func _make_summary(counts: Dictionary) -> String:
	var parts: Array[String] = []
	var clues: int = int(counts["clue"])
	var leads: int = int(counts["lead"])
	var proven: int = int(counts["proven"])
	if clues > 0:
		parts.append("%d clue%s" % [clues, "" if clues == 1 else "s"])
	if leads > 0:
		parts.append("%d lead%s" % [leads, "" if leads == 1 else "s"])
	if proven > 0:
		parts.append("%d proven" % proven)
	return " · ".join(parts)


func unseen_count() -> int:
	var count: int = 0
	for row: TrayCardScript in rows.values():
		if row.is_new:
			count += 1
	return count


func refresh() -> void:
	queue_redraw()
	front.queue_redraw()


func _content_height() -> float:
	return _content_size


func _max_scroll() -> float:
	return maxf(0.0, _content_height() - ITEMS_SIZE.y)


# The entry at `index` fades in 0.1 of the page time after the one before it.
func _cascade_alpha(index: int) -> float:
	var start: float = 0.25 + minf(float(index), 5.0) * 0.1
	return clampf((page - start) / 0.25, 0.0, 1.0)


func _layout_rows() -> void:
	if items == null:
		return
	_scroll = clampf(_scroll, 0.0, _max_scroll())
	var cascading: bool = page < 0.999
	for index: int in range(_entries.size()):
		var node: Control = _entries[index]["node"]
		var at: Vector2 = _entries[index]["at"]
		var alpha: float = _cascade_alpha(index) if cascading else 1.0
		node.position = at + Vector2(0.0, -_scroll + (1.0 - alpha) * CASCADE_RISE_PX)
		if cascading or node.modulate.a < 1.0 and not _is_dragged(node):
			node.modulate.a = alpha
	if front != null:
		front.queue_redraw()


# The board dims a row while its ghost card is being dragged. Do not undo that.
func _is_dragged(node: Control) -> bool:
	return node is TrayCardScript and absf(node.modulate.a - 0.35) < 0.01


func _ensure_visible(card: Control) -> void:
	var top: float = card.position.y
	var bottom: float = top + card.size.y
	if top < 0.0:
		_scroll += top
	elif bottom > ITEMS_SIZE.y:
		_scroll += bottom - ITEMS_SIZE.y
	_layout_rows()


func focus_first() -> void:
	if not order.is_empty() and is_open:
		rows[order[0]].grab_focus()


func _scroll_by(amount: float) -> void:
	var before: float = _scroll
	_scroll = clampf(_scroll + amount, 0.0, _max_scroll())
	if absf(_scroll - before) > 0.5:
		Audio.play("page_rustle", 0.25)
	_layout_rows()


# ---------- geometry and input ----------

func _body_size() -> Vector2:
	return CLOSED_SIZE.lerp(OPEN_SIZE, lift)


func _body_rotation() -> float:
	return lerpf(deg_to_rad(CLOSED_ROTATION_DEG), 0.0, clampf(lift, 0.0, 1.0))


func _body_center() -> Vector2:
	var center: Vector2 = CLOSED_CENTER.lerp(OPEN_CENTER, lift)
	return center + Vector2(0.0, -HOVER_LIFT_PX * _hover * (1.0 - clampf(lift, 0.0, 1.0)))


# Maps the notebook's own space (top-left = 0,0) onto this node's space.
func _body_transform() -> Transform2D:
	var size_now: Vector2 = _body_size()
	return Transform2D(_body_rotation(), _body_center()) * Transform2D(0.0, Vector2.ONE, 0.0, -size_now * 0.5)


func _to_notebook(local_point: Vector2) -> Vector2:
	return _body_transform().affine_inverse() * local_point


func _tab_rect() -> Rect2:
	var s: Vector2 = CLOSED_SIZE
	return Rect2(s.x - 6.0, s.y * 0.62, 54.0, 22.0)


func _hit_body(local_point: Vector2) -> bool:
	var p: Vector2 = _to_notebook(local_point)
	if Rect2(Vector2.ZERO, _body_size()).has_point(p):
		return true
	return not is_open and unseen_count() > 0 and lift < 0.5 and _tab_rect().grow(4.0).has_point(p)


# Only the notebook itself takes the mouse, not the empty space around it in the column.
func _has_point(point: Vector2) -> bool:
	return _hit_body(point)


# The screen rectangle that just contains the notebook as it is drawn right now (used by tests and by
# anything that must keep clear of it).
func body_global_rect() -> Rect2:
	var to_screen: Transform2D = get_global_transform() * _body_transform()
	var size_now: Vector2 = _body_size()
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(size_now.x, 0.0), size_now, Vector2(0.0, size_now.y)]
	var result: Rect2 = Rect2(to_screen * corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		result = result.expand(to_screen * corner)
	return result


func body_rotation_degrees() -> float:
	return rad_to_deg(_body_rotation())


func body_size() -> Vector2:
	return _body_size()


func over_notebook(global_point: Vector2) -> bool:
	return _hit_body(get_global_transform().affine_inverse() * global_point)


func _in_binding(local_point: Vector2) -> bool:
	var p: Vector2 = _to_notebook(local_point)
	return is_open and p.y <= BINDING_HEIGHT and p.x >= 0.0 and p.x <= _body_size().x and p.y >= -10.0


func is_binding_hovered() -> bool:
	return _binding_hover


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		var over_binding: bool = _in_binding(motion.position)
		var over_cover: bool = (not is_open) and _hit_body(motion.position) and not is_animating()
		if over_binding != _binding_hover:
			_binding_hover = over_binding
			queue_redraw()
		_set_hover(over_cover)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (over_binding or over_cover) else Control.CURSOR_ARROW
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if is_open and _in_binding(button.position):
				toggle()
				accept_event()
			elif not is_open and _hit_body(button.position):
				toggle()
				accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and is_open:
			_scroll_by(SCROLL_STEP)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and is_open:
			_scroll_by(-SCROLL_STEP)
			accept_event()


func _on_mouse_exited() -> void:
	if _binding_hover:
		_binding_hover = false
		queue_redraw()
	_set_hover(false)
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _set_hover(value: bool) -> void:
	var target: float = 1.0 if value else 0.0
	if is_equal_approx(target, _hover) and (_hover_tween == null or not _hover_tween.is_running()):
		return
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_method(
		func(amount: float) -> void:
			_hover = amount
			queue_redraw(),
		_hover, target, 0.12
	)


# While a board card is dragged over the notebook, its edge glows gold.
func set_hot(value: bool) -> void:
	if _hot == value:
		return
	_hot = value
	queue_redraw()


# A new clue arrived while the notebook is set down: the sticky tab wiggles.
func wiggle_tab() -> void:
	if is_open or unseen_count() == 0:
		return
	if _tab_tween != null:
		_tab_tween.kill()
	_tab_tween = create_tween()
	var from: float = _tab_wiggle
	for degrees: float in [6.0, -6.0, 6.0, -6.0, 6.0, -6.0, 0.0]:
		_tab_tween.tween_method(
			func(amount: float) -> void:
				_tab_wiggle = amount
				queue_redraw(),
			from, degrees, 0.4 / 7.0
		)
		from = degrees


func tab_wiggle_degrees() -> float:
	return _tab_wiggle


func _on_state_changed() -> void:
	queue_redraw()
	if front != null:
		front.queue_redraw()


# ---------- drawing ----------

func _draw() -> void:
	if _body_style == null:
		return
	var size_now: Vector2 = _body_size()
	var transform_now: Transform2D = _body_transform()
	draw_set_transform_matrix(transform_now)
	_draw_ribbon(size_now)
	_shadow_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	_shadow_style.shadow_size = 14 + int(6.0 * _hover)
	draw_style_box(_shadow_style, Rect2(Vector2.ZERO, size_now))
	if flip > 0.0:
		_draw_page(size_now)
	_draw_cover(size_now, transform_now)
	draw_set_transform_matrix(transform_now)
	_draw_binding(size_now)
	_draw_tab()
	if _hot:
		draw_style_box(_hot_style, Rect2(Vector2.ZERO, size_now).grow(3.0))
	draw_set_transform(Vector2.ZERO)


# The red ribbon bookmark hangs out of the bottom edge near the left.
func _draw_ribbon(size_now: Vector2) -> void:
	var x: float = size_now.x * 0.2
	var top: float = size_now.y - 8.0
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(x, top), Vector2(x + 9.0, top), Vector2(x + 9.0, top + 52.0),
		Vector2(x + 4.5, top + 45.0), Vector2(x, top + 52.0)
	])
	var shadow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		shadow.append(point + Vector2(2.0, 3.0))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.25))
	draw_colored_polygon(points, RIBBON)
	draw_line(Vector2(x + 2.0, top), Vector2(x + 2.0, top + 48.0), Color(1.0, 0.7, 0.65, 0.25), 1.0)


func _draw_page(size_now: Vector2) -> void:
	var whole: Rect2 = Rect2(Vector2.ZERO, size_now)
	draw_style_box(_paper_style, whole)
	draw_polygon(
		PackedVector2Array([Vector2(1.0, 1.0), Vector2(size_now.x - 1.0, 1.0), Vector2(size_now.x - 1.0, size_now.y - 1.0), Vector2(1.0, size_now.y - 1.0)]),
		PackedColorArray([PAPER_TOP, PAPER_TOP, PAPER_BOTTOM, PAPER_BOTTOM])
	)
	# Paper fibres, and a darker edge where the pages have been thumbed.
	draw_texture_rect(PaperFx.grain(), Rect2(Vector2(2.0, 2.0), size_now - Vector2(4.0, 4.0)), true, Color(0.45, 0.32, 0.18, 0.11))
	draw_polygon(
		PackedVector2Array([Vector2(size_now.x - 16.0, 2.0), Vector2(size_now.x - 2.0, 2.0), Vector2(size_now.x - 2.0, size_now.y - 2.0), Vector2(size_now.x - 16.0, size_now.y - 2.0)]),
		PackedColorArray([Color(0.4, 0.26, 0.12, 0.0), Color(0.4, 0.26, 0.12, 0.16), Color(0.4, 0.26, 0.12, 0.16), Color(0.4, 0.26, 0.12, 0.0)])
	)
	draw_polygon(
		PackedVector2Array([Vector2(2.0, size_now.y - 22.0), Vector2(size_now.x - 2.0, size_now.y - 22.0), Vector2(size_now.x - 2.0, size_now.y - 2.0), Vector2(2.0, size_now.y - 2.0)]),
		PackedColorArray([Color(0.4, 0.26, 0.12, 0.0), Color(0.4, 0.26, 0.12, 0.0), Color(0.4, 0.26, 0.12, 0.14), Color(0.4, 0.26, 0.12, 0.14)])
	)
	# A faint dot grid, like a reporter's field journal. Things are stuck in over it.
	var dot_y: float = 28.0
	while dot_y < size_now.y - 8.0:
		var dot_x: float = 14.0
		while dot_x < size_now.x - 8.0:
			draw_rect(Rect2(dot_x, dot_y, 1.5, 1.5), Color(0.5, 0.4, 0.27, 0.32))
			dot_x += 18.0
		dot_y += 18.0
	# Binding holes along the top edge.
	for index: int in range(LOOP_COUNT):
		draw_circle(Vector2(_loop_x(size_now, index), 11.0), 2.2, Color(0.25, 0.18, 0.12, 0.55))
	# The heading.
	var heading_alpha: float = clampf(page / 0.3, 0.0, 1.0)
	if heading_alpha > 0.0:
		draw_string(FONT, Vector2(18.0, 56.0), "Evidence", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, Color(INK, heading_alpha))
		var width: float = FONT.get_string_size("Evidence", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_draw_wavy(Vector2(18.0, 64.0), width + 4.0, Color(INK, 0.8 * heading_alpha), 1.8)
		if _summary != "":
			var summary_width: float = FONT.get_string_size(_summary, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(FONT, Vector2(size_now.x - 18.0 - summary_width, 56.0), _summary, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(SEPIA, heading_alpha))
	if rows.is_empty():
		var empty_alpha: float = clampf((page - 0.25) / 0.25, 0.0, 1.0)
		if empty_alpha > 0.0:
			draw_string(FONT, Vector2(18.0, ITEMS_OFFSET.y + 26.0), empty_text, HORIZONTAL_ALIGNMENT_LEFT, size_now.x - 30.0, 17, Color(GRAPHITE, 0.75 * empty_alpha))


# A slightly wavy line, like an underline drawn with a pen.
func _draw_wavy(start: Vector2, length: float, color: Color, width: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var x: float = 0.0
	while x <= length:
		points.append(start + Vector2(x, sin(x * 0.12) * 1.5 + x * 0.004))
		x += 4.0
	if points.size() >= 2:
		draw_polyline(points, color, width, true)


func _loop_x(size_now: Vector2, index: int) -> float:
	return 16.0 + float(index) * (size_now.x - 32.0) / float(LOOP_COUNT - 1)


# The cover. Closed it is a rounded leatherette rectangle. While it flips it is a four-point polygon
# whose top corners stay on the binding (fake 3D): bottom_y = H * cos(angle), and the bottom corners
# spread outwards by W * 0.08 * sin(angle), so it seems to swing towards the camera.
func _draw_cover(size_now: Vector2, transform_now: Transform2D) -> void:
	var angle: float = deg_to_rad(flip)
	var cosine: float = cos(angle)
	var sine: float = sin(angle)
	if flip < 0.5:
		draw_style_box(_body_style, Rect2(Vector2.ZERO, size_now))
		_draw_cover_decor(size_now, transform_now, 1.0)
		return
	if flip >= 179.5:
		return
	var bottom_y: float = size_now.y * cosine
	if absf(bottom_y) < 1.5:
		return  # edge-on: nothing to see, and a flat polygon cannot be drawn
	var spread: float = size_now.x * 0.08 * sine
	var shape: PackedVector2Array = PackedVector2Array([
		Vector2.ZERO, Vector2(size_now.x, 0.0), Vector2(size_now.x + spread, bottom_y), Vector2(-spread, bottom_y)
	])
	if flip <= 90.0:
		draw_colored_polygon(shape, COVER)
		var squashed: Transform2D = transform_now * Transform2D(0.0, Vector2(1.0, cosine), 0.0, Vector2.ZERO)
		_draw_cover_decor(size_now, squashed, 1.0)
		draw_set_transform_matrix(transform_now)
		draw_colored_polygon(shape, Color(0.0, 0.0, 0.0, 0.35 * sine))
	else:
		var fade: float = 1.0 - clampf((flip - 120.0) / 40.0, 0.0, 1.0)
		if fade > 0.0:
			draw_colored_polygon(shape, Color(COVER_INSIDE, fade))
			draw_polyline(PackedVector2Array([shape[0], shape[1], shape[2], shape[3], shape[0]]), Color(0.0, 0.0, 0.0, 0.3 * fade), 1.5, true)


# Grain, edge light, pencil, elastic band and gold initials, drawn in cover space.
func _draw_cover_decor(size_now: Vector2, decor_transform: Transform2D, alpha: float) -> void:
	draw_set_transform_matrix(decor_transform)
	for index: int in range(_grain.size()):
		var spot: Vector2 = _grain[index] * size_now
		if spot.x < 6.0 or spot.y < 8.0 or spot.x > size_now.x - 6.0 or spot.y > size_now.y - 6.0:
			continue
		var dark: bool = index % 3 != 0
		draw_circle(spot, 0.8 + 0.8 * float(index % 4) * 0.3, Color(0.0, 0.0, 0.0, 0.16) if dark else Color(1.0, 0.8, 0.6, 0.07))
	# A soft lighter edge along the top and left.
	draw_polyline(PackedVector2Array([Vector2(1.5, size_now.y - 12.0), Vector2(1.5, 11.0), Vector2(11.0, 1.5), Vector2(size_now.x - 12.0, 1.5)]), Color(1.0, 0.8, 0.6, 0.16), 2.0, true)
	# Gold initials, blind-embossed bottom-right.
	var initials_at: Vector2 = Vector2(size_now.x - 50.0, size_now.y - 18.0)
	draw_string(FONT, initials_at + Vector2(1.0, 1.0), "J.F.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.0, 0.0, 0.0, 0.45))
	draw_string(FONT, initials_at, "J.F.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(GOLD, 0.45))
	# The band and the pencil slide off to the right and fade as `band` goes 0 to 1.
	var gone: float = clampf(band, 0.0, 1.0)
	if gone < 0.999:
		var shift: Vector2 = Vector2(gone * size_now.x * 0.4, 0.0)
		var fade: float = 1.0 - gone
		var band_x: float = size_now.x * 0.78
		# Pencil first (it is tucked under the band), then the band over it.
		draw_set_transform_matrix(decor_transform * Transform2D(deg_to_rad(8.0), Vector2.ONE, 0.0, Vector2(band_x - 14.0 + shift.x, size_now.y * 0.42)))
		_draw_pencil(Color(1.0, 1.0, 1.0, fade))
		draw_set_transform_matrix(decor_transform)
		draw_rect(Rect2(Vector2(band_x - 3.0 + shift.x, 0.0), Vector2(6.0, size_now.y)), Color(BAND, fade))
		draw_line(Vector2(band_x - 1.5 + shift.x, 0.0), Vector2(band_x - 1.5 + shift.x, size_now.y), Color(1.0, 1.0, 1.0, 0.18 * fade), 1.0)


# A yellow pencil lying along the cover, drawn around its own middle. `tint` fades it out.
func _draw_pencil(tint: Color) -> void:
	var half: float = 62.0
	var body: Rect2 = Rect2(Vector2(-4.5, -half + 8.0), Vector2(9.0, half * 2.0 - 22.0))
	draw_rect(Rect2(body.position + Vector2(2.0, 3.0), body.size), Color(0.0, 0.0, 0.0, 0.25 * tint.a))
	draw_rect(body, Color(PENCIL_BODY, tint.a))
	draw_rect(Rect2(body.position, Vector2(3.0, body.size.y)), Color(1.0, 0.9, 0.6, 0.35 * tint.a))
	draw_rect(Rect2(body.position + Vector2(6.0, 0.0), Vector2(3.0, body.size.y)), Color(0.0, 0.0, 0.0, 0.2 * tint.a))
	# Eraser end on top, sharpened tip at the bottom.
	draw_rect(Rect2(Vector2(-4.5, -half), Vector2(9.0, 5.0)), Color(0.85, 0.5, 0.5, tint.a))
	draw_rect(Rect2(Vector2(-4.5, -half + 5.0), Vector2(9.0, 3.0)), Color(0.7, 0.7, 0.72, tint.a))
	var tip_top: float = body.end.y
	draw_colored_polygon(PackedVector2Array([Vector2(-4.5, tip_top), Vector2(4.5, tip_top), Vector2(0.0, tip_top + 14.0)]), Color(0.93, 0.8, 0.6, tint.a))
	draw_colored_polygon(PackedVector2Array([Vector2(-1.6, tip_top + 9.0), Vector2(1.6, tip_top + 9.0), Vector2(0.0, tip_top + 14.0)]), Color(0.2, 0.18, 0.18, tint.a))


# The wire binding along the top. It stays visible whatever the cover is doing.
func _draw_binding(size_now: Vector2) -> void:
	var wire: Color = STEEL_LIGHT if _binding_hover else STEEL
	var thickness: float = 3.0 if _binding_hover else 2.0
	for index: int in range(LOOP_COUNT):
		var center: Vector2 = Vector2(_loop_x(size_now, index), 4.0)
		draw_arc(center, 6.0, PI, TAU, 12, Color(0.0, 0.0, 0.0, 0.3), thickness + 1.0, true)
		draw_arc(center, 6.0, PI, TAU, 12, wire, thickness, true)
		draw_arc(center + Vector2(0.0, -0.6), 5.0, PI + 0.5, TAU - 1.1, 8, Color(STEEL_LIGHT, 0.9), 1.0, true)


# The sticky tab on the right edge when something has not been looked at yet.
func _draw_tab() -> void:
	var count: int = unseen_count()
	var alpha: float = clampf(1.0 - lift * 4.0, 0.0, 1.0)
	if count <= 0 or alpha <= 0.0:
		return
	var rect: Rect2 = _tab_rect()
	var pivot: Vector2 = Vector2(rect.position.x + 8.0, rect.get_center().y)
	var base: Transform2D = _body_transform()
	draw_set_transform_matrix(base * Transform2D(deg_to_rad(_tab_wiggle), pivot) * Transform2D(0.0, Vector2.ONE, 0.0, -pivot))
	draw_rect(Rect2(rect.position + Vector2(1.0, 2.0), rect.size), Color(0.0, 0.0, 0.0, 0.3 * alpha))
	draw_rect(rect, Color(PAPER_TOP, alpha))
	draw_rect(rect, Color(0.62, 0.52, 0.36, 0.7 * alpha), false, 1.0)
	draw_string(FONT, rect.position + Vector2(11.0, 16.0), "%d new" % count, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(GRAPHITE, alpha))
	draw_set_transform_matrix(base)


func _draw_header(header: Control, title: String) -> void:
	header.draw_string(FONT, Vector2(6.0, 24.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, SEPIA)
	var width: float = FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var points: PackedVector2Array = PackedVector2Array()
	var x: float = 0.0
	while x <= width:
		points.append(Vector2(6.0 + x, 28.0 + sin(x * 0.2) * 1.2))
		x += 3.0
	if points.size() >= 2:
		header.draw_polyline(points, Color(INK, 0.6), 1.3, true)


# Drawn above the rows: the fade and the pencil arrow when the list is longer than the page.
func _draw_overlay() -> void:
	if not is_open or page < 0.999 or _scroll >= _max_scroll() - 1.0:
		return
	var rect: Rect2 = Rect2(items.position, items.size)
	var bottom: float = rect.end.y
	var clear: Color = Color(PAPER_BOTTOM, 0.0)
	front.draw_polygon(
		PackedVector2Array([Vector2(rect.position.x, bottom - 24.0), Vector2(rect.end.x, bottom - 24.0), Vector2(rect.end.x, bottom), Vector2(rect.position.x, bottom)]),
		PackedColorArray([clear, clear, PAPER_BOTTOM, PAPER_BOTTOM])
	)
	var arrow: Vector2 = Vector2(rect.end.x - 14.0, bottom - 10.0)
	front.draw_line(arrow + Vector2(0.0, -8.0), arrow + Vector2(0.0, 4.0), Color(GRAPHITE, 0.8), 1.8, true)
	front.draw_polyline(PackedVector2Array([arrow + Vector2(-4.0, 0.0), arrow + Vector2(0.0, 5.0), arrow + Vector2(4.0, 0.0)]), Color(GRAPHITE, 0.8), 1.8, true)
