extends Control

# Reusable dialogue box, laid out like a visual novel:
#   - a big portrait on the right side of the screen
#   - a soft dark gradient along the bottom (no hard border)
#   - the speaker's name and the typewriter text floating on the left
#
# Four ways to use it:
#   play_conversation("ch01_jonah_signal_hill")  - a branching talk: topics to pick, evidence to present
#   play_dialogue("test_dialogue")               - plain lines from data/dialogue/, click to advance
#   play_lines([...], true)                      - the same, but with lines built in code
#   show_notice("Title", "Body")                 - a short message with no portrait that closes by itself
#
# In a conversation this script is only the stage. The rules (which topics show, what a piece of
# evidence proves) are answered by Conversation.gd from the JSON file, and everything that has to
# be remembered goes to GameState.

signal line_started(index: int)
signal dialogue_finished
signal evidence_presented(evidence_id: String, caught: bool)

enum Mode { READING, CHOOSING, PICKING, PRESENTING }

const ConversationScript := preload("res://scripts/dialogue/Conversation.gd")
const EvidenceCatalog := preload("res://scripts/data/EvidenceCatalog.gd")
const ChoiceListScript := preload("res://scripts/ui/ChoiceList.gd")
const EvidencePickerScript := preload("res://scripts/ui/EvidencePicker.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const PromptBarScript := preload("res://scripts/mechanics/PromptBar.gd")
const CardScene: PackedScene = preload("res://scenes/mechanics/evidence_card.tscn")

const GOLD: Color = Color(0.85, 0.68, 0.3)
const INK: Color = Color(0.1, 0.08, 0.12)
const PORTRAIT_SLIDE_PX: float = 260.0
const TEXT_SLIDE_PX: float = 40.0
const OPEN_SECONDS: float = 0.5
const SWAP_SECONDS: float = 0.4
const FADE_SECONDS: float = 0.35
const NOTICE_TYPE_SPEEDUP: float = 2.5
const EXPRESSION_FADE_SECONDS: float = 0.15
const PROMPTS_PATH: String = "res://data/ui/dialogue_prompts.json"
const THOUGHT_NAME_SUFFIX: String = " (thinking)"
const THOUGHT_NAME_COLOR: Color = Color(0.66, 0.64, 0.6)
const ACTION_TEXT_COLOR: Color = Color(0.96, 0.93, 0.84, 0.8)
const VOICE_EDGE_COLOR: Color = Color(0.96, 0.93, 0.84, 0.55)
const ITALIC_SLANT: float = 0.2
const PRESENT_ACTION: String = "present_evidence"

# The present moment: the folder drops, the card rises and lands, then it holds.
const PRESENT_RISE_START: float = 0.2
const PRESENT_LAND: float = 0.48
const PRESENT_SECONDS: float = 0.98
const PRESENT_CENTER: Vector2 = Vector2(700.0, 430.0)
const PRESENT_SCALE: float = 1.4
const PRESENT_TILT_DEG: float = -4.0
const LAND_SHAKE_PX: float = 6.0
const FLINCH_PX: float = 12.0
const FLINCH_SECONDS: float = 0.35
const CAUGHT_PAUSE: float = 0.5
const CARD_LINES_ON_SCREEN: int = 2  # the presented card leaves when the second line after it starts

@export_file("*.json") var portraits_path: String = "res://data/characters/portraits.json"
@export_dir var dialogue_folder: String = "res://data/dialogue/"
@export var chars_per_second: float = 45.0

@onready var shade: TextureRect = $Shade
@onready var portrait: TextureRect = $Portrait
@onready var text_block: VBoxContainer = $TextBlock
@onready var name_label: Label = $TextBlock/NameLabel
@onready var text_label: RichTextLabel = $TextBlock/TextLabel
@onready var advance_hint: Polygon2D = $TextBlock/AdvanceHint
@onready var choices: ChoiceListScript = $Choices
@onready var prompts: PromptBarScript = $Prompts
@onready var picker: EvidencePickerScript = $Picker
@onready var present_layer: Control = $PresentLayer
@onready var fx: Control = $Fx
@onready var anim: AnimationPlayer = $AnimationPlayer

var portraits: Dictionary = {}
var lines: Array = []
var line_index: int = -1
var blocking: bool = true
var notice_seconds: float = 3.0
var is_open: bool = false
var typing: bool = false
var mode: Mode = Mode.READING
var current_portrait_id: String = ""
var current_expression: String = "neutral"
var placeholder_color: Color = Color(0.5, 0.5, 0.5)
var placeholder_name: String = ""
var portrait_home: Vector2
var text_home: Vector2
var type_tween: Tween
var hint_tween: Tween

# The card rising from the bottom of the screen: 0 = below the screen, 1 = landed.
var present_amount: float = 0.0:
	set(value):
		present_amount = value
		_place_present_card()
# The short warm flash when the card lands: 0..1.
var flash_amount: float = 0.0:
	set(value):
		flash_amount = value
		if fx != null:
			fx.queue_redraw()

var _conversation: ConversationScript = null
var _node_id: String = ""
var _interlude: bool = false  # true while the "wrong evidence" lines play
var _resume: Dictionary = {}  # where to go back to after those lines
var _was_choosing: bool = false
var _present_id: String = ""
var _present_card: Control = null
var _card_lines_left: int = 0
var _vignette_amount: float = 0.0
var _vignette_tex: GradientTexture2D
var _shake_tween: Tween
var _fx_tween: Tween
var _card_tween: Tween
var _expression_tween: Tween
var _prompt_texts: Dictionary = {}
var _line_style: String = ""
var _body_font: Font
var _italic_font: FontVariation

static var _folder_checked: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_home = portrait.position
	text_home = text_block.position
	var data: Dictionary = _read_json(portraits_path)
	portraits = data.get("portraits", {})
	_prompt_texts = _read_json(PROMPTS_PATH)
	portrait.draw.connect(_draw_placeholder)
	fx.draw.connect(_draw_fx)
	choices.choice_picked.connect(_on_choice_picked)
	picker.presented.connect(_on_evidence_chosen)
	picker.cancelled.connect(_close_picker)
	prompts.set_suppressed(true)
	_vignette_tex = _make_vignette()
	# Klee One has no italic, so thoughts and stage directions use the same font, slanted.
	_body_font = text_label.get_theme_font("normal_font")
	_italic_font = FontVariation.new()
	_italic_font.base_font = _body_font
	_italic_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(ITALIC_SLANT, 1.0), Vector2.ZERO)
	_ensure_present_action()
	_build_animations()
	anim.animation_finished.connect(_on_animation_finished)
	if OS.is_debug_build() and not _folder_checked:
		_folder_checked = true
		var problems: Dictionary = validate_folder()
		for file_name: String in problems.keys():
			for problem: String in problems[file_name]:
				push_warning("Dialogue file %s: %s" % [file_name, problem])


