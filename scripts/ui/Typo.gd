extends RefCounted

# The game's one typeface: Klee One (handwriting-style, from the dialogue box we chose).
# Everything on screen uses it: titles, menus, prompts, notes, captions and dialogue.
#
#   Typo.sans(300, 6)   Klee One for titles, menus and prompts: any weight (light = Regular, 500 and up = SemiBold),
#                       with extra pixels between the letters. The name is kept so old calls still work.
#   Typo.hand()         Klee One Regular
#   Typo.hand_bold()    Klee One SemiBold
#
# Fonts are made once and reused.

const HAND: FontFile = preload("res://assets/fonts/KleeOne-Regular.ttf")
const HAND_BOLD: FontFile = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

const CREAM: Color = Color(0.96, 0.93, 0.84)
const AMBER: Color = Color(0.93, 0.68, 0.34)

static var _cache: Dictionary = {}


# `weight` 100 to 700. Klee One has two weights, so 500 and above pick SemiBold.
# `spacing` is extra pixels between letters.
static func sans(weight: int = 400, spacing: int = 0) -> Font:
	var key: String = "%d_%d" % [1 if weight >= 500 else 0, spacing]
	if not _cache.has(key):
		var font: FontVariation = FontVariation.new()
		font.base_font = HAND_BOLD if weight >= 500 else HAND
		font.spacing_glyph = spacing
		_cache[key] = font
	return _cache[key]


static func hand() -> Font:
	return HAND


static func hand_bold() -> Font:
	return HAND_BOLD
