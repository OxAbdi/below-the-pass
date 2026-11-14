extends Area2D
## An open way out of a map: a street end, an archway. Walking into it moves James to another map.
## (A door James has to press a key on is a Hotspot with action "door" instead.)
## Give it a CollisionShape2D child, or leave it without one and set `size`.

signal entered(exit: Node)

const StoryVisibility := preload("res://scripts/story/StoryVisibility.gd")

@export var to_map: String = ""
@export var to_spawn: String = ""
@export var size: Vector2 = Vector2(80.0, 300.0)

@export_group("When it exists")
@export var phases: PackedStringArray = PackedStringArray()
@export var show_if_flag: String = ""
@export var hide_if_flag: String = ""

var shown: bool = true


func _ready() -> void:
	add_to_group("exits")
	collision_layer = 0
	if not has_node("CollisionShape2D"):
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = size
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.name = "CollisionShape2D"
		collider.shape = shape
		add_child(collider)
	body_entered.connect(_on_body_entered)
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.state_reset.connect(refresh_visibility)
	refresh_visibility()


func refresh_visibility() -> void:
	shown = StoryVisibility.is_shown(phases, show_if_flag, hide_if_flag)
	collision_mask = 2 if shown else 0   # sees layer 2 "player"


func _on_body_entered(_body: Node) -> void:
	if shown:
		entered.emit(self)


func _on_flag_changed(_flag_id: String, _on: bool) -> void:
	refresh_visibility()


func _on_phase_changed(_phase: String) -> void:
	refresh_visibility()
