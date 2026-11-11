extends Control

# Reusable dialogue box, laid out like a visual novel:
#   - a big portrait on the right side of the screen
#   - a soft dark gradient along the bottom (no hard border)
#   - the speaker's name and the typewriter text floating on the left
#
# Three ways to use it:
#   play_dialogue("test_dialogue")   - a full conversation from data/dialogue/, click to advance
#   play_lines([...], true)          - the same, but with lines built in code
#   show_notice("Title", "Body")     - a short message with no portrait that closes by itself

signal line_started(index: int)
signal dialogue_finished

const GOLD: Color = Color(0.85, 0.68, 0.3)
const PORTRAIT_SLIDE_PX: float = 260.0
const TEXT_SLIDE_PX: float = 40.0
const OPEN_SECONDS: float = 0.5
const SWAP_SECONDS: float = 0.4
const FADE_SECONDS: float = 0.35
const NOTICE_TYPE_SPEEDUP: float = 2.5

@export_file("*.json") var portraits_path: String = "res://data/characters/portraits.json"
@export_dir var dialogue_folder: String = "res://data/dialogue/"
@export var chars_per_second: float = 45.0

@onready var shade: TextureRect = $Shade
@onready var portrait: TextureRect = $Portrait
@onready var text_block: VBoxContainer = $TextBlock
@onready var name_label: Label = $TextBlock/NameLabel
@onready var text_label: RichTextLabel = $TextBlock/TextLabel
@onready var advance_hint: Polygon2D = $TextBlock/AdvanceHint
@onready var anim: AnimationPlayer = $AnimationPlayer

var portraits: Dictionary = {}
var lines: Array = []
var line_index: int = -1
var blocking: bool = true
var notice_seconds: float = 3.0
var is_open: bool = false
var typing: bool = false
var current_portrait_id: String = ""
var placeholder_color: Color = Color(0.5, 0.5, 0.5)
var placeholder_name: String = ""
var portrait_home: Vector2
var text_home: Vector2
var type_tween: Tween
var hint_tween: Tween


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_home = portrait.position
	text_home = text_block.position
	var data: Dictionary = _read_json(portraits_path)
	portraits = data.get("portraits", {})
	portrait.draw.connect(_draw_placeholder)
	_build_animations()
	anim.animation_finished.connect(_on_animation_finished)


# ---------- public API ----------

func play_dialogue(dialogue_id: String) -> void:
	var path: String = dialogue_folder.path_join(dialogue_id + ".json")
	var data: Dictionary = _read_json(path)
	var raw_lines: Array = data.get("lines", [])
	if raw_lines.is_empty():
		push_error("DialogueBox: no lines found in %s" % path)
		return
	play_lines(raw_lines, true)


func play_lines(new_lines: Array, is_blocking: bool = true, seconds: float = 3.0) -> void:
	if new_lines.is_empty():
		return
	lines = new_lines
	blocking = is_blocking
	notice_seconds = seconds
	mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	_show_line(0)


func show_notice(title: String, body: String, seconds: float = 3.0) -> void:
	play_lines([{ "name": title, "text": body }], false, seconds)


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if not blocking or not is_open:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if not blocking or not is_open:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	if typing:
		type_tween.kill()
		text_label.visible_ratio = 1.0
		_on_typed()
	else:
		_next_line_or_close()


# ---------- showing lines ----------

func _show_line(index: int) -> void:
	line_index = index
	var line: Dictionary = lines[index]
	var speaker_id: String = str(line.get("speaker", ""))
	var info: Dictionary = portraits.get(speaker_id, {})
	if speaker_id != "" and info.is_empty():
		push_warning("DialogueBox: no portrait entry for '%s' in %s" % [speaker_id, portraits_path])
	var has_portrait: bool = not info.is_empty()
	var shown_name: String = str(line.get("name", info.get("display_name", speaker_id)))

	name_label.text = shown_name
	name_label.visible = shown_name != ""
	name_label.add_theme_color_override("font_color", Color.html(str(info.get("name_color", "#d9ad4d"))))
	text_label.text = str(line.get("text", ""))
	text_label.visible_ratio = 0.0
	_stop_hint()

	var portrait_changed: bool = speaker_id != current_portrait_id
	current_portrait_id = speaker_id if has_portrait else ""
	portrait.visible = has_portrait
	if has_portrait:
		_apply_portrait_look(info, shown_name)

	if not is_open:
		is_open = true
		modulate.a = 1.0
		visible = true
		anim.play("open" if has_portrait else "open_text_only")
	elif has_portrait and portrait_changed:
		_finish_running_animation()
		anim.play("swap")

	_start_typing()
	line_started.emit(index)


# If an animation is still running, jump it to its end so nothing is left half-faded.
func _finish_running_animation() -> void:
	if anim.is_playing():
		anim.seek(anim.current_animation_length, true)


