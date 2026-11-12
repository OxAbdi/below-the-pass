extends Control

# The Case Board. Shows one card per piece of evidence the player holds.
# The player moves cards and drags a string from one card's pin onto another to try a link.
#   - correct pair: the string locks in gold and is stored in GameState
#   - wrong pair: the string snaps back and James reacts
# Clicking a card that belongs to a locked link selects that link: both cards glow, the string
# glows, and the deduction panel on the right slides in. Clicking empty board hides it again.
# Nothing is remembered here. Links and card positions live in GameState.

signal closed

const EvidenceCardScript := preload("res://scripts/mechanics/EvidenceCard.gd")
const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")
const CardScene: PackedScene = preload("res://scenes/mechanics/evidence_card.tscn")
const TAG_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

# The board surface, in this scene's coordinates. Cards stay inside it.
const BOARD_RECT: Rect2 = Rect2(60.0, 130.0, 1040.0, 660.0)
# Where cards and tags may stand: the cork, inside the wooden frame.
const PLAY_RECT: Rect2 = Rect2(84.0, 154.0, 992.0, 612.0)
const GRID_ORIGIN: Vector2 = Vector2(96.0, 180.0)
const GRID_STEP: Vector2 = Vector2(355.0, 250.0)
const GRID_COLUMNS: int = 3

# Minimum empty space between two cards.
const CARD_GAP: float = 40.0
const FREE_SPOT_STEP: float = 10.0

const GOLD: Color = Color(0.98, 0.8, 0.36)
const GOLD_DARK: Color = Color(0.42, 0.26, 0.07)
const LOOSE_STRING: Color = Color(0.98, 0.93, 0.8)
const INK: Color = Color(0.1, 0.08, 0.17)
const DEFAULT_ACCENT: String = "#d9ad4d"

# Paper tag on a locked string. The round hole on the left is where the string "passes through".
const TAG_PAPER: Color = Color(1.0, 0.96, 0.82)
const TAG_TEXT_SIZE: int = 22
const TAG_PAD_LEFT: float = 32.0
const TAG_PAD_RIGHT: float = 16.0
const TAG_HEIGHT: float = 36.0
# The tag hangs this far below its string, on a short thread, so the string stays visible.
const TAG_HANG: float = 14.0

# Board look: walnut frame, gold inlay, warm cork.
const WOOD: Color = Color(0.3, 0.17, 0.1)
const WOOD_GRAIN_DARK: Color = Color(0.12, 0.06, 0.03, 0.3)
const WOOD_GRAIN_LIGHT: Color = Color(0.7, 0.45, 0.25, 0.22)
const CORK: Color = Color(0.64, 0.45, 0.28)
const FRAME_WIDTH: float = 24.0
const SNAP_SECONDS: float = 0.25
const REACTION_SECONDS: float = 4.5
const PANEL_SLIDE_PX: float = 26.0

@export_file("*.json") var board_path: String = "res://data/puzzles/ch01_board.json"
@export_file("*.json") var registry_path: String = "res://data/evidence/evidence_registry.json"

@onready var surface: Control = $Surface
@onready var strings: Control = $Strings
@onready var cards_root: Control = $Cards
@onready var tags: Control = $Tags
@onready var wall: Control = $Wall
@onready var title_label: Label = $Title
@onready var empty_label: Label = $EmptyLabel
@onready var hint_label: Label = $Hint
@onready var detail_panel: Panel = $DetailPanel
@onready var detail_text: RichTextLabel = $DetailPanel/Text
@onready var dialogue: DialogueBoxScript = $DialogueBox

var evidence_registry: Dictionary = {}
var card_ids: Array = []
var link_defs: Array = []
var link_by_pair: Dictionary = {}
var wrong_by_pair: Dictionary = {}
var fallback_reactions: Array = []
var already_linked_line: String = ""
var reaction_name: String = ""

var cards: Dictionary = {}
var link_source: EvidenceCardScript = null
var drag_to: Vector2 = Vector2.ZERO
var highlighted_card: EvidenceCardScript = null
var mouse_linking: bool = false
var fallback_index: int = 0
var snap_tween: Tween
var panel_tween: Tween
var selected_link_id: String = ""

var _panel_x: float = 0.0
var _panel_style: StyleBoxFlat
var _frame_style: StyleBoxFlat
var _bevel_style: StyleBoxFlat
var _inlay_style: StyleBoxFlat
var _cork_style: StyleBoxFlat
var _lip_style: StyleBoxFlat
var _tag_style: StyleBoxFlat
var _vignette: GradientTexture2D
var _lamp_glow: GradientTexture2D
var _wall_glow: GradientTexture2D


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_data()
	_build_styles()
	_panel_x = detail_panel.position.x
	detail_panel.visible = false
	wall.draw.connect(_draw_wall)
	surface.draw.connect(_draw_surface)
	strings.draw.connect(_draw_strings)
	tags.draw.connect(_draw_tags)
	GameState.state_reset.connect(_on_data_changed)
	GameState.evidence_added.connect(_on_evidence_added)


