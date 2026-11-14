extends Control

# Plays a short film made of still paintings: each shot drifts slowly (a pan and a zoom), shots
# cross-fade into each other, and words can appear over them: a caption on black, the game's title,
# or lines of dialogue. Like the opening of an anime film, made from a handful of paintings.
#
#   await cinematic.play("ch01_intro", dialogue_box)
#
# The film is described in data/cinematics/<id>.json. A shot whose painting does not exist yet is
# drawn as a coloured stand-in with its "brief" written on it: that brief is the description to make
# the real painting from.
#
# Hold Esc (or Start) for one second to skip the whole film.

signal finished

const StoryRules := preload("res://scripts/story/StoryRules.gd")
const Typo := preload("res://scripts/ui/Typo.gd")
const KeyGlyphs := preload("res://scripts/ui/KeyGlyphs.gd")

const FOLDER: String = "res://data/cinematics/"
const BAR_HEIGHT: float = 120.0
const HOLD_TO_SKIP: float = 1.0
const PROMPT_SECONDS: float = 2.5
const CAPTION_PAUSE: float = 1.0   # plain black before a caption on black ("Winter, 1986."), while the game settles behind it
const CAPTION_IN: float = 1.6      # the words rise out of the dark slowly
const CAPTION_OUT: float = 1.2
const SKIP_ACTION: String = "pause"

var is_playing: bool = false
var film_id: String = ""
var shot_index: int = -1
var skipped: bool = false
var texts: Dictionary = {}

var current: Dictionary = {}   # the shot on top: { "shot", "texture", "progress", "number" }
var previous: Dictionary = {}  # the shot underneath, while they cross-fade
var mix: float = 1.0           # 0 = only the previous shot shows, 1 = only the current one
var black: float = 1.0         # a black veil over the pictures (shots fade in from it)
var caption: String = ""
var caption_alpha: float = 0.0
var title: Dictionary = {}
var title_alpha: float = 0.0
var hold: float = 0.0          # 0..1 while the skip button is held
var prompt_left: float = 0.0   # seconds the "Hold to skip" prompt stays

var _over: Control
var _snow: CPUParticles2D
var _dialogue: Node = null
var _shot_count: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_snow = _make_snow()
	add_child(_snow)
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)
	texts = (StoryRules.read_json("res://data/ui/menus.json").get("cinematic", {}) as Dictionary)


static func exists(id: String) -> bool:
	return FileAccess.file_exists(FOLDER + id + ".json")


# Plays the film and waits until it has ended (or been skipped). The screen is left black.
func play(id: String, dialogue: Node) -> void:
	var data: Dictionary = StoryRules.read_json(FOLDER + id + ".json")
	var shots: Array = data.get("shots", [])
	if shots.is_empty():
		push_warning("Cinematic: '%s' has no shots (or %s%s.json is missing)." % [id, FOLDER, id])
		return
	film_id = id
	_dialogue = dialogue
	_shot_count = shots.size()
	is_playing = true
	skipped = false
	visible = true
	black = 1.0
	mix = 1.0
	current = {}
	previous = {}
	caption = ""
	title = {}
	hold = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	if str(data.get("music", "")) != "":
		Audio.play_music(str(data["music"]), 1.5)
	for i: int in range(shots.size()):
		if skipped:
			break
		shot_index = i
		await _play_shot(shots[i], i)
	# Into black, then away.
	if _dialogue != null and _dialogue.is_open:
		_dialogue.close_now()
	await _tween_property("black", 1.0, 0.35 if skipped else 1.0)
	caption_alpha = 0.0
	title_alpha = 0.0
	if bool(data.get("stop_music", true)):
		Audio.stop_music(1.5)
	_snow.emitting = false
	is_playing = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot_index = -1
	finished.emit()


