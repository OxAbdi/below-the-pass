extends Control

# The painted title screen: one finished painting, brought to life.
#
#   the painting    a shader moves the curtains and blows the blizzard across the glass (shaders/title_painting.gdshader)
#   the lights      the lit windows in the storm glow and flicker
#   the cup         steam rises from the tea and bends in the draught
#   the camera      a glint slides across the lens now and then
#   the room        large soft flakes drift past, out of focus, in front of everything
#
# Where everything sits is set in data/ui/title.json under "painting", in painting pixels,
# so a new painting only needs new numbers and new files. No code changes.
#
# TitleBackdrop owns this and calls setup(). It returns false when a file is missing,
# and the backdrop falls back to its own stand-in.

const SHADER_PATH: String = "res://shaders/title_painting.gdshader"

var gust: float = 0.5            # 0 calm .. 1 hard blast. Drives curtains, flakes and steam together.
var time: float = 0.0
var wake: float = 1.0            # 0 .. 1: the picture "wakes up" when the title appears (snow and cloth start still, then stir)

var _image_size: Vector2 = Vector2(2576.0, 1438.0)
var _art: TextureRect
var _material: ShaderMaterial
var _fx: Control                 # additive light: windows, glint, steam
var _glow: GradientTexture2D
var _lights: Array = []
var _mug: Vector2 = Vector2.ZERO
var _glint_at: Vector2 = Vector2.ZERO
var _wind_phase: float = 0.0
var _curtain_base: float = 12.0
var _room: CPUParticles2D
var _steam: Array[Dictionary] = []
var _steam_timer: float = 0.0
var _glint_timer: float = 4.0
var _glint_age: float = -1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# `config` is the "painting" block of title.json. Returns false (and builds nothing) if a file is missing.
func setup(config: Dictionary) -> bool:
	var image_path: String = str(config.get("image", ""))
	var masks_path: String = str(config.get("masks", ""))
	if image_path == "" or masks_path == "" or not ResourceLoader.exists(image_path) or not ResourceLoader.exists(masks_path) or not ResourceLoader.exists(SHADER_PATH):
		return false
	var picture: Texture2D = load(image_path)
	var masks: Texture2D = load(masks_path)
	var shader: Shader = load(SHADER_PATH)
	if picture == null or masks == null or shader == null:
		return false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size_list: Array = config.get("size", [picture.get_width(), picture.get_height()])
	_image_size = Vector2(float(size_list[0]), float(size_list[1]))
	_rng.seed = 21

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("masks", masks)
	_material.set_shader_parameter("image_px", _image_size)
	_curtain_base = float(config.get("curtain_px", 12.0))
	_material.set_shader_parameter("curtain_px", _curtain_base)
	_art = TextureRect.new()
	_art.texture = picture
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.material = _material
	var cover: Rect2 = art_rect()
	_art.position = cover.position
	_art.size = cover.size
	add_child(_art)

	_lights = config.get("lights", [])
	_mug = _point(config.get("mug", [0, 0]))
	_glint_at = _point(config.get("glint", [0, 0]))
	_glow = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)], [0.0, 0.3, 1.0])
	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx.material = additive
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_room = _room_flakes()
	add_child(_room)
	return true


# Where the painting sits on screen: it fills the screen and keeps its shape.
func art_rect() -> Rect2:
	var area: Vector2 = Vector2(1920.0, 1080.0)
	var factor: float = maxf(area.x / _image_size.x, area.y / _image_size.y)
	var drawn: Vector2 = _image_size * factor
	return Rect2((area - drawn) * 0.5, drawn)


# A point in painting pixels -> a point on screen.
func to_screen(painting_point: Vector2) -> Vector2:
	var cover: Rect2 = art_rect()
	return cover.position + painting_point / _image_size * cover.size


func _point(value: Variant) -> Vector2:
	var list: Array = value if value is Array else [0, 0]
	return Vector2(float(list[0]), float(list[1]))


func _process(delta: float) -> void:
	if _material == null:
		return
	time += delta
	# Wind: slow swells, a quicker flutter, and now and then a hard gust.
	gust = clampf(0.42 + 0.26 * sin(time * 0.37) + 0.18 * sin(time * 0.91 + 1.3) + 0.1 * sin(time * 2.3 + 0.4) + 0.2 * maxf(0.0, sin(time * 0.13 + 2.0) - 0.55) * 3.0, 0.0, 1.0)
	_wind_phase += delta * (0.55 + 1.1 * gust)
	var lamp: float = 0.97 + 0.04 * sin(time * 1.9) + 0.025 * sin(time * 5.3 + 1.1) + 0.015 * sin(time * 11.0)
	_material.set_shader_parameter("time_s", time)
	_material.set_shader_parameter("wind_phase", _wind_phase)
	_material.set_shader_parameter("gust", gust)
	_material.set_shader_parameter("lamp_flicker", lamp)
	var stir: float = wake * wake * (3.0 - 2.0 * wake)
	_material.set_shader_parameter("snow_amount", lerpf(0.12, 1.0, stir))
	_material.set_shader_parameter("curtain_px", _curtain_base * lerpf(0.3, 1.0, stir))
	_room.modulate.a = stir
	_update_steam(delta)
	_update_glint(delta)
	_fx.queue_redraw()


# ---------- steam ----------

