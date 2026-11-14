extends Node
## Makes a map look like the right time of day. One of these sits in every map.
##
##   - lights in group "mains" are on only when the phase has power
##   - lights in group "candles" are on only when the phase has candles
##   - the whole map is tinted (a CanvasModulate) with the colour from maps.json
##   - outside maps get falling snow: heavy, light or none
##
## The Game calls apply() when the map loads and whenever GameState.phase changes.

const TINT_SECONDS: float = 1.0
const SCREEN_AREA: float = 1920.0 * 1080.0
const FLAKES: Dictionary = { "heavy": 220, "light": 60 }

var _tint: CanvasModulate
var _snow: CPUParticles2D
var _tween: Tween


func apply(info: Dictionary, tint: Color, exterior: bool, instant: bool) -> void:
	var map: Node = get_parent()
	for light: Node in get_tree().get_nodes_in_group("mains"):
		if map.is_ancestor_of(light) and light is CanvasItem:
			(light as CanvasItem).visible = bool(info.get("power", true))
	for light: Node in get_tree().get_nodes_in_group("candles"):
		if map.is_ancestor_of(light) and light is CanvasItem:
			(light as CanvasItem).visible = bool(info.get("candles", false))
	_apply_tint(tint, instant or bool(info.get("instant", false)))
	_apply_snow(str(info.get("snow", "none")) if exterior else "none")


func current_tint() -> Color:
	return _tint.color if _tint != null else Color.WHITE


func snow_amount() -> int:
	return _snow.amount if _snow != null and _snow.emitting else 0


func _apply_tint(tint: Color, instant: bool) -> void:
	if _tint == null:
		_tint = CanvasModulate.new()
		_tint.color = tint
		get_parent().add_child(_tint)
		return
	if _tween != null:
		_tween.kill()
	if instant:
		_tint.color = tint
		return
	_tween = create_tween()
	_tween.tween_property(_tint, "color", tint, TINT_SECONDS)


func _apply_snow(kind: String) -> void:
	if not FLAKES.has(kind):
		if _snow != null:
			_snow.emitting = false
		return
	var bounds: Rect2 = get_parent().camera_bounds()
	if _snow == null:
		_snow = CPUParticles2D.new()
		_snow.z_index = 100
		_snow.texture = _flake_texture()
		_snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_snow.direction = Vector2(-0.25, 1.0)
		_snow.spread = 12.0
		_snow.gravity = Vector2(-6.0, 14.0)
		_snow.initial_velocity_min = 45.0
		_snow.initial_velocity_max = 110.0
		_snow.scale_amount_min = 0.35
		_snow.scale_amount_max = 1.0
		_snow.lifetime = 7.0
		_snow.preprocess = 7.0
		var fade: Gradient = Gradient.new()
		fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
		fade.offsets = PackedFloat32Array([0.0, 0.12, 0.8, 1.0])
		_snow.color_ramp = fade
		get_parent().add_child(_snow)
	_snow.position = bounds.get_center() - Vector2(0.0, 220.0)
	_snow.emission_rect_extents = bounds.size * 0.5 + Vector2(200.0, 0.0)
	# The flake count in the data is "per screen", so a wide street gets more of them.
	var wanted: int = maxi(1, int(round(float(FLAKES[kind]) * bounds.get_area() / SCREEN_AREA)))
	if _snow.amount != wanted:
		_snow.amount = wanted
	_snow.emitting = true


func _flake_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 12
	texture.height = 12
	return texture
