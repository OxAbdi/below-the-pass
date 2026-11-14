extends Area2D
## Anything James can press "interact" on: an object to look at, a person to talk to, a door.
## It does nothing by itself. It tells the Game it was used, and the Game decides what happens.
##
## What it does is set by `action`:
##   conversation  play `target` (a file name in data/dialogue/)
##   loupe         open the photo puzzle `target` (a file name in data/puzzles/)
##   board         open the case board
##   overlay       open the full-screen view `target` (Milestone 6 part B)
##   door          walk through to `to_map` / `to_spawn` (or play `locked_conversation` if it is shut)

signal used(hotspot: Node)

const StoryRules := preload("res://scripts/story/StoryRules.gd")
const StoryVisibility := preload("res://scripts/story/StoryVisibility.gd")

@export_enum("conversation", "loupe", "board", "door", "overlay") var action: String = "conversation"
@export var target: String = ""
@export var prompt_text: String = "Examine"
@export var reach_radius: float = 70.0

@export_group("Door")
@export var to_map: String = ""
@export var to_spawn: String = ""
## Played instead of going through, while the door is shut.
@export var locked_conversation: String = ""
## The door is shut until this flag is on. Empty = no flag needed.
@export var open_if_flag: String = ""
## The door is shut until this condition passes. Written as JSON, for example {"has_evidence": "ch01_whisky"}.
@export_multiline var open_if: String = ""

@export_group("When it exists")
## The times of day this exists in. Empty = always.
@export var phases: PackedStringArray = PackedStringArray()
@export var show_if_flag: String = ""
@export var hide_if_flag: String = ""

@export_group("Camera (part B)")
@export var shot_id: String = ""

var prompt: Label
var shown: bool = true


func _ready() -> void:
	add_to_group("hotspots")
	collision_mask = 0
	if not has_node("CollisionShape2D"):
		var shape: CircleShape2D = CircleShape2D.new()
		shape.radius = reach_radius
		var collider: CollisionShape2D = CollisionShape2D.new()
		collider.name = "CollisionShape2D"
		collider.shape = shape
		add_child(collider)
	prompt = get_node_or_null("Prompt") as Label
	if prompt == null:
		prompt = _make_prompt()
		add_child(prompt)
	prompt.text = "[E]  " + prompt_text
	prompt.visible = false
	GameState.flag_changed.connect(_on_flag_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.state_reset.connect(refresh_visibility)
	refresh_visibility()


func interact() -> void:
	if shown:
		used.emit(self)


func set_prompt_visible(value: bool) -> void:
	prompt.visible = value and shown


## A door is open when its flag is on (if it has one) and its condition passes (if it has one).
func is_open() -> bool:
	if open_if_flag != "" and not GameState.has_flag(open_if_flag):
		return false
	return StoryRules.check(StoryRules.parse_condition(open_if))


func refresh_visibility() -> void:
	shown = StoryVisibility.is_shown(phases, show_if_flag, hide_if_flag)
	# A hidden hotspot cannot be found by James's reach at all.
	collision_layer = 4 if shown else 0   # layer 3 "interactables"
	if not shown:
		prompt.visible = false


func _on_flag_changed(_flag_id: String, _on: bool) -> void:
	refresh_visibility()


func _on_phase_changed(_phase: String) -> void:
	refresh_visibility()


func _make_prompt() -> Label:
	var label: Label = Label.new()
	label.name = "Prompt"
	label.position = Vector2(-120.0, -220.0)
	label.size = Vector2(240.0, 30.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", 26)
	label.z_index = 50
	return label
