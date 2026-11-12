extends StaticBody2D
## A grey-box prop: a coloured block with an "origin at the feet" rule.
##
## The node's position is where the prop touches the floor. The block is drawn
## UP from that point, and only a thin strip at the bottom blocks movement.
## That is what lets James walk "behind" a tall prop (its top is just picture).

@export var size: Vector2 = Vector2(160, 120)   ## width, height of the picture
@export var footprint_depth: float = 40.0       ## how deep the blocking strip is
@export var color: Color = Color(0.48, 0.31, 0.25)
@export var label: String = ""


func _ready() -> void:
	collision_layer = 1   # "world"
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = Vector2(size.x, footprint_depth)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -footprint_depth / 2.0)
	add_child(collider)
	queue_redraw()


func _draw() -> void:
	var body := Rect2(-size.x / 2.0, -size.y, size.x, size.y)
	draw_rect(body, color)
	# lighter top strip so it reads as a 3D block
	draw_rect(Rect2(body.position, Vector2(size.x, 14)), color.lightened(0.25))
	draw_rect(body, color.darkened(0.45), false, 3.0)
	if label != "":
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-size.x / 2.0 + 8, -size.y / 2.0 + 8), label,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 22, Color(1, 1, 1, 0.85))
