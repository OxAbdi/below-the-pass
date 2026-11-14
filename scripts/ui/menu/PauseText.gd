extends Control

# All the words of the pause menu except the menu itself: the chapter, its title, the little snowflake
# rule, where James is, the current lead, what the chosen item does, the key hints and the play time.
#
# Every piece has its own opacity, so the pause menu can fade them in one after another.
# Nothing here ever moves: slow-moving big text shimmers, so words only fade (see art-direction.md).

const Typo := preload("res://scripts/ui/Typo.gd")
const KeyGlyphs := preload("res://scripts/ui/KeyGlyphs.gd")
const SlotListScript := preload("res://scripts/ui/menu/SlotList.gd")

enum Part { CHAPTER, TITLE, RULE, PLACE, LEAD_LABEL, LEAD, DESCRIPTION, HINTS, TIME }

const LEFT: float = 144.0
const RIGHT_EDGE: float = 1776.0
const ICE: Color = Color(0.659, 0.776, 0.941)      # #a8c6f0
const FLAKE: Color = Color(0.812, 0.878, 0.965)    # #cfe0f6

var words: Dictionary = {}          # the "pause" part of menus.json
var slot_words: Dictionary = {}     # the "slots" part (the "Select" label)
var chapter_number: int = 1
var chapter_title: String = ""
var place: String = ""
var lead: String = ""
var description: String = ""
var saved_flash: float = 0.0

var fade: float = 1.0               # everything together: the pause menu fades this out when it closes
var dim: float = 1.0                # everything together: lowered while the "Return to the title?" question is up
var _alpha: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _desc_mix: float = 1.0          # dips to 0 and back when the description changes, so it never pops
var _desc_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func get_alpha(part: int) -> float:
	return _alpha[part]


func set_alpha(value: float, part: int) -> void:
	_alpha[part] = value
	queue_redraw()


func set_all_alphas(value: float) -> void:
	for i: int in range(_alpha.size()):
		_alpha[i] = value
	queue_redraw()


func set_fade(value: float) -> void:
	fade = value
	queue_redraw()


func set_dim(value: float) -> void:
	dim = value
	queue_redraw()


# Changes the line under the menu with a short fade out and in.
func show_description(text: String) -> void:
	if text == description:
		return
	if _desc_tween != null:
		_desc_tween.kill()
	_desc_tween = create_tween()
	_desc_tween.tween_method(_set_desc_mix, _desc_mix, 0.0, 0.12)
	_desc_tween.tween_callback(func() -> void: description = text)
	_desc_tween.tween_method(_set_desc_mix, 0.0, 1.0, 0.3)


func set_description_now(text: String) -> void:
	if _desc_tween != null:
		_desc_tween.kill()
	description = text
	_desc_mix = 1.0
	queue_redraw()


func _set_desc_mix(value: float) -> void:
	_desc_mix = value
	queue_redraw()


func _process(delta: float) -> void:
	if saved_flash > 0.0:
		saved_flash = maxf(0.0, saved_flash - delta / 2.0)
		queue_redraw()


func _a(part: int) -> float:
	return _alpha[part] * fade * dim


# A line's top edge to the baseline Godot draws text on.
func _base(font: Font, top: float, font_size: int) -> float:
	return top + font.get_ascent(font_size)


func _draw() -> void:
	if fade <= 0.0 or dim <= 0.0:
		return
	_draw_header()
	_draw_footer()