# ---------- public API ----------

func open() -> void:
	visible = true
	rebuild()


func close() -> void:
	_cancel_link()
	_clear_selection(true)
	visible = false
	closed.emit()


# Esc / B / the board key: cancels a started link first, otherwise closes the board.
func request_close() -> void:
	if link_source != null:
		_cancel_link()
	else:
		close()


func rebuild() -> void:
	_cancel_link()
	for child: Node in cards_root.get_children():
		cards_root.remove_child(child)
		child.queue_free()
	cards.clear()
	var index: int = 0
	for id: Variant in card_ids:
		if GameState.has_evidence(str(id)):
			_add_card(str(id), index)
		index += 1
	for id: Variant in card_ids:
		if cards.has(str(id)):
			_keep_card_off_others(cards[str(id)])
	empty_label.visible = cards.is_empty()
	_clear_selection(true)
	_redraw_strings()
	if not cards.is_empty():
		var first_id: String = ""
		for id: Variant in card_ids:
			if cards.has(str(id)):
				first_id = str(id)
				break
		var first: EvidenceCardScript = cards[first_id]
		first.grab_focus()


# ---------- loading ----------

func _load_data() -> void:
	var board: Dictionary = _read_json(board_path)
	evidence_registry = _read_json(registry_path).get("evidence", {})
	title_label.text = str(board.get("title", "CASE BOARD"))
	reaction_name = str(board.get("reaction_name", ""))
	card_ids = board.get("cards", [])
	link_defs = board.get("links", [])
	fallback_reactions = board.get("fallback_reactions", [])
	already_linked_line = str(board.get("already_linked_line", ""))
	for link: Dictionary in link_defs:
		var pair: Array = link.get("pair", [])
		if pair.size() == 2:
			link_by_pair[_pair_key(str(pair[0]), str(pair[1]))] = link
	for wrong: Dictionary in board.get("wrong_reactions", []):
		var wrong_pair: Array = wrong.get("pair", [])
		if wrong_pair.size() == 2:
			wrong_by_pair[_pair_key(str(wrong_pair[0]), str(wrong_pair[1]))] = str(wrong.get("line", ""))


func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _add_card(id: String, index: int) -> void:
	var info: Dictionary = evidence_registry.get(id, {})
	var card: EvidenceCardScript = CardScene.instantiate()
	cards_root.add_child(card)
	card.setup(id, str(info.get("name", id)), str(info.get("description", "")), str(info.get("card_style", "note")), _accent_for(id))
	card.placement_check = _can_place
	card.bounds = PLAY_RECT
	card.position = _clamp_to_board(GameState.get_card_position(id, _default_position(index)))
	card.hovered.connect(_on_card_hovered)
	card.clicked.connect(_on_card_clicked)
	card.moved.connect(_on_card_moved)
	card.move_finished.connect(_on_card_move_finished)
	card.link_drag_started.connect(_on_link_drag_started)
	card.link_drag_moved.connect(_on_link_drag_moved)
	card.link_drag_released.connect(_on_link_drag_released)
	card.activated.connect(_on_card_activated)
	cards[id] = card


func _default_position(index: int) -> Vector2:
	return GRID_ORIGIN + Vector2(index % GRID_COLUMNS, index / GRID_COLUMNS) * GRID_STEP


func _clamp_to_board(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, PLAY_RECT.position.x, PLAY_RECT.end.x - EvidenceCardScript.CARD_SIZE.x),
		clampf(pos.y, PLAY_RECT.position.y, PLAY_RECT.end.y - EvidenceCardScript.CARD_SIZE.y)
	)


# ---------- where cards may stand ----------

# True if a card can stand in this rectangle (same coordinates as card.position)
# without touching another card.
func _can_place(card: EvidenceCardScript, rect: Rect2) -> bool:
	var padded: Rect2 = rect.grow(CARD_GAP * 0.5)
	for other: EvidenceCardScript in cards.values():
		if other == card:
			continue
		if padded.intersects(Rect2(other.position, other.size).grow(CARD_GAP * 0.5)):
			return false
	return true


# If a card (for example from an old saved layout) sits on top of another one, move it to the
# closest empty spot on the board.
func _keep_card_off_others(card: EvidenceCardScript) -> void:
	if _can_place(card, Rect2(card.position, card.size)):
		return
	card.position = _find_free_position(card, card.position)
	GameState.set_card_position(card.evidence_id, card.position)


