extends CharacterBody2D
## James. Free 360-degree movement (keyboard, d-pad or analogue stick),
## 8-way facing, and an interaction reach. Placeholder art is drawn in code.

signal facing_changed(direction_name: String)

const DIRECTION_NAMES: Array[String] = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]

@export var max_speed: float = 620.0
@export var acceleration: float = 5200.0
@export var friction: float = 6000.0

var frozen: bool = false
var facing_index: int = 2          # start facing South (toward the camera)
var current_target: Node = null    # the interactable in reach, if any

@onready var reach: Area2D = $InteractReach


func _ready() -> void:
	collision_layer = 2   # "player"
	collision_mask = 1    # bumps into "world"
	reach.collision_layer = 0
	reach.collision_mask = 4   # sees "interactables"
	queue_redraw()


func set_frozen(value: bool) -> void:
	frozen = value
	if frozen:
		velocity = Vector2.ZERO
		_update_target(null)


## James moves once per drawn frame (not on the physics clock), so he and the
## camera share one clock and can never drift apart (that drift = vibration).
func _process(raw_delta: float) -> void:
	if frozen:
		return
	var delta: float = minf(raw_delta, 1.0 / 30.0)   # a lag spike must not let him jump through a wall
	# get_vector handles keyboard, d-pad and stick; it also clamps length to 1,
	# so a diagonal is never faster than straight.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input != Vector2.ZERO:
		velocity = velocity.move_toward(input * max_speed, acceleration * delta)
		_set_facing(input.angle())
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()
	_update_target(_nearest_interactable())


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event.is_action_pressed("interact") and current_target != null:
		get_viewport().set_input_as_handled()
		current_target.interact()


func _set_facing(angle: float) -> void:
	var index := int(round(angle / (TAU / 8.0))) % 8
	if index < 0:
		index += 8
	if index != facing_index:
		facing_index = index
		facing_changed.emit(DIRECTION_NAMES[facing_index])
		queue_redraw()


func facing_name() -> String:
	return DIRECTION_NAMES[facing_index]


func _nearest_interactable() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for area in reach.get_overlapping_areas():
		var d: float = global_position.distance_to(area.global_position)
		if d < best_dist:
			best_dist = d
			best = area
	return best


func _update_target(target: Node) -> void:
	if target == current_target:
		return
	if current_target != null and current_target.has_method("set_prompt_visible"):
		current_target.set_prompt_visible(false)
	current_target = target
	if current_target != null and current_target.has_method("set_prompt_visible"):
		current_target.set_prompt_visible(true)


func _draw() -> void:
	# Origin is at the feet. Sprite is about 128 px tall.
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 36, Color(0, 0, 0, 0.35))   # ground shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(-26, -96, 52, 88), Color(0.36, 0.50, 0.65))        # coat
	draw_rect(Rect2(-26, -96, 52, 88), Color(0.1, 0.12, 0.2), false, 3.0)
	draw_circle(Vector2(0, -112), 20, Color(0.93, 0.78, 0.65))          # head
	draw_arc(Vector2(0, -112), 20, 0, TAU, 24, Color(0.1, 0.12, 0.2), 3.0)
	# facing arrow, snapped to the 8 directions
	var a := facing_index * (TAU / 8.0)
	var dir := Vector2.from_angle(a)
	var centre := Vector2(0, -52)
	var tip := centre + dir * 44
	var side := dir.orthogonal() * 10
	draw_colored_polygon(PackedVector2Array([tip, centre + dir * 22 + side, centre + dir * 22 - side]),
		Color(0.85, 0.68, 0.30))
