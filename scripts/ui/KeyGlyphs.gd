extends RefCounted

# Small key prompts ("ENTER  Select", "A  Select") drawn the same way on every screen.
# It remembers whether the player last used a controller, so prompts show the right buttons.
#
#   KeyGlyphs.note(event)                          call from _input() on any screen
#   KeyGlyphs.draw(item, pos, "accept", "Select")  draws one prompt, returns its width

const Typo := preload("res://scripts/ui/Typo.gd")

const KEYS: Dictionary = {
	"accept": ["ENTER", "A"],
	"back": ["ESC", "B"],
	"skip": ["ESC", "START"],
	"move": ["WASD", "L-STICK"],
	"interact": ["E", "A"],
	"pause": ["ESC", "START"],
	"present": ["Q", "Y"],
	"board": ["B", "LB"],
}
const PAD_COLORS: Dictionary = {
	"A": Color(0.45, 0.78, 0.45), "B": Color(0.9, 0.42, 0.38), "Y": Color(0.95, 0.8, 0.35),
}

static var using_pad: bool = false


static func note(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


static func key_text(action: String) -> String:
	var pair: Array = KEYS.get(action, [action.to_upper(), action.to_upper()])
	return str(pair[1] if using_pad else pair[0])


# Draws [KEY] Label at `pos` (the left end of the text's baseline). Returns the width used.
static func draw(item: CanvasItem, pos: Vector2, action: String, label: String, alpha: float = 1.0, size: int = 20) -> float:
	var key: String = key_text(action)
	var key_font: Font = Typo.sans(600, 1)
	var label_font: Font = Typo.sans(400, 3)
	var key_size: int = size - 4
	var key_width: float = key_font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size).x
	var box: Rect2
	if using_pad and key.length() == 1:
		var radius: float = size * 0.62
		box = Rect2(pos + Vector2(0.0, -size * 0.36 - radius), Vector2(radius * 2.0, radius * 2.0))
		var ring: Color = PAD_COLORS.get(key, Typo.CREAM)
		item.draw_arc(box.get_center(), radius, 0.0, TAU, 32, Color(ring, 0.9 * alpha), 2.0, true)
	else:
		box = Rect2(pos + Vector2(0.0, -size * 0.36 - size * 0.62), Vector2(key_width + 16.0, size * 1.24))
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.border_color = Color(Typo.CREAM, 0.75 * alpha)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		item.draw_style_box(style, box)
	item.draw_string(key_font, Vector2(box.get_center().x - key_width * 0.5, pos.y + 1.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1.0, key_size, Color(Typo.CREAM, alpha))
	var label_at: Vector2 = Vector2(box.end.x + 12.0, pos.y)
	var upper: String = label.to_upper()
	item.draw_string(label_font, label_at, upper, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, Color(Typo.CREAM, 0.85 * alpha))
	return box.size.x + 12.0 + label_font.get_string_size(upper, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