# ---------- public API ----------

func play_conversation(conversation_id: String) -> void:
	var conversation: ConversationScript = ConversationScript.new()
	if not conversation.load_from(dialogue_folder.path_join(conversation_id + ".json")):
		return
	if not conversation.is_conversation():
		play_dialogue(conversation_id)
		return
	_reset_talk()
	_conversation = conversation
	blocking = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_play_node(conversation.entry_node())


func play_dialogue(dialogue_id: String) -> void:
	var path: String = dialogue_folder.path_join(dialogue_id + ".json")
	var data: Dictionary = _read_json(path)
	var raw_lines: Array = data.get("lines", [])
	if raw_lines.is_empty():
		push_error("DialogueBox: no lines found in %s" % path)
		return
	play_lines(raw_lines, true)


func play_lines(new_lines: Array, is_blocking: bool = true, seconds: float = 3.0) -> void:
	if new_lines.is_empty():
		return
	_reset_talk()
	lines = new_lines
	blocking = is_blocking
	notice_seconds = seconds
	mouse_filter = Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	_show_line(0)


func show_notice(title: String, body: String, seconds: float = 3.0) -> void:
	play_lines([{ "name": title, "text": body }], false, seconds)


# Closes whatever is showing at once (used when a cinematic is skipped).
func close_now() -> void:
	if is_open:
		_close()


func in_conversation() -> bool:
	return _conversation != null


