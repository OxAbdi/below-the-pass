extends Area2D
## Anything James can press "interact" on. It holds the id of something to play (a file name in
## data/dialogue/) and shouts a signal. It does NOT play it itself: the room listens and decides
## what happens.
##
## Fill in ONE of the two ids:
##   dialogue_id      - plain lines that play top to bottom (a note on a desk)
##   conversation_id  - a branching talk with topics and evidence (a person)

signal interacted(id: String, kind: String)

const KIND_DIALOGUE: String = "dialogue"
const KIND_CONVERSATION: String = "conversation"

@export var dialogue_id: String = ""
@export var conversation_id: String = ""
@export var prompt_text: String = "Examine"

@onready var prompt: Label = $Prompt


func _ready() -> void:
	collision_layer = 4   # layer 3 "interactables"
	collision_mask = 0
	prompt.text = "[E]  " + prompt_text
	prompt.visible = false


func interact() -> void:
	if conversation_id != "":
		interacted.emit(conversation_id, KIND_CONVERSATION)
	else:
		interacted.emit(dialogue_id, KIND_DIALOGUE)


func set_prompt_visible(shown: bool) -> void:
	prompt.visible = shown
