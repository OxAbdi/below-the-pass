extends Node

# Writes and reads save files. It holds NO story state: only which slot this play session
# saves into. Everything that is saved comes from GameState.get_save_data().
#
#   user://saves/slot_1.json ... slot_3.json
#   (on Windows, user:// is %APPDATA%\Godot\app_userdata\Below the Pass\)
#
# Each slot is one playthrough. New Game picks a slot; from then on autosaves go there.
#
# A save is written in three steps, so a crash in the middle never destroys the last good save:
#   1. write slot_N.json.tmp
#   2. rename the old slot_N.json to slot_N.json.bak
#   3. rename the .tmp to slot_N.json

signal saved(slot: int)

const VERSION: int = 1
const SLOT_COUNT: int = 3

# Tests point this somewhere else so they never touch real saves.
var saves_dir: String = "user://saves"

# The slot this play session writes to (1..3). 0 = none yet.
var active_slot: int = 0

# True while an autosave is waiting for a safe moment. The Game does it when James is back in control.
var autosave_pending: bool = false

# Unix time of the last successful save in this session (0 = none).
var last_saved_at: int = 0

# Set by the Game: called just before saving so it can write James's exact position into GameState.
var before_save: Callable = Callable()
# Set by the Game: returns the small "summary" shown on the save card.
var summary_provider: Callable = Callable()


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [saves_dir, slot]


func request_autosave() -> void:
	autosave_pending = true


# Saves GameState into `slot` (the active slot when left out). Returns false if it could not write.
func save_now(slot: int = 0) -> bool:
	if slot <= 0:
		slot = active_slot
	if slot <= 0:
		return false
	if before_save.is_valid():
		before_save.call()
	var now: int = int(Time.get_unix_time_from_system())
	var data: Dictionary = {
		"version": VERSION,
		"saved_at": now,
		"summary": summary_provider.call() if summary_provider.is_valid() else {},
		"state": GameState.get_save_data(),
	}
	DirAccess.make_dir_recursive_absolute(saves_dir)
	var path: String = slot_path(slot)
	var file: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not write %s.tmp" % path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		push_warning("SaveManager: could not finish writing %s" % path)
		return false
	if slot == active_slot:
		autosave_pending = false
	last_saved_at = now
	Audio.play("save_write")
	saved.emit(slot)
	return true


# What a save card needs to know: { "status": "empty" | "ok" | "damaged", "summary", "saved_at", "has_backup" }.
func slot_info(slot: int) -> Dictionary:
	var path: String = slot_path(slot)
	var has_backup: bool = FileAccess.file_exists(path + ".bak")
	if not FileAccess.file_exists(path):
		return { "status": "empty", "summary": {}, "saved_at": 0, "has_backup": has_backup }
	var data: Dictionary = _read(path)
	if data.is_empty():
		return { "status": "damaged", "summary": {}, "saved_at": 0, "has_backup": has_backup }
	return { "status": "ok", "summary": data.get("summary", {}), "saved_at": int(data.get("saved_at", 0)), "has_backup": has_backup }


func has_any_save() -> bool:
	return newest_slot() > 0


# The slot saved most recently, or 0 when there are no good saves.
func newest_slot() -> int:
	var best: int = 0
	var best_time: int = -1
	for slot: int in range(1, SLOT_COUNT + 1):
		var info: Dictionary = slot_info(slot)
		if info["status"] == "ok" and int(info["saved_at"]) > best_time:
			best = slot
			best_time = int(info["saved_at"])
	return best


# Loads a slot into GameState and makes it the active slot. Returns false on a missing or damaged file.
func load_slot(slot: int) -> bool:
	var data: Dictionary = _read(slot_path(slot))
	if data.is_empty():
		return false
	GameState.load_save_data(_migrate(data)["state"])
	active_slot = slot
	autosave_pending = false
	last_saved_at = int(data.get("saved_at", 0))
	return true


func delete_slot(slot: int) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = slot_path(slot) + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# Puts the backup back in place of a damaged save. Returns false when there is no good backup.
func restore_backup(slot: int) -> bool:
	var path: String = slot_path(slot)
	if _read(path + ".bak").is_empty():
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.copy_absolute(path + ".bak", path) == OK


# A save is good when it is a JSON object with a "state" object inside.
func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).get("state") is Dictionary:
		return parsed
	return {}


# Future changes to the save format go here: read data["version"], and update old saves step by step.
func _migrate(data: Dictionary) -> Dictionary:
	return data
