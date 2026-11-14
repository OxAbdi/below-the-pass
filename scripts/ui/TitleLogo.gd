extends Control

# The game's name, drawn as a small lockup (Klee One, the game's one typeface):
#
#        B E L O W   T H E        a small, widely spaced line
#        PASS                     the last word, large, with an icy glow
#        ───────  ❄  ───────     a thin line with a snowflake in the middle
#
# `reveal` goes 0 -> 1 and plays the whole entrance: the small line fades in, the big word
# blooms out of a soft glow, the line draws outward from the snowflake, then two sparkles twinkle.
# The words come from data/ui/menus.json ("game_title"), so a new name needs no code change.
#
# This node only draws. TitleScreen decides when the reveal runs.

const Typo := preload("res://scripts/ui/Typo.gd")

const SMALL_SIZE: int = 28
const BIG_SIZE: int = 104
const BIG_SPACING: int = 10
const BIG_DROP: float = 104.0     # from the small line's baseline down to the big word's baseline
const RULE_DROP: float = 138.0    # from the small line's baseline down to the thin line
const RIM: Color = Color(0.72, 0.86, 1.0)       # cold light along the top edge of the letters
const GLOW: Color = Color(0.82, 0.9, 1.0)       # the icy halo

var title: String = "Below the Pass":
	set(value):
		title = value
		_measure()
		queue_redraw()
var reveal: float = 1.0:
	set(value):
		reveal = value
		queue_redraw()

var _small_text: String = ""
var _big_text: String = ""
var _big_font: Font
var _small_font: Font
var _width: float = 0.0           # the width of the big word; the small line and the rule match it
var _time: float = 0.0
var _halo: GradientTexture2D      # one soft oval of light behind the big word (cheap: a single picture)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	_halo = GradientTexture2D.new()
	_halo.gradient = gradient
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	_halo.width = 128
	_halo.height = 128
	_measure()


# How wide the lockup is (so the menu or other code can line up with it).
func lockup_width() -> float:
	return _width


func _process(delta: float) -> void:
	_time += delta
	if reveal > 0.0:
		queue_redraw()


func _measure() -> void:
	var words: PackedStringArray = title.to_upper().split(" ", false)
	if words.is_empty():
		_small_text = ""
		_big_text = ""
		return
	_big_text = words[words.size() - 1]
	words.remove_at(words.size() - 1)
	_small_text = " ".join(words)
	_big_font = Typo.sans(600, BIG_SPACING)
	_width = _big_font.get_string_size(_big_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BIG_SIZE).x - BIG_SPACING
	# The small line is spaced out until it is exactly as wide as the big word.
	var plain: float = Typo.sans(400, 0).get_string_size(_small_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SMALL_SIZE).x
	var gaps: int = maxi(1, _small_text.length() - 1)
	var spacing: int = maxi(0, roundi((_width - plain) / float(gaps)))
	_small_font = Typo.sans(400, spacing)


# Not shown yet. Draw one of everything, all but invisible, while the screen is still black. The first time the graphics
# card sees a kind of shape (big letters, a soft picture, a line, a polygon) it has to prepare it, which takes a moment;
# doing that here means nothing has to be prepared in the middle of the entrance, where it would show up as a stutter.
func _warm_up() -> void:
	var faint: Color = Color(1, 1, 1, 0.004)
	draw_string(_big_font, Vector2(0.0, BIG_DROP), _big_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BIG_SIZE, faint)
	draw_string(_small_font, Vector2.ZERO, _small_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SMALL_SIZE, faint)
	draw_texture_rect(_halo, Rect2(Vector2(0.0, BIG_DROP - 60.0), Vector2(200.0, 100.0)), false, faint)
	draw_polyline_colors(PackedVector2Array([Vector2(0.0, RULE_DROP), Vector2(40.0, RULE_DROP)]), PackedColorArray([faint, faint]), 1.4, true)
	_draw_snowflake(Vector2(20.0, RULE_DROP), 9.0, faint, 0.0)
	_draw_sparkle(Vector2(_width + 14.0, BIG_DROP - 80.0), 15.0, 0.004)