func _find_free_position(card: EvidenceCardScript, desired: Vector2) -> Vector2:
	var best: Vector2 = desired
	var best_distance: float = INF
	var x: float = PLAY_RECT.position.x
	while x <= PLAY_RECT.end.x - card.size.x:
		var y: float = PLAY_RECT.position.y
		while y <= PLAY_RECT.end.y - card.size.y:
			var candidate: Vector2 = Vector2(x, y)
			var distance: float = candidate.distance_squared_to(desired)
			if distance < best_distance and _can_place(card, Rect2(candidate, card.size)):
				best = candidate
				best_distance = distance
			y += FREE_SPOT_STEP
		x += FREE_SPOT_STEP
	return best


# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()
	elif event.is_action_pressed("board_inspect") and not event.is_echo():
		# Keyboard / pad version of clicking a card: read the link of the focused card.
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is EvidenceCardScript:
			get_viewport().set_input_as_handled()
			_on_card_clicked(focused)


# A click on empty board (cards stop their own clicks) hides the deduction panel.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_select_link("")


func _on_card_hovered(card: EvidenceCardScript) -> void:
	# Keyboard / controller linking: the string follows the focused card.
	if link_source != null and not mouse_linking and card != link_source:
		drag_to = _to_strings_space(card.get_pin_global())
		_redraw_strings()


func _on_card_moved(_card: EvidenceCardScript) -> void:
	_redraw_strings()


func _on_card_move_finished(card: EvidenceCardScript) -> void:
	GameState.set_card_position(card.evidence_id, card.position)


func _on_link_drag_started(card: EvidenceCardScript) -> void:
	mouse_linking = true
	_begin_link(card)
	drag_to = _to_strings_space(card.get_pin_global())


func _on_link_drag_moved(card: EvidenceCardScript, global_mouse: Vector2) -> void:
	if card != link_source:
		return
	drag_to = _to_strings_space(global_mouse)
	_set_highlight(_card_at(global_mouse, card))
	_redraw_strings()


func _on_link_drag_released(card: EvidenceCardScript, global_mouse: Vector2) -> void:
	mouse_linking = false
	if card != link_source:
		return
	_finish_link(card, _card_at(global_mouse, card))


func _on_card_activated(card: EvidenceCardScript) -> void:
	if link_source == null:
		mouse_linking = false
		_begin_link(card)
		drag_to = _to_strings_space(card.get_pin_global())
		_redraw_strings()
	elif card == link_source:
		_cancel_link()
	else:
		_finish_link(link_source, card)


func _on_data_changed() -> void:
	if visible:
		rebuild()


func _on_evidence_added(_evidence_id: String) -> void:
	if visible:
		rebuild()


# ---------- linking ----------

func _begin_link(card: EvidenceCardScript) -> void:
	if snap_tween != null:
		snap_tween.kill()
	_end_link()
	link_source = card
	card.set_linking(true)


func _end_link() -> void:
	if link_source != null and is_instance_valid(link_source):
		link_source.set_linking(false)
	link_source = null
	_set_highlight(null)
	_redraw_strings()


func _cancel_link() -> void:
	if snap_tween != null:
		snap_tween.kill()
	mouse_linking = false
	_end_link()


func _finish_link(source: EvidenceCardScript, target: EvidenceCardScript) -> void:
	_set_highlight(null)
	if target == null or target == source:
		_snap_back(source)
		return
	var key: String = _pair_key(source.evidence_id, target.evidence_id)
	if link_by_pair.has(key):
		var link: Dictionary = link_by_pair[key]
		var link_id: String = str(link.get("link_id", ""))
		if GameState.has_link(link_id):
			_snap_back(source)
			_say(already_linked_line)
		else:
			GameState.add_link(link_id)
			_end_link()
			source.pulse()
			target.pulse()
			_select_link(link_id)
			_say(str(link.get("line", "")))
	else:
		_snap_back(source)
		target.shake()
		_say(_wrong_line(key))


func _wrong_line(key: String) -> String:
	if wrong_by_pair.has(key):
		return wrong_by_pair[key]
	if fallback_reactions.is_empty():
		return ""
	var line: String = str(fallback_reactions[fallback_index % fallback_reactions.size()])
	fallback_index += 1
	return line


