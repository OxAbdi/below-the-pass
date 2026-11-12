extends Node

# Test scene script for the Case Board (Milestone 3).
#   B  open / close the board (also cancels a started link)
#   C  collect all four test clues
#   X  reset GameState (clears clues, links and card positions)

const CaseBoardScript := preload("res://scripts/mechanics/CaseBoard.gd")

const TEST_EVIDENCE: Array[String] = [
	"ch01_shadow_directions",
	"ch01_snowbank_depth",
	"ch01_logo_patch",
	"ch01_anniversary_leaflet",
]

@onready var board: CaseBoardScript = $BoardLayer/CaseBoard
@onready var signal_log: Label = $SignalLog

var link_counts: Dictionary = {}


func _ready() -> void:
	GameState.link_made.connect(_on_link_made)
	GameState.state_reset.connect(_on_state_reset)
	_collect_all()
	_refresh_log()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_board"):
		if board.visible:
			board.request_close()
		else:
			board.open()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		if key_event.keycode == KEY_C:
			_collect_all()
		elif key_event.keycode == KEY_X:
			GameState.reset()


func _collect_all() -> void:
	for id: String in TEST_EVIDENCE:
		GameState.collect_evidence(id)


func _on_link_made(link_id: String) -> void:
	link_counts[link_id] = int(link_counts.get(link_id, 0)) + 1
	print("link_made fired: %s (count %d)" % [link_id, link_counts[link_id]])
	_refresh_log()


func _on_state_reset() -> void:
	link_counts.clear()
	_refresh_log()


func _refresh_log() -> void:
	var text: String = "link_made fired:"
	if link_counts.is_empty():
		text += " (nothing yet)"
	for link_id: String in link_counts:
		text += "\n  %s x%d" % [link_id, link_counts[link_id]]
	signal_log.text = text
