extends Control

# The screens before the title: the studio, the engine, a short word before you play, and the
# autosave notice. Each fades in from black, holds, and fades out. All the words are in
# data/ui/boot.json, so nothing here changes when the studio name or the rating is decided.
#
# A press skips the current card (after its min_seconds). Esc or Start skips them all.

const StoryRules := preload("res://scripts/story/StoryRules.gd")
const SaveIndicatorScript := preload("res://scripts/ui/SaveIndicator.gd")
const Typo := preload("res://scripts/ui/Typo.gd")
const RuntimeSetup := preload("res://scripts/ui/RuntimeSetup.gd")

const BOOT_PATH: String = "res://data/ui/boot.json"
const TITLE_SCENE: String = "res://scenes/ui/title.tscn"
const TITLE_DATA: String = "res://data/ui/title.json"
const TITLE_SHADER: String = "res://shaders/title_painting.gdshader"
const FADE_SECONDS: float = 0.7
const LINE_GAP: float = 22.0

var cards: Array = []
var index: int = -1
var card_alpha: float = 0.0
var shown_for: float = 0.0

var _skip_card: bool = false
var _skip_all: bool = false
var _angle: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RuntimeSetup.apply(get_tree())
	cards = StoryRules.read_json(BOOT_PATH).get("cards", [])
	_warm_up_title()
	_run()


func current_id() -> String:
	if index < 0 or index >= cards.size():
		return ""
	return str((cards[index] as Dictionary).get("id", ""))


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	for i: int in range(cards.size()):
		if _skip_all:
			break
		index = i
		_skip_card = false
		shown_for = 0.0
		var card: Dictionary = cards[i]
		await _fade(1.0)
		while shown_for < float(card.get("seconds", 3.0)) and not _skip_card and not _skip_all:
			await get_tree().process_frame
		await _fade(0.0)
	index = -1
	# The title was loading while the cards played, so this is instant and the black screen never stalls.
	var packed: Variant = null
	if ResourceLoader.load_threaded_get_status(TITLE_SCENE) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		packed = ResourceLoader.load_threaded_get(TITLE_SCENE)
	if packed is PackedScene:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(TITLE_SCENE)


# Loads the title screen and its painting on other threads while the studio cards are showing.
func _warm_up_title() -> void:
	var paths: Array[String] = [TITLE_SCENE, TITLE_SHADER]
	var painting: Dictionary = StoryRules.read_json(TITLE_DATA).get("painting", {})
	for key: String in ["image", "masks"]:
		paths.append(str(painting.get(key, "")))
	for path: String in paths:
		if path != "" and ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)


func _fade(target: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "card_alpha", target, FADE_SECONDS * (0.6 if _skip_all else 1.0))
	await tween.finished


func _process(delta: float) -> void:
	shown_for += delta
	_angle += delta * 2.4
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if index < 0 or not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	var is_start: bool = event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START
	if event.is_action_pressed("ui_cancel") or is_start:
		_skip_all = true
	elif shown_for >= float((cards[index] as Dictionary).get("min_seconds", 0.5)):
		_skip_card = true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if index < 0 or card_alpha <= 0.0:
		return
	var card: Dictionary = cards[index]
	# Measure first, so the whole card sits in the middle of the screen.
	var blocks: Array = []
	var total: float = 0.0
	if str(card.get("icon", "")) == "shutter":
		total += 60.0 + LINE_GAP
	for line: Variant in card.get("lines", []):
		var item: Dictionary = line
		var font: Font = _font_for(item)
		var font_size: int = int(item.get("size", 24))
		var width: float = float(item.get("width", 1400.0))
		var height: float = font.get_multiline_string_size(str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, font_size).y
		blocks.append({ "item": item, "font": font, "size": font_size, "width": width, "height": height })
		total += height + LINE_GAP
	var y: float = (size.y - total + LINE_GAP) * 0.5
	if str(card.get("icon", "")) == "shutter":
		SaveIndicatorScript.draw_icon(self, Vector2(size.x * 0.5, y + 30.0), 28.0, _angle, card_alpha)
		y += 60.0 + LINE_GAP
	for block: Dictionary in blocks:
		var item: Dictionary = block["item"]
		var color: Color = Color(Typo.CREAM, float(item.get("alpha", 1.0)) * card_alpha)
		var width: float = block["width"]
		var font: Font = block["font"]
		draw_multiline_string(font, Vector2((size.x - width) * 0.5, y + font.get_ascent(block["size"])), str(item.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, width, block["size"], -1, color)
		y += float(block["height"]) + LINE_GAP


func _font_for(item: Dictionary) -> Font:
	if str(item.get("font", "sans")) == "hand":
		return Typo.hand()
	return Typo.sans(int(item.get("weight", 400)), int(item.get("spacing", 0)))