func _start_typing() -> void:
	var speed: float = chars_per_second if blocking else chars_per_second * NOTICE_TYPE_SPEEDUP
	var duration: float = maxf(float(text_label.text.length()) / speed, 0.05)
	typing = true
	if type_tween != null:
		type_tween.kill()
	type_tween = create_tween()
	type_tween.tween_property(text_label, "visible_ratio", 1.0, duration)
	type_tween.tween_callback(_on_typed)
	if not blocking:
		type_tween.tween_interval(notice_seconds)
		type_tween.tween_callback(_next_line_or_close)


func _on_typed() -> void:
	typing = false
	if not blocking:
		return
	advance_hint.visible = true
	advance_hint.modulate.a = 1.0
	hint_tween = create_tween().set_loops()
	hint_tween.tween_property(advance_hint, "modulate:a", 0.2, 0.5)
	hint_tween.tween_property(advance_hint, "modulate:a", 1.0, 0.5)


func _next_line_or_close() -> void:
	if line_index + 1 < lines.size():
		_show_line(line_index + 1)
	else:
		_close()


func _close() -> void:
	_stop_hint()
	if type_tween != null:
		type_tween.kill()
	typing = false
	is_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anim.play("fade_out")
	dialogue_finished.emit()


func _stop_hint() -> void:
	if hint_tween != null:
		hint_tween.kill()
	advance_hint.visible = false


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"fade_out" and not is_open:
		visible = false
		modulate.a = 1.0
		current_portrait_id = ""


# ---------- portrait ----------

func _apply_portrait_look(info: Dictionary, shown_name: String) -> void:
	placeholder_color = Color.html(str(info.get("placeholder_color", "#808080")))
	placeholder_name = shown_name
	var texture_path: String = str(info.get("texture", ""))
	if texture_path != "" and ResourceLoader.exists(texture_path):
		portrait.texture = load(texture_path)
	else:
		portrait.texture = null
	portrait.queue_redraw()


# Grey-box stand-in: a tall rectangle with a simple silhouette, drawn only while
# a portrait has no texture yet.
func _draw_placeholder() -> void:
	if portrait.texture != null:
		return
	var s: Vector2 = portrait.size
	var frame: Rect2 = Rect2(Vector2.ZERO, s)
	portrait.draw_rect(frame, Color(placeholder_color.darkened(0.5), 0.92), true)

	var shoulders: PackedVector2Array = PackedVector2Array()
	var center: Vector2 = Vector2(s.x * 0.5, s.y)
	for i in range(33):
		var angle: float = PI + PI * float(i) / 32.0
		shoulders.append(center + Vector2(cos(angle) * s.x * 0.46, sin(angle) * s.y * 0.38))
	portrait.draw_colored_polygon(shoulders, placeholder_color.darkened(0.2))
	portrait.draw_circle(Vector2(s.x * 0.5, s.y * 0.33), s.x * 0.2, placeholder_color)

	portrait.draw_rect(frame, GOLD, false, 3.0)
	portrait.draw_string(ThemeDB.fallback_font, Vector2(0.0, 56.0), "%s (portrait placeholder)" % placeholder_name, HORIZONTAL_ALIGNMENT_CENTER, s.x, 28, Color(1, 1, 1, 0.8))


# ---------- animations (built here so the scene file stays simple) ----------

func _build_animations() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation("open", _slide_anim(true, true, OPEN_SECONDS))
	library.add_animation("open_text_only", _slide_anim(true, false, OPEN_SECONDS))
	library.add_animation("swap", _slide_anim(false, true, SWAP_SECONDS))
	var fade: Animation = Animation.new()
	fade.length = FADE_SECONDS
	_add_value_track(fade, ".:modulate:a", 1.0, 0.0, FADE_SECONDS)
	library.add_animation("fade_out", fade)
	anim.add_animation_library("", library)


func _slide_anim(with_text: bool, with_portrait: bool, seconds: float) -> Animation:
	var a: Animation = Animation.new()
	a.length = seconds
	if with_portrait:
		_add_value_track(a, "Portrait:position:x", portrait_home.x + PORTRAIT_SLIDE_PX, portrait_home.x, seconds)
		_add_value_track(a, "Portrait:modulate:a", 0.0, 1.0, seconds)
	if with_text:
		_add_value_track(a, "TextBlock:position:y", text_home.y + TEXT_SLIDE_PX, text_home.y, seconds)
		_add_value_track(a, "TextBlock:modulate:a", 0.0, 1.0, seconds)
		_add_value_track(a, "Shade:modulate:a", 0.0, 1.0, seconds)
	return a


func _add_value_track(a: Animation, path: String, from_value: float, to_value: float, seconds: float) -> void:
	var track: int = a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(track, NodePath(path))
	a.track_insert_key(track, 0.0, from_value, 0.4)
	a.track_insert_key(track, seconds, to_value)


# ---------- data ----------

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DialogueBox: missing file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("DialogueBox: %s is not valid JSON" % path)
	return {}
