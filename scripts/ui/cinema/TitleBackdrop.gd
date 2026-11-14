extends Control

# The moving picture behind the title screen.
#
# When real art exists, list its layers in data/ui/title.json ("layers"): each one is a full-screen
# image that drifts a little (far layers less, near layers more), so the picture breathes.
#
# Until then it paints a stand-in in code: a frosted studio window at night. Snow falls on Northvale
# outside, the moon lights the glass, a lamp flickers in the room, steam rises from a cup of tea and
# the curtains move in a draught. The whole view drifts very slowly, like a held camera.

const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const PaintingScript := preload("res://scripts/ui/cinema/TitlePainting.gd")

const WINDOW: Rect2 = Rect2(1060.0, 120.0, 560.0, 720.0)   # the outside edge of the window frame
const FRAME: float = 26.0
const MULLION: float = 12.0
const SILL: Rect2 = Rect2(1000.0, 840.0, 680.0, 30.0)
const LAMP_AT: Vector2 = Vector2(260.0, 820.0)

var layers: Array = []          # [{ "texture": Texture2D, "depth": float }]
var time: float = 0.0
var painting: Control = null    # the finished, animated painting (TitlePainting), when its files exist

var _painting: Control           # everything that drifts together
var _outside: Control            # the view through the glass (clipped to the window)
var _front: Control              # glass, frame, curtains, sill, camera, cup
var _glow: GradientTexture2D
var _frost: GradientTexture2D
var _rng_seed: int = 7


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_glow = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)], [0.0, 0.35, 1.0])
	_frost = _radial([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)], [0.0, 1.0])
	_painting = _layer(self, Rect2(0, 0, 1920, 1080))
	_painting.pivot_offset = Vector2(960, 540)
	_painting.draw.connect(_draw_room)
	_painting.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var opening: Rect2 = WINDOW.grow(-FRAME)
	_outside = _layer(_painting, opening)
	_outside.clip_contents = true
	_outside.draw.connect(_draw_outside)
	_outside.add_child(_snow(opening.size))
	_front = _layer(_painting, Rect2(0, 0, 1920, 1080))
	_front.draw.connect(_draw_front)
	_painting.add_child(_dust())


# `textures`: [{ "texture": Texture2D, "depth": 0..1 }]. With any, the painted stand-in is hidden.
func use_layers(textures: Array) -> void:
	layers = textures
	_show_stand_in(layers.is_empty() and painting == null)
	_painting.queue_redraw()


# The finished painting from data/ui/title.json ("painting"). Returns false if its files are missing,
# and then the stand-in below stays.
func use_painting(config: Dictionary) -> bool:
	if config.is_empty():
		return false
	var made: Control = PaintingScript.new()
	if not made.setup(config):
		made.free()
		return false
	if painting != null:
		painting.queue_free()
	painting = made
	_painting.add_child(painting)
	_show_stand_in(false)
	_painting.queue_redraw()
	return true


func _show_stand_in(shown: bool) -> void:
	_outside.visible = shown
	_front.visible = shown
	for child: Node in _painting.get_children():
		if child is CPUParticles2D and child.get_parent() == _painting:
			(child as CPUParticles2D).visible = shown


func _process(delta: float) -> void:
	time += delta
	if painting != null:
		# The finished painting stays perfectly still: only what is inside it moves. (The held-camera drift below made
		# the whole screen bob up and down like a train carriage.)
		if _painting.scale != Vector2.ONE or _painting.position != Vector2.ZERO:
			_painting.scale = Vector2.ONE
			_painting.position = Vector2.ZERO
		return
	# The stand-in room: a slow, held-camera drift, a little zoom and a little sway, never quite repeating.
	_painting.scale = Vector2.ONE * (1.035 + 0.012 * sin(time * 0.07))
	_painting.position = Vector2(sin(time * 0.05) * 14.0, cos(time * 0.037) * 7.0)
	_painting.queue_redraw()
	_outside.queue_redraw()
	_front.queue_redraw()


