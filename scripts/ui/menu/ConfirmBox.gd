extends Control

# A small paper card that asks a yes / no question, over a dimmed screen.
#
#   if await confirm.ask("Overwrite this save?"):
#       ...
#
# It starts on "No", so a hasty press never destroys anything.

signal answered(yes: bool)

const MenuSlipsScript := preload("res://scripts/ui/menu/MenuSlips.gd")
const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

const CARD_SIZE: Vector2 = Vector2(620.0, 300.0)
const PAPER: Color = Color(0.965, 0.933, 0.839)
const INK: Color = Color(0.169, 0.114, 0.078)

var is_open: bool = false
var question: String = ""
var yes_text: String = "Yes"
var no_text: String = "No"

var _slips: MenuSlipsScript


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	_slips = MenuSlipsScript.new()
	_slips.slip_size = Vector2(220.0, 50.0)
	add_child(_slips)
	_slips.picked.connect(_on_picked)


# Shows the question and waits for the answer.
func ask(text: String) -> bool:
	question = text
	is_open = true
	visible = true
	_slips.set_items([{ "id": "yes", "text": yes_text }, { "id": "no", "text": no_text }], "no")
	_slips.position = Vector2((size.x - 220.0) * 0.5, (size.y - CARD_SIZE.y) * 0.5 + 150.0)
	queue_redraw()
	var yes: bool = await answered
	return yes


# Returns true when the event was used (always, while open: nothing behind it may react).
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if UiInput.is_cancel(event):
		_close(false)
	else:
		_slips.handle_input(event)
	return true


func _on_picked(id: String) -> void:
	_close(id == "yes")


func _close(yes: bool) -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	answered.emit(yes)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55))
	var card: Rect2 = Rect2((size - CARD_SIZE) * 0.5, CARD_SIZE)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 16
	style.shadow_offset = Vector2(2.0, 8.0)
	draw_set_transform(card.get_center(), deg_to_rad(-0.8))
	var local: Rect2 = Rect2(-CARD_SIZE * 0.5, CARD_SIZE)
	draw_style_box(style, local)
	draw_texture_rect(PaperFx.grain(), local.grow(-3.0), true, Color(0.45, 0.32, 0.18, 0.1))
	draw_multiline_string(FONT, local.position + Vector2(40.0, 70.0), question, HORIZONTAL_ALIGNMENT_CENTER, CARD_SIZE.x - 80.0, 26, 3, INK)
	draw_set_transform(Vector2.ZERO)