func _draw() -> void:
	if _big_text == "":
		return
	if reveal <= 0.0:
		_warm_up()
		return
	# Each part runs on its own slice of `reveal`, eased so it starts and ends gently.
	var small_in: float = _ease(_slice(reveal, 0.0, 0.4))
	var big_in: float = _ease(_slice(reveal, 0.18, 0.72))
	var rule_in: float = _ease(_slice(reveal, 0.55, 0.95))
	var sparkle_in: float = _slice(reveal, 0.8, 1.0)

	# --- the small line ---
	# Motion is done with a transform (which can sit between two pixels) and never by moving the text itself: Godot
	# snaps text to whole pixels, so a slow slide drawn that way moves in tiny jerks that look like a low frame rate.
	if _small_text != "":
		draw_set_transform(Vector2(0.0, (1.0 - small_in) * 8.0))
		draw_string(_small_font, Vector2(2.0, 2.0), _small_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SMALL_SIZE, Color(0, 0, 0, 0.5 * small_in))
		draw_string(_small_font, Vector2.ZERO, _small_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, SMALL_SIZE, Color(Typo.CREAM, 0.82 * small_in))
		draw_set_transform(Vector2.ZERO)

	# --- the big word ---
	var base: Vector2 = Vector2(0.0, BIG_DROP)
	var slide: float = (1.0 - big_in) * 14.0
	# A soft glow behind it: it starts wide and bright (the word blooms out of light) and settles into a gentle halo.
	var bloom: float = 1.0 + (1.0 - big_in) * 0.55
	var halo_alpha: float = (0.2 * big_in + 0.2 * (1.0 - big_in) * _slice(reveal, 0.18, 0.4)) * (0.92 + 0.08 * sin(_time * 0.9))
	var halo_size: Vector2 = Vector2(_width + 150.0, BIG_SIZE * 1.5) * bloom
	var halo_centre: Vector2 = Vector2(_width * 0.5, base.y - BIG_SIZE * 0.36)
	draw_texture_rect(_halo, Rect2(halo_centre - halo_size * 0.5, halo_size), false, Color(GLOW, halo_alpha))
	draw_set_transform(Vector2(0.0, slide))
	draw_string(_big_font, base + Vector2(3.0, 5.0), _big_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BIG_SIZE, Color(0, 0, 0, 0.55 * big_in))
	draw_string(_big_font, base + Vector2(-2.0, -2.0), _big_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BIG_SIZE, Color(RIM, 0.55 * big_in))
	draw_string(_big_font, base, _big_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, BIG_SIZE, Color(Typo.CREAM, 0.97 * big_in))
	draw_set_transform(Vector2.ZERO)

	# --- the thin line with a snowflake ---
	var middle: float = _width * 0.5
	var y: float = RULE_DROP
	var reach: float = (middle - 22.0) * rule_in
	var strong: Color = Color(Typo.CREAM, 0.7 * rule_in)
	var faint: Color = Color(Typo.CREAM, 0.0)
	draw_polyline_colors(PackedVector2Array([Vector2(middle - 22.0, y), Vector2(middle - 22.0 - reach, y)]), PackedColorArray([strong, faint]), 1.4, true)
	draw_polyline_colors(PackedVector2Array([Vector2(middle + 22.0, y), Vector2(middle + 22.0 + reach, y)]), PackedColorArray([strong, faint]), 1.4, true)
	_draw_snowflake(Vector2(middle, y), 9.0 * rule_in, Color(Typo.CREAM, 0.9 * rule_in), _time * 0.12)

	# --- two sparkles just off the big word ---
	if sparkle_in > 0.0:
		_draw_sparkle(Vector2(_width + 14.0, BIG_DROP - BIG_SIZE * 0.8), 15.0, sparkle_in * _twinkle(0.0))
		_draw_sparkle(Vector2(_width + 34.0, BIG_DROP - BIG_SIZE * 0.46), 8.5, sparkle_in * _twinkle(2.3))


func _twinkle(offset: float) -> float:
	var wave: float = 0.5 + 0.5 * sin(_time * 1.5 + offset)
	return pow(wave, 3.0)


# A four-point star: long thin points up, down, left and right.
func _draw_sparkle(at: Vector2, radius: float, strength: float) -> void:
	if strength <= 0.01:
		return
	var r: float = radius * (0.55 + 0.45 * strength)
	var waist: float = r * 0.17
	var points: PackedVector2Array = PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(waist, -waist), at + Vector2(r, 0), at + Vector2(waist, waist),
		at + Vector2(0, r), at + Vector2(-waist, waist), at + Vector2(-r, 0), at + Vector2(-waist, -waist)])
	draw_colored_polygon(points, Color(1.0, 0.98, 0.92, 0.85 * strength))
	draw_circle(at, r * 0.28, Color(1.0, 0.98, 0.92, 0.35 * strength))


# Six arms, each with two small branches.
func _draw_snowflake(at: Vector2, radius: float, color: Color, turn: float) -> void:
	if radius <= 0.5:
		return
	for arm: int in range(6):
		var angle: float = turn + TAU * float(arm) / 6.0
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var side: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(at, at + dir * radius, color, 1.4, true)
		var branch_at: Vector2 = at + dir * radius * 0.62
		draw_line(branch_at, branch_at + (dir + side) * radius * 0.3, color, 1.2, true)
		draw_line(branch_at, branch_at + (dir - side) * radius * 0.3, color, 1.2, true)


static func _slice(value: float, from: float, to: float) -> float:
	return clampf((value - from) / maxf(0.0001, to - from), 0.0, 1.0)


static func _ease(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
