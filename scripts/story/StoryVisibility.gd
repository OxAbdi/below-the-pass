extends RefCounted

# Decides whether a person, hotspot, door or exit is "there" right now.
# The same three settings mean the same thing on every one of them:
#   phases        the times of day it exists in (empty = always)
#   show_if_flag  it only exists once this flag is on
#   hide_if_flag  it stops existing once this flag is on

static func is_shown(phases: PackedStringArray, show_if_flag: String, hide_if_flag: String) -> bool:
	if not phases.is_empty() and not phases.has(GameState.phase):
		return false
	if show_if_flag != "" and not GameState.has_flag(show_if_flag):
		return false
	if hide_if_flag != "" and GameState.has_flag(hide_if_flag):
		return false
	return true
