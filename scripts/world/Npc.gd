extends StaticBody2D
## A grey-box person standing in a map. Like a prop, the node's position is where the feet touch
## the floor, and only a small circle at the feet blocks movement, so James can walk behind them.
## Talking is handled by a Hotspot placed at the same spot (give both the same "when it exists" settings).

const StoryVisibility := preload("res://scripts/story/StoryVisibility.gd")
const FADE_SECONDS: float = 0.6

@export var color: Color = Color(0.42, 0.36, 0.56)
@export var label: String = ""
@export var footprint_radius: float = 22.0

@export_group("When they are here")
## The times of day this person is here. Empty = always.
@export var phases: PackedStringArray = PackedStringArray()
@export var show_if_flag: String = ""
@export var hide_if_flag: String = ""

var shown: bool = true
var _fade: Tween


func _ready() -> void:
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = footprint_radius
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.state_reset.connect(_refresh_visibility.bind(true))
	_refresh_visibility(false)
	queue_redraw()


# People fade in and out (0.6 s) when the story moves them. When the map first loads they are
# simply there or not.
func _refresh_visibility(animate: bool) -> void:
	var now_shown: bool = StoryVisibility.is_shown(phases, show_if_flag, hide_if_flag)
	if now_shown == shown and (animate or _fade != null):
		return
	shown = now_shown
	collision_layer = 1 if shown else 0   # "world": a person who is not here blocks nothing
	if _fade != null:
		_fade.kill()
	if not animate or not is_inside_tree():
		modulate.a = 1.0 if shown else 0.0
		visible = shown
		return
	visible = true
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0 if shown else 0.0, FADE_SECONDS)
	if not shown:
		_fade.tween_callback(hide)


## Walks this person to `target` (in a cutscene). Await it to wait until they get there.
## Their talk hotspot (a sibling with "Spot" after the name, for example "Bellamy" and "BellamySpot")
## walks with them.
func walk_to(target: Vector2, speed: float = 240.0) -> void:
	var seconds: float = global_position.distance_to(target) / maxf(speed, 1.0)
	if seconds <= 0.0:
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", target, seconds)
	var spot: Node2D = get_parent().get_node_or_null(NodePath(str(name) + "Spot")) as Node2D
	if spot != null:
		tween.parallel().tween_property(spot, "global_position", target, seconds)
	await tween.finished


func _on_flag_changed(_flag_id: String, _on: bool) -> void:
	_refresh_visibility(true)


func _on_phase_changed(_phase: String) -> void:
	_refresh_visibility(true)


func _draw() -> void:
	# Same build as James: origin at the feet, about 128 px tall.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 36, Color(0, 0, 0, 0.35))   # ground shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-26, -96, 52, 88), color)                           # coat
	draw_rect(Rect2(-26, -96, 52, 88), Color(0.1, 0.12, 0.2), false, 3.0)
	draw_circle(Vector2(0, -112), 20, Color(0.93, 0.78, 0.65))          # head
	draw_arc(Vector2(0, -112), 20, 0, TAU, 24, Color(0.1, 0.12, 0.2), 3.0)
	if label != "":
		var font := ThemeDB.fallback_font
		var width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(-width / 2.0, -144), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85))