# ---------- the room ----------

func _draw_room() -> void:
	var c: Control = _painting
	if painting != null:
		return
	if not layers.is_empty():
		for layer: Dictionary in layers:
			var texture: Texture2D = layer["texture"]
			var depth: float = float(layer.get("depth", 0.5))
			var sway: Vector2 = Vector2(sin(time * 0.05) * 22.0, cos(time * 0.037) * 10.0) * depth
			c.draw_texture_rect(texture, _cover(texture.get_size(), Rect2(Vector2(-40, -30) + sway, Vector2(2000, 1140))), false)
		return
	var full: Rect2 = Rect2(0, 0, 1920, 1080)
	# Plaster wall: warm and dark, lighter where the moon reaches it.
	c.draw_polygon(PackedVector2Array([full.position, Vector2(1920, 0), Vector2(1920, 1080), Vector2(0, 1080)]),
		PackedColorArray([Color(0.11, 0.09, 0.1), Color(0.16, 0.15, 0.19), Color(0.1, 0.09, 0.1), Color(0.07, 0.055, 0.055)]))
	PaperFx.tile(c, PaperFx.streaks(), full, Color(0.55, 0.45, 0.4, 0.1), Vector2(3.0, 3.0))
	PaperFx.tile(c, PaperFx.grain(), full, Color(0.0, 0.0, 0.0, 0.28), Vector2(2.0, 2.0))
	# Moonlight on the wall around the window.
	c.draw_texture_rect(_glow, Rect2(WINDOW.get_center() - Vector2(900, 700), Vector2(1800, 1400)), false, Color(0.55, 0.65, 0.95, 0.16))
	# The lamp somewhere left of the picture: a warm pool that breathes and flickers.
	var flicker: float = 0.86 + 0.06 * sin(time * 2.3) + 0.04 * sin(time * 7.1 + 1.3) + 0.03 * sin(time * 13.7)
	c.draw_texture_rect(_glow, Rect2(LAMP_AT - Vector2(900, 760), Vector2(1800, 1520)), false, Color(1.0, 0.62, 0.3, 0.3 * flicker))
	# Wainscot along the bottom.
	c.draw_rect(Rect2(0, 930, 1920, 150), Color(0.09, 0.065, 0.055))
	c.draw_line(Vector2(0, 930), Vector2(1920, 930), Color(0.3, 0.22, 0.16, 0.8), 3.0)
	c.draw_line(Vector2(0, 936), Vector2(1920, 936), Color(0, 0, 0, 0.5), 2.0)
	# Moonlight falling through the panes and across the room.
	var opening: Rect2 = WINDOW.grow(-FRAME)
	var shaft: Color = Color(0.7, 0.8, 1.0, 0.075)
	var clear: Color = Color(0.7, 0.8, 1.0, 0.0)
	for column: int in range(3):
		var x0: float = opening.position.x + opening.size.x * column / 3.0 + 8.0
		var x1: float = x0 + opening.size.x / 3.0 - 20.0
		c.draw_polygon(PackedVector2Array([Vector2(x0, opening.position.y + 20), Vector2(x1, opening.position.y + 20), Vector2(x1 - 620, 1080), Vector2(x0 - 760, 1080)]),
			PackedColorArray([shaft, shaft, clear, clear]))


# ---------- through the glass ----------