func _play_shot(shot: Dictionary, number: int) -> void:
	var seconds: float = float(shot.get("seconds", 5.0))
	var fade: float = float(shot.get("fade", 1.2))
	if shot.has("sound"):
		Audio.play(str(shot["sound"]))
	if str(shot.get("music", "")) != "":
		Audio.play_music(str(shot["music"]), 1.5)

	# A caption on black ("Winter, 1986.").
	if shot.has("caption") and not shot.has("image") and not shot.has("brief"):
		caption = str(shot["caption"])
		await _tween_property("black", 1.0, 0.6 if black < 1.0 else 0.0)
		current = {}
		previous = {}
		# A moment of plain black first (the game is still settling behind it), then the words rise out of the dark.
		await _wait(CAPTION_PAUSE)
		await _tween_property("caption_alpha", 1.0, CAPTION_IN)
		await _lines_and_wait(shot, seconds - CAPTION_IN - CAPTION_OUT)
		await _tween_property("caption_alpha", 0.0, CAPTION_OUT)
		return

	# A black shot that only carries words (a voice over darkness).
	if bool(shot.get("black", false)):
		await _tween_property("black", 1.0, 0.6 if black < 1.0 else 0.0)
		await _lines_and_wait(shot, seconds)
		return

	# A painting.
	var texture: Texture2D = null
	var path: String = str(shot.get("image", ""))
	if path != "" and ResourceLoader.exists(path):
		texture = load(path)
	var state: Dictionary = { "shot": shot, "texture": texture, "progress": 0.0, "number": number + 1 }
	previous = current
	current = state
	_set_snow(str(shot.get("snow", "none")))
	# The slow pan and zoom keeps going through the next cross-fade, so the picture never stops.
	var drift: Tween = create_tween()
	drift.tween_method(func(v: float) -> void: state["progress"] = v, 0.0, 1.0, seconds + fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if black > 0.0:
		mix = 1.0
		previous = {}
		await _tween_property("black", 0.0, fade)
	elif str(shot.get("transition", "fade")) == "cut" or previous.is_empty():
		mix = 1.0
		previous = {}
	else:
		mix = 0.0
		await _tween_property("mix", 1.0, fade)
		previous = {}
	if shot.has("title"):
		title = shot["title"]
		var show: Tween = create_tween()
		show.tween_property(self, "title_alpha", 1.0, 1.4)
		show.tween_interval(maxf(0.5, seconds - 3.2))
		show.tween_property(self, "title_alpha", 0.0, 1.0)
	await _lines_and_wait(shot, seconds - fade)


# Plays the shot's lines (if any), and waits at least `seconds` in total.
func _lines_and_wait(shot: Dictionary, seconds: float) -> void:
	var started: int = Time.get_ticks_msec()
	var lines: Array = shot.get("lines", [])
	if not lines.is_empty() and _dialogue != null and not skipped:
		await _wait(float(shot.get("lines_delay", 0.5)))
		if not skipped:
			_dialogue.play_lines(lines, true)
			if _dialogue.is_open:
				await _dialogue.dialogue_finished
	var spent: float = float(Time.get_ticks_msec() - started) / 1000.0
	await _wait(seconds - spent)


func _wait(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0 and not skipped:
		await get_tree().process_frame
		left -= get_process_delta_time()


func _tween_property(property: String, value: float, seconds: float) -> void:
	if skipped or seconds <= 0.0:
		set(property, value)
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, property, value, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	while tween.is_running() and not skipped:
		await get_tree().process_frame
	set(property, value)


# ---------- skipping ----------

func _input(event: InputEvent) -> void:
	if not is_playing:
		return
	KeyGlyphs.note(event)
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo():
		prompt_left = PROMPT_SECONDS


func _process(delta: float) -> void:
	if not is_playing:
		return
	if Input.is_action_pressed(SKIP_ACTION) and not skipped:
		hold = minf(1.0, hold + delta / HOLD_TO_SKIP)
		prompt_left = PROMPT_SECONDS
		if hold >= 1.0:
			skip()
	else:
		hold = maxf(0.0, hold - delta * 3.0)
	prompt_left = maxf(0.0, prompt_left - delta)
	queue_redraw()
	_over.queue_redraw()


func skip() -> void:
	if skipped or not is_playing:
		return
	skipped = true
	if _dialogue != null and _dialogue.is_open:
		_dialogue.close_now()


# ---------- drawing ----------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if not previous.is_empty():
		_draw_shot(previous, 1.0)
	if not current.is_empty():
		_draw_shot(current, mix)


func _draw_shot(state: Dictionary, alpha: float) -> void:
	var shot: Dictionary = state["shot"]
	var p: float = float(state.get("progress", 0.0))
	var from: Array = (shot.get("move", {}) as Dictionary).get("from", [1.0, 0.0, 0.0])
	var to: Array = (shot.get("move", {}) as Dictionary).get("to", [1.08, 0.0, 0.0])
	var zoom: float = lerpf(float(from[0]), float(to[0]), p)
	var offset: Vector2 = Vector2(lerpf(float(from[1]), float(to[1]), p), lerpf(float(from[2]), float(to[2]), p))
	var texture: Texture2D = state.get("texture")
	if texture != null:
		var cover: float = maxf(size.x / texture.get_width(), size.y / texture.get_height()) * zoom
		var drawn: Vector2 = texture.get_size() * cover
		draw_texture_rect(texture, Rect2(size * 0.5 - drawn * 0.5 + offset, drawn), false, Color(1, 1, 1, alpha))
		return
	# Stand-in painting: the shot's colours, a moving horizon so the drift can be seen, and the brief.
	var palette: Array = shot.get("palette", ["#0b1430", "#3a4a78"])
	var top: Color = Color.html(str(palette[0]))
	var bottom: Color = Color.html(str(palette[1] if palette.size() > 1 else palette[0]))
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([Color(top, alpha), Color(top, alpha), Color(bottom, alpha), Color(bottom, alpha)]))
	draw_set_transform(size * 0.5 + offset, 0.0, Vector2.ONE * zoom)
	for band: int in range(2):
		var points: PackedVector2Array = PackedVector2Array()
		var base: float = 180.0 + band * 150.0
		points.append(Vector2(-1200, 700))
		var x: float = -1200.0
		var k: int = 0
		while x <= 1200.0:
			points.append(Vector2(x, base - (160.0 if k % 2 == 0 else 30.0) * (1.0 - band * 0.4) - sin(x * 0.01 + band) * 30.0))
			x += 130.0 + float((k * 37 + band * 11) % 70)
			k += 1
		points.append(Vector2(1200, 700))
		draw_colored_polygon(points, Color(top.darkened(0.45 + band * 0.25), alpha * 0.9))
	draw_set_transform(Vector2.ZERO)


func _draw_over() -> void:
	var c: Control = _over
	var veil: float = black
	if veil > 0.0 and (not current.is_empty() or not previous.is_empty()):
		c.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, veil))
	# Wide-screen bars.
	c.draw_rect(Rect2(0, 0, size.x, BAR_HEIGHT), Color.BLACK)
	c.draw_rect(Rect2(0, size.y - BAR_HEIGHT, size.x, BAR_HEIGHT), Color.BLACK)
	# The brief of a stand-in shot, small, top left, so everyone knows which painting goes here.
	if not current.is_empty() and current.get("texture") == null and black < 1.0:
		var shot: Dictionary = current["shot"]
		var a: float = (1.0 - black) * mix * 0.75
		var label: String = "%s  ·  %s %d / %d" % [str(texts.get("art_needed", "Art needed")).to_upper(), film_id, int(current["number"]), _shot_count]
		c.draw_string(Typo.sans(600, 4), Vector2(60, BAR_HEIGHT + 44), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(Typo.AMBER, a))
		c.draw_multiline_string(Typo.sans(300, 0), Vector2(60, BAR_HEIGHT + 74), str(shot.get("brief", "")), HORIZONTAL_ALIGNMENT_LEFT, 860.0, 18, 5, Color(Typo.CREAM, a * 0.8))
	# A caption on black.
	if caption != "" and caption_alpha > 0.0:
		var font: Font = Typo.hand()
		var lines: PackedStringArray = caption.split("\n")
		var y: float = size.y * 0.5 - (lines.size() - 1) * 28.0
		for i: int in range(lines.size()):
			var line_size: int = 40 if i == 0 else 28
			var width: float = font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x
			c.draw_string(font, Vector2((size.x - width) * 0.5, y), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, line_size, Color(Typo.CREAM, caption_alpha * (1.0 if i == 0 else 0.75)))
			y += 64.0
	# The title over a shot.
	if not title.is_empty() and title_alpha > 0.0:
		var big: String = str(title.get("title", "")).to_upper()
		var small: String = str(title.get("subtitle", ""))
		var big_font: Font = Typo.sans(300, 14)
		var bw: float = big_font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
		var center_y: float = size.y * float(title.get("at", 0.42))
		c.draw_string(big_font, Vector2((size.x - bw) * 0.5 + 2, center_y + 3), big, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 72, Color(0, 0, 0, 0.55 * title_alpha))
		c.draw_string(big_font, Vector2((size.x - bw) * 0.5, center_y), big, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 72, Color(Typo.CREAM, title_alpha))
		c.draw_line(Vector2(size.x * 0.5 - 32, center_y + 34), Vector2(size.x * 0.5 + 32, center_y + 34), Color(Typo.AMBER, 0.9 * title_alpha), 2.0)
		var sw: float = Typo.hand().get_string_size(small, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		c.draw_string(Typo.hand(), Vector2((size.x - sw) * 0.5, center_y + 82), small, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, Color(Typo.CREAM, 0.8 * title_alpha))
	# "Hold to skip", with a ring that fills while the button is held.
	var prompt: float = clampf(prompt_left / 0.5, 0.0, 1.0)
	if prompt > 0.0 and not skipped:
		var at: Vector2 = Vector2(size.x - 380, size.y - BAR_HEIGHT * 0.5 + 8)
		var width: float = KeyGlyphs.draw(c, at, "skip", str(texts.get("hold_to_skip", "Hold to skip")), 0.85 * prompt, 18)
		var ring: Vector2 = at + Vector2(width + 30, -7)
		c.draw_arc(ring, 12.0, 0.0, TAU, 32, Color(Typo.CREAM, 0.3 * prompt), 2.0, true)
		if hold > 0.0:
			c.draw_arc(ring, 12.0, -PI * 0.5, -PI * 0.5 + TAU * hold, 32, Color(Typo.AMBER, prompt), 3.0, true)


func _set_snow(kind: String) -> void:
	var amounts: Dictionary = { "light": 70, "heavy": 260 }
	if not amounts.has(kind):
		_snow.emitting = false
		return
	_snow.amount = int(amounts[kind])
	_snow.initial_velocity_min = 60.0 if kind == "light" else 160.0
	_snow.initial_velocity_max = 120.0 if kind == "light" else 320.0
	_snow.emitting = true


func _make_snow() -> CPUParticles2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var flake: GradientTexture2D = GradientTexture2D.new()
	flake.gradient = gradient
	flake.fill = GradientTexture2D.FILL_RADIAL
	flake.fill_from = Vector2(0.5, 0.5)
	flake.fill_to = Vector2(1.0, 0.5)
	flake.width = 14
	flake.height = 14
	var snow: CPUParticles2D = CPUParticles2D.new()
	snow.texture = flake
	snow.emitting = false
	snow.lifetime = 5.0
	snow.preprocess = 5.0
	snow.position = Vector2(1100, -40)
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(1300, 10)
	snow.direction = Vector2(-0.45, 1.0)
	snow.spread = 10.0
	snow.gravity = Vector2(-20, 30)
	snow.scale_amount_min = 0.3
	snow.scale_amount_max = 1.2
	snow.color = Color(1, 1, 1, 0.8)
	return snow
