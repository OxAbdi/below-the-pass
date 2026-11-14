extends Control

# The walnut desk under the lamp: the same surface the case board hangs over.
# A plain backdrop for the title screen. No state, no input.

const PaperFx := preload("res://scripts/ui/PaperFx.gd")

@export var lamp_at: Vector2 = Vector2(0.36, 0.42)   # where the pool of light sits, 0..1 across and down

var _glow: GradientTexture2D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.78, 0.5, 0.34), Color(1.0, 0.7, 0.42, 0.12), Color(1.0, 0.7, 0.4, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 256
	_glow.height = 256


func _draw() -> void:
	var full: Rect2 = Rect2(Vector2.ZERO, size)
	var top: Color = Color(0.135, 0.088, 0.078)
	var bottom: Color = Color(0.075, 0.052, 0.058)
	draw_polygon(
		PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)
	PaperFx.tile(self, PaperFx.streaks(), full, Color(0.62, 0.4, 0.24, 0.16), Vector2(11.0, 0.9))
	PaperFx.tile(self, PaperFx.grain(), full, Color(0.0, 0.0, 0.0, 0.2), Vector2(14.0, 1.0))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var seam_y: float = 150.0
	while seam_y < full.size.y:
		draw_line(Vector2(0.0, seam_y), Vector2(full.size.x, seam_y), Color(0.0, 0.0, 0.0, 0.42), 2.0)
		draw_line(Vector2(0.0, seam_y + 2.0), Vector2(full.size.x, seam_y + 2.0), Color(1.0, 0.75, 0.5, 0.05), 1.0)
		var butt_x: float = rng.randf_range(200.0, full.size.x - 200.0)
		draw_line(Vector2(butt_x, seam_y), Vector2(butt_x, seam_y + 232.0), Color(0.0, 0.0, 0.0, 0.3), 2.0)
		seam_y += 232.0
	var pool: Vector2 = Vector2(2300.0, 1600.0)
	draw_texture_rect(_glow, Rect2(size * lamp_at - pool * 0.5, pool), false)
