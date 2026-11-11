extends Control

# LoupeExamination.gd - attach to the ROOT node of the loupe scene.
#
# What it does:
#   - Scroll wheel zooms toward the mouse cursor. Left-click and drag pans the photo.
#   - Reads the puzzle from JSON (photo, zoom limits, clue circles) and the clue
#     names from the evidence registry. No clue data is written in this script.
#   - Clicking a clue circle (zoomed in far enough) calls GameState.collect_evidence().
#     That makes GameState emit its evidence_added signal, and this scene listens
#     to that signal to show the feedback (gold ring, message box, print message).
#
# Input only changes the TARGET zoom and position. _process() then glides the
# photo toward those targets a little every frame.

signal all_clues_found

const DialogueBoxScene: PackedScene = preload("res://scenes/ui/dialogue/dialogue_box.tscn")
const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")

@export_file("*.json") var puzzle_path: String = "res://data/puzzles/ch01_loupe.json"
@export_file("*.json") var evidence_registry_path: String = "res://data/evidence/evidence_registry.json"
# Shows a dim red circle over every clue that has not been found yet. Press H in game to toggle.
@export var show_debug_hotspots: bool = true

# These three are the defaults. The puzzle JSON overrides them.
@export var min_zoom: float = 1.0
@export var max_zoom: float = 6.0
@export var zoom_step: float = 1.15
# Higher = snappier, lower = floatier. Around 8 to 20 feels good.
@export var smoothing: float = 12.0

# The glide stops once the photo is within this many SCREEN pixels of its target.
const SETTLE_PIXELS: float = 0.1
# A click that moves the mouse further than this (in pixels) counts as a drag, not a click.
const CLICK_TRAVEL_LIMIT: float = 8.0
# Extra screen pixels around a clue circle that still count as a hit.
const CLICK_FORGIVENESS_PX: float = 14.0
const PULSE_SECONDS: float = 0.9
const PULSE_GROWTH_PX: float = 90.0
const MESSAGE_HOLD_SECONDS: float = 3.0
const FOUND_COLOR: Color = Color(1.0, 0.82, 0.25)
const DEBUG_COLOR: Color = Color(1.0, 0.3, 0.3, 0.55)


# One clickable clue circle, in PHOTO pixels (so it moves and scales with the photo).
class ClueTarget extends RefCounted:
	var evidence_id: String = ""
	var center_px: Vector2 = Vector2.ZERO
	var radius_px: float = 0.0
	var min_zoom: float = 1.0
	var node: Control


@onready var backdrop: ColorRect = $Backdrop
@onready var photo: TextureRect = $Photo

# fit_scale makes the whole photo fit the screen.
# zoom_level is the TARGET multiplier on top of it: 1.0 = whole photo visible.
var fit_scale: float = 1.0
var zoom_level: float = 1.0
var target_position: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var press_travel: float = 0.0
var previous_pixel_snap: bool = true

var puzzle_id: String = ""
var puzzle_targets: Array = []
var evidence_info: Dictionary = {}
var targets: Array[ClueTarget] = []
var pulses: Dictionary = {}

var overlay: Control
var dialogue: DialogueBoxScript


func _ready() -> void:
	set_process(false)
	clip_contents = true

	# By default Godot rounds every UI node's position to whole pixels. While the
	# photo glides, its position would jump a full pixel at a time while its scale
	# changes smoothly, which looks like trembling. Turn that off while this scene
	# is open, and restore it when the scene closes.
	previous_pixel_snap = get_viewport().gui_snap_controls_to_pixels
	get_viewport().gui_snap_controls_to_pixels = false

	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.pivot_offset = Vector2.ZERO

	_load_puzzle_data()

	if photo.texture == null:
		push_warning("LoupeExamination: no photo. Check the Photo node or the 'photo' path in the puzzle JSON.")
		return

	_enable_smooth_minifying()
	_build_overlay_and_dialogue()
	resized.connect(_fit_photo)
	_fit_photo()
	_spawn_hotspots()

	GameState.evidence_added.connect(_on_evidence_added)


func _exit_tree() -> void:
	get_viewport().gui_snap_controls_to_pixels = previous_pixel_snap
	if GameState.evidence_added.is_connected(_on_evidence_added):
		GameState.evidence_added.disconnect(_on_evidence_added)


func _gui_input(event: InputEvent) -> void:
	if photo.texture == null:
		return

	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event
		match button_event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(zoom_step, button_event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / zoom_step, button_event.position)
			MOUSE_BUTTON_LEFT:
				if button_event.pressed:
					is_dragging = true
					press_travel = 0.0
				else:
					# Let go without moving much = a click, not a drag.
					if is_dragging and press_travel < CLICK_TRAVEL_LIMIT:
						_try_click(button_event.position)
					is_dragging = false
	elif event is InputEventMouseMotion and is_dragging:
		var motion_event: InputEventMouseMotion = event
		press_travel += motion_event.relative.length()
		target_position = _clamp_position(target_position + motion_event.relative, fit_scale * zoom_level)
		set_process(true)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_H:
		show_debug_hotspots = not show_debug_hotspots
		overlay.queue_redraw()


