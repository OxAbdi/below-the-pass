extends StaticBody2D
## A wall James cannot pass that says why: a snowdrift, a fence, a closed road.
## When he walks into it, `conversation` plays (at most once every 8 seconds, so it never nags).
## Like a prop, the node's position is where it touches the floor.

signal bumped(blocker: Node)

const BUMP_GAP_SECONDS: float = 8.0
const SENSE_MARGIN: float = 14.0

@export var size: Vector2 = Vector2(120.0, 400.0)   ## width and depth of the wall on the floor
@export var conversation: String = ""
@export var color: Color = Color(0.86, 0.9, 0.96)
@export var label: String = "SNOW"

var _last_bump_msec: int = -100000


func _ready() -> void:
	add_to_group("blockers")
	collision_layer = 1   # "world"
	collision_mask = 0
	var wall: RectangleShape2D = RectangleShape2D.new()
	wall.size = size
	var collider: CollisionShape2D = CollisionShape2D.new()
	collider.shape = wall
	collider.position = Vector2(0.0, -size.y * 0.5)
	add_child(collider)
	# A slightly bigger invisible area around the wall notices James touching it.
	var sense: RectangleShape2D = RectangleShape2D.new()
	sense.size = size + Vector2.ONE * SENSE_MARGIN * 2.0
	var sense_collider: CollisionShape2D = CollisionShape2D.new()
	sense_collider.shape = sense
	sense_collider.position = collider.position
	var area: Area2D = Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2   # sees layer 2 "player"
	area.add_child(sense_collider)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	queue_redraw()


func _on_body_entered(_body: Node) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_bump_msec < int(BUMP_GAP_SECONDS * 1000.0):
		return
	_last_bump_msec = now
	bumped.emit(self)


## Lets the next touch speak at once (used by tests, and after a map loads).
func reset_gap() -> void:
	_last_bump_msec = -100000


func _draw() -> void:
	var body: Rect2 = Rect2(-size.x * 0.5, -size.y, size.x, size.y)
	draw_rect(body, color)
	draw_rect(Rect2(body.position, Vector2(size.x, 14.0)), color.lightened(0.4))
	draw_rect(body, color.darkened(0.3), false, 3.0)
	if label != "":
		draw_string(ThemeDB.fallback_font, Vector2(-size.x * 0.5 + 8.0, -size.y * 0.5 + 8.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 22, Color(0.2, 0.25, 0.35, 0.85))
