extends Control

# Tiny test scene script. Plays the test conversation on start, and again when you press R.

const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")

@onready var box: DialogueBoxScript = $DialogueBox


func _ready() -> void:
	box.dialogue_finished.connect(_on_finished)
	box.play_dialogue("test_dialogue")


func _on_finished() -> void:
	print("Dialogue finished. Press R to play it again.")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if not box.is_open:
			box.play_dialogue("test_dialogue")
