extends RefCounted

# Small shared textures that make flat shapes look like real materials: paper fibres, cork, wood.
# They are made once in code (no image files) and reused by every screen that draws paper or wood.
#
# How to use: turn on `texture_repeat` on the Control, then call PaperFx.tile(...) inside its draw.

const KEY_PAPER: Color = Color(0.965, 0.93, 0.84)
const KEY_SIDE: Color = Color(0.56, 0.44, 0.3)  # the front edge of a key, which gives it height
const KEY_INK: Color = Color(0.13, 0.09, 0.1)
const KEY_DEPTH: float = 3.0

static var _grain: ImageTexture
static var _streaks: ImageTexture


# Fine, even speckle. Good for paper fibres and cork.
static func grain() -> ImageTexture:
	if _grain == null:
		_grain = _make(7, 0.32, 3)
	return _grain


# Soft, slow noise. Stretched sideways it reads as wood grain.
static func streaks() -> ImageTexture:
	if _streaks == null:
		_streaks = _make(23, 0.045, 4)
	return _streaks


static func _make(noise_seed: int, frequency: float, octaves: int) -> ImageTexture:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var grey: Image = noise.get_seamless_image(256, 256)
	var image: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y: int in range(256):
		for x: int in range(256):
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, grey.get_pixel(x, y).r))
	return ImageTexture.create_from_image(image)


# Tiles `texture` over `rect`, tinted with `color`. `stretch` scales the pattern (for example
# Vector2(9, 1) pulls the noise into long horizontal wood grain). Resets the draw transform after.
static func tile(item: CanvasItem, texture: Texture2D, rect: Rect2, color: Color, stretch: Vector2 = Vector2.ONE) -> void:
	item.draw_set_transform(rect.position, 0.0, stretch)
	item.draw_texture_rect(texture, Rect2(Vector2.ZERO, rect.size / stretch), true, color)
	item.draw_set_transform(Vector2.ZERO)


# A paper key: a darker front edge below, the cream top above, one ink outline around both.
# The prompt bar and the choice slips both draw their keys with this, so they always match.
static func draw_key(item: CanvasItem, rect: Rect2, radius: int) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(radius)
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	item.draw_style_box(style, Rect2(rect.position + Vector2(1.0, KEY_DEPTH + 3.0), rect.size))
	style.bg_color = KEY_SIDE
	style.border_color = KEY_INK
	style.set_border_width_all(2)
	item.draw_style_box(style, Rect2(rect.position + Vector2(0.0, KEY_DEPTH), rect.size))
	style.bg_color = KEY_PAPER
	item.draw_style_box(style, rect)
	item.draw_line(rect.position + Vector2(float(radius), 3.5), Vector2(rect.end.x - float(radius), rect.position.y + 3.5), Color(1.0, 1.0, 1.0, 0.7), 1.0)


# A slightly wavy line, like one drawn with a pen. `progress` 0..1 draws only the first part.
static func draw_wavy(item: CanvasItem, start: Vector2, length: float, color: Color, width: float, progress: float = 1.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var x: float = 0.0
	while x <= length * progress:
		points.append(start + Vector2(x, sin(x * 0.16) * 1.5))
		x += 3.0
	if points.size() >= 2:
		item.draw_polyline(points, color, width, true)
