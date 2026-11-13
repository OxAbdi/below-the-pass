extends Control

# The evidence folder that slides up when the player wants to present something.
#
# It shows everything James holds as the same little objects as the notebook (TrayCard tiles),
# lets the player choose one, and reports it with `presented`. It decides nothing about the story.
#
# Select with a click, arrows / d-pad, the wheel or LB / RB. Present with a second click, Enter or A.
# Esc, B, a right click or a click outside the folder closes it (`cancelled`).

signal presented(evidence_id: String)
signal cancelled

const TrayCardScript := preload("res://scripts/mechanics/TrayCard.gd")
const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const TITLE_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/KleeOne-Regular.ttf")

const OPEN_TOP: float = 600.0  # screen y of the folder's top edge when it is open
const CLOSED_TOP: float = 1080.0
const SLIDE_SECONDS: float = 0.3
const DROP_SECONDS: float = 0.2
const PAGE: Rect2 = Rect2(120.0, 40.0, 1680.0, 260.0)
const TILES: Rect2 = Rect2(150.0, 106.0, 1100.0, 156.0)
const TILE_STEP: float = 130.0  # tile width 112 + gap 18
const DETAIL_LEFT: float = 1300.0
const DETAIL_WIDTH: float = 470.0
const LIFT_PX: float = 6.0
const CIRCLE_SECONDS: float = 0.2

const LEATHER: Color = Color(0.231, 0.122, 0.094)
const LEATHER_LIGHT: Color = Color(0.353, 0.227, 0.173)
const THREAD: Color = Color(0.85, 0.68, 0.3, 0.75)
const PAPER_TOP: Color = Color(0.953, 0.918, 0.827)
const PAPER_BOTTOM: Color = Color(0.925, 0.878, 0.769)
const INK: Color = Color(0.169, 0.114, 0.078)
const SEPIA: Color = Color(0.478, 0.384, 0.282)
const RED_PENCIL: Color = Color(0.8, 0.2, 0.18)
const CREAM: Color = Color(0.97, 0.93, 0.85)

var is_open: bool = false
var selected: int = 0
var ids: Array[String] = []

var _infos: Array[Dictionary] = []
var _tiles: Array[TrayCardScript] = []
var _heading: String = ""
var _empty_text: String = ""
var _quote_name: String = ""
var _quote_text: String = ""
var _scroll: float = 0.0
var _circle: float = 0.0  # 0..1, how much of the red pencil circle is drawn
var _slide_tween: Tween
var _circle_tween: Tween
var _row: Control
var _marks: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	position = Vector2(0.0, CLOSED_TOP)
	size = Vector2(1920.0, CLOSED_TOP - OPEN_TOP)
	_row = Control.new()
	_row.clip_contents = true
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.position = TILES.position
	_row.size = TILES.size
	add_child(_row)
	_marks = Control.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.position = TILES.position
	_marks.size = TILES.size
	_marks.clip_contents = true
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


