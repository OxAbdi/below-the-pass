extends Control

# A column of paper slips to pick from: the menus on the title screen, in the pause menu and in
# "Yes / No" questions. Same look as the topic slips in a conversation.
#
# It only shows slips and reports which one was picked:
#   set_items([{ "id": "resume", "text": "Resume" }, { "id": "settings", "text": "Settings", "disabled": true }])
#   picked(id)
#
# Pick with the mouse, or arrows / d-pad and Enter / A. The screen that owns it passes key and
# controller presses to handle_input().

signal picked(id: String)

const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

const SLIP_GAP: float = 12.0
const SLIDE_PX: float = 12.0
const PAPER: Color = Color(0.965, 0.933, 0.839)
const INK: Color = Color(0.169, 0.114, 0.078)

@export var slip_size: Vector2 = Vector2(380.0, 52.0)

var items: Array[Dictionary] = []
var selected: int = 0
var active: bool = true

var _hover: Array[float] = []
var _time: float = 0.0
var _style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_style = StyleBoxFlat.new()
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(5)
	_style.shadow_size = 7
	_style.shadow_offset = Vector2(1.0, 4.0)


func set_items(new_items: Array, select_id: String = "") -> void:
	items.clear()
	_hover.clear()
	for item: Variant in new_items:
		items.append(item)
		_hover.append(0.0)
	selected = 0
	for index: int in range(items.size()):
		if (select_id == "" and not _disabled(index)) or str(items[index].get("id", "")) == select_id:
			selected = index
			break
	_time = 0.0
	custom_minimum_size = Vector2(slip_size.x + SLIDE_PX, float(items.size()) * (slip_size.y + SLIP_GAP))
	size = custom_minimum_size
	queue_redraw()


func selected_id() -> String:
	if selected < 0 or selected >= items.size():
		return ""
	return str(items[selected].get("id", ""))


# Keyboard and controller. Returns true when the event was used.
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


func slip_rect(index: int) -> Rect2:
	return Rect2(Vector2(0.0, float(index) * (slip_size.y + SLIP_GAP)), slip_size)


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
	queue_redraw()


func _pick(index: int) -> void:
	if index < 0 or index >= items.size() or _disabled(index):
		return
	selected = index
	Audio.play("choice_pick")
	picked.emit(str(items[index].get("id", "")))


func _slip_at(point: Vector2) -> int:
	for index: int in range(items.size()):
		if slip_rect(index).grow_individual(0.0, SLIP_GAP * 0.5, SLIDE_PX, SLIP_GAP * 0.5).has_point(point):
			return index
	return -1


func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		var over: int = _slip_at((event as InputEventMouseMotion).position)
		if over >= 0:
			_select(over)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var over: int = _slip_at(button.position)
			if over >= 0:
				accept_event()
				_pick(over)


func _process(delta: float) -> void:
	_time += delta
	var moving: bool = _time < 1.0
	for index: int in range(items.size()):
		var target: float = 1.0 if index == selected and active else 0.0
		if not is_equal_approx(_hover[index], target):
			_hover[index] = move_toward(_hover[index], target, delta / 0.12)
			moving = true
	if moving:
		queue_redraw()


func _draw() -> void:
	for index: int in range(items.size()):
		var rect: Rect2 = slip_rect(index)
		var appear: float = clampf((_time - float(index) * 0.04) / 0.16, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var disabled: bool = _disabled(index)
		var slide: float = 1.0 - pow(1.0 - _hover[index], 2.0)
		var text: String = str(items[index].get("text", ""))
		var tilt: float = deg_to_rad(float(posmod(hash(text), 3) - 1) * 0.5)
		draw_set_transform(rect.get_center() + Vector2(slide * SLIDE_PX, (1.0 - appear) * 10.0), tilt)
		var local: Rect2 = Rect2(-slip_size * 0.5, slip_size)
		var alpha: float = appear * (0.55 if disabled else 1.0)
		_style.bg_color = Color(PAPER, alpha)
		_style.border_color = Color(INK, alpha)
		_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4 * alpha)
		draw_style_box(_style, local)
		draw_texture_rect(PaperFx.grain(), local.grow(-3.0), true, Color(0.45, 0.32, 0.18, 0.1 * alpha))
		var text_at: Vector2 = local.position + Vector2(24.0, slip_size.y * 0.5 + 8.0)
		draw_string(FONT, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, slip_size.x - 48.0, 22, Color(INK, alpha))
		if _hover[index] > 0.0:
			var width: float = minf(FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, slip_size.x - 48.0)
			PaperFx.draw_wavy(self, text_at + Vector2(0.0, 7.0), width, Color(INK, 0.7 * alpha), 1.5, _hover[index])
	draw_set_transform(Vector2.ZERO)
