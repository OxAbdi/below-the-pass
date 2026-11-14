extends Control

# The first time James can walk in a new game, a quiet line of key prompts appears in the
# bottom-left corner: how to move, look and talk, and pause. It fades once he has walked a few
# steps (or after a while), and never shows again in that save (flag "hint:controls").

const KeyGlyphs := preload("res://scripts/ui/KeyGlyphs.gd")

const FLAG: String = "hint:controls"
const WALK_TO_DISMISS: float = 260.0
const MAX_SECONDS: float = 14.0
const AT: Vector2 = Vector2(144.0, 980.0)

var texts: Dictionary = {}
var showing: bool = false

var _start: Vector2 = Vector2.ZERO
var _shown_for: float = 0.0
var _alpha: float = 0.0
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# Called every frame by the Game while James is free to walk.
func track(player_position: Vector2, in_control: bool, delta: float) -> void:
	if GameState.has_flag(FLAG) and not showing:
		return
	if not showing:
		if not in_control:
			return
		showing = true
		_start = player_position
		_shown_for = 0.0
		_fade_to(1.0, 0.8)
		return
	if in_control:
		_shown_for += delta
	if player_position.distance_to(_start) > WALK_TO_DISMISS or _shown_for > MAX_SECONDS:
		dismiss()
	elif not in_control and _alpha > 0.0:
		modulate.a = 0.0   # never on top of a conversation
	elif in_control:
		modulate.a = 1.0


func dismiss() -> void:
	if not showing:
		return
	showing = false
	GameState.set_flag(FLAG)
	_fade_to(0.0, 0.8)


func _fade_to(target: float, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_alpha = v
		queue_redraw(), _alpha, target, seconds)


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var x: float = AT.x
	x += KeyGlyphs.draw(self, Vector2(x, AT.y), "move", str(texts.get("move", "Move")), 0.85 * _alpha, 18) + 44.0
	x += KeyGlyphs.draw(self, Vector2(x, AT.y), "interact", str(texts.get("interact", "Look / Talk")), 0.85 * _alpha, 18) + 44.0
	KeyGlyphs.draw(self, Vector2(x, AT.y), "pause", str(texts.get("pause", "Pause")), 0.85 * _alpha, 18)