func _draw_header() -> void:
	var chapter_text: String = (str(words.get("chapter", "Chapter %d")) % chapter_number).to_upper()
	var small: Font = Typo.sans(600, 8)
	draw_string(small, Vector2(LEFT + 2.0, _base(small, 118.0, 20)), chapter_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(0.851, 0.678, 0.302, _a(Part.CHAPTER)))

	var big: Font = Typo.sans(600, 1)
	var title_at: Vector2 = Vector2(LEFT, _base(big, 150.0, 64))
	var title_a: float = _a(Part.TITLE)
	draw_string_outline(big, title_at, chapter_title, HORIZONTAL_ALIGNMENT_LEFT, 900.0, 64, 10, Color(ICE, 0.15 * title_a))
	draw_string(big, title_at + Vector2(0.0, 2.0), chapter_title, HORIZONTAL_ALIGNMENT_LEFT, 900.0, 64, Color(0, 0, 0, 0.5 * title_a))
	draw_string(big, title_at, chapter_title, HORIZONTAL_ALIGNMENT_LEFT, 900.0, 64, Color(0.965, 0.937, 0.863, title_a))

	# The snowflake with a thin line fading away from it.
	var rule_a: float = _a(Part.RULE)
	var flake_at: Vector2 = Vector2(LEFT + 9.0, 246.0 + 9.0)
	_draw_snowflake(flake_at, 9.0, Color(FLAKE, rule_a))
	var line_from: float = LEFT + 18.0 + 12.0
	var line_y: float = 246.0 + 9.0
	var line_to: float = line_from + 230.0
	draw_polygon(
		PackedVector2Array([Vector2(line_from, line_y - 0.6), Vector2(line_to, line_y - 0.6), Vector2(line_to, line_y + 0.6), Vector2(line_from, line_y + 0.6)]),
		PackedColorArray([Color(FLAKE, 0.8 * rule_a), Color(FLAKE, 0.0), Color(FLAKE, 0.0), Color(FLAKE, 0.8 * rule_a)]))

	var hand: Font = Typo.hand()
	if place != "":
		draw_string(hand, Vector2(LEFT + 2.0, _base(hand, 276.0, 21)), place, HORIZONTAL_ALIGNMENT_LEFT, 700.0, 21, Color(Typo.CREAM, 0.62 * _a(Part.PLACE)))

	var label: Font = Typo.sans(600, 6)
	var label_text: String = str(words.get("current_lead", "Current lead")).to_upper()
	draw_string(label, Vector2(LEFT + 2.0, _base(label, 336.0, 15)), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.851, 0.678, 0.302, 0.85 * _a(Part.LEAD_LABEL)))
	var lead_text: String = lead if lead != "" else str(words.get("no_lead", ""))
	draw_multiline_string(hand, Vector2(LEFT + 2.0, _base(hand, 364.0, 25)), lead_text, HORIZONTAL_ALIGNMENT_LEFT, 520.0, 25, 2, Color(Typo.CREAM, 0.88 * _a(Part.LEAD)))


func _draw_footer() -> void:
	var hand: Font = Typo.hand()
	draw_multiline_string(hand, Vector2(LEFT + 2.0, _base(hand, 900.0, 21)), description, HORIZONTAL_ALIGNMENT_LEFT, 500.0, 21, 3, Color(Typo.CREAM, 0.55 * _a(Part.DESCRIPTION) * _desc_mix))

	var hints_a: float = _a(Part.HINTS)
	var x: float = LEFT
	x += KeyGlyphs.draw(self, Vector2(x, 1002.0), "accept", str(slot_words.get("hint_choose", "Select")), 0.8 * hints_a, 19) + 44.0
	KeyGlyphs.draw(self, Vector2(x, 1002.0), "back", str(words.get("resume", "Resume")), 0.8 * hints_a, 19)

	var time_a: float = _a(Part.TIME)
	var info: Font = Typo.hand()
	var played: String = str(words.get("play_time", "Play time %s")) % SlotListScript.format_play_time(GameState.play_seconds)
	var right_x: float = RIGHT_EDGE - 520.0
	draw_string(info, Vector2(right_x, _base(info, 968.0, 19)), played, HORIZONTAL_ALIGNMENT_RIGHT, 520.0, 19, Color(Typo.CREAM, 0.55 * time_a))
	var saved_text: String = str(words.get("never_saved", "Not saved yet"))
	if SaveManager.last_saved_at > 0:
		saved_text = str(words.get("last_saved", "Last saved %s")) % SlotListScript.format_date(SaveManager.last_saved_at)
		if SaveManager.active_slot > 0:
			saved_text += " · " + str(words.get("slot", "Slot %d")) % SaveManager.active_slot
	draw_string(info, Vector2(right_x, _base(info, 968.0, 19) + 29.0), saved_text, HORIZONTAL_ALIGNMENT_RIGHT, 520.0, 19, Color(Typo.CREAM, 0.55 * time_a))
	if saved_flash > 0.0:
		var saved_word: String = str(slot_words.get("saved", "Saved")).to_upper()
		draw_string(Typo.sans(500, 6), Vector2(right_x, 944.0), saved_word, HORIZONTAL_ALIGNMENT_RIGHT, 520.0, 24, Color(Typo.AMBER, minf(1.0, saved_flash * 2.0) * fade * dim))


# The same six-armed flake as the title screen's logo, each arm with two small branches.
func _draw_snowflake(at: Vector2, radius: float, color: Color) -> void:
	for arm: int in range(6):
		var angle: float = TAU * float(arm) / 6.0 + PI * 0.5
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var side: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(at, at + dir * radius, color, 1.4, true)
		var branch_at: Vector2 = at + dir * radius * 0.62
		draw_line(branch_at, branch_at + (dir + side) * radius * 0.3, color, 1.2, true)
		draw_line(branch_at, branch_at + (dir - side) * radius * 0.3, color, 1.2, true)