func _draw_outside() -> void:
	var c: Control = _outside
	var s: Vector2 = c.size
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _rng_seed
	# Night sky, deep at the top, paler towards the mountains.
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([Color(0.04, 0.06, 0.15), Color(0.05, 0.07, 0.17), Color(0.2, 0.27, 0.46), Color(0.18, 0.24, 0.42)]))
	for i: int in range(80):
		var star: Vector2 = Vector2(rng.randf() * s.x, rng.randf() * s.y * 0.5)
		var twinkle: float = 0.35 + 0.35 * sin(time * rng.randf_range(0.6, 2.2) + rng.randf() * TAU)
		c.draw_circle(star, rng.randf_range(0.6, 1.6), Color(0.9, 0.93, 1.0, twinkle))
	# The moon and its halo.
	var moon: Vector2 = Vector2(s.x * 0.24, s.y * 0.17)
	c.draw_texture_rect(_glow, Rect2(moon - Vector2(240, 240), Vector2(480, 480)), false, Color(0.75, 0.82, 1.0, 0.35))
	c.draw_circle(moon, 30.0, Color(0.97, 0.95, 0.88))
	c.draw_circle(moon + Vector2(9, -5), 26.0, Color(0.9, 0.9, 0.86, 0.35))
	# Far mountains with snow along the ridges, and the notch of the pass.
	_draw_range(c, s, s.y * 0.48, 120.0, Color(0.16, 0.21, 0.4), Color(0.6, 0.68, 0.88, 0.55), 11)
	_draw_range(c, s, s.y * 0.62, 70.0, Color(0.1, 0.13, 0.27), Color(0.45, 0.52, 0.72, 0.4), 23)
	# A band of mist in the valley.
	c.draw_polygon(PackedVector2Array([Vector2(0, s.y * 0.66), Vector2(s.x, s.y * 0.64), Vector2(s.x, s.y * 0.78), Vector2(0, s.y * 0.8)]),
		PackedColorArray([Color(0.7, 0.75, 0.9, 0.0), Color(0.7, 0.75, 0.9, 0.0), Color(0.7, 0.75, 0.9, 0.14), Color(0.7, 0.75, 0.9, 0.14)]))
	# Northvale's rooftops, white with snow, a few windows still lit.
	var x: float = -10.0
	var town_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	town_rng.seed = 41
	while x < s.x:
		var w: float = town_rng.randf_range(46.0, 88.0)
		var h: float = town_rng.randf_range(56.0, 120.0)
		var base: float = s.y + 4.0
		var top: float = base - h
		var roof: float = town_rng.randf_range(18.0, 34.0)
		var body: Color = Color(0.06, 0.07, 0.15)
		c.draw_rect(Rect2(x, top, w, h), body)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 4, top), Vector2(x + w * 0.5, top - roof), Vector2(x + w + 4, top)]), body)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, top + 1), Vector2(x + w * 0.5, top - roof), Vector2(x + w + 5, top + 1), Vector2(x + w * 0.5, top - roof + 7)]), Color(0.72, 0.78, 0.93, 0.85))
		if town_rng.randf() < 0.3:
			c.draw_rect(Rect2(x + w * 0.7, top - roof * 0.7, 7, roof * 0.7), body)
		for row: int in range(2):
			for col: int in range(2):
				if town_rng.randf() < 0.42:
					var lit: Rect2 = Rect2(x + 9 + col * (w * 0.45), top + 16 + row * 28, 9, 12)
					var warm: float = 0.75 + 0.25 * sin(time * town_rng.randf_range(0.4, 1.4) + town_rng.randf() * 6.0)
					c.draw_texture_rect(_glow, lit.grow(14), false, Color(1.0, 0.7, 0.35, 0.22 * warm))
					c.draw_rect(lit, Color(1.0, 0.8, 0.48, 0.9 * warm))
		x += w + town_rng.randf_range(4.0, 22.0)
	# A street lamp down in the town.
	var lamp: Vector2 = Vector2(s.x * 0.72, s.y - 70.0)
	c.draw_texture_rect(_glow, Rect2(lamp - Vector2(90, 90), Vector2(180, 180)), false, Color(1.0, 0.78, 0.45, 0.5))
	c.draw_circle(lamp, 3.0, Color(1.0, 0.92, 0.7))