# Checks every file in the dialogue folder. Returns { file name: [problems] } for files with problems.
func validate_folder() -> Dictionary:
	var result: Dictionary = {}
	var folder: DirAccess = DirAccess.open(dialogue_folder)
	if folder == null:
		return result
	for file_name: String in folder.get_files():
		if not file_name.ends_with(".json"):
			continue
		var conversation: ConversationScript = ConversationScript.new()
		if not conversation.load_from(dialogue_folder.path_join(file_name)):
			result[file_name] = ["The file is missing or is not valid JSON."]
			continue
		var problems: Array[String] = conversation.validate(portraits)
		var partner: String = str(conversation.data.get("partner", ""))
		if partner != "" and not portraits.has(partner):
			problems.append("\"partner\" is '%s', who is not in portraits.json." % partner)
		if not problems.is_empty():
			result[file_name] = problems
	return result


# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if not blocking or not is_open:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if not mouse_event.pressed:
			return
		if mode == Mode.PICKING:
			# A click outside the folder (or a right click) puts it away.
			if mouse_event.button_index == MOUSE_BUTTON_LEFT or mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				accept_event()
				_close_picker()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if mode == Mode.READING:
				_advance()


func _unhandled_input(event: InputEvent) -> void:
	if not blocking or not is_open:
		return
	if event is InputEventMouse:
		return
	match mode:
		Mode.PICKING:
			if picker.handle_input(event):
				get_viewport().set_input_as_handled()
		Mode.PRESENTING:
			if UiInput.is_accept(event) or event.is_action(PRESENT_ACTION):
				get_viewport().set_input_as_handled()
		Mode.CHOOSING:
			if event.is_action_pressed(PRESENT_ACTION) and not event.is_echo():
				get_viewport().set_input_as_handled()
				_open_picker()
			elif choices.handle_input(event):
				get_viewport().set_input_as_handled()
		Mode.READING:
			if UiInput.is_accept(event):
				get_viewport().set_input_as_handled()
				_advance()
			elif event.is_action_pressed(PRESENT_ACTION) and not event.is_echo():
				get_viewport().set_input_as_handled()
				_open_picker()


func _advance() -> void:
	if typing:
		type_tween.kill()
		text_label.visible_ratio = 1.0
		_on_typed()
	else:
		_next_line_or_close()


# The Present key normally comes from project.godot. If it is missing there, add it here so the
# game still works: Q on the keyboard, Y on a controller.
func _ensure_present_action() -> void:
	if InputMap.has_action(PRESENT_ACTION):
		return
	InputMap.add_action(PRESENT_ACTION)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_Q
	InputMap.action_add_event(PRESENT_ACTION, key)
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_Y
	InputMap.action_add_event(PRESENT_ACTION, button)


# ---------- conversations: nodes and topics ----------

func _play_node(node_id: String) -> void:
	if _conversation == null:
		return
	if node_id == ConversationScript.END or not _conversation.has_node(node_id):
		_close()
		return
	_node_id = node_id
	_conversation.begin_node(node_id)
	mode = Mode.READING
	if _conversation.is_silent(node_id):
		# Effects only: show nothing and move straight on.
		_play_node(_conversation.next_of(node_id))
		return
	var node_lines: Array = _conversation.node(node_id).get("lines", [])
	if node_lines.is_empty():
		# A node with no lines (a list of topics). The last line stays on screen behind it.
		# If nothing is on screen yet, show the person James is talking to.
		if not is_open:
			lines = [{ "speaker": _partner_id(), "text": "" }]
			_show_line(0, true)
		_after_node_lines()
		return
	lines = node_lines
	_show_line(0)


# The last line of the node has been read: show its topics, or move on.
func _after_node_lines() -> void:
	var options: Array[Dictionary] = _conversation.visible_choices(_node_id)
	if options.is_empty():
		_play_node(_conversation.next_of(_node_id))
		return
	mode = Mode.CHOOSING
	_stop_hint()
	choices.show_choices(options, _conversation.choice_tag(_node_id))
	_refresh_prompts()


func _on_choice_picked(index: int) -> void:
	if _conversation == null or mode != Mode.CHOOSING:
		return
	var options: Array[Dictionary] = _conversation.visible_choices(_node_id)
	if index < 0 or index >= options.size():
		return
	_play_node(str(options[index]["goto"]))


func _partner_id() -> String:
	if _conversation == null:
		return current_portrait_id
	var partner: String = str(_conversation.data.get("partner", ""))
	return partner if partner != "" else current_portrait_id


func _partner_name() -> String:
	var info: Dictionary = portraits.get(_partner_id(), {})
	return str(info.get("display_name", _partner_id()))


# ---------- conversations: presenting evidence ----------

