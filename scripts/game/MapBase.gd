extends Node2D
## The root of every map. A map is pure content: props, people, hotspots, doors, exits, blockers
## and spawn points. It keeps no state and plays no dialogue. The Game loads one map at a time,
## puts James in it and runs the camera.
##
## A map scene needs these children:
##   Actors  (Node2D, y-sort on)   props and people; James is put in here
##   Spawns  (Node2D)              SpawnPoint / Marker2D children, named by spawn id
##   Bounds  (ReferenceRect)       the area the camera may show
##   Focus   (Node2D, optional)    Marker2D children the camera can look at in a cut-away
##   PhaseLights (Node)            switches lights, tint and snow with the time of day

const SpawnPointScript := preload("res://scripts/world/SpawnPoint.gd")

@export var map_id: String = ""

@onready var actors: Node2D = $Actors


func has_spawn(spawn_id: String) -> bool:
	return has_node("Spawns/" + spawn_id)


func get_spawn(spawn_id: String) -> Vector2:
	var marker: Node2D = get_node_or_null("Spawns/" + spawn_id) as Node2D
	if marker == null:
		push_warning("Map '%s' has no spawn '%s'." % [map_id, spawn_id])
		var fallback: Rect2 = camera_bounds()
		return fallback.get_center()
	return marker.global_position


func get_spawn_facing(spawn_id: String) -> String:
	var marker: Node = get_node_or_null("Spawns/" + spawn_id)
	if marker is SpawnPointScript:
		return (marker as SpawnPointScript).facing
	return "S"


func spawn_ids() -> Array[String]:
	var result: Array[String] = []
	if has_node("Spawns"):
		for child: Node in get_node("Spawns").get_children():
			result.append(str(child.name))
	return result


func has_focus(focus_id: String) -> bool:
	return has_node("Focus/" + focus_id)


func get_focus(focus_id: String) -> Vector2:
	var marker: Node2D = get_node_or_null("Focus/" + focus_id) as Node2D
	if marker == null:
		push_warning("Map '%s' has no focus point '%s'." % [map_id, focus_id])
		return camera_bounds().get_center()
	return marker.global_position


func focus_ids() -> Array[String]:
	var result: Array[String] = []
	if has_node("Focus"):
		for child: Node in get_node("Focus").get_children():
			result.append(str(child.name))
	return result


func camera_bounds() -> Rect2:
	var bounds: ReferenceRect = get_node_or_null("Bounds") as ReferenceRect
	if bounds == null:
		return Rect2(0.0, 0.0, 1920.0, 1080.0)
	return Rect2(bounds.global_position, bounds.size)


## Lights, tint and snow for a time of day. `info` is the phase's entry in the chapter file.
func apply_phase(info: Dictionary, tint: Color, exterior: bool, instant: bool) -> void:
	var lights: Node = get_node_or_null("PhaseLights")
	if lights != null:
		lights.apply(info, tint, exterior, instant)
