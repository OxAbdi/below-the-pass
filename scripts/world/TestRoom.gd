extends Node2D
## Milestone 2 grey-box room. It wires the pieces together:
## interactable -> dialogue box, dialogue open -> player frozen, L -> lighting.

const PlayerScript := preload("res://scripts/world/Player.gd")
const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")

@export var room_size: Vector2 = Vector2(2560, 1440)

@onready var player: PlayerScript = $World/Player
@onready var camera: Camera2D = $Camera2D
@onready var dialogue: DialogueBoxScript = $UI/DialogueBox
@onready var tint: CanvasModulate = $Tint
@onready var lamp_light: PointLight2D = $World/Lamp/PointLight2D
@onready var info: Label = $UI/Info
@onready var fps_label: Label = $UI/Fps

## How quickly the camera catches up to James. Higher = tighter.
@export var camera_follow_speed: float = 9.0
const CAMERA_HEIGHT_OFFSET := Vector2(0, -60)

const BUILD := "M2 build 6"   # shown on screen, so we know which version is running

const NIGHT_COLOR := Color(0.3, 0.36, 0.56)
const DAY_COLOR := Color(0.86, 0.88, 0.98)

var night: bool = true


func _ready() -> void:
	process_priority = 10   # run AFTER James has moved this frame, so the camera never lags a frame behind
	# We keep the camera inside the room ourselves (see _clamp_camera). The
	# engine's built-in limits are switched off so the two can never disagree.
	# Safety: if any other camera is hiding inside James, remove it. One camera only.
	for old_camera in player.find_children("*", "Camera2D", true, false):
		old_camera.queue_free()
	camera.make_current()
	camera.set("limit_enabled", false)   # property exists in newer Godot; ignored on older
	camera.position_smoothing_enabled = false
	camera.global_position = _clamp_camera(player.global_position + CAMERA_HEIGHT_OFFSET)
	for node in get_tree().get_nodes_in_group("interactables"):
		node.interacted.connect(_on_interacted)
	dialogue.dialogue_finished.connect(_on_dialogue_finished)
	player.facing_changed.connect(func(_n: String) -> void: _refresh_info())
	_refresh_info()


func _process(delta: float) -> void:
	# James and the camera both update once per frame, James first (see process_priority).
	var target: Vector2 = player.global_position + CAMERA_HEIGHT_OFFSET
	var t: float = 1.0 - exp(-camera_follow_speed * delta)
	camera.global_position = _clamp_camera(camera.global_position.lerp(target, t))
	fps_label.text = "FPS: %d   %s" % [Engine.get_frames_per_second(), BUILD]


## Keeps the camera's centre far enough from the room edges that the screen
## never shows anything outside the room.
func _clamp_camera(wanted: Vector2) -> Vector2:
	var half: Vector2 = get_viewport_rect().size / camera.zoom / 2.0
	var result := wanted
	if room_size.x <= half.x * 2.0:
		result.x = room_size.x / 2.0
	else:
		result.x = clampf(wanted.x, half.x, room_size.x - half.x)
	if room_size.y <= half.y * 2.0:
		result.y = room_size.y / 2.0
	else:
		result.y = clampf(wanted.y, half.y, room_size.y - half.y)
	return result


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_lighting"):
		set_lighting(not night)


func set_lighting(on: bool) -> void:
	night = on
	tint.color = NIGHT_COLOR if night else DAY_COLOR
	lamp_light.visible = night
	_refresh_info()


func _on_interacted(dialogue_id: String) -> void:
	player.set_frozen(true)
	dialogue.play_dialogue(dialogue_id)


func _on_dialogue_finished() -> void:
	player.set_frozen(false)


func _refresh_info() -> void:
	info.text = "Move: WASD / arrows / left stick     Interact: E / pad A     Lighting (%s): L     Facing: %s" % [
		"NIGHT" if night else "DAY", player.facing_name()]