func can_present_now() -> bool:
	if _conversation == null or _interlude or typing or not is_open:
		return false
	if mode != Mode.READING and mode != Mode.CHOOSING:
		return false
	return _conversation.can_present(_node_id)


func _open_picker() -> void:
	if not can_present_now():
		return
	_was_choosing = mode == Mode.CHOOSING
	choices.visible = false
	mode = Mode.PICKING
	_stop_hint()
	var items: Array = []
	for id: String in EvidenceCatalog.held_items(GameState):
		var info: Dictionary = EvidenceCatalog.item_info(id)
		info["id"] = id
		items.append(info)
	var heading: String = str(_prompt_texts.get("picker_heading", "Present to %s")) % _partner_name()
	picker.open(items, heading, str(_prompt_texts.get("empty_picker_text", "")), name_label.text if name_label.visible else "", text_label.text)
	portrait.self_modulate = Color(0.7, 0.7, 0.7)
	_refresh_prompts()


func _close_picker() -> void:
	if mode != Mode.PICKING:
		return
	picker.close()
	portrait.self_modulate = Color.WHITE
	_back_to_where_we_were()


# After the folder closes or a wrong try: the same line, or the same list of topics.
func _back_to_where_we_were() -> void:
	if _was_choosing:
		mode = Mode.CHOOSING
		choices.visible = true
		if not choices.is_showing:
			choices.show_choices(_conversation.visible_choices(_node_id), _conversation.choice_tag(_node_id))
	else:
		mode = Mode.READING
		_on_typed()
	_refresh_prompts()


func _on_evidence_chosen(evidence_id: String) -> void:
	if mode != Mode.PICKING:
		return
	mode = Mode.PRESENTING
	_present_id = evidence_id
	picker.close(true)
	portrait.self_modulate = Color.WHITE
	choices.hide_choices()
	_refresh_prompts()
	# The person being shown the evidence is the one on screen.
	_face_partner()
	_spawn_present_card(evidence_id)
	anim.play("present")


func _face_partner() -> void:
	var partner: String = _partner_id()
	if partner == "" or partner == current_portrait_id or not portraits.has(partner):
		return
	_set_portrait(partner, "neutral", true)


func _spawn_present_card(evidence_id: String) -> void:
	_remove_present_card()
	var info: Dictionary = EvidenceCatalog.item_info(evidence_id)
	var card: Control = CardScene.instantiate()
	present_layer.add_child(card)
	card.setup(evidence_id, str(info["name"]), str(info["description"]), str(info["style"]), info["accent"])
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	card.set_process_input(false)
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 1.0
	_present_card = card
	present_amount = 0.0


