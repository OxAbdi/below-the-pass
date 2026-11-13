extends StaticBody2D
## A grey-box person standing in a map. Like a prop, the node's position is where the feet touch
## the floor, and only a small circle at the feet blocks movement, so James can walk behind them.
## Talking is handled by an Interactable placed at the same spot.

@export var color: Color = Color(0.42, 0.36, 0.56)
@export var label: String = ""
@export var footprint_radius: float = 22.0


func _ready() -> void:
	collision_layer = 1   # "world"
	collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = footprint_radius
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	queue_redraw()


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