func _draw_range(c: Control, s: Vector2, base_y: float, height: float, body: Color, snow: Color, seed_value: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ridge: PackedVector2Array = PackedVector2Array()
	var x: float = -20.0
	var up: bool = true
	while x <= s.x + 40.0:
		ridge.append(Vector2(x, base_y - (height * rng.randf_range(0.55, 1.0) if up else height * rng.randf_range(0.05, 0.3))))
		x += rng.randf_range(40.0, 90.0)
		up = not up
	var fill: PackedVector2Array = ridge.duplicate()
	fill.append(Vector2(s.x + 40, s.y + 10))
	fill.append(Vector2(-20, s.y + 10))
	c.draw_colored_polygon(fill, body)
	for i: int in range(ridge.size() - 1):
		var a: Vector2 = ridge[i]
		var b: Vector2 = ridge[i + 1]
		var peak: Vector2 = a if a.y < b.y else b
		var other: Vector2 = b if peak == a else a
		var down: Vector2 = peak.lerp(other, 0.45) + Vector2(0, 10)
		c.draw_colored_polygon(PackedVector2Array([peak, peak.lerp(other, 0.5), down]), snow)


# ---------- glass, frame and the things on the sill ----------

func _draw_front() -> void:
	var c: Control = _front
	var opening: Rect2 = WINDOW.grow(-FRAME)
	# Frost gathers in the corners of every pane; a faint reflection crosses the glass.
	var pane: Vector2 = Vector2((opening.size.x - MULLION * 2.0) / 3.0, (opening.size.y - MULLION * 2.0) / 3.0)
	for row: int in range(3):
		for col: int in range(3):
			var p: Rect2 = Rect2(opening.position + Vector2(col * (pane.x + MULLION), row * (pane.y + MULLION)), pane)
			c.draw_texture_rect(_frost, Rect2(p.position + Vector2(-60, p.size.y - 70), Vector2(150, 130)), false, Color(0.85, 0.9, 1.0, 0.35))
			c.draw_texture_rect(_frost, Rect2(p.end - Vector2(80, 60), Vector2(130, 110)), false, Color(0.85, 0.9, 1.0, 0.25))
	c.draw_polygon(_clip_quad(opening, 60.0, 150.0),
		PackedColorArray([Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))
	# Frame and glazing bars, painted wood lit from outside.
	var wood: Color = Color(0.42, 0.4, 0.42)
	var edge: Color = Color(0.68, 0.7, 0.78)
	for bar: Rect2 in [Rect2(WINDOW.position, Vector2(WINDOW.size.x, FRAME)), Rect2(WINDOW.position + Vector2(0, WINDOW.size.y - FRAME), Vector2(WINDOW.size.x, FRAME)),
			Rect2(WINDOW.position, Vector2(FRAME, WINDOW.size.y)), Rect2(WINDOW.position + Vector2(WINDOW.size.x - FRAME, 0), Vector2(FRAME, WINDOW.size.y))]:
		c.draw_rect(bar, wood)
	c.draw_rect(opening, edge, false, 2.0)
	for i: int in range(1, 3):
		var vx: float = opening.position.x + i * (pane.x + MULLION) - MULLION
		c.draw_rect(Rect2(vx, opening.position.y, MULLION, opening.size.y), wood)
		c.draw_line(Vector2(vx, opening.position.y), Vector2(vx, opening.end.y), edge, 1.5)
		var hy: float = opening.position.y + i * (pane.y + MULLION) - MULLION
		c.draw_rect(Rect2(opening.position.x, hy, opening.size.x, MULLION), wood)
		c.draw_line(Vector2(opening.position.x, hy), Vector2(opening.end.x, hy), edge, 1.5)
	c.draw_rect(WINDOW, Color(0.0, 0.0, 0.0, 0.5), false, 3.0)
	# The sill.
	c.draw_rect(Rect2(SILL.position + Vector2(0, SILL.size.y), Vector2(SILL.size.x, 26)), Color(0.18, 0.15, 0.14))
	c.draw_rect(SILL, Color(0.5, 0.48, 0.5))
	c.draw_line(SILL.position, Vector2(SILL.end.x, SILL.position.y), Color(0.8, 0.84, 0.92, 0.8), 2.0)
	_draw_camera(c, Vector2(1420, SILL.position.y))
	_draw_cup(c, Vector2(1160, SILL.position.y))
	_draw_curtain(c, 940.0, 1110.0, 1.0)
	_draw_curtain(c, 1570.0, 1740.0, -1.0)
	# The curtain rod.
	c.draw_rect(Rect2(910, 84, 860, 10), Color(0.12, 0.1, 0.1))
	c.draw_circle(Vector2(910, 89), 11.0, Color(0.16, 0.13, 0.12))
	c.draw_circle(Vector2(1770, 89), 11.0, Color(0.16, 0.13, 0.12))


func _clip_quad(opening: Rect2, width: float, lean: float) -> PackedVector2Array:
	var x: float = opening.position.x + opening.size.x * 0.55
	return PackedVector2Array([Vector2(x, opening.position.y), Vector2(x + width, opening.position.y), Vector2(x + width - lean, opening.end.y), Vector2(x - lean, opening.end.y)])


# Helen's old rangefinder on the sill, its strap hanging over the edge.
func _draw_camera(c: Control, foot: Vector2) -> void:
	var body: Rect2 = Rect2(foot + Vector2(-70, -62), Vector2(140, 62))
	c.draw_rect(body.grow(2), Color(0, 0, 0, 0.5))
	c.draw_rect(body, Color(0.1, 0.1, 0.12))
	c.draw_rect(Rect2(body.position + Vector2(0, -12), Vector2(body.size.x, 14)), Color(0.55, 0.58, 0.63))
	c.draw_line(body.position + Vector2(0, -12), body.position + Vector2(body.size.x, -12), Color(0.85, 0.88, 0.95), 1.5)
	c.draw_rect(Rect2(body.position + Vector2(14, -22), Vector2(26, 10)), Color(0.45, 0.48, 0.52))
	c.draw_rect(Rect2(body.position + Vector2(100, -18), Vector2(18, 6)), Color(0.45, 0.48, 0.52))
	var lens: Vector2 = body.get_center() + Vector2(8, 4)
	c.draw_circle(lens, 27.0, Color(0.35, 0.37, 0.4))
	c.draw_circle(lens, 22.0, Color(0.05, 0.05, 0.07))
	c.draw_circle(lens, 13.0, Color(0.12, 0.14, 0.22))
	c.draw_circle(lens + Vector2(-6, -6), 4.0, Color(0.8, 0.86, 1.0, 0.7))
	var strap: PackedVector2Array = PackedVector2Array()
	for i: int in range(16):
		var t: float = i / 15.0
		strap.append(Vector2(body.end.x - 4.0 + sin(t * PI * 0.5) * 30.0, foot.y - 36.0 + t * t * 92.0))
	c.draw_polyline(strap, Color(0.22, 0.14, 0.1), 5.0, true)


# A cup of tea, three sugars, still steaming.
func _draw_cup(c: Control, foot: Vector2) -> void:
	c.draw_set_transform(foot, 0.0, Vector2(1.0, 0.28))
	c.draw_circle(Vector2.ZERO, 56.0, Color(0.82, 0.8, 0.78))
	c.draw_set_transform(Vector2.ZERO)
	var cup: PackedVector2Array = PackedVector2Array([foot + Vector2(-34, -54), foot + Vector2(34, -54), foot + Vector2(26, -6), foot + Vector2(-26, -6)])
	c.draw_colored_polygon(cup, Color(0.9, 0.88, 0.84))
	c.draw_arc(foot + Vector2(40, -36), 13.0, -PI * 0.5, PI * 0.5, 12, Color(0.85, 0.83, 0.8), 5.0)
	c.draw_set_transform(foot + Vector2(0, -54), 0.0, Vector2(1.0, 0.25))
	c.draw_circle(Vector2.ZERO, 34.0, Color(0.42, 0.28, 0.18))
	c.draw_set_transform(Vector2.ZERO)
	for wisp: int in range(3):
		var points: PackedVector2Array = PackedVector2Array()
		var phase: float = time * 0.9 + wisp * 2.1
		for i: int in range(24):
			var t: float = i / 23.0
			points.append(foot + Vector2(-14 + wisp * 14 + sin(t * 5.0 + phase) * 9.0 * t, -64 - t * 130.0))
		var fade: float = 0.5 + 0.5 * sin(time * 0.7 + wisp)
		c.draw_polyline(points, Color(1, 1, 1, 0.1 * fade), 4.0, true)


# A sheer curtain, swaying a little in the draught from the old window.
func _draw_curtain(c: Control, left: float, right: float, side: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 30
	for i: int in range(steps + 1):
		var y: float = 92.0 + (900.0 - 92.0) * i / float(steps)
		var sway: float = sin(y * 0.008 + time * 0.55) * 10.0 * (i / float(steps)) * side
		points.append(Vector2((right if side > 0.0 else left) + sway, y))
	for i: int in range(steps, -1, -1):
		var y: float = 92.0 + (900.0 - 92.0) * i / float(steps)
		var sway: float = sin(y * 0.008 + time * 0.55 + 0.8) * 6.0 * (i / float(steps))
		points.append(Vector2((left if side > 0.0 else right) + sway, y))
	c.draw_colored_polygon(points, Color(0.82, 0.84, 0.9, 0.16))
	for fold: int in range(5):
		var x: float = lerpf(left, right, (fold + 0.5) / 5.0)
		var line: PackedVector2Array = PackedVector2Array()
		for i: int in range(steps + 1):
			var y: float = 92.0 + (900.0 - 92.0) * i / float(steps)
			line.append(Vector2(x + sin(y * 0.008 + time * 0.55 + fold) * 7.0 * (i / float(steps)), y))
		c.draw_polyline(line, Color(1, 1, 1, 0.07), 3.0, true)


# ---------- helpers ----------

func _layer(parent: Control, rect: Rect2) -> Control:
	var layer: Control = Control.new()
	layer.position = rect.position
	layer.size = rect.size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer


func _snow(area: Vector2) -> CPUParticles2D:
	var snow: CPUParticles2D = CPUParticles2D.new()
	snow.texture = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 1.0], 12)
	snow.amount = 170
	snow.lifetime = 9.0
	snow.preprocess = 9.0
	snow.position = Vector2(area.x * 0.5 + 60.0, -20.0)
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(area.x * 0.7, 10.0)
	snow.direction = Vector2(-0.25, 1.0)
	snow.spread = 14.0
	snow.gravity = Vector2(-4.0, 10.0)
	snow.initial_velocity_min = 40.0
	snow.initial_velocity_max = 95.0
	snow.scale_amount_min = 0.25
	snow.scale_amount_max = 0.9
	snow.color = Color(1, 1, 1, 0.85)
	return snow


# Specks of dust turning slowly in the moonlight.
func _dust() -> CPUParticles2D:
	var dust: CPUParticles2D = CPUParticles2D.new()
	dust.texture = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 1.0], 8)
	dust.amount = 40
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.position = Vector2(820, 640)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(420, 300)
	dust.direction = Vector2(0.3, -1.0)
	dust.spread = 180.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 10.0
	dust.scale_amount_min = 0.3
	dust.scale_amount_max = 0.7
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(0.8, 0.85, 1, 0), Color(0.8, 0.85, 1, 0.35), Color(0.8, 0.85, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	dust.color_ramp = fade
	return dust


func _radial(colors: Array, offsets: Array, size_px: int = 256) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array(offsets)
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = size_px
	texture.height = size_px
	return texture


# The rect that covers `area` with an image of `image_size`, keeping its shape.
static func _cover(image_size: Vector2, area: Rect2) -> Rect2:
	var scale_value: float = maxf(area.size.x / image_size.x, area.size.y / image_size.y)
	var drawn: Vector2 = image_size * scale_value
	return Rect2(area.get_center() - drawn * 0.5, drawn)
