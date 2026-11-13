extends Node

# Plays one-shot sound effects by id. It holds NO game state (GameState is the only state autoload).
#
#   Audio.play("pin_push")
#
# Sounds are listed in res://data/audio/sfx.json. If a sound file is missing, nothing plays and one
# warning is printed per id, so the game always runs, silent, until the real sounds arrive.
# Sounds are played on the "SFX" bus (created by default_bus_layout.tres).

const SFX_JSON: String = "res://data/audio/sfx.json"
const BUS_NAME: String = "SFX"
const POOL_SIZE: int = 6

var _sounds: Dictionary = {}  # id -> { "stream": AudioStream or null, "volume_db": float, "pitch_jitter": float }
var _folder: String = ""
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _warned: Dictionary = {}  # ids we already warned about
var _last_play_msec: Dictionary = {}  # id -> msec, for the optional min_gap argument
var played_log: Array[String] = []  # every id that was asked for, in order (used by tests)


func _ready() -> void:
	for index: int in range(POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = BUS_NAME if AudioServer.get_bus_index(BUS_NAME) >= 0 else "Master"
		add_child(player)
		_players.append(player)
	_load_list()


func _load_list() -> void:
	_sounds.clear()
	if not FileAccess.file_exists(SFX_JSON):
		push_warning("Audio: %s not found" % SFX_JSON)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Audio: %s is not a JSON object" % SFX_JSON)
		return
	var data: Dictionary = parsed
	_folder = str(data.get("folder", "res://assets/audio/sfx/"))
	var list: Dictionary = data.get("sounds", {})
	for id: String in list.keys():
		var entry: Dictionary = list[id]
		var path: String = _folder + str(entry.get("file", id + ".ogg"))
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
		_sounds[id] = {
			"stream": stream,
			"path": path,
			"volume_db": float(entry.get("volume_db", 0.0)),
			"pitch_jitter": float(entry.get("pitch_jitter", 0.0)),
		}


# `min_gap` (seconds) stops fast repeats, for example a paper rustle while scrolling.
func play(id: String, min_gap: float = 0.0) -> void:
	played_log.append(id)
	if not _sounds.has(id):
		_warn_once(id, "Audio: unknown sound id '%s' (add it to %s)" % [id, SFX_JSON])
		return
	if min_gap > 0.0:
		var now: int = Time.get_ticks_msec()
		if now - int(_last_play_msec.get(id, -100000)) < int(min_gap * 1000.0):
			return
		_last_play_msec[id] = now
	var entry: Dictionary = _sounds[id]
	var stream: AudioStream = entry["stream"]
	if stream == null:
		_warn_once(id, "Audio: sound file missing for '%s' (%s). Playing nothing." % [id, entry["path"]])
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = float(entry["volume_db"])
	var jitter: float = float(entry["pitch_jitter"])
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	player.play()


# Re-reads the sound list (for example after the user drops new files in). Mostly for tests.
func reload() -> void:
	_warned.clear()
	_load_list()


func warning_count() -> int:
	return _warned.size()


func _warn_once(id: String, message: String) -> void:
	if _warned.has(id):
		return
	_warned[id] = true
	push_warning(message)