# `items`: [{ "id", "name", "description", "style", "accent" }, ...] in the order to show.
# `quote_name` / `quote_text`: the line on screen, repeated on the folder so it can still be read.
func open(items: Array, heading: String, empty_text: String, quote_name: String, quote_text: String) -> void:
	_heading = heading
	_empty_text = empty_text
	_quote_name = quote_name
	_quote_text = quote_text
	for tile: TrayCardScript in _tiles:
		_row.remove_child(tile)
		tile.queue_free()
	_tiles.clear()
	_infos.clear()
	ids.clear()
	for item: Variant in items:
		var info: Dictionary = item
		var tile: TrayCardScript = TrayCardScript.new()
		_row.add_child(tile)
		tile.setup(str(info["id"]), str(info["name"]), str(info["style"]), info["accent"], false)
		tile.focus_mode = Control.FOCUS_NONE
		tile.clicked.connect(_on_tile_clicked)
		_tiles.append(tile)
		_infos.append(info)
		ids.append(str(info["id"]))
	selected = 0
	_scroll = 0.0
	_layout()
	_restart_circle()
	is_open = true
	visible = true
	Audio.play("page_rustle")
	if _slide_tween != null:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(self, "position:y", OPEN_TOP, SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


# The folder drops away. `fast` is used when a card is being presented.
func close(fast: bool = false) -> void:
	if not is_open:
		return
	is_open = false
	if _slide_tween != null:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(self, "position:y", CLOSED_TOP, DROP_SECONDS if fast else SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_slide_tween.tween_callback(func() -> void: visible = false)


func selected_id() -> String:
	if selected >= 0 and selected < ids.size():
		return ids[selected]
	return ""


# Keyboard and controller. Returns true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if UiInput.is_cancel(event):
		_cancel()
		return true
	if event.is_action_pressed("ui_left") or _is_pad_button(event, JOY_BUTTON_LEFT_SHOULDER):
		_select(selected - 1)
		return true
	if event.is_action_pressed("ui_right") or _is_pad_button(event, JOY_BUTTON_RIGHT_SHOULDER):
		_select(selected + 1)
		return true
	if UiInput.is_accept(event):
		_present()
		return true
	return event is InputEventKey or event is InputEventJoypadButton


func _is_pad_button(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == button


func _gui_input(event: InputEvent) -> void:
	if not is_open or not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event
	if not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		accept_event()
		_cancel()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		accept_event()
		_select(selected + 1)
	elif button.button_index == MOUSE_BUTTON_WHEEL_UP:
		accept_event()
		_select(selected - 1)
	else:
		accept_event()  # a click on the folder itself does nothing (and does not close it)


func _on_tile_clicked(tile: Control) -> void:
	if not is_open:
		return
	var index: int = _tiles.find(tile)
	if index == selected:
		_present()
	else:
		_select(index)


func _select(index: int) -> void:
	if ids.is_empty():
		return
	index = clampi(index, 0, ids.size() - 1)
	if index == selected:
		return
	selected = index
	_layout()
	_restart_circle()
	queue_redraw()


func _present() -> void:
	if ids.is_empty():
		return
	presented.emit(ids[selected])


func _cancel() -> void:
	cancelled.emit()


# Puts the tiles in a row, lifts the selected one, and scrolls so it can be seen.
func _layout() -> void:
	var selected_left: float = float(selected) * TILE_STEP
	if selected_left - _scroll < 0.0:
		_scroll = selected_left
	elif selected_left + TILE_STEP - _scroll > TILES.size.x:
		_scroll = selected_left + TILE_STEP - TILES.size.x
	for index: int in range(_tiles.size()):
		var lift: float = LIFT_PX if index == selected else 0.0
		_tiles[index].position = Vector2(float(index) * TILE_STEP - _scroll + 8.0, 14.0 - lift)
	_marks.queue_redraw()


func _restart_circle() -> void:
	if _circle_tween != null:
		_circle_tween.kill()
	_circle = 0.0
	if ids.is_empty():
		return
	Audio.play("pencil_circle", 0.1)
	_circle_tween = create_tween()
	_circle_tween.tween_method(
		func(amount: float) -> void:
			_circle = amount
			_marks.queue_redraw(),
		0.0, 1.0, CIRCLE_SECONDS
	)


# ---------- drawing ----------

func _draw() -> void:
	var whole: Rect2 = Rect2(Vector2.ZERO, size)
	# The leather folder: a soft shadow above it, grain, a line of brass thread.
	draw_polygon(
		PackedVector2Array([Vector2(0.0, -26.0), Vector2(size.x, -26.0), Vector2(size.x, 0.0), Vector2(0.0, 0.0)]),
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.45), Color(0.0, 0.0, 0.0, 0.45)])
	)
	draw_polygon(
		PackedVector2Array([whole.position, Vector2(whole.end.x, 0.0), whole.end, Vector2(0.0, whole.end.y)]),
		PackedColorArray([LEATHER_LIGHT, LEATHER_LIGHT, LEATHER, LEATHER])
	)
	draw_texture_rect(PaperFx.grain(), whole, true, Color(0.0, 0.0, 0.0, 0.28))
	draw_line(Vector2(0.0, 1.0), Vector2(size.x, 1.0), Color(1.0, 0.8, 0.6, 0.25), 2.0)
	var stitch_x: float = 14.0
	while stitch_x < size.x - 14.0:
		draw_line(Vector2(stitch_x, 12.0), Vector2(stitch_x + 12.0, 12.0), THREAD, 2.0, true)
		stitch_x += 22.0

	# The cream page inside it.
	draw_rect(Rect2(PAGE.position + Vector2(2.0, 5.0), PAGE.size), Color(0.0, 0.0, 0.0, 0.35))
	draw_polygon(
		PackedVector2Array([PAGE.position, Vector2(PAGE.end.x, PAGE.position.y), PAGE.end, Vector2(PAGE.position.x, PAGE.end.y)]),
		PackedColorArray([PAPER_TOP, PAPER_TOP, PAPER_BOTTOM, PAPER_BOTTOM])
	)
	draw_texture_rect(PaperFx.grain(), PAGE.grow(-2.0), true, Color(0.45, 0.32, 0.18, 0.11))
	draw_rect(PAGE, Color(INK, 0.85), false, 2.0)

	draw_string(TITLE_FONT, PAGE.position + Vector2(30.0, 44.0), _heading, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, INK)
	var heading_width: float = TITLE_FONT.get_string_size(_heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	PaperFx.draw_wavy(self, PAGE.position + Vector2(30.0, 52.0), heading_width + 4.0, Color(INK, 0.8), 1.8)

	if ids.is_empty():
		draw_string(TITLE_FONT, Vector2(TILES.position.x + 8.0, TILES.position.y + 70.0), _empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(SEPIA, 0.9))
	else:
		# What the selected thing is, so the player can read before choosing.
		var info: Dictionary = _infos[selected]
		draw_line(Vector2(DETAIL_LEFT - 24.0, PAGE.position.y + 24.0), Vector2(DETAIL_LEFT - 24.0, PAGE.end.y - 24.0), Color(SEPIA, 0.35), 1.5)
		draw_multiline_string(TITLE_FONT, Vector2(DETAIL_LEFT, PAGE.position.y + 58.0), str(info["name"]), HORIZONTAL_ALIGNMENT_LEFT, DETAIL_WIDTH, 22, 2, INK)
		var name_height: float = TITLE_FONT.get_multiline_string_size(str(info["name"]), HORIZONTAL_ALIGNMENT_LEFT, DETAIL_WIDTH, 22, 2).y
		draw_multiline_string(BODY_FONT, Vector2(DETAIL_LEFT, PAGE.position.y + 58.0 + name_height + 6.0), str(info["description"]), HORIZONTAL_ALIGNMENT_LEFT, DETAIL_WIDTH, 17, 6, SEPIA)

	# The line being answered, written on the leather under the page.
	if _quote_text != "":
		var quote_top: float = PAGE.end.y + 46.0
		if _quote_name != "":
			draw_string(TITLE_FONT, Vector2(200.0, quote_top), _quote_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(THREAD, 1.0))
		draw_multiline_string(BODY_FONT, Vector2(200.0, quote_top + 34.0), _quote_text, HORIZONTAL_ALIGNMENT_LEFT, 1100.0, 22, 2, Color(CREAM, 0.9))


# Drawn over the tiles: the red pencil circle round the selected one.
func _draw_marks() -> void:
	if ids.is_empty() or _circle <= 0.0:
		return
	var tile: TrayCardScript = _tiles[selected]
	var center: Vector2 = tile.position + Vector2(56.0, 44.0)
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = int(54.0 * _circle)
	for step: int in range(steps + 1):
		# A little more than one turn, and slightly off-round, so the ends overlap like a real pencil circle.
		var angle: float = -2.3 + float(step) / 54.0 * (TAU + 0.5)
		var wobble: float = 1.0 + 0.035 * sin(angle * 3.0 + 1.0)
		points.append(center + Vector2(cos(angle) * 55.0 * wobble, sin(angle) * 41.0 * wobble + float(step) * 0.05))
	if points.size() >= 2:
		_marks.draw_polyline(points, Color(RED_PENCIL, 0.9), 2.6, true)