# Runs every frame, but only while the photo is still gliding.
func _process(delta: float) -> void:
	# Frame-rate independent easing: the same feel at 60 fps or 144 fps.
	var weight: float = 1.0 - exp(-smoothing * delta)
	var goal_scale: float = fit_scale * zoom_level
	var new_scale: float = lerpf(photo.scale.x, goal_scale, weight)

	photo.scale = Vector2.ONE * new_scale
	photo.position = photo.position.lerp(target_position, weight)

	# How many screen pixels is the far edge of the photo from its resting place?
	var scale_error_px: float = absf(new_scale - goal_scale) * maxf(photo.size.x, photo.size.y)
	var position_error_px: float = photo.position.distance_to(target_position)
	if scale_error_px + position_error_px < SETTLE_PIXELS:
		photo.scale = Vector2.ONE * goal_scale
		photo.position = target_position
		set_process(false)

	overlay.queue_redraw()


# ---------------------------------------------------------------- loading data

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("LoupeExamination: file not found: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("LoupeExamination: not valid JSON (check commas and brackets): %s" % path)
	return {}


func _load_puzzle_data() -> void:
	var registry: Dictionary = _read_json(evidence_registry_path)
	evidence_info = registry.get("evidence", {})

	var puzzle: Dictionary = _read_json(puzzle_path)
	if puzzle.is_empty():
		return

	puzzle_id = str(puzzle.get("puzzle_id", ""))
	puzzle_targets = puzzle.get("targets", [])

	var photo_path: String = str(puzzle.get("photo", ""))
	if photo_path != "":
		if ResourceLoader.exists(photo_path):
			photo.texture = load(photo_path)
		else:
			push_warning("LoupeExamination: photo not found: %s (using the Photo node's texture)" % photo_path)

	var zoom: Dictionary = puzzle.get("zoom", {})
	min_zoom = float(zoom.get("min", min_zoom))
	max_zoom = float(zoom.get("max", max_zoom))
	zoom_step = float(zoom.get("wheel_factor", zoom_step))


# Creates one invisible Control per clue under the Photo node, so the clues move and
# scale with the photo. (Open the Remote tab while the game runs to see them.)
func _spawn_hotspots() -> void:
	for entry: Dictionary in puzzle_targets:
		var target: ClueTarget = ClueTarget.new()
		target.evidence_id = str(entry.get("evidence_id", ""))
		if target.evidence_id == "":
			push_warning("LoupeExamination: a target has no evidence_id, skipped.")
			continue
		if not evidence_info.has(target.evidence_id):
			push_warning("LoupeExamination: '%s' is not in the evidence registry." % target.evidence_id)

		var center: Array = entry.get("center", [0.5, 0.5])
		target.center_px = Vector2(float(center[0]) * photo.size.x, float(center[1]) * photo.size.y)
		target.radius_px = float(entry.get("radius", 0.05)) * photo.size.x
		target.min_zoom = float(entry.get("min_zoom", 1.0))

		var node: Control = Control.new()
		node.name = "Hotspot_%s" % target.evidence_id
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.position = target.center_px - Vector2.ONE * target.radius_px
		node.size = Vector2.ONE * target.radius_px * 2.0
		photo.add_child(node)
		target.node = node

		targets.append(target)
		print("Hotspot ready: %s at photo pixel %s, radius %d px, needs zoom %.1f" % [
			target.evidence_id, target.center_px.round(), int(target.radius_px), target.min_zoom
		])


# A big photo shown small shimmers while it moves, because thin details flicker in
# and out. Mipmaps (pre-shrunk copies of the photo) prevent that.
func _enable_smooth_minifying() -> void:
	photo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	var image: Image = photo.texture.get_image()
	if image == null or image.has_mipmaps():
		return
	if image.is_compressed():
		image.decompress()
	image.generate_mipmaps()
	photo.texture = ImageTexture.create_from_image(image)


# The overlay draws the rings on top of the photo. The dialogue box (added last, so it
# sits on top) shows the clue text along the bottom of the screen.
func _build_overlay_and_dialogue() -> void:
	overlay = Control.new()
	overlay.name = "ClueOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)

	dialogue = DialogueBoxScene.instantiate()
	dialogue.name = "DialogueBox"
	add_child(dialogue)


# ------------------------------------------------------------------ the photo

# Fits the photo to the screen instantly (used at start and when the window resizes).
func _fit_photo() -> void:
	var photo_size: Vector2 = photo.texture.get_size()
	photo.size = photo_size
	fit_scale = minf(size.x / photo_size.x, size.y / photo_size.y)

	var goal_scale: float = fit_scale * zoom_level
	target_position = _clamp_position(target_position, goal_scale)
	photo.scale = Vector2.ONE * goal_scale
	photo.position = target_position
	overlay.queue_redraw()


# Sets a new target zoom while keeping the spot under the cursor in place.
func _zoom_at(factor: float, focus: Vector2) -> void:
	var new_zoom: float = clampf(zoom_level * factor, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, zoom_level):
		return

	var old_scale: float = fit_scale * zoom_level
	var photo_point: Vector2 = (focus - target_position) / old_scale

	zoom_level = new_zoom
	var new_scale: float = fit_scale * zoom_level
	target_position = _clamp_position(focus - photo_point * new_scale, new_scale)
	set_process(true)


# Keeps the photo from being dragged off screen at the given scale.
# If the photo is smaller than the screen on an axis, it is centred on that axis.
func _clamp_position(wanted: Vector2, scale_value: float) -> Vector2:
	var scaled_size: Vector2 = photo.size * scale_value
	return Vector2(
		_clamp_axis(wanted.x, scaled_size.x, size.x),
		_clamp_axis(wanted.y, scaled_size.y, size.y)
	)


func _clamp_axis(current: float, photo_length: float, view_length: float) -> float:
	if photo_length <= view_length:
		return (view_length - photo_length) / 2.0
	return clampf(current, view_length - photo_length, 0.0)


# ------------------------------------------------------------- clicking clues

func _try_click(screen_position: Vector2) -> void:
	var scale_value: float = photo.scale.x
	var photo_point: Vector2 = (screen_position - photo.position) / scale_value
	var shown_zoom: float = scale_value / fit_scale

	for target: ClueTarget in targets:
		if GameState.has_evidence(target.evidence_id):
			continue
		var reach: float = target.radius_px + CLICK_FORGIVENESS_PX / scale_value
		if photo_point.distance_to(target.center_px) > reach:
			continue
		if shown_zoom + 0.05 < target.min_zoom:
			_show_message("", "There is something here, but it is too small to make out. Zoom in closer.")
			return
		GameState.collect_evidence(target.evidence_id)
		return


# GameState announces new evidence. Only react to the clues that belong to this photo.
func _on_evidence_added(evidence_id: String) -> void:
	var target: ClueTarget = _find_target(evidence_id)
	if target == null:
		return

	var info: Dictionary = evidence_info.get(evidence_id, {})
	var clue_name: String = str(info.get("name", evidence_id))
	print("CLUE FOUND: %s (%s)" % [clue_name, evidence_id])

	var description: String = str(info.get("description", ""))
	var everything_found: bool = _all_found()

	var messages: Array = [{ "name": "Clue found: %s" % clue_name, "text": description }]
	if everything_found:
		messages.append({ "name": "Photo complete", "text": "You found every clue in this photo." })
	dialogue.play_lines(messages, false, MESSAGE_HOLD_SECONDS + 1.0)
	_play_found_effect(evidence_id)

	if everything_found:
		print("PUZZLE COMPLETE: %s" % puzzle_id)
		GameState.mark_puzzle_solved(puzzle_id)
		all_clues_found.emit()


func _find_target(evidence_id: String) -> ClueTarget:
	for target: ClueTarget in targets:
		if target.evidence_id == evidence_id:
			return target
	return null


func _all_found() -> bool:
	if targets.is_empty():
		return false
	for target: ClueTarget in targets:
		if not GameState.has_evidence(target.evidence_id):
			return false
	return true


# ------------------------------------------------------------------- feedback

func _show_message(title: String, body: String) -> void:
	dialogue.show_notice(title, body, MESSAGE_HOLD_SECONDS)


# A gold ring grows out from the clue and fades. After it, a thin gold outline stays.
func _play_found_effect(evidence_id: String) -> void:
	var tween: Tween = create_tween()
	tween.tween_method(_set_pulse.bind(evidence_id), 1.0, 0.0, PULSE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_set_pulse.bind(0.0, evidence_id))


func _set_pulse(value: float, evidence_id: String) -> void:
	if value <= 0.0:
		pulses.erase(evidence_id)
	else:
		pulses[evidence_id] = value
	overlay.queue_redraw()


func _draw_overlay() -> void:
	var scale_value: float = photo.scale.x
	for target: ClueTarget in targets:
		var center: Vector2 = photo.position + target.center_px * scale_value
		var radius: float = target.radius_px * scale_value

		if GameState.has_evidence(target.evidence_id):
			overlay.draw_arc(center, radius, 0.0, TAU, 64, FOUND_COLOR, 3.0, true)
		elif show_debug_hotspots:
			overlay.draw_arc(center, radius, 0.0, TAU, 64, DEBUG_COLOR, 2.0, true)

		var pulse: float = pulses.get(target.evidence_id, 0.0)
		if pulse > 0.0:
			var ring_color: Color = FOUND_COLOR
			ring_color.a = pulse * 0.3
			overlay.draw_circle(center, radius, ring_color)
			ring_color.a = pulse
			overlay.draw_arc(center, radius + (1.0 - pulse) * PULSE_GROWTH_PX, 0.0, TAU, 64, ring_color, 2.0 + 6.0 * pulse, true)
