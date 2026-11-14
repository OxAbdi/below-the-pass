extends Control

# The pause menu's yes / no question, written on the frost: "Return to the title?"
# It has the same way of use as ConfirmBox (the paper card the save slots still use):
#
#   confirm.heading = "Return to the title?"
#   if await confirm.ask("Unsaved progress will be lost."):
#       ...
#
# It starts on NO, so a hasty press never throws anything away.
# The pause menu dims its own words and spreads the frost while this is open; this script only draws
# the question and the two answers (it fades in and out on its own).

signal answered(yes: bool)

const Typo := preload("res://scripts/ui/Typo.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")

const FADE_SECONDS: float = 0.3
const QUESTION_Y: float = 468.0
const LINE_Y: float = 522.0
const ANSWER_Y: float = 618.0
const ANSWER_SIZE: int = 32
const ANSWER_PAD: float = 34.0
const ANSWER_GAP: float = 70.0
const AMBER_GLOW: Color = Color(1.0, 0.667, 0.345)
const WARM: Color = Color(0.988, 0.835, 0.651)    # #fcd5a6, the same warm tone as a chosen menu word
const ICE: Color = Color(0.659, 0.776, 0.941)     # #a8c6f0, the cold glow around big words

var is_open: bool = false
var heading: String = ""     # the big question
var question: String = ""    # the quieter line under it
var yes_text: String = "Yes"
var no_text: String = "No"

var _choice: int = 0                              # 0 = NO, 1 = YES
var _warm: Array[float] = [1.0, 0.0]              # how warm each answer is right now (glides, never jumps)
var _glow: GradientTexture2D
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 128
	_glow.height = 128


# Shows the question and waits for the answer.
func ask(text: String) -> bool:
	question = text
	_choice = 0
	_warm = [1.0, 0.0]
	is_open = true
	visible = true
	_fade_to(1.0)
	queue_redraw()
	var yes: bool = await answered
	return yes


# Returns true when the event was used (always, while open: nothing behind it may react).
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if UiInput.is_cancel(event):
		_answer(false)
	elif event.is_action_pressed("ui_left"):
		_select(0)
	elif event.is_action_pressed("ui_right"):
		_select(1)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_select(1 - _choice)
	elif UiInput.is_accept(event):
		_answer(_choice == 1)
	return true


func _select(index: int) -> void:
	if index == _choice:
		return
	_choice = index
	Audio.play("choice_hover", 0.08)


func _answer(yes: bool) -> void:
	if not is_open:
		return
	is_open = false
	Audio.play("choice_pick")
	_fade_to(0.0)
	answered.emit(yes)


func _fade_to(target: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", target, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if target == 0.0:
		_tween.tween_callback(hide)


func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		for index: int in range(2):
			if _answer_rect(index).has_point((event as InputEventMouseMotion).position):
				_select(index)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for index: int in range(2):
			if _answer_rect(index).has_point((event as InputEventMouseButton).position):
				accept_event()
				_choice = index
				_answer(index == 1)


func _process(delta: float) -> void:
	if not visible:
		return
	for index: int in range(2):
		var target: float = 1.0 if index == _choice else 0.0
		_warm[index] = move_toward(_warm[index], target, delta / 0.3)
	queue_redraw()


func _answer_font() -> Font:
	return Typo.sans(500, 6)


func _answer_text(index: int) -> String:
	return (no_text if index == 0 else yes_text).to_upper()


# The clickable box around an answer. NO is on the left, YES on the right, the pair centred.
func _answer_rect(index: int) -> Rect2:
	var font: Font = _answer_font()
	var no_width: float = font.get_string_size(_answer_text(0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, ANSWER_SIZE).x + ANSWER_PAD * 2.0
	var yes_width: float = font.get_string_size(_answer_text(1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, ANSWER_SIZE).x + ANSWER_PAD * 2.0
	var left: float = (size.x - (no_width + ANSWER_GAP + yes_width)) * 0.5
	var top: float = ANSWER_Y - ANSWER_SIZE * 1.1
	if index == 0:
		return Rect2(left, top, no_width, ANSWER_SIZE * 1.8)
	return Rect2(left + no_width + ANSWER_GAP, top, yes_width, ANSWER_SIZE * 1.8)


func _draw() -> void:
	var big: Font = Typo.sans(600, 1)
	var width: float = size.x
	# The question, with a cold glow and a small dark shadow under it.
	draw_string_outline(big, Vector2(0.0, QUESTION_Y), heading, HORIZONTAL_ALIGNMENT_CENTER, width, 46, 10, Color(ICE, 0.15))
	draw_string(big, Vector2(0.0, QUESTION_Y + 2.0), heading, HORIZONTAL_ALIGNMENT_CENTER, width, 46, Color(0, 0, 0, 0.5))
	draw_string(big, Vector2(0.0, QUESTION_Y), heading, HORIZONTAL_ALIGNMENT_CENTER, width, 46, Typo.CREAM)
	draw_string(Typo.hand(), Vector2(0.0, LINE_Y), question, HORIZONTAL_ALIGNMENT_CENTER, width, 23, Color(Typo.CREAM, 0.62))
	var font: Font = _answer_font()
	for index: int in range(2):
		var box: Rect2 = _answer_rect(index)
		var warm: float = _warm[index] * _warm[index] * (3.0 - 2.0 * _warm[index])
		if warm > 0.0:
			draw_texture_rect(_glow, box.grow_individual(40.0, 26.0, 40.0, 26.0), false, Color(AMBER_GLOW, 0.28 * warm))
		var color: Color = Color(Typo.CREAM, 0.55).lerp(Color(WARM, 1.0), warm)
		var text: String = _answer_text(index)
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ANSWER_SIZE).x
		draw_string(font, Vector2(box.get_center().x - text_width * 0.5, ANSWER_Y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ANSWER_SIZE, color)
