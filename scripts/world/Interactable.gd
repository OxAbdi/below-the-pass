extends Area2D
## Anything James can press "interact" on. It holds a dialogue_id (a file name in
## data/dialogue/) and shouts a signal. It does NOT play the dialogue itself:
## the room listens and decides what happens.

signal interacted(dialogue_id: String)

@export var dialogue_id: String = ""
@export var prompt_text: String = "Examine"

@onready var prompt: Label = $Prompt


func _ready() -> void:
	collision_layer = 4   # layer 3 "interactables"
	collision_mask = 0
	prompt.text = "[E]  " + prompt_text
	prompt.visible = false


func interact() -> void:
	interacted.emit(dialogue_id)


func set_prompt_visible(shown: bool) -> void:
	prompt.visible = shown