# The loose end of the string springs back to the pin it came from.
func _snap_back(source: EvidenceCardScript) -> void:
	var start: Vector2 = drag_to
	var end: Vector2 = _to_strings_space(source.get_pin_global())
	if snap_tween != null:
		snap_tween.kill()
	snap_tween = create_tween()
	snap_tween.tween_method(
		func(amount: float) -> void:
			drag_to = start.lerp(end, amount)
			_redraw_strings(),
		0.0, 1.0, SNAP_SECONDS
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	snap_tween.tween_callback(_end_link)


func _say(line: String) -> void:
	if line == "":
		return
	# No "speaker" key means a text-only line (no portrait). "name" is the label shown above it.
	dialogue.play_lines([{ "name": reaction_name, "text": line }], false, REACTION_SECONDS)


func _card_at(global_point: Vector2, exclude: EvidenceCardScript) -> EvidenceCardScript:
	var children: Array[Node] = cards_root.get_children()
	for i: int in range(children.size() - 1, -1, -1):
		var card: EvidenceCardScript = children[i]
		if card == exclude:
			continue
		var local_point: Vector2 = card.get_global_transform().affine_inverse() * global_point
		if Rect2(Vector2.ZERO, card.size).has_point(local_point):
			return card
	return null


func _set_highlight(card: EvidenceCardScript) -> void:
	if highlighted_card == card:
		return
	if highlighted_card != null and is_instance_valid(highlighted_card):
		highlighted_card.highlighted = false
	highlighted_card = card
	if card != null:
		card.highlighted = true


func _to_strings_space(global_point: Vector2) -> Vector2:
	return strings.get_global_transform().affine_inverse() * global_point


# ---------- selecting a link ----------

# Clicking a card (or pressing Q / pad X on the focused card) reads the locked link it belongs to.
# If the card belongs to several locked links, each click moves on to the next one.
func _on_card_clicked(card: EvidenceCardScript) -> void:
	var options: Array[Dictionary] = _locked_links_of(card.evidence_id)
	if options.is_empty():
		_select_link("")
		return
	var chosen: String = str(options[0].get("link_id", ""))
	for i: int in range(options.size()):
		if str(options[i].get("link_id", "")) == selected_link_id:
			chosen = str(options[(i + 1) % options.size()].get("link_id", ""))
			break
	_select_link(chosen)


func _locked_links_of(evidence_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for link: Dictionary in link_defs:
		var pair: Array = link.get("pair", [])
		if pair.size() != 2 or not (str(pair[0]) == evidence_id or str(pair[1]) == evidence_id):
			continue
		if _locked_string_points(link).is_empty():
			continue
		result.append(link)
	return result


func _link_by_id(link_id: String) -> Dictionary:
	for link: Dictionary in link_defs:
		if str(link.get("link_id", "")) == link_id:
			return link
	return {}


func _select_link(link_id: String) -> void:
	var link: Dictionary = _link_by_id(link_id)
	if link.is_empty():
		_clear_selection(false)
		return
	selected_link_id = link_id
	var pair: Array = link.get("pair", [])
	for card: EvidenceCardScript in cards.values():
		card.selected = card.evidence_id == str(pair[0]) or card.evidence_id == str(pair[1])
	hint_label.visible = false
	_show_link_panel(link)
	_redraw_strings()


func _clear_selection(instant: bool) -> void:
	selected_link_id = ""
	for card: EvidenceCardScript in cards.values():
		card.selected = false
	hint_label.visible = not cards.is_empty()
	if panel_tween != null:
		panel_tween.kill()
	if instant or not detail_panel.visible:
		detail_panel.visible = false
		detail_panel.modulate.a = 1.0
		detail_panel.position.x = _panel_x
	else:
		panel_tween = create_tween()
		panel_tween.tween_property(detail_panel, "modulate:a", 0.0, 0.15)
		panel_tween.tween_callback(func() -> void: detail_panel.visible = false)
	_redraw_strings()


func _show_link_panel(link: Dictionary) -> void:
	var pair: Array = link.get("pair", [])
	var accent: Color = _link_accent(link)
	_panel_style.border_color = accent
	_panel_style.shadow_color = Color(accent, 0.35)
	var text: String = "[font_size=36][color=#%s]%s[/color][/font_size]\n\n" % [GOLD.to_html(false), _bb(str(link.get("deduction", "")))]
	var line: String = str(link.get("line", ""))
	if line != "":
		text += "[color=#f4efe2]\"%s\"[/color]\n" % _bb(line)
		if reaction_name != "":
			text += "[color=#a99fcb]- %s[/color]\n" % _bb(reaction_name)
		text += "\n"
	text += "[color=#a99fcb][font_size=18]EVIDENCE[/font_size][/color]\n"
	for id: Variant in pair:
		var info: Dictionary = evidence_registry.get(str(id), {})
		var shown: Color = _accent_for(str(id)).lerp(Color.WHITE, 0.3)
		text += "[color=#%s][b]%s[/b][/color]\n[color=#e8e2f2]%s[/color]\n\n" % [shown.to_html(false), _bb(str(info.get("name", id))), _bb(str(info.get("description", "")))]
	detail_text.text = text
	if panel_tween != null:
		panel_tween.kill()
	detail_panel.visible = true
	detail_panel.modulate.a = 0.0
	detail_panel.position.x = _panel_x + PANEL_SLIDE_PX
	panel_tween = create_tween().set_parallel(true)
	panel_tween.tween_property(detail_panel, "modulate:a", 1.0, 0.2)
	panel_tween.tween_property(detail_panel, "position:x", _panel_x, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Stops story text from being read as BBCode.
func _bb(text: String) -> String:
	return text.replace("[", "[lb]")


func _accent_for(evidence_id: String) -> Color:
	var info: Dictionary = evidence_registry.get(evidence_id, {})
	return Color.html(str(info.get("accent", DEFAULT_ACCENT)))


func _link_accent(link: Dictionary) -> Color:
	var pair: Array = link.get("pair", [])
	if pair.size() != 2:
		return GOLD
	return _accent_for(str(pair[0])).lerp(_accent_for(str(pair[1])), 0.5)


# ---------- styles ----------

func _build_styles() -> void:
	_panel_style = detail_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_frame_style = _flat(WOOD, INK, 3, 24)
	_frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	_frame_style.shadow_size = 30
	_frame_style.shadow_offset = Vector2(0.0, 12.0)
	_bevel_style = _flat(Color(0.0, 0.0, 0.0, 0.0), Color(1.0, 0.78, 0.5, 0.22), 2, 22)
	_inlay_style = _flat(Color(0.0, 0.0, 0.0, 0.0), Color(0.96, 0.76, 0.34, 0.9), 2, 16)
	_cork_style = _flat(CORK, Color(0.0, 0.0, 0.0, 0.0), 0, 10)
	_lip_style = _flat(Color(0.0, 0.0, 0.0, 0.0), Color(INK, 0.95), 4, 11)
	_tag_style = _flat(TAG_PAPER, INK, 2, 9)
	_tag_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	_tag_style.shadow_size = 6
	_tag_style.shadow_offset = Vector2(0.0, 3.0)
	_vignette = _radial([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.5)], [0.0, 0.55, 1.0], Vector2i(256, 168), Vector2(0.5, 0.5), Vector2(1.0, 1.0))
	_lamp_glow = _radial([Color(1.0, 0.84, 0.52, 0.24), Color(1.0, 0.84, 0.52, 0.0)], [0.0, 1.0], Vector2i(256, 168), Vector2(0.5, 0.38), Vector2(1.0, 0.95))
	_wall_glow = _radial([Color(1.0, 0.56, 0.42, 0.3), Color(1.0, 0.56, 0.42, 0.0)], [0.0, 1.0], Vector2i(256, 256), Vector2(0.5, 0.5), Vector2(1.0, 0.5))


func _flat(fill: Color, outline: Color, outline_width: int, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_border_width_all(outline_width)
	box.set_corner_radius_all(radius)
	return box


func _radial(colors: Array, offsets: Array, texture_size: Vector2i, from: Vector2, to: Vector2) -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array(offsets)
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = from
	texture.fill_to = to
	texture.width = texture_size.x
	texture.height = texture_size.y
	return texture


# ---------- drawing the strings ----------

# Strings are drawn under the cards. The paper tags are drawn on a layer above the
# cards so a card never hides a tag.
func _redraw_strings() -> void:
	strings.queue_redraw()
	tags.queue_redraw()


func _draw_strings() -> void:
	for link: Dictionary in link_defs:
		var points: PackedVector2Array = _locked_string_points(link)
		if points.is_empty():
			continue
		if str(link.get("link_id", "")) == selected_link_id:
			var glow: Color = _link_accent(link).lerp(Color.WHITE, 0.2)
			strings.draw_polyline(points, Color(glow, 0.16), 26.0, true)
			strings.draw_polyline(points, Color(glow, 0.3), 16.0, true)
		_draw_gold_string(points)
	if link_source != null:
		var loose: PackedVector2Array = _string_points(_to_strings_space(link_source.get_pin_global()), drag_to)
		strings.draw_polyline(_shifted(loose, Vector2(0.0, 5.0)), Color(0.0, 0.0, 0.0, 0.3), 6.0, true)
		strings.draw_polyline(loose, Color(0.3, 0.2, 0.1), 5.0, true)
		strings.draw_polyline(loose, LOOSE_STRING, 3.0, true)


func _draw_gold_string(points: PackedVector2Array) -> void:
	strings.draw_polyline(_shifted(points, Vector2(0.0, 6.0)), Color(0.0, 0.0, 0.0, 0.32), 9.0, true)
	strings.draw_polyline(points, GOLD_DARK, 9.0, true)
	strings.draw_polyline(points, GOLD, 6.0, true)
	strings.draw_polyline(_shifted(points, Vector2(0.0, -1.5)), Color(1.0, 0.97, 0.8, 0.7), 1.8, true)


func _shifted(points: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		result.append(point + delta)
	return result


# Only the link being read gets a name tag. Every other locked string just carries a small
# brass knot, so the board stays clean and the text appears when the player clicks.
func _draw_tags() -> void:
	var rects: Array[Rect2] = _card_rects()
	for link: Dictionary in link_defs:
		var points: PackedVector2Array = _locked_string_points(link)
		if points.is_empty() or str(link.get("link_id", "")) == selected_link_id:
			continue
		_draw_knot(_visible_anchors(points, rects)[0], false)
	for entry: Dictionary in _layout_tags(false):
		_draw_tag(entry)


# The knot is the "node" on the string. A tag thread always ends on a knot.
func _draw_knot(center: Vector2, active: bool) -> void:
	tags.draw_circle(center + Vector2(1.5, 3.0), 9.0, Color(0.0, 0.0, 0.0, 0.4))
	if active:
		tags.draw_circle(center, 13.0, Color(1.0, 0.95, 0.75, 0.55))
	tags.draw_circle(center, 9.0, GOLD_DARK)
	tags.draw_circle(center, 7.0, GOLD)
	tags.draw_circle(center + Vector2(-1.8, -2.0), 2.4, Color(1.0, 0.97, 0.8, 0.9))


# Card rectangles in the same coordinates as the strings (a little larger than the cards).
func _card_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for card: EvidenceCardScript in cards.values():
		rects.append(Rect2(_to_strings_space(cards_root.get_global_transform() * card.position), card.size).grow(10.0))
	return rects


# Points of a string that can be seen (not hidden behind a card), nearest to the middle first.
# The knot and the tag thread are placed on these, so they always point at a visible part of the string.
func _visible_anchors(points: PackedVector2Array, rects: Array[Rect2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var mid: int = points.size() / 2
	for distance: int in range(points.size()):
		for index: int in [mid - distance, mid + distance]:
			if index < 3 or index > points.size() - 4:
				continue
			if distance > 0 and index == mid + distance and mid - distance == mid + distance:
				continue
			var hidden: bool = false
			for rect: Rect2 in rects:
				if rect.has_point(points[index]):
					hidden = true
					break
			if not hidden:
				result.append(points[index])
	if result.is_empty():
		result.append(points[mid])
	return result


# Works out where each tag sits. The tag hangs from a knot on a visible part of its own string.
# It prefers a spot that covers no card and no other tag. If the string is squeezed between
# cards, the tag moves out into the nearest empty cork, still tied to the knot by its thread.
func _layout_tags(all_links: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var taken: Array[Rect2] = []
	var card_rects: Array[Rect2] = _card_rects()
	for link: Dictionary in link_defs:
		var points: PackedVector2Array = _locked_string_points(link)
		var text: String = str(link.get("deduction", ""))
		if points.is_empty() or text == "":
			continue
		if not all_links and str(link.get("link_id", "")) != selected_link_id:
			continue
		var tag_size: Vector2 = Vector2(TAG_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAG_TEXT_SIZE).x + TAG_PAD_LEFT + TAG_PAD_RIGHT, TAG_HEIGHT)
		var anchors: Array[Vector2] = _visible_anchors(points, card_rects)
		var chosen: Rect2 = _tag_rect_at(anchors[0], tag_size, false)
		var anchor: Vector2 = anchors[0]
		var least_covered: float = INF
		var done: bool = false
		# 1. Hang the tag from a visible spot of the string: below it first, then above it.
		for i: int in range(0, mini(anchors.size(), 24), 2):
			for above: bool in [false, true]:
				var rect: Rect2 = _tag_rect_at(anchors[i], tag_size, above)
				if _hits_any(rect, taken):
					continue
				var covered: float = _tag_cost(rect, anchors[i], card_rects)
				if covered < least_covered:
					least_covered = covered
					chosen = rect
					anchor = anchors[i]
				if covered == 0.0:
					done = true
					break
			if done:
				break
		# 2. Nothing free right there: look for empty cork around the first visible spot.
		if not done:
			var radius: float = 50.0
			while radius <= 460.0 and not done:
				for step: int in range(16):
					var angle: float = TAU * float(step) / 16.0
					var center: Vector2 = anchors[0] + Vector2(cos(angle), sin(angle)) * radius
					var rect: Rect2 = _clamp_tag(Rect2(center - tag_size * 0.5, tag_size))
					if _hits_any(rect, taken):
						continue
					var covered: float = _tag_cost(rect, anchors[0], card_rects)
					if covered < least_covered:
						least_covered = covered
						chosen = rect
						anchor = anchors[0]
					if covered == 0.0:
						done = true
						break
				radius += 30.0
		taken.append(chosen)
		result.append({ "rect": chosen, "anchor": anchor, "text": text, "link_id": str(link.get("link_id", "")), "accent": _link_accent(link) })
	return result


func _tag_rect_at(anchor: Vector2, tag_size: Vector2, above: bool) -> Rect2:
	var top_left: Vector2 = anchor + Vector2(-tag_size.x * 0.5, -TAG_HANG - tag_size.y if above else TAG_HANG)
	return _clamp_tag(Rect2(top_left, tag_size))


func _clamp_tag(rect: Rect2) -> Rect2:
	return Rect2(
		Vector2(
			clampf(rect.position.x, PLAY_RECT.position.x, PLAY_RECT.end.x - rect.size.x),
			clampf(rect.position.y, PLAY_RECT.position.y, PLAY_RECT.end.y - rect.size.y)
		),
		rect.size
	)


# How bad a tag position is: card area it hides, plus a big penalty if its thread crosses a card.
func _tag_cost(rect: Rect2, anchor: Vector2, card_rects: Array[Rect2]) -> float:
	var cost: float = _covered_area(rect, card_rects)
	var hook: Vector2 = _hook_for(anchor, rect)
	for i: int in range(1, 13):
		var point: Vector2 = anchor.lerp(hook, float(i) / 12.0)
		for card_rect: Rect2 in card_rects:
			if card_rect.grow(-8.0).has_point(point):
				return cost + 1000.0
	return cost


# Where the thread meets the tag: the nearest point on the tag's top, bottom or side.
func _hook_for(anchor: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clampf(anchor.x, rect.position.x + 14.0, rect.end.x - 14.0), clampf(anchor.y, rect.position.y + 2.0, rect.end.y - 2.0))


func _covered_area(rect: Rect2, others: Array[Rect2]) -> float:
	var total: float = 0.0
	for other: Rect2 in others:
		var overlap: Rect2 = rect.intersection(other)
		total += overlap.size.x * overlap.size.y
	return total


func _hits_any(rect: Rect2, others: Array[Rect2]) -> bool:
	for other: Rect2 in others:
		if rect.grow(4.0).intersects(other):
			return true
	return false


# The curve of a locked link, or an empty array if it is not locked or a card is not on the board.
func _locked_string_points(link: Dictionary) -> PackedVector2Array:
	if not GameState.has_link(str(link.get("link_id", ""))):
		return PackedVector2Array()
	var pair: Array = link.get("pair", [])
	if pair.size() != 2 or not cards.has(str(pair[0])) or not cards.has(str(pair[1])):
		return PackedVector2Array()
	var card_a: EvidenceCardScript = cards[str(pair[0])]
	var card_b: EvidenceCardScript = cards[str(pair[1])]
	return _string_points(_to_strings_space(card_a.get_pin_global()), _to_strings_space(card_b.get_pin_global()))


func _string_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var sag: float = clampf(from.distance_to(to) * 0.15, 10.0, 70.0)
	var control: Vector2 = (from + to) * 0.5 + Vector2(0.0, sag)
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(33):
		var t: float = float(i) / 32.0
		points.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return points


func _draw_tag(entry: Dictionary) -> void:
	var rect: Rect2 = entry["rect"]
	var accent: Color = entry["accent"]
	var is_selected: bool = str(entry["link_id"]) == selected_link_id
	# Thread from the string down to the tag.
	var anchor: Vector2 = entry["anchor"]
	var hook: Vector2 = _hook_for(anchor, rect)
	tags.draw_line(anchor, hook, GOLD_DARK, 4.0, true)
	tags.draw_line(anchor, hook, GOLD, 2.0, true)
	_draw_knot(anchor, true)
	_tag_style.border_color = accent.darkened(0.1) if is_selected else INK
	_tag_style.set_border_width_all(3 if is_selected else 2)
	_tag_style.bg_color = TAG_PAPER if is_selected else TAG_PAPER.darkened(0.05)
	tags.draw_style_box(_tag_style, rect)
	# The punched hole, with a little gold thread through it.
	var hole: Vector2 = rect.position + Vector2(17.0, rect.size.y * 0.5)
	tags.draw_circle(hole, 6.5, Color(0.7, 0.55, 0.3, 0.9))
	tags.draw_circle(hole, 4.5, Color(0.2, 0.13, 0.1))
	tags.draw_arc(hole, 6.0, 0.0, TAU, 20, GOLD, 1.5, true)
	tags.draw_string(TAG_FONT, rect.position + Vector2(TAG_PAD_LEFT, 26.0), str(entry["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAG_TEXT_SIZE, INK)


# ---------- drawing the wall and the board ----------

func _draw_wall() -> void:
	var full: Rect2 = Rect2(Vector2.ZERO, wall.size)
	var top: Color = Color(0.07, 0.06, 0.2)
	var bottom: Color = Color(0.23, 0.09, 0.2)
	wall.draw_polygon(
		PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)
	# A warm glow behind the board and a cool one behind the reading panel.
	var board_center: Vector2 = surface.position + surface.size * 0.5
	var warm: Vector2 = Vector2(1900.0, 1400.0)
	wall.draw_texture_rect(_wall_glow, Rect2(board_center - warm * 0.5, warm), false)
	var cool: Vector2 = Vector2(1100.0, 900.0)
	wall.draw_texture_rect(_wall_glow, Rect2(Vector2(1510.0, 400.0) - cool * 0.5, cool), false, Color(0.45, 0.55, 1.0, 0.8))
	# Floating dust, lit by the lamp.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in range(70):
		var spot: Vector2 = Vector2(rng.randf() * full.size.x, rng.randf() * full.size.y)
		wall.draw_circle(spot, rng.randf_range(1.0, 3.2), Color(1.0, 0.9, 0.85, rng.randf_range(0.04, 0.16)))


func _draw_surface() -> void:
	var full: Rect2 = Rect2(Vector2.ZERO, surface.size)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	# Walnut frame: body, bevel, grain, gold inlay.
	surface.draw_style_box(_frame_style, full)
	surface.draw_style_box(_bevel_style, full.grow(-2.0))
	_draw_frame_grain(full, rng)
	surface.draw_style_box(_inlay_style, full.grow(-8.0))
	# Cork with fine speckles, lamp light and a soft vignette.
	var inner: Rect2 = full.grow(-FRAME_WIDTH)
	surface.draw_style_box(_cork_style, inner)
	var speckles: Array[Color] = [Color(0.8, 0.6, 0.38, 0.45), Color(0.4, 0.25, 0.14, 0.32), Color(0.72, 0.5, 0.32, 0.5)]
	for i: int in range(650):
		var spot: Vector2 = inner.position + Vector2(rng.randf() * inner.size.x, rng.randf() * inner.size.y)
		surface.draw_circle(spot, rng.randf_range(0.8, 2.2), speckles[rng.randi() % speckles.size()])
	surface.draw_texture_rect(_lamp_glow, inner, false)
	surface.draw_texture_rect(_vignette, inner, false)
	surface.draw_style_box(_lip_style, inner.grow(2.0))
	# Brass rivets.
	var inset: float = 12.0
	for spot: Vector2 in [
		Vector2(inset, inset), Vector2(full.size.x - inset, inset),
		Vector2(inset, full.size.y - inset), full.size - Vector2(inset, inset),
		Vector2(full.size.x * 0.5, inset), Vector2(full.size.x * 0.5, full.size.y - inset),
		Vector2(inset, full.size.y * 0.5), Vector2(full.size.x - inset, full.size.y * 0.5)
	]:
		_draw_rivet(spot)


func _draw_frame_grain(full: Rect2, rng: RandomNumberGenerator) -> void:
	var band: float = FRAME_WIDTH - 6.0
	var edge: float = 28.0
	for i: int in range(34):
		var color: Color = WOOD_GRAIN_DARK if i % 2 == 0 else WOOD_GRAIN_LIGHT
		var offset: float = rng.randf_range(6.0, band)
		var x0: float = rng.randf_range(edge, full.size.x - edge - 40.0)
		var x1: float = minf(x0 + rng.randf_range(40.0, 170.0), full.size.x - edge)
		surface.draw_line(Vector2(x0, offset), Vector2(x1, offset + rng.randf_range(-1.0, 1.0)), color, 1.2, true)
		var x2: float = rng.randf_range(edge, full.size.x - edge - 40.0)
		var x3: float = minf(x2 + rng.randf_range(40.0, 170.0), full.size.x - edge)
		surface.draw_line(Vector2(x2, full.size.y - offset), Vector2(x3, full.size.y - offset + rng.randf_range(-1.0, 1.0)), color, 1.2, true)
		var y0: float = rng.randf_range(edge, full.size.y - edge - 40.0)
		var y1: float = minf(y0 + rng.randf_range(40.0, 150.0), full.size.y - edge)
		surface.draw_line(Vector2(offset, y0), Vector2(offset + rng.randf_range(-1.0, 1.0), y1), color, 1.2, true)
		var y2: float = rng.randf_range(edge, full.size.y - edge - 40.0)
		var y3: float = minf(y2 + rng.randf_range(40.0, 150.0), full.size.y - edge)
		surface.draw_line(Vector2(full.size.x - offset, y2), Vector2(full.size.x - offset + rng.randf_range(-1.0, 1.0), y3), color, 1.2, true)


func _draw_rivet(center: Vector2) -> void:
	surface.draw_circle(center + Vector2(0.0, 1.5), 6.5, Color(0.0, 0.0, 0.0, 0.35))
	surface.draw_circle(center, 6.0, Color(0.2, 0.11, 0.04))
	surface.draw_circle(center, 4.8, Color(0.88, 0.66, 0.28))
	surface.draw_circle(center + Vector2(-1.0, -1.2), 2.8, Color(1.0, 0.88, 0.55))
	surface.draw_circle(center + Vector2(-1.6, -1.9), 1.2, Color(1.0, 1.0, 0.92))


# ---------- data ----------

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CaseBoard: missing file %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("CaseBoard: %s is not valid JSON" % path)
	return {}