func _update_steam(delta: float) -> void:
	_steam_timer -= delta
	if _steam_timer <= 0.0:
		_steam_timer = _rng.randf_range(0.28, 0.5)
		_steam.append({ "age": 0.0, "life": _rng.randf_range(3.2, 4.6), "seed": _rng.randf() * 10.0, "x": _rng.randf_range(-14.0, 14.0) })
	var kept: Array[Dictionary] = []
	for puff: Dictionary in _steam:
		puff["age"] = float(puff["age"]) + delta
		if float(puff["age"]) < float(puff["life"]):
			kept.append(puff)
	_steam = kept


# ---------- glint ----------

func _update_glint(delta: float) -> void:
	if _glint_age >= 0.0:
		_glint_age += delta
		if _glint_age > 1.1:
			_glint_age = -1.0
			_glint_timer = _rng.randf_range(6.0, 11.0)
		return
	_glint_timer -= delta
	if _glint_timer <= 0.0:
		_glint_age = 0.0


# ---------- drawing the light ----------

func _draw_fx() -> void:
	var scale_value: float = art_rect().size.x / _image_size.x
	# Lit windows and lamps in the storm.
	for index: int in range(_lights.size()):
		var info: Dictionary = _lights[index]
		var at: Vector2 = to_screen(_point(info.get("at", [0, 0])))
		var radius: float = float(info.get("radius", 40.0)) * scale_value
		var tint: Color = Color.html(str(info.get("color", "#ffb866")))
		var strength: float = float(info.get("strength", 0.8))
		var seed_value: float = float(index) * 3.7
		# A warm light seen through blowing snow dims and flares as the flakes pass in front of it.
		var flicker: float = 0.78 + 0.1 * sin(time * 2.1 + seed_value) + 0.07 * sin(time * 6.3 + seed_value * 1.9) + 0.05 * sin(time * 13.0 + seed_value) - 0.18 * gust * absf(sin(time * 3.1 + seed_value))
		_fx.draw_texture_rect(_glow, Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(tint, strength * flicker))
		_fx.draw_texture_rect(_glow, Rect2(at - Vector2(radius * 0.4, radius * 0.4), Vector2(radius, radius) * 0.8), false, Color(1.0, 0.95, 0.85, 0.55 * strength * flicker))
		if bool(info.get("flare", false)):
			var length: float = radius * 6.0
			_fx.draw_texture_rect(_glow, Rect2(at - Vector2(length, radius * 0.18), Vector2(length * 2.0, radius * 0.36)), false, Color(tint, 0.38 * strength * flicker))
	# Steam from the cup.
	var cup: Vector2 = to_screen(_mug)
	for puff: Dictionary in _steam:
		var age: float = float(puff["age"]) / float(puff["life"])
		var rise: float = age * 150.0 * scale_value * 1.4
		var drift: float = sin(float(puff["age"]) * 1.4 + float(puff["seed"])) * (10.0 + 24.0 * age) - gust * 36.0 * age
		var where: Vector2 = cup + Vector2(float(puff["x"]) * scale_value + drift, -rise)
		var width: float = (18.0 + 52.0 * age) * scale_value * 1.3
		var alpha: float = sin(age * PI) * (0.1 + 0.05 * (1.0 - gust))
		_fx.draw_texture_rect(_glow, Rect2(where - Vector2(width, width) * 0.5, Vector2(width, width)), false, Color(0.85, 0.9, 1.0, alpha))
	# The glint across the lens.
	if _glint_age >= 0.0:
		var t: float = _glint_age / 1.1
		var center: Vector2 = to_screen(_point_from_config_glint(t))
		var pulse: float = sin(t * PI)
		var arm: float = 46.0 * scale_value * pulse
		_fx.draw_texture_rect(_glow, Rect2(center - Vector2(20, 20) * scale_value, Vector2(40, 40) * scale_value), false, Color(1, 0.97, 0.9, 0.5 * pulse))
		_fx.draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0), Color(1, 0.97, 0.9, 0.55 * pulse), 1.4)
		_fx.draw_line(center - Vector2(0, arm * 0.7), center + Vector2(0, arm * 0.7), Color(1, 0.97, 0.9, 0.4 * pulse), 1.2)


# The glint travels a little way along the top of the lens.
func _point_from_config_glint(t: float) -> Vector2:
	var center: Vector2 = _glint_at
	return center + Vector2(lerpf(-26.0, 26.0, t), lerpf(8.0, -8.0, t))


# ---------- flakes in the room ----------

# Big soft flakes, out of focus, drifting past in front of the painting.
func _room_flakes() -> CPUParticles2D:
	var flakes: CPUParticles2D = CPUParticles2D.new()
	flakes.texture = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)], [0.0, 0.4, 1.0], 32)
	flakes.amount = 46
	flakes.lifetime = 12.0
	flakes.preprocess = 12.0
	flakes.position = Vector2(1100.0, -30.0)
	flakes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	flakes.emission_rect_extents = Vector2(1300.0, 10.0)
	flakes.direction = Vector2(-0.35, 1.0)
	flakes.spread = 12.0
	flakes.gravity = Vector2(-6.0, 14.0)
	flakes.initial_velocity_min = 50.0
	flakes.initial_velocity_max = 110.0
	flakes.scale_amount_min = 0.12
	flakes.scale_amount_max = 0.42
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.85, 1.0])
	flakes.color_ramp = fade
	return flakes


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