# Where the presented card is for a given `present_amount`: it rises from below the screen,
# tilts, and grows a little past its final size before settling.
func _place_present_card() -> void:
	if _present_card == null or not is_instance_valid(_present_card):
		return
	var t: float = clampf(present_amount, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var overshoot: float = sin(t * PI) * 0.12
	var center: Vector2 = Vector2(PRESENT_CENTER.x, lerpf(1080.0 + 200.0, PRESENT_CENTER.y, eased))
	_present_card.scale = Vector2.ONE * (lerpf(0.6, 1.0, eased) + overshoot) * PRESENT_SCALE
	_present_card.rotation = deg_to_rad(PRESENT_TILT_DEG) * eased
	_present_card.position = center - _present_card.size * 0.5


func _remove_present_card() -> void:
	if _card_tween != null:
		_card_tween.kill()
	if _present_card != null and is_instance_valid(_present_card):
		_present_card.queue_free()
	_present_card = null
	_card_lines_left = 0


func _fade_present_card() -> void:
	if _present_card == null or not is_instance_valid(_present_card):
		return
	var card: Control = _present_card
	_present_card = null
	_card_tween = create_tween()
	_card_tween.tween_property(card, "modulate:a", 0.0, 0.2)
	_card_tween.tween_callback(card.queue_free)


# Called by the "present" animation at the moment the card lands.
func _on_present_landed() -> void:
	Audio.play("present_slam")
	_shake_portrait(LAND_SHAKE_PX, 0.2)


# The card has been shown. Ask the conversation what it proves.
func _resolve_present() -> void:
	if _conversation == null or mode != Mode.PRESENTING:
		return
	var result: Dictionary = _conversation.present(_present_id)
	if result.has("caught"):
		var caught_node: String = str(result["caught"])
		evidence_presented.emit(_present_id, true)
		Audio.play("confront_sting")
		_shake_portrait(FLINCH_PX, FLINCH_SECONDS)
		_flash_vignette()
		_set_portrait(current_portrait_id, _first_expression_of(caught_node, current_portrait_id), false)
		_card_lines_left = CARD_LINES_ON_SCREEN
		var pause: Tween = create_tween()
		pause.tween_interval(CAUGHT_PAUSE)
		pause.tween_callback(_play_node.bind(caught_node))
		return
	if result.has("reaction"):
		# Not a lie, but this person has something to say about it. The card stays up while they do.
		evidence_presented.emit(_present_id, false)
		_card_lines_left = CARD_LINES_ON_SCREEN
		var beat: Tween = create_tween()
		beat.tween_interval(0.25)
		beat.tween_callback(_play_node.bind(str(result["reaction"])))
		return
	# Not what he is hiding: the card goes back down and he says so.
	evidence_presented.emit(_present_id, false)
	Audio.play("wrong_present")
	_card_tween = create_tween()
	_card_tween.tween_property(self, "present_amount", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_card_tween.tween_callback(_free_present_card)
	_card_tween.tween_callback(_start_interlude.bind(result.get("wrong", [])))


func _free_present_card() -> void:
	if _present_card != null and is_instance_valid(_present_card):
		_present_card.queue_free()
	_present_card = null


# The first expression `speaker_id` wears in a node (used for the flinch when a lie is caught).
func _first_expression_of(node_id: String, speaker_id: String) -> String:
	for line: Variant in _conversation.node(node_id).get("lines", []):
		if str((line as Dictionary).get("speaker", "")) == speaker_id:
			return str((line as Dictionary).get("expression", "neutral"))
	return current_expression


func _start_interlude(wrong_lines: Array) -> void:
	if wrong_lines.is_empty():
		_back_to_where_we_were()
		return
	_resume = { "lines": lines, "index": line_index }
	_interlude = true
	mode = Mode.READING
	lines = wrong_lines
	_show_line(0)


func _end_interlude() -> void:
	_interlude = false
	lines = _resume.get("lines", [])
	if not lines.is_empty():
		_show_line(int(_resume.get("index", 0)), true)
	_back_to_where_we_were()


# ---------- showing lines ----------

func _show_line(index: int, instant: bool = false) -> void:
	line_index = index
	var line: Dictionary = lines[index]
	var speaker_id: String = str(line.get("speaker", ""))
	var info: Dictionary = portraits.get(speaker_id, {})
	if speaker_id != "" and info.is_empty():
		push_warning("DialogueBox: no portrait entry for '%s' in %s" % [speaker_id, portraits_path])
	# A line's "style" changes how it is shown:
	#   thought  James thinking: his portrait, a pencil-grey "(thinking)" name, slanted text
	#   action   a stage direction: no name, no portrait, slanted text
	#   voice    a voice with no face (a phone call): the name only, and a thin pencil edge
	_line_style = str(line.get("style", ""))
	var has_portrait: bool = not info.is_empty() and _line_style != "action" and _line_style != "voice"
	var shown_name: String = str(line.get("name", info.get("display_name", speaker_id)))
	var name_color: Color = Color.html(str(line.get("name_color", info.get("name_color", "#d9ad4d"))))
	var slanted: bool = false
	var text_color: Color = Color.WHITE
	match _line_style:
		"thought":
			shown_name += THOUGHT_NAME_SUFFIX
			name_color = THOUGHT_NAME_COLOR
			slanted = true
		"action":
			shown_name = ""
			slanted = true
			text_color = ACTION_TEXT_COLOR

	name_label.text = shown_name
	name_label.visible = shown_name != ""
	name_label.add_theme_color_override("font_color", name_color)
	text_label.add_theme_font_override("normal_font", _italic_font if slanted else _body_font)
	text_label.add_theme_color_override("default_color", text_color)
	fx.queue_redraw()
	text_label.text = str(line.get("text", ""))
	text_label.visible_ratio = 0.0
	_stop_hint()

	var portrait_changed: bool = speaker_id != current_portrait_id
	if has_portrait:
		portrait.visible = true
		_set_portrait(speaker_id, str(line.get("expression", "neutral")), false, true)
	else:
		current_portrait_id = ""
		portrait.visible = false

	if not is_open:
		is_open = true
		modulate.a = 1.0
		visible = true
		anim.play("open" if has_portrait else "open_text_only")
	elif has_portrait and portrait_changed:
		_finish_running_animation()
		anim.play("swap")

	if _conversation != null and not _interlude:
		_conversation.note_statement(line)
	if _card_lines_left > 0:
		_card_lines_left -= 1
		if _card_lines_left == 0:
			_fade_present_card()

	if instant:
		typing = false
		text_label.visible_ratio = 1.0
	else:
		_start_typing()
	_refresh_prompts()
	line_started.emit(index)


# If an animation is still running, jump it to its end so nothing is left half-faded.
func _finish_running_animation() -> void:
	if anim.is_playing() and anim.current_animation != &"present":
		anim.seek(anim.current_animation_length, true)


func _start_typing() -> void:
	var speed: float = chars_per_second if blocking else chars_per_second * NOTICE_TYPE_SPEEDUP
	var duration: float = maxf(float(text_label.text.length()) / speed, 0.05)
	typing = true
	if type_tween != null:
		type_tween.kill()
	type_tween = create_tween()
	type_tween.tween_property(text_label, "visible_ratio", 1.0, duration)
	type_tween.tween_callback(_on_typed)
	if not blocking:
		type_tween.tween_interval(notice_seconds)
		type_tween.tween_callback(_next_line_or_close)


func _on_typed() -> void:
	typing = false
	if not blocking:
		return
	_refresh_prompts()
	if mode != Mode.READING:
		return
	advance_hint.visible = true
	advance_hint.modulate.a = 1.0
	if hint_tween != null:
		hint_tween.kill()
	hint_tween = create_tween().set_loops()
	hint_tween.tween_property(advance_hint, "modulate:a", 0.2, 0.5)
	hint_tween.tween_property(advance_hint, "modulate:a", 1.0, 0.5)


func _next_line_or_close() -> void:
	if line_index + 1 < lines.size():
		_show_line(line_index + 1)
	elif _interlude:
		_end_interlude()
	elif _conversation != null:
		_after_node_lines()
	else:
		_close()


func _close() -> void:
	_stop_hint()
	if type_tween != null:
		type_tween.kill()
	typing = false
	is_open = false
	_line_style = ""
	fx.queue_redraw()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reset_talk()
	_refresh_prompts()
	anim.play("fade_out")
	dialogue_finished.emit()


# Clears everything that belongs to one conversation.
func _reset_talk() -> void:
	_conversation = null
	_node_id = ""
	_interlude = false
	_resume = {}
	_was_choosing = false
	mode = Mode.READING
	if choices != null:
		choices.hide_choices()
	if picker != null and picker.is_open:
		picker.close(true)
	if portrait != null:
		portrait.self_modulate = Color.WHITE
	_remove_present_card()


func _stop_hint() -> void:
	if hint_tween != null:
		hint_tween.kill()
	advance_hint.visible = false


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"fade_out" and not is_open:
		visible = false
		modulate.a = 1.0
		current_portrait_id = ""
	elif animation_name == &"present":
		_resolve_present()


# The key prompts under the text: only in talks the player controls, and never while a line is typing.
func _refresh_prompts() -> void:
	if prompts == null:
		return
	var context: String = ""
	if blocking and is_open and not typing:
		match mode:
			Mode.PICKING:
				context = "picking"
			Mode.CHOOSING:
				context = "choosing" if can_present_now() else "choosing_only"
			Mode.READING:
				context = "reading_present" if can_present_now() else "reading"
	if context == "":
		prompts.set_suppressed(true)
	else:
		prompts.set_context(context)
		prompts.set_suppressed(false)


# ---------- portrait ----------

# Shows `speaker_id` with `expression`. A new face on the same person cross-fades quickly;
# `slide` plays the full swap animation (used when the portrait changes outside a line).
func _set_portrait(speaker_id: String, expression: String, slide: bool, from_line: bool = false) -> void:
	var info: Dictionary = portraits.get(speaker_id, {})
	if info.is_empty():
		return
	var same_person: bool = speaker_id == current_portrait_id
	var new_face: bool = same_person and expression != current_expression
	current_portrait_id = speaker_id
	current_expression = expression
	portrait.visible = true
	placeholder_color = Color.html(str(info.get("placeholder_color", "#808080")))
	placeholder_name = str(info.get("display_name", speaker_id))
	var texture_path: String = str((info.get("expressions", {}) as Dictionary).get(expression, ""))
	if texture_path == "":
		texture_path = str(info.get("texture", ""))
	if texture_path != "" and ResourceLoader.exists(texture_path):
		portrait.texture = load(texture_path)
	else:
		portrait.texture = null
	portrait.queue_redraw()
	if new_face:
		if _expression_tween != null:
			_expression_tween.kill()
		portrait.modulate.a = 0.45
		_expression_tween = create_tween()
		_expression_tween.tween_property(portrait, "modulate:a", 1.0, EXPRESSION_FADE_SECONDS)
	elif slide and not same_person and not from_line:
		_finish_running_animation()
		var swap: Tween = create_tween().set_parallel(true)
		portrait.position.x = portrait_home.x + PORTRAIT_SLIDE_PX * 0.4
		portrait.modulate.a = 0.0
		swap.tween_property(portrait, "position:x", portrait_home.x, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		swap.tween_property(portrait, "modulate:a", 1.0, 0.2)


# A quick sideways shake that dies away (the card landing, or a lie being caught).
func _shake_portrait(pixels: float, seconds: float) -> void:
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps: int = 6
	for step: int in range(steps):
		var strength: float = pixels * (1.0 - float(step) / float(steps))
		var side: float = -1.0 if step % 2 == 0 else 1.0
		_shake_tween.tween_property(portrait, "position:x", portrait_home.x + side * strength, seconds / float(steps + 1))
	_shake_tween.tween_property(portrait, "position:x", portrait_home.x, seconds / float(steps + 1))


func _flash_vignette() -> void:
	if _fx_tween != null:
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_method(_set_vignette, 0.0, 1.0, 0.15)
	_fx_tween.tween_method(_set_vignette, 1.0, 0.0, 0.35)


func _set_vignette(amount: float) -> void:
	_vignette_amount = amount
	fx.queue_redraw()


func _make_vignette() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color(0.45, 0.05, 0.05, 0.0), Color(0.45, 0.05, 0.05, 0.0), Color(0.45, 0.05, 0.05, 1.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 1.0)
	texture.width = 256
	texture.height = 144
	return texture


# Drawn over everything: the warm flash when a card lands, the dark red edge when a lie is caught.
func _draw_fx() -> void:
	var whole: Rect2 = Rect2(Vector2.ZERO, fx.size)
	if flash_amount > 0.0:
		fx.draw_rect(whole, Color(1.0, 0.95, 0.85, 0.25 * flash_amount))
	if _vignette_amount > 0.0:
		fx.draw_texture_rect(_vignette_tex, whole, false, Color(1.0, 1.0, 1.0, 0.3 * _vignette_amount))
	if _line_style == "voice" and is_open:
		# A voice with no face: a thin pencil line down the left of the text, where a quote mark would be.
		var top: Vector2 = text_home + Vector2(-26.0, 6.0)
		var points: PackedVector2Array = PackedVector2Array()
		var y: float = 0.0
		while y <= 150.0:
			points.append(top + Vector2(sin(y * 0.16) * 1.5, y))
			y += 3.0
		fx.draw_polyline(points, VOICE_EDGE_COLOR, 2.0, true)


# Grey-box stand-in: a tall rectangle with a simple silhouette, drawn only while a portrait has
# no picture yet. The eyebrows show the expression, so a change can be seen without real art.
func _draw_placeholder() -> void:
	if portrait.texture != null:
		return
	var s: Vector2 = portrait.size
	var frame: Rect2 = Rect2(Vector2.ZERO, s)
	portrait.draw_rect(frame, Color(placeholder_color.darkened(0.5), 0.92), true)

	var shoulders: PackedVector2Array = PackedVector2Array()
	var center: Vector2 = Vector2(s.x * 0.5, s.y)
	for i in range(33):
		var angle: float = PI + PI * float(i) / 32.0
		shoulders.append(center + Vector2(cos(angle) * s.x * 0.46, sin(angle) * s.y * 0.38))
	portrait.draw_colored_polygon(shoulders, placeholder_color.darkened(0.2))
	var head: Vector2 = Vector2(s.x * 0.5, s.y * 0.33)
	var radius: float = s.x * 0.2
	portrait.draw_circle(head, radius, placeholder_color)

	# Eyes and eyebrows. Worried: brows up in the middle. Angry: brows down in the middle.
	var inner_lift: float = 0.0
	if current_expression == "worried":
		inner_lift = -radius * 0.16
	elif current_expression == "angry":
		inner_lift = radius * 0.2
	for side: float in [-1.0, 1.0]:
		var eye: Vector2 = head + Vector2(side * radius * 0.4, -radius * 0.05)
		portrait.draw_circle(eye, radius * 0.07, INK)
		var inner: Vector2 = eye + Vector2(-side * radius * 0.2, -radius * 0.26 + inner_lift)
		var outer: Vector2 = eye + Vector2(side * radius * 0.22, -radius * 0.26 - inner_lift * 0.5)
		portrait.draw_line(inner, outer, INK, 7.0, true)

	portrait.draw_rect(frame, GOLD, false, 3.0)
	portrait.draw_string(ThemeDB.fallback_font, Vector2(0.0, 56.0), "%s (portrait placeholder)" % placeholder_name, HORIZONTAL_ALIGNMENT_CENTER, s.x, 28, Color(1, 1, 1, 0.8))
	portrait.draw_string(ThemeDB.fallback_font, Vector2(0.0, 92.0), current_expression, HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, Color(1, 1, 1, 0.6))


# ---------- animations (built here so the scene file stays simple) ----------

func _build_animations() -> void:
	var library: AnimationLibrary = AnimationLibrary.new()
	library.add_animation("open", _slide_anim(true, true, OPEN_SECONDS))
	library.add_animation("open_text_only", _slide_anim(true, false, OPEN_SECONDS))
	library.add_animation("swap", _slide_anim(false, true, SWAP_SECONDS))
	var fade: Animation = Animation.new()
	fade.length = FADE_SECONDS
	_add_value_track(fade, ".:modulate:a", 1.0, 0.0, FADE_SECONDS)
	library.add_animation("fade_out", fade)
	library.add_animation("present", _present_anim())
	anim.add_animation_library("", library)


# The present moment in one animation: the card rises (0.2 to 0.48 s), lands with a sound, a
# flash and a shake, then holds until 0.98 s. When it ends, the result plays.
func _present_anim() -> Animation:
	var a: Animation = Animation.new()
	a.length = PRESENT_SECONDS
	var rise: int = a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(rise, NodePath(".:present_amount"))
	a.track_insert_key(rise, 0.0, 0.0)
	a.track_insert_key(rise, PRESENT_RISE_START, 0.0)
	a.track_insert_key(rise, PRESENT_LAND, 1.0)
	var flash: int = a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(flash, NodePath(".:flash_amount"))
	a.track_insert_key(flash, 0.0, 0.0)
	a.track_insert_key(flash, PRESENT_LAND - 0.01, 0.0)
	a.track_insert_key(flash, PRESENT_LAND + 0.02, 1.0)
	a.track_insert_key(flash, PRESENT_LAND + 0.1, 0.0)
	var calls: int = a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(calls, NodePath("."))
	a.track_insert_key(calls, PRESENT_LAND, { "method": &"_on_present_landed", "args": [] })
	return a


func _slide_anim(with_text: bool, with_portrait: bool, seconds: float) -> Animation:
	var a: Animation = Animation.new()
	a.length = seconds
	if with_portrait:
		_add_value_track(a, "Portrait:position:x", portrait_home.x + PORTRAIT_SLIDE_PX, portrait_home.x, seconds)
		_add_value_track(a, "Portrait:modulate:a", 0.0, 1.0, seconds)
	if with_text:
		_add_value_track(a, "TextBlock:position:y", text_home.y + TEXT_SLIDE_PX, text_home.y, seconds)
		_add_value_track(a, "TextBlock:modulate:a", 0.0, 1.0, seconds)
		_add_value_track(a, "Shade:modulate:a", 0.0, 1.0, seconds)
	return a


func _add_value_track(a: Animation, path: String, from_value: float, to_value: float, seconds: float) -> void:
	var track: int = a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(track, NodePath(path))
	a.track_insert_key(track, 0.0, from_value, 0.4)
	a.track_insert_key(track, seconds, to_value)


# ---------- data ----------

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DialogueBox: missing file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("DialogueBox: %s is not valid JSON" % path)
	return {}
