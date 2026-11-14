extends Control

# The title screen's menu: plain words down the left of the screen, film-poster style.
# The chosen word glides a little to the right and brightens; the others wait in shadow.
# Items in different groups have a little more space between them.
#
#   set_items([{ "id": "new", "text": "New Game", "group": 0, "description": "..." }, ...])
#   picked(id)
#
# Mouse, arrows / d-pad and Enter / A. The screen that owns it passes key presses to handle_input().

signal picked(id: String)
signal selection_changed(id: String)

const Typo := preload("res://scripts/ui/Typo.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")

const ROW: float = 56.0
const GROUP_GAP: float = 32.0
const FONT_SIZE: int = 36
const SLIDE_PX: float = 46.0

var items: Array[Dictionary] = []
var selected: int = 0
var active: bool = true
var reveal: float = 1.0   # 0..1: the items fade in one after another as this rises

const SLIDE_SECONDS: float = 0.3   # a word glides to the right (and back) in this long, easing in and out
const GLOW_FOLLOW: float = 13.0    # how quickly the warm light follows the chosen word (bigger = snappier)

var _slide: Array[float] = []
var _rows: Array[float] = []
var _glow: GradientTexture2D
var _light_y: float = -1.0         # where the warm light is now (it travels from word to word instead of popping)
var _light_width: float = 0.0
var _light_alpha: float = 0.0


func _ready() -> void:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_items(new_items: Array, select_id: String = "") -> void:
	items.clear()
	_slide.clear()
	_rows.clear()
	_light_y = -1.0
	var y: float = 0.0
	var last_group: int = -1
	for item: Variant in new_items:
		var group: int = int((item as Dictionary).get("group", 0))
		if last_group >= 0 and group != last_group:
			y += GROUP_GAP
		last_group = group
		items.append(item)
		_rows.append(y)
		_slide.append(0.0)
		y += ROW
	selected = 0
	for index: int in range(items.size()):
		if (select_id == "" and not _disabled(index)) or str(items[index].get("id", "")) == select_id:
			selected = index
			break
	size = Vector2(620.0, y)
	queue_redraw()


func selected_id() -> String:
	if selected < 0 or selected >= items.size():
		return ""
	return str(items[selected].get("id", ""))


func selected_description() -> String:
	if selected < 0 or selected >= items.size():
		return ""
	return str(items[selected].get("description", ""))


func handle_input(event: InputEvent) -> bool:
	if not active or items.is_empty() or not is_visible_in_tree():
		return false
	if event.is_action_pressed("ui_up"):
		_step(-1)
		return true
	if event.is_action_pressed("ui_down"):
		_step(1)
		return true
	if UiInput.is_accept(event):
		_pick(selected)
		return true
	return false


# Where the warm light is right now, in this menu's own coordinates (a little left of its middle).
# The pause menu's frost melts around this spot. It does not change how the title screen looks.
func light_position() -> Vector2:
	return Vector2(-60.0 + _light_width * 0.38, _light_y)


func row_rect(index: int) -> Rect2:
	return Rect2(Vector2(0.0, _rows[index]), Vector2(size.x, ROW))


func _disabled(index: int) -> bool:
	return bool(items[index].get("disabled", false))


func _step(direction: int) -> void:
	var index: int = selected
	for _i: int in range(items.size()):
		index = posmod(index + direction, items.size())
		if not _disabled(index):
			break
	_select(index)


func _select(index: int) -> void:
	if index == selected or _disabled(index):
		return
	selected = index
	Audio.play("choice_hover", 0.08)
	selection_changed.emit(selected_id())
	queue_redraw()


func _pick(index: int) -> void:
	if index < 0 or index >= items.size() or _disabled(index):
		return
	selected = index
	Audio.play("choice_pick")
	picked.emit(str(items[index].get("id", "")))


func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		for index: int in range(items.size()):
			if row_rect(index).has_point((event as InputEventMouseMotion).position):
				_select(index)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for index: int in range(items.size()):
			if row_rect(index).has_point((event as InputEventMouseButton).position):
				accept_event()
				_pick(index)


func _process(delta: float) -> void:
	var moving: bool = reveal < 1.0
	for index: int in range(items.size()):
		var target: float = 1.0 if index == selected and active else 0.0
		if not is_equal_approx(_slide[index], target):
			_slide[index] = move_toward(_slide[index], target, delta / SLIDE_SECONDS)
			moving = true
	# The warm light glides to the chosen word, stretching to fit it, and fades if nothing is chosen.
	if selected >= 0 and selected < items.size():
		var want_y: float = _rows[selected] + ROW * 0.5
		var want_width: float = _word_width(selected) + SLIDE_PX + 120.0
		var want_alpha: float = 1.0 if active else 0.0
		if _light_y < 0.0:
			_light_y = want_y
			_light_width = want_width
		var follow: float = 1.0 - exp(-GLOW_FOLLOW * delta)
		if absf(_light_y - want_y) > 0.1 or absf(_light_width - want_width) > 0.1 or not is_equal_approx(_light_alpha, want_alpha):
			_light_y = lerpf(_light_y, want_y, follow)
			_light_width = lerpf(_light_width, want_width, follow)
			_light_alpha = move_toward(_light_alpha, want_alpha, delta / 0.2)
			moving = true
	if moving:
		queue_redraw()


func _word_width(index: int) -> float:
	return Typo.sans(400, 5).get_string_size(str(items[index].get("text", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x


func _draw() -> void:
	var font: Font = Typo.sans(400, 5)
	# The warm light first, under all the words.
	if selected >= 0 and selected < items.size() and _light_y >= 0.0:
		var shown: float = clampf(reveal * float(items.size() + 2) - float(selected), 0.0, 1.0)
		draw_texture_rect(_glow, Rect2(Vector2(-60.0, _light_y - 44.0), Vector2(_light_width, 88.0)), false, Color(0.95, 0.52, 0.18, 0.34 * _light_alpha * shown))
	for index: int in range(items.size()):
		var appear: float = clampf(reveal * float(items.size() + 2) - float(index), 0.0, 1.0)
		if appear <= 0.0:
			continue
		var smooth: float = _slide[index] * _slide[index] * (3.0 - 2.0 * _slide[index])
		var alpha: float = 0.3 if _disabled(index) else lerpf(0.55, 1.0, smooth)
		alpha *= appear
		var text: String = str(items[index].get("text", "")).to_upper()
		var baseline: Vector2 = Vector2(smooth * SLIDE_PX, _rows[index] + ROW * 0.5 + FONT_SIZE * 0.36)
		var middle: float = baseline.y - FONT_SIZE * 0.34
		if smooth > 0.0:
			# A short dash leads the chosen word in.
			draw_line(Vector2(baseline.x - 46.0, middle), Vector2(baseline.x - 46.0 + 24.0 * smooth, middle), Color(0.99, 0.78, 0.55, 0.95 * smooth * appear), 2.0, true)
			draw_string(font, baseline + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, Color(0, 0, 0, 0.55 * smooth * appear))
		var color: Color = Typo.CREAM.lerp(Color(0.99, 0.8, 0.58), smooth)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, Color(color, alpha))
