extends "res://scripts/world/Hotspot.gd"
## The old name for a Hotspot, kept so the test room still works. New maps use Hotspot.gd.
##
## Fill in ONE of the two ids:
##   dialogue_id      - plain lines that play top to bottom (a note on a desk)
##   conversation_id  - a branching talk with topics and evidence (a person)

signal interacted(id: String, kind: String)

const KIND_DIALOGUE: String = "dialogue"
const KIND_CONVERSATION: String = "conversation"

@export var dialogue_id: String = ""
@export var conversation_id: String = ""


func interact() -> void:
	if conversation_id != "":
		interacted.emit(conversation_id, KIND_CONVERSATION)
	else:
		interacted.emit(dialogue_id, KIND_DIALOGUE)
