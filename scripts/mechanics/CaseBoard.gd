extends Control

# The Case Board (Milestone 4, notebook and handwriting from M4.2).
#
#   Notebook  James's pocket notebook on the left. It holds every clue, Lead and Conclusion the player has
#             and has not pinned. Drag one onto the board to pin it.
#   Board     at most `max_pinned` cards stand on the cork.
#   Questions index cards along the top. Each one is answered by linking exactly two cards.
#   Merging   a correct link folds the two cards into one deduction card. A deduction that still has to be
#             combined further is a LEAD (a torn notebook page with a loose end of string). One that does not
#             is a CONCLUSION (a finished index card, it cannot be linked).
#
# Nothing persistent is kept here. GameState holds links, pinned cards, positions, seen flags and
# wrong tries. Everything else (held, used, visible and solved) is worked out from GameState plus the
# JSON, so an old save can never show a half-merged board.

signal closed

const EvidenceCardScript := preload("res://scripts/mechanics/EvidenceCard.gd")
const TrayCardScript := preload("res://scripts/mechanics/TrayCard.gd")
const NotebookScript := preload("res://scripts/mechanics/Notebook.gd")
const PromptBarScript := preload("res://scripts/mechanics/PromptBar.gd")
const QuestionCardScript := preload("res://scripts/mechanics/QuestionCard.gd")
const DialogueBoxScript := preload("res://scripts/ui/DialogueBox.gd")
const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const EvidenceCatalog := preload("res://scripts/data/EvidenceCatalog.gd")
const CardScene: PackedScene = preload("res://scenes/mechanics/evidence_card.tscn")
const TITLE_FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")

# The board surface, in this scene's coordinates. Cards stay inside it.
const BOARD_RECT: Rect2 = Rect2(380.0, 56.0, 1040.0, 734.0)
# Where cards may stand: the cork inside the wooden frame, below the question cards.
const PLAY_RECT: Rect2 = Rect2(404.0, 100.0, 992.0, 666.0)
const GRID_ORIGIN: Vector2 = Vector2(430.0, 170.0)
const GRID_STEP: Vector2 = Vector2(310.0, 260.0)
const GRID_COLUMNS: int = 3

# Minimum empty space between two cards.
const CARD_GAP: float = 40.0
const FREE_SPOT_STEP: float = 10.0

# Question cards along the top of the board, and the solved chips beside the case-notes page.
const MAX_OPEN_QUESTIONS: int = 3
const CHIP_STEP: Vector2 = Vector2(222.0, 64.0)
const CHIP_COLUMNS: int = 2
const GHOST_SMALL_SCALE: float = 0.4
# After this many wrong links, the soft hint makes the answer cards glow.
const HINT_AFTER_WRONG_TRIES: int = 3
# The question card waits for its ink tick and strike-through before it moves to the chips.
const QUESTION_MOVE_DELAY: float = 0.8
const BLOOM_SECONDS: float = 0.4
const BLOOM_SIZE: float = 380.0

const GOLD: Color = Color(0.98, 0.8, 0.36)
const GOLD_DARK: Color = Color(0.42, 0.26, 0.07)
const LOOSE_STRING: Color = Color(0.98, 0.93, 0.8)
const INK: Color = Color(0.1, 0.08, 0.17)
const DEFAULT_ACCENT: String = "#d9ad4d"

# Board look: walnut frame, gold inlay, warm cork.
const LEATHER: Color = Color(0.231, 0.122, 0.094)
const BRASS: Color = Color(0.85, 0.68, 0.3)
const BRASS_DARK: Color = Color(0.72, 0.525, 0.184)
const LEATHER_INK: Color = Color(0.17, 0.11, 0.08)
const OXBLOOD: Color = Color(0.56, 0.17, 0.15)
const WOOD: Color = Color(0.3, 0.17, 0.1)
const WOOD_GRAIN_DARK: Color = Color(0.12, 0.06, 0.03, 0.3)
const WOOD_GRAIN_LIGHT: Color = Color(0.7, 0.45, 0.25, 0.22)
const CORK: Color = Color(0.64, 0.45, 0.28)
const FRAME_WIDTH: float = 24.0
const SNAP_SECONDS: float = 0.25
const REACTION_SECONDS: float = 4.5
const PANEL_SLIDE_PX: float = 26.0
const MERGE_GLOW_SECONDS: float = 0.18
const MERGE_SLIDE_SECONDS: float = 0.35
const TAG_SIZE: Vector2 = Vector2(300.0, 64.0)
const TAG_PAPER: Color = Color(0.953, 0.918, 0.827)
const SEPIA: Color = Color(0.478, 0.384, 0.282)
const NOTES_INK: Color = Color(0.169, 0.114, 0.078)

@export_file("*.json") var board_path: String = "res://data/puzzles/ch01_board.json"
@export_file("*.json") var registry_path: String = "res://data/evidence/evidence_registry.json"

@onready var surface: Control = $Surface
@onready var strings: Control = $Strings
@onready var cards_root: Control = $Cards
@onready var solved_strip: Control = $SolvedStrip
@onready var notebook: NotebookScript = $Tray
@onready var plate: Control = $Plate
@onready var case_tag: Control = $CaseTag
@onready var ghost_layer: Control = $Ghost
@onready var wall: Control = $Wall
@onready var empty_label: Label = $EmptyLabel
@onready var detail_panel: Panel = $DetailPanel
@onready var detail_text: RichTextLabel = $DetailPanel/Text
@onready var prompt_bar: PromptBarScript = $PromptBar
@onready var dialogue: DialogueBoxScript = $DialogueBox

var evidence_registry: Dictionary = {}
var card_ids: Array = []
var question_defs: Array = []
var link_defs: Array = []
var link_by_pair: Dictionary = {}
var link_by_id: Dictionary = {}
var deduction_link: Dictionary = {}  # deduction_id -> the link that makes it
var question_by_link: Dictionary = {}  # link_id -> the question it answers
var wrong_by_pair: Dictionary = {}
var fallback_reactions: Array = []
var already_linked_line: String = ""
var board_full_line: String = ""
var reaction_name: String = ""
var max_pinned: int = 6
var case_title: String = ""
var chapter_text: String = ""
var intro_lines: Array = []
var settled_line: String = ""
var empty_notes_text: String = ""
var empty_notebook_text: String = ""
var lead_ids: Dictionary = {}  # deduction_id -> true if another link still uses it (a Lead)

var cards: Dictionary = {}  # id -> EvidenceCard, the cards standing on the board
# The rows and their order live in the notebook. These are read-only views of them.
var tray_cards: Dictionary:
	get:
		return notebook.rows
var tray_order: Array[String]:
	get:
		return notebook.order
var question_nodes: Dictionary = {}  # question_id -> open QuestionCard
var chip_nodes: Dictionary = {}  # question_id -> solved chip

var link_source: EvidenceCardScript = null
var drag_to: Vector2 = Vector2.ZERO
var highlighted_card: EvidenceCardScript = null
var mouse_linking: bool = false
var fallback_index: int = 0
var selected_link_id: String = ""

var snap_tween: Tween
var panel_tween: Tween
var merge_tween: Tween
var question_tween: Tween
var line_tween: Tween
var plate_tween: Tween
var bloom_tween: Tween

var _busy: bool = false  # true while two cards are folding into a deduction
var _dirty: bool = false  # something changed during a drag or merge; rebuild afterwards
var _ghost: EvidenceCardScript = null
var _ghost_source: TrayCardScript = null
var _ghost_big: bool = false
var _tray_hot: bool = false
var _notebook_open_pref: bool = false  # how the player left the notebook this session (a UI var, never saved)
var _plate_red: bool = false
var _intro_delay: float = 0.0
var _moving_card: EvidenceCardScript = null
var _moving_start_card: EvidenceCardScript = null
var _moving_start: Vector2 = Vector2.ZERO
var _bloom_center: Vector2 = Vector2.ZERO
var _bloom_alpha: float = 0.0
var _merge_pair: Array = []
var _merge_glow: float = 0.0
var _panel_x: float = 0.0
var _panel_style: StyleBoxFlat
var _notes_heading: String = ""  # the title of the link being read (its hand-drawn underline is drawn under it)
var _frame_style: StyleBoxFlat
var _bevel_style: StyleBoxFlat
var _inlay_style: StyleBoxFlat
var _cork_style: StyleBoxFlat
var _lip_style: StyleBoxFlat
var _brass_style: StyleBoxFlat
var _bloom_tex: GradientTexture2D
var _vignette: GradientTexture2D
var _lamp_glow: GradientTexture2D
var _wall_glow: GradientTexture2D
var _desk_vignette: GradientTexture2D


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_data()
	_build_styles()
	_panel_x = detail_panel.position.x
	for item: CanvasItem in [wall, surface, detail_panel]:
		item.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	wall.draw.connect(_draw_wall)
	surface.draw.connect(_draw_surface)
	strings.draw.connect(_draw_strings)
	plate.draw.connect(_draw_plate)
	case_tag.draw.connect(_draw_case_tag)
	detail_panel.draw.connect(_draw_notes_overlay)
	detail_text.finished.connect(detail_panel.queue_redraw)
	notebook.toggled.connect(_on_notebook_toggled)
	notebook.entry_clicked.connect(_on_tray_card_clicked)
	notebook.entry_activated.connect(_on_tray_card_activated)
	notebook.entry_drag_started.connect(_on_tray_drag_started)
	notebook.entry_drag_moved.connect(_on_tray_drag_moved)
	notebook.entry_drag_released.connect(_on_tray_drag_released)
	# The dialogue's dark fade starts at y=540, which would dirty the notes page and notebook.
	# On this screen only the area under the board needs it.
	dialogue.shade.offset_top = 770.0
	GameState.state_reset.connect(_on_data_changed)
	GameState.evidence_added.connect(_on_evidence_added)


# ---------- public API ----------

func open() -> void:
	visible = true
	# The first time the board opens in a save, James says how it works (once, then never again).
	var intro: Array = []
	if not GameState.board_intro_seen and not intro_lines.is_empty():
		GameState.board_intro_seen = true
		for line: Variant in intro_lines:
			intro.append({ "name": reaction_name, "text": str(line) })
		_intro_delay = REACTION_SECONDS * float(intro.size())
	rebuild()
	if not intro.is_empty():
		dialogue.play_lines(intro, false, REACTION_SECONDS)
	# The notebook starts held up when clues are waiting and the board is empty. Otherwise it stays
	# the way the player left it.
	var start_open: bool = _notebook_open_pref
	if cards.is_empty() and not tray_order.is_empty():
		start_open = true
	notebook.set_open(start_open, false)
	_update_focus_links()
	if start_open and cards.is_empty():
		notebook.focus_first()
	else:
		_focus_board()


func close() -> void:
	_cancel_link()
	_end_ghost()
	_kill_effects()
	_clear_selection(true)
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	# The prompt bar shows what the player can do right now, and hides while someone is talking.
	prompt_bar.set_context(_prompt_context())
	prompt_bar.set_suppressed(dialogue.is_open)


# Which set of prompts fits what the mouse (or keyboard focus) is on.
func _prompt_context() -> String:
	if link_source != null:
		return "dragging_string"
	var node: Node = null
	if get_viewport().has_method("gui_get_hovered_control"):
		node = get_viewport().gui_get_hovered_control()
	if node == null:
		node = get_viewport().gui_get_focus_owner()
	while node != null and node != self:
		if node is EvidenceCardScript:
			return "board_card" if (node as EvidenceCardScript).linkable else "conclusion"
		if node is TrayCardScript:
			return "notebook_entry"
		if node == notebook:
			return "notebook_binding" if notebook.is_binding_hovered() else "default"
		node = node.get_parent()
	return "default"


func request_close() -> void:
	if link_source != null:
		_cancel_link()
	else:
		close()


func rebuild() -> void:
	_cancel_link()
	_end_ghost()
	_kill_effects()
	_prune_pinned()
	for child: Node in cards_root.get_children():
		cards_root.remove_child(child)
		child.queue_free()
	cards.clear()
	for id: String in GameState.board_pinned:
		_add_card(id, false)
	for id: String in GameState.board_pinned:
		if cards.has(id):
			_keep_card_off_others(cards[id])
	_rebuild_tray()
	var fresh: Array[String] = _sync_questions(false)
	if not fresh.is_empty():
		_queue_line(str(_question_def(fresh[0]).get("appear_line", "")), 0.8 + _intro_delay)
	_intro_delay = 0.0
	_clear_selection(true)
	_refresh_empty_label()
	_update_hints()
	_redraw_strings()


# ---------- loading ----------

func _load_data() -> void:
	var board: Dictionary = _read_json(board_path)
	evidence_registry = _read_json(registry_path).get("evidence", {})
	case_title = str(board.get("case_title", ""))
	var chapter_file: String = str(board.get("chapter_file", ""))
	var chapter: Dictionary = _read_json(chapter_file) if chapter_file != "" else {}
	if not chapter.is_empty():
		chapter_text = "Chapter %d · %s" % [int(chapter.get("chapter", 1)), str(chapter.get("title", ""))]
	intro_lines = board.get("intro_lines", [])
	settled_line = str(board.get("settled_line", ""))
	empty_notes_text = str(board.get("empty_notes_text", ""))
	empty_notebook_text = str(board.get("empty_notebook_text", ""))
	reaction_name = str(board.get("reaction_name", ""))
	max_pinned = int(board.get("max_pinned", 6))
	board_full_line = str(board.get("board_full_line", ""))
	card_ids = board.get("cards", [])
	question_defs = board.get("questions", [])
	link_defs = board.get("links", [])
	fallback_reactions = board.get("fallback_reactions", [])
	already_linked_line = str(board.get("already_linked_line", ""))
	for link: Dictionary in link_defs:
		var pair: Array = link.get("pair", [])
		link_by_id[str(link.get("link_id", ""))] = link
		if str(link.get("deduction_id", "")) != "":
			deduction_link[str(link.get("deduction_id", ""))] = link
		if pair.size() == 2:
			link_by_pair[_pair_key(str(pair[0]), str(pair[1]))] = link
	for question: Dictionary in question_defs:
		question_by_link[str(question.get("answered_by", ""))] = question
	# A deduction that another link uses in its pair still has to be combined: it is a Lead.
	for link: Dictionary in link_defs:
		for used: Variant in link.get("pair", []):
			if deduction_link.has(str(used)):
				lead_ids[str(used)] = true
	for wrong: Dictionary in board.get("wrong_reactions", []):
		var wrong_pair: Array = wrong.get("pair", [])
		if wrong_pair.size() == 2:
			wrong_by_pair[_pair_key(str(wrong_pair[0]), str(wrong_pair[1]))] = str(wrong.get("line", ""))


func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _question_def(question_id: String) -> Dictionary:
	for question: Dictionary in question_defs:
		if str(question.get("question_id", "")) == question_id:
			return question
	return {}


# ---------- what the player holds (worked out, never stored) ----------

func is_deduction(id: String) -> bool:
	return deduction_link.has(id)


# A Lead is a deduction that another link still uses. A Conclusion is a deduction nothing else uses.
func is_lead(id: String) -> bool:
	return lead_ids.has(id)


# The player has it: a clue they collected, or a deduction whose link is locked.
func is_held(id: String) -> bool:
	if is_deduction(id):
		return GameState.has_link(str(deduction_link[id].get("link_id", "")))
	return GameState.has_evidence(id)


# It was folded into a deduction by a locked link, so it lives inside that deduction now.
func is_used(id: String) -> bool:
	for link: Dictionary in link_defs:
		var pair: Array = link.get("pair", [])
		if pair.has(id) and GameState.has_link(str(link.get("link_id", ""))):
			return true
	return false


func is_available(id: String) -> bool:
	return is_held(id) and not is_used(id)


func _tray_ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in card_ids:
		if is_available(str(id)) and not GameState.is_pinned(str(id)):
			result.append(str(id))
	for link: Dictionary in link_defs:
		var ded_id: String = str(link.get("deduction_id", ""))
		if ded_id != "" and is_available(ded_id) and not GameState.is_pinned(ded_id):
			result.append(ded_id)
	return result


# Drops anything from the saved pin list that is no longer on offer (for example a clue that was
# folded into a deduction, or an id that is not in this chapter).
func _prune_pinned() -> void:
	for id: String in GameState.board_pinned.duplicate():
		if not is_available(id):
			GameState.unpin_card(id)


# A question with clues in its answer appears as soon as the player holds any one of them (a lead).
# A big question, answered by two deductions, waits until the player holds both. Its answer needs
# both conclusions, and showing it earlier would spoil the second one.
func _question_visible(question: Dictionary) -> bool:
	var link: Dictionary = link_by_id.get(str(question.get("answered_by", "")), {})
	var pair: Array = link.get("pair", [])
	var all_deductions: bool = not pair.is_empty()
	for id: Variant in pair:
		if not is_deduction(str(id)):
			all_deductions = false
	for id: Variant in pair:
		if all_deductions and not is_held(str(id)):
			return false
		if not all_deductions and is_held(str(id)):
			return true
	return all_deductions


func _question_solved(question: Dictionary) -> bool:
	return GameState.has_link(str(question.get("answered_by", "")))


# The question the soft hint is about: the first open one, in the order of the JSON.
func _oldest_open_question() -> Dictionary:
	for question: Dictionary in question_defs:
		if not _question_solved(question) and _question_visible(question):
			return question
	return {}


# Names, looks and colours come from the shared EvidenceCatalog, so a clue looks the same on the
# board, in the notebook and when it is presented in a conversation.
func _item_info(id: String) -> Dictionary:
	return EvidenceCatalog.item_info(id)


func _accent_for(evidence_id: String) -> Color:
	return EvidenceCatalog.accent_for(evidence_id)


func _blend_accent(id: String) -> Color:
	return EvidenceCatalog.blend_accent(id)


func _link_accent(link: Dictionary) -> Color:
	var pair: Array = link.get("pair", [])
	if pair.size() != 2:
		return GOLD
	return _blend_accent(str(pair[0])).lerp(_blend_accent(str(pair[1])), 0.5)


# ---------- cards on the board ----------

func _add_card(id: String, animate: bool) -> EvidenceCardScript:
	var info: Dictionary = _item_info(id)
	var card: EvidenceCardScript = CardScene.instantiate()
	cards_root.add_child(card)
	card.setup(id, str(info["name"]), str(info["description"]), str(info["style"]), info["accent"])
	_set_answers_line(card, id)
	card.placement_check = _can_place
	card.bounds = PLAY_RECT
	card.position = _clamp_to_board(_stored_position(id, _first_free_slot()))
	card.hovered.connect(_on_card_hovered)
	card.clicked.connect(_on_card_clicked)
	card.moved.connect(_on_card_moved)
	card.move_finished.connect(_on_card_move_finished)
	card.dropped.connect(_on_card_dropped)
	card.link_drag_started.connect(_on_link_drag_started)
	card.link_drag_moved.connect(_on_link_drag_moved)
	card.link_drag_released.connect(_on_link_drag_released)
	card.activated.connect(_on_card_activated)
	card.settled_pressed.connect(_on_settled_pressed)
	cards[id] = card
	if animate:
		card.pop_in()
	return card


# A Conclusion shows the question it answers on top ("ANSWERS · Is the photo real?").
func _set_answers_line(card: EvidenceCardScript, id: String) -> void:
	card.answers_text = ""
	if is_deduction(id) and not is_lead(id):
		var question: Dictionary = question_by_link.get(str(deduction_link[id].get("link_id", "")), {})
		card.answers_text = str(question.get("text", ""))


# Card positions are saved relative to the board's top-left corner, so the board can move later
# without breaking saves. Everything on screen still uses screen coordinates.
func _store_position(id: String, pos: Vector2) -> void:
	GameState.set_card_position(id, pos - BOARD_RECT.position)


func _stored_position(id: String, fallback: Vector2) -> Vector2:
	return GameState.get_card_position(id, fallback - BOARD_RECT.position) + BOARD_RECT.position


func _slot_position(index: int) -> Vector2:
	return GRID_ORIGIN + Vector2(index % GRID_COLUMNS, index / GRID_COLUMNS) * GRID_STEP


# The first tidy grid spot with nothing on it, or the nearest free spot if the grid is crowded.
func _first_free_slot() -> Vector2:
	var card_size: Vector2 = EvidenceCardScript.CARD_SIZE
	for index: int in range(maxi(max_pinned, 1)):
		var spot: Vector2 = _slot_position(index)
		if _rect_is_free(Rect2(spot, card_size), []):
			return spot
	return _find_free_position(card_size, GRID_ORIGIN, [])


func _clamp_to_board(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, PLAY_RECT.position.x, PLAY_RECT.end.x - EvidenceCardScript.CARD_SIZE.x),
		clampf(pos.y, PLAY_RECT.position.y, PLAY_RECT.end.y - EvidenceCardScript.CARD_SIZE.y)
	)


func _pinned_count() -> int:
	return cards.size()


# ---------- where cards may stand ----------

# True if a card can stand in this rectangle (same coordinates as card.position)
# without touching another card.
func _can_place(card: EvidenceCardScript, rect: Rect2) -> bool:
	return _rect_is_free(rect, [card])


func _rect_is_free(rect: Rect2, ignore: Array) -> bool:
	var padded: Rect2 = rect.grow(CARD_GAP * 0.5)
	for other: EvidenceCardScript in cards.values():
		if ignore.has(other):
			continue
		if padded.intersects(Rect2(other.position, other.size).grow(CARD_GAP * 0.5)):
			return false
	return true


# If a card (for example from an old saved layout) sits on top of another one, move it to the
# closest empty spot on the board.
func _keep_card_off_others(card: EvidenceCardScript) -> void:
	if _can_place(card, Rect2(card.position, card.size)):
		return
	card.position = _find_free_position(card.size, card.position, [card])
	_store_position(card.evidence_id, card.position)


func _find_free_position(card_size: Vector2, desired: Vector2, ignore: Array) -> Vector2:
	var best: Vector2 = desired
	var best_distance: float = INF
	var x: float = PLAY_RECT.position.x
	while x <= PLAY_RECT.end.x - card_size.x:
		var y: float = PLAY_RECT.position.y
		while y <= PLAY_RECT.end.y - card_size.y:
			var candidate: Vector2 = Vector2(x, y)
			var distance: float = candidate.distance_squared_to(desired)
			if distance < best_distance and _rect_is_free(Rect2(candidate, card_size), ignore):
				best = candidate
				best_distance = distance
			y += FREE_SPOT_STEP
		x += FREE_SPOT_STEP
	return best


# ---------- the notebook ----------

# Entries for the notebook page: clues first, then Leads, then Proven (finished conclusions).
func _notebook_entries() -> Array:
	var entries: Array = []
	for rank: int in range(3):
		for id: String in _tray_ids():
			var section: String = "clue"
			if is_deduction(id):
				section = "lead" if is_lead(id) else "proven"
			if ["clue", "lead", "proven"].find(section) != rank:
				continue
			var info: Dictionary = _item_info(id)
			entries.append({
				"id": id, "name": str(info["name"]), "style": str(info["style"]),
				"accent": info["accent"], "section": section, "is_new": not GameState.has_seen(id),
			})
	return entries


func _rebuild_tray() -> void:
	notebook.set_entries(_notebook_entries(), empty_notebook_text)
	_update_count()
	_update_focus_links()


func _on_notebook_toggled(is_open: bool) -> void:
	_notebook_open_pref = is_open
	_update_focus_links()


# The notebook is opened or closed with T / the pad shoulder button, a click on its cover or its binding.
func _toggle_tray() -> void:
	var now_open: bool = notebook.toggle()
	if now_open:
		notebook.focus_first()
	else:
		_focus_board()


func _set_tray_open(value: bool, animate: bool) -> void:
	notebook.set_open(value, animate)


# Left from the left-most board column steps into the notebook; Right from an entry steps back.
func _update_focus_links() -> void:
	var first_row: Control = null
	if notebook.is_open and not tray_order.is_empty():
		first_row = tray_cards[tray_order[0]]
	var first_card: Control = null
	for id: String in GameState.board_pinned:
		if cards.has(id):
			first_card = cards[id]
			break
	for thumb: TrayCardScript in tray_cards.values():
		thumb.focus_neighbor_right = thumb.get_path_to(first_card) if first_card != null else NodePath("")
	for card: EvidenceCardScript in cards.values():
		var left_column: bool = card.position.x < GRID_ORIGIN.x + GRID_STEP.x * 0.5
		card.focus_neighbor_left = card.get_path_to(first_row) if (left_column and first_row != null) else NodePath("")


# True if this screen point is over the notebook, open or closed.
func _over_tray(global_point: Vector2) -> bool:
	return notebook.over_notebook(global_point)


func _update_count() -> void:
	notebook.refresh()
	plate.queue_redraw()


# The counter turns oxblood for a second when a pin is refused because the board is full.
func _flash_plate() -> void:
	_plate_red = true
	plate.queue_redraw()
	if plate_tween != null:
		plate_tween.kill()
	plate_tween = create_tween()
	plate_tween.tween_interval(1.0)
	plate_tween.tween_callback(func() -> void:
		_plate_red = false
		plate.queue_redraw()
	)


func _set_tray_hot(value: bool) -> void:
	if _tray_hot == value:
		return
	_tray_hot = value
	notebook.set_hot(value)


func _on_tray_card_clicked(card: TrayCardScript) -> void:
	GameState.mark_seen(card.item_id)
	card.is_new = false
	notebook.refresh()


func _on_tray_card_activated(card: TrayCardScript) -> void:
	if _pin_from_tray(card.item_id, null) and cards.has(card.item_id):
		cards[card.item_id].grab_focus()


func _on_tray_drag_started(card: TrayCardScript) -> void:
	if _busy:
		return
	var info: Dictionary = _item_info(card.item_id)
	_ghost = CardScene.instantiate()
	ghost_layer.add_child(_ghost)
	_ghost.setup(card.item_id, str(info["name"]), str(info["description"]), str(info["style"]), info["accent"])
	_set_answers_line(_ghost, card.item_id)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.focus_mode = Control.FOCUS_NONE
	_ghost.scale = Vector2(GHOST_SMALL_SCALE, GHOST_SMALL_SCALE)
	_ghost.modulate.a = 0.92
	_ghost_big = false
	_ghost_source = card
	card.modulate.a = 0.35
	_move_ghost(card.get_global_mouse_position())


func _on_tray_drag_moved(_card: TrayCardScript, global_mouse: Vector2) -> void:
	_move_ghost(global_mouse)


func _on_tray_drag_released(card: TrayCardScript, global_mouse: Vector2) -> void:
	var over_board: bool = _ghost != null and BOARD_RECT.has_point(get_global_transform().affine_inverse() * global_mouse)
	_end_ghost()
	if over_board:
		_pin_from_tray(card.item_id, global_mouse)


func _move_ghost(global_mouse: Vector2) -> void:
	if _ghost == null:
		return
	_ghost.position = ghost_layer.get_global_transform().affine_inverse() * global_mouse - _ghost.size * 0.5
	var big: bool = BOARD_RECT.has_point(get_global_transform().affine_inverse() * global_mouse)
	if big != _ghost_big:
		_ghost_big = big
		var target: float = 1.0 if big else GHOST_SMALL_SCALE
		var tween: Tween = create_tween()
		tween.tween_property(_ghost, "scale", Vector2(target, target), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _end_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		ghost_layer.remove_child(_ghost)
		_ghost.queue_free()
	_ghost = null
	if _ghost_source != null and is_instance_valid(_ghost_source):
		_ghost_source.modulate.a = 1.0
	_ghost_source = null
	if _dirty and not _busy:
		_dirty = false
		rebuild()


# Puts a tray card on the board. `drop_global` is where the player let go, or null for the
# keyboard / pad version, which uses the first tidy spot.
func _pin_from_tray(id: String, drop_global: Variant) -> bool:
	if _busy or not is_available(id) or GameState.is_pinned(id):
		return false
	if _pinned_count() >= max_pinned:
		_say(board_full_line)
		_flash_plate()
		if tray_cards.has(id):
			tray_cards[id].shake()
		return false
	var card_size: Vector2 = EvidenceCardScript.CARD_SIZE
	var desired: Vector2 = _first_free_slot()
	if drop_global is Vector2:
		var local_drop: Vector2 = cards_root.get_global_transform().affine_inverse() * (drop_global as Vector2)
		desired = _clamp_to_board(local_drop - card_size * 0.5)
	var spot: Vector2 = desired if _rect_is_free(Rect2(desired, card_size), []) else _find_free_position(card_size, desired, [])
	GameState.pin_card(id)
	GameState.mark_seen(id)
	_store_position(id, spot)
	_add_card(id, true)
	Audio.play("pin_push")
	_rebuild_tray()
	_refresh_empty_label()
	_update_hints()
	return true


# Takes a card off the board and puts it back in the tray.
func _unpin(card: EvidenceCardScript) -> void:
	var id: String = card.evidence_id
	if link_source == card:
		_cancel_link()
	GameState.unpin_card(id)
	Audio.play("card_lift")
	cards.erase(id)
	if selected_link_id != "" and card.selected:
		_clear_selection(false)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(card, "scale", Vector2(0.35, 0.35), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(card):
			card.queue_free()
	)
	_rebuild_tray()
	if tray_cards.has(id):
		var thumb: TrayCardScript = tray_cards[id]
		thumb.scale = Vector2(0.5, 0.5)
		create_tween().tween_property(thumb, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_empty_label()
	_update_hints()
	_redraw_strings()


func _refresh_empty_label() -> void:
	empty_label.visible = cards.is_empty()
	if tray_order.is_empty():
		empty_label.text = "Nothing on the board yet. Clues you find go into James's notebook."
	else:
		empty_label.text = "Drag a clue from the notebook onto the board."


func _focus_first() -> void:
	_focus_board()


# Focus goes to the first pinned card. With an empty board there is nothing on it to focus.
func _focus_board() -> void:
	for id: String in GameState.board_pinned:
		if cards.has(id):
			cards[id].grab_focus()
			return


# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()
	elif event.is_action_pressed("board_inspect") and not event.is_echo():
		# Keyboard / pad version of clicking a card: read the deduction of the focused card.
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is EvidenceCardScript:
			get_viewport().set_input_as_handled()
			_on_card_clicked(focused)
	elif event.is_action_pressed("board_tray") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_toggle_tray()
	elif event.is_action_pressed("board_unpin") and not event.is_echo():
		var focused_card: Control = get_viewport().gui_get_focus_owner()
		if focused_card is EvidenceCardScript and not _busy and cards.has((focused_card as EvidenceCardScript).evidence_id):
			get_viewport().set_input_as_handled()
			var id: String = (focused_card as EvidenceCardScript).evidence_id
			_unpin(focused_card)
			# Open the folder so the player sees the card land in it.
			_set_tray_open(true, true)
			if tray_cards.has(id):
				tray_cards[id].grab_focus()


# A click on empty board (cards stop their own clicks) hides the reading panel.
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


func _on_card_moved(card: EvidenceCardScript) -> void:
	_redraw_strings()
	_set_tray_hot(_over_tray(get_global_mouse_position()))
	# The card comes off the cork: one soft sound per drag, once the card has really moved.
	if _moving_card != card:
		if _moving_start_card != card:
			_moving_start_card = card
			_moving_start = card.position
		elif card.position.distance_to(_moving_start) > 8.0:
			_moving_card = card
			Audio.play("card_lift")


func _on_card_move_finished(card: EvidenceCardScript) -> void:
	_moving_card = null
	_moving_start_card = null
	_store_position(card.evidence_id, card.position)


# Dragging a board card down onto the tray takes it off the board.
func _on_card_dropped(card: EvidenceCardScript, global_mouse: Vector2) -> void:
	_set_tray_hot(false)
	if _busy or not cards.has(card.evidence_id):
		return
	if _over_tray(global_mouse):
		_unpin(card)


func _on_link_drag_started(card: EvidenceCardScript) -> void:
	if _busy:
		return
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
	if _busy:
		return
	if link_source == null:
		if not card.linkable:
			_say(settled_line)
			return
		mouse_linking = false
		_begin_link(card)
		drag_to = _to_strings_space(card.get_pin_global())
		_redraw_strings()
	elif card == link_source:
		_cancel_link()
	else:
		_finish_link(link_source, card)


# The tack of a finished Conclusion was pressed. No string starts; James says it is settled.
func _on_settled_pressed(_card: EvidenceCardScript) -> void:
	if _busy:
		return
	_say(settled_line)


func _on_data_changed() -> void:
	if visible:
		rebuild()


func _on_evidence_added(_evidence_id: String) -> void:
	if not visible:
		return
	if _busy or _ghost != null:
		_dirty = true
	else:
		rebuild()
		# A new clue while the notebook is set down: its sticky tab wiggles.
		notebook.wiggle_tab()


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
	if target == null or target == source or _busy:
		_snap_back(source)
		return
	var key: String = _pair_key(source.evidence_id, target.evidence_id)
	if link_by_pair.has(key):
		var link: Dictionary = link_by_pair[key]
		if GameState.has_link(str(link.get("link_id", ""))):
			_snap_back(source)
			_say(already_linked_line)
		else:
			_lock_link(link, source, target)
	else:
		_snap_back(source)
		target.shake()
		Audio.play("string_snap")
		_note_wrong_try()
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


# Says a line after a pause (used so a question's line does not talk over the previous one).
func _queue_line(line: String, delay: float) -> void:
	if line == "":
		return
	if line_tween != null:
		line_tween.kill()
	line_tween = create_tween()
	line_tween.tween_interval(delay)
	line_tween.tween_callback(_say.bind(line))


func _card_at(global_point: Vector2, exclude: EvidenceCardScript) -> EvidenceCardScript:
	var children: Array[Node] = cards_root.get_children()
	for i: int in range(children.size() - 1, -1, -1):
		var card: EvidenceCardScript = children[i]
		if card == exclude or not cards.has(card.evidence_id):
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


# ---------- locking a link and merging ----------

# A correct pair. The state changes at once (so a save is never half-merged), then the two cards
# slide together along the gold string and fold into one deduction card.
func _lock_link(link: Dictionary, card_a: EvidenceCardScript, card_b: EvidenceCardScript) -> void:
	var link_id: String = str(link.get("link_id", ""))
	var ded_id: String = str(link.get("deduction_id", ""))
	var merge_pos: Vector2 = _merge_position(card_a, card_b)
	GameState.add_link(link_id)
	GameState.unpin_card(card_a.evidence_id)
	GameState.unpin_card(card_b.evidence_id)
	if ded_id != "":
		GameState.pin_card(ded_id)
		GameState.mark_seen(ded_id)
		_store_position(ded_id, merge_pos)
	else:
		push_warning("CaseBoard: link %s has no deduction_id" % link_id)
	var answered: Array[String] = []
	for question: Dictionary in question_defs:
		if str(question.get("answered_by", "")) == link_id:
			answered.append(str(question.get("question_id", "")))
			GameState.announce_question_answered(str(question.get("question_id", "")))
	_busy = true
	Audio.play("string_tie")
	_end_link()
	_clear_selection(true)
	_say(str(link.get("line", "")))
	for question_id: String in answered:
		if question_nodes.has(question_id):
			question_nodes[question_id].tick_solved(0.4)
	_update_hints()
	_merge_pair = [card_a, card_b]
	_merge_glow = 0.0
	card_a.move_to_front()
	card_b.move_to_front()
	if merge_tween != null:
		merge_tween.kill()
	merge_tween = create_tween()
	merge_tween.tween_method(
		func(amount: float) -> void:
			_merge_glow = amount
			_redraw_strings(),
		0.0, 1.0, MERGE_GLOW_SECONDS
	)
	merge_tween.tween_property(card_a, "position", merge_pos, MERGE_SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	merge_tween.parallel().tween_property(card_b, "position", merge_pos, MERGE_SLIDE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	merge_tween.parallel().tween_method(func(_amount: float) -> void: _redraw_strings(), 0.0, 1.0, MERGE_SLIDE_SECONDS)
	merge_tween.tween_callback(_finish_merge.bind(card_a, card_b, link_id, ded_id))


# Halfway between the two cards, on a free spot (the two cards themselves do not count).
func _merge_position(card_a: EvidenceCardScript, card_b: EvidenceCardScript) -> Vector2:
	var middle: Vector2 = _clamp_to_board((card_a.position + card_b.position) * 0.5)
	var ignore: Array = [card_a, card_b]
	if _rect_is_free(Rect2(middle, card_a.size), ignore):
		return middle
	return _find_free_position(card_a.size, middle, ignore)


func _finish_merge(card_a: EvidenceCardScript, card_b: EvidenceCardScript, link_id: String, ded_id: String) -> void:
	_merge_pair.clear()
	for old_card: EvidenceCardScript in [card_a, card_b]:
		cards.erase(old_card.evidence_id)
		if is_instance_valid(old_card):
			cards_root.remove_child(old_card)
			old_card.queue_free()
	if ded_id != "":
		var deduction: EvidenceCardScript = _add_card(ded_id, false)
		if is_lead(ded_id):
			deduction.appear_lead()
		else:
			deduction.appear_conclusion()
			_start_bloom(deduction.position + deduction.size * 0.5)
	_busy = false
	_update_count()
	_refresh_empty_label()
	_redraw_strings()
	_select_link(link_id)
	# The ink tick is still being drawn on the question card. Move it into the strip afterwards.
	if question_tween != null:
		question_tween.kill()
	question_tween = create_tween()
	question_tween.tween_interval(QUESTION_MOVE_DELAY)
	question_tween.tween_callback(_after_merge_questions)
	if _dirty and _ghost == null:
		_dirty = false
		rebuild()


# A soft warm light blooms where the two cards met and a Conclusion appears.
func _start_bloom(center: Vector2) -> void:
	_bloom_center = center
	if bloom_tween != null:
		bloom_tween.kill()
	bloom_tween = create_tween()
	bloom_tween.tween_method(
		func(amount: float) -> void:
			_bloom_alpha = 0.35 * sin(PI * amount)
			_redraw_strings(),
		0.0, 1.0, BLOOM_SECONDS
	)
	bloom_tween.tween_callback(func() -> void:
		_bloom_alpha = 0.0
		_redraw_strings()
	)


func _after_merge_questions() -> void:
	var fresh: Array[String] = _sync_questions(true)
	if not fresh.is_empty():
		# James has just spoken about the link. Let him finish before the next question's line.
		_queue_line(str(_question_def(fresh[0]).get("appear_line", "")), REACTION_SECONDS - 1.0)
	_update_hints()


# ---------- questions ----------

# Brings the question list (top of the right column) in line with GameState. Every question keeps
# one slot in the list: first as an open slip with a "?", then as a ticked slip with the answer.
# Returns the questions that appeared for the first time (James says their line).
func _sync_questions(animate_chips: bool) -> Array[String]:
	var open_ids: Array[String] = []
	var solved_ids: Array[String] = []
	var slots: Dictionary = {}  # question_id -> its place in the list
	for question: Dictionary in question_defs:
		var question_id: String = str(question.get("question_id", ""))
		if _question_solved(question):
			solved_ids.append(question_id)
			slots[question_id] = slots.size()
		elif _question_visible(question) and open_ids.size() < MAX_OPEN_QUESTIONS:
			open_ids.append(question_id)
			slots[question_id] = slots.size()
	for question_id: String in question_nodes.keys():
		if not open_ids.has(question_id):
			question_nodes[question_id].queue_free()
			solved_strip.remove_child(question_nodes[question_id])
			question_nodes.erase(question_id)
	for question_id: String in chip_nodes.keys():
		if not solved_ids.has(question_id):
			chip_nodes[question_id].queue_free()
			solved_strip.remove_child(chip_nodes[question_id])
			chip_nodes.erase(question_id)
	var fresh: Array[String] = []
	for question_id: String in open_ids:
		var target: Vector2 = _slot_in_list(int(slots[question_id]))
		if question_nodes.has(question_id):
			question_nodes[question_id].position = target
			continue
		var node: QuestionCardScript = QuestionCardScript.new()
		solved_strip.add_child(node)
		node.setup(question_id, str(_question_def(question_id).get("text", "")), false)
		node.position = target
		question_nodes[question_id] = node
		if not GameState.has_seen(question_id):
			node.slide_in(0.12 * float(fresh.size()))
			GameState.mark_seen(question_id)
			fresh.append(question_id)
	for question_id: String in solved_ids:
		var chip_target: Vector2 = _slot_in_list(int(slots[question_id]))
		if chip_nodes.has(question_id):
			chip_nodes[question_id].position = chip_target
			continue
		var question: Dictionary = _question_def(question_id)
		var link: Dictionary = link_by_id.get(str(question.get("answered_by", "")), {})
		var chip: QuestionCardScript = QuestionCardScript.new()
		solved_strip.add_child(chip)
		chip.setup(question_id, str(question.get("text", "")), true, str(link.get("deduction", "")))
		chip.position = chip_target
		chip.clicked.connect(_on_chip_clicked)
		chip_nodes[question_id] = chip
		if animate_chips:
			chip.pop_in()
	return fresh


func _slot_in_list(index: int) -> Vector2:
	return Vector2(float(index % CHIP_COLUMNS) * CHIP_STEP.x, float(index / CHIP_COLUMNS) * CHIP_STEP.y)


func _on_chip_clicked(question_id: String) -> void:
	_select_link(str(_question_def(question_id).get("answered_by", "")))


# ---------- soft hint ----------

# A wrong link counts against the oldest open question.
func _note_wrong_try() -> void:
	var question: Dictionary = _oldest_open_question()
	if question.is_empty():
		return
	GameState.add_wrong_try(str(question.get("question_id", "")))
	_update_hints()


# After a few wrong tries the cards that answer the oldest open question glow softly,
# on the board or in the tray. This is tier 1 of the hint system.
func _update_hints() -> void:
	for card: EvidenceCardScript in cards.values():
		card.hinted = false
	for thumb: TrayCardScript in tray_cards.values():
		thumb.hinted = false
	var question: Dictionary = _oldest_open_question()
	if question.is_empty():
		return
	if GameState.get_wrong_tries(str(question.get("question_id", ""))) < HINT_AFTER_WRONG_TRIES:
		return
	var link: Dictionary = link_by_id.get(str(question.get("answered_by", "")), {})
	for id: Variant in link.get("pair", []):
		if cards.has(str(id)):
			cards[str(id)].hinted = true
		elif tray_cards.has(str(id)):
			tray_cards[str(id)].hinted = true


func _kill_effects() -> void:
	for tween: Tween in [merge_tween, question_tween, line_tween, snap_tween, bloom_tween]:
		if tween != null:
			tween.kill()
	_bloom_alpha = 0.0
	_busy = false
	_merge_pair.clear()
	_set_tray_hot(false)
	for question_id: String in question_nodes.keys():
		if is_instance_valid(question_nodes[question_id]):
			question_nodes[question_id].queue_free()
	for chip_id: String in chip_nodes.keys():
		if is_instance_valid(chip_nodes[chip_id]):
			chip_nodes[chip_id].queue_free()
	for child: Node in solved_strip.get_children():
		solved_strip.remove_child(child)
		child.queue_free()
	question_nodes.clear()
	chip_nodes.clear()


# ---------- reading a deduction ----------

# Clicking a deduction card (or pressing Q / pad X on it) reads it in the panel.
func _on_card_clicked(card: EvidenceCardScript) -> void:
	_moving_card = null
	_moving_start_card = null
	GameState.mark_seen(card.evidence_id)
	if is_deduction(card.evidence_id):
		_select_link(str(deduction_link[card.evidence_id].get("link_id", "")))
	else:
		_select_link("")


func _select_link(link_id: String) -> void:
	var link: Dictionary = link_by_id.get(link_id, {})
	if link.is_empty() or not GameState.has_link(link_id):
		_clear_selection(false)
		return
	selected_link_id = link_id
	var ded_id: String = str(link.get("deduction_id", ""))
	for card: EvidenceCardScript in cards.values():
		card.selected = card.evidence_id == ded_id
	_show_link_panel(link)
	_redraw_strings()


func _clear_selection(_instant: bool) -> void:
	selected_link_id = ""
	for card: EvidenceCardScript in cards.values():
		card.selected = false
	if panel_tween != null:
		panel_tween.kill()
	# The case-notes page is always there. With nothing to read it shows faint pencil text.
	detail_panel.visible = true
	detail_panel.modulate.a = 1.0
	detail_panel.position.x = _panel_x
	_notes_heading = ""
	detail_text.text = "[font_size=22][color=#9c8c72]%s[/color][/font_size]" % _bb(empty_notes_text)
	detail_panel.queue_redraw()
	_redraw_strings()


func _show_link_panel(link: Dictionary) -> void:
	var pair: Array = link.get("pair", [])
	var accent: Color = _link_accent(link)
	_panel_style.border_color = Color(0.231, 0.165, 0.118)
	_notes_heading = str(link.get("deduction", ""))
	var heading: String = "[font_size=34][color=#2b1d14]%s[/color][/font_size]\n" % _bb(_notes_heading)
	var text: String = heading
	var question: Dictionary = question_by_link.get(str(link.get("link_id", "")), {})
	if not question.is_empty():
		text += "[color=#7a6248][font_size=17]ANSWERS[/font_size][/color]  [color=#2b1d14]%s[/color]\n" % _bb(str(question.get("text", "")))
	text += "\n"
	var line: String = str(link.get("line", ""))
	if line != "":
		text += "[color=#2b1d14]\"%s\"[/color]\n" % _bb(line)
		if reaction_name != "":
			text += "[color=#7a6248]- %s[/color]\n" % _bb(reaction_name)
		text += "\n"
	text += "[color=#7a6248][font_size=17]BUILT FROM[/font_size][/color]\n"
	for id: Variant in pair:
		var info: Dictionary = _item_info(str(id))
		var shown: Color = (info["accent"] as Color).darkened(0.4)
		text += "[color=#%s][b]%s[/b][/color]\n[color=#3a2a1e]%s[/color]\n\n" % [shown.to_html(false), _bb(str(info["name"])), _bb(str(info["description"]))]
	detail_text.text = text
	if panel_tween != null:
		panel_tween.kill()
	detail_panel.visible = true
	detail_panel.queue_redraw()
	detail_panel.modulate.a = 0.0
	detail_panel.position.x = _panel_x + PANEL_SLIDE_PX
	panel_tween = create_tween().set_parallel(true)
	panel_tween.tween_property(detail_panel, "modulate:a", 1.0, 0.2)
	panel_tween.tween_property(detail_panel, "position:x", _panel_x, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Stops story text from being read as BBCode.
func _bb(text: String) -> String:
	return text.replace("[", "[lb]")


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
	_brass_style = _flat(Color(0.8, 0.62, 0.25), Color(0.4, 0.26, 0.07), 1, 6)
	_bloom_tex = _radial([Color(1.0, 0.86, 0.55, 1.0), Color(1.0, 0.86, 0.55, 0.0)], [0.0, 1.0], Vector2i(128, 128), Vector2(0.5, 0.5), Vector2(1.0, 0.5))
	_vignette = _radial([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.5)], [0.0, 0.55, 1.0], Vector2i(256, 168), Vector2(0.5, 0.5), Vector2(1.0, 1.0))
	_lamp_glow = _radial([Color(1.0, 0.84, 0.52, 0.24), Color(1.0, 0.84, 0.52, 0.0)], [0.0, 1.0], Vector2i(256, 168), Vector2(0.5, 0.38), Vector2(1.0, 0.95))
	_wall_glow = _radial([Color(1.0, 0.69, 0.35, 0.3), Color(1.0, 0.69, 0.35, 0.0)], [0.0, 1.0], Vector2i(256, 256), Vector2(0.5, 0.5), Vector2(1.0, 0.5))
	_desk_vignette = _radial([Color(0.06, 0.08, 0.16, 0.0), Color(0.06, 0.08, 0.16, 0.0), Color(0.05, 0.065, 0.14, 0.72)], [0.0, 0.5, 1.0], Vector2i(256, 144), Vector2(0.5, 0.42), Vector2(1.08, 1.0))


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

func _redraw_strings() -> void:
	strings.queue_redraw()


# Only two strings are ever drawn: the loose one the player is pulling, and the gold one that
# lights up for a moment while two cards fold together.
func _draw_strings() -> void:
	if _bloom_alpha > 0.0:
		var bloom_size: Vector2 = Vector2(BLOOM_SIZE, BLOOM_SIZE)
		strings.draw_texture_rect(_bloom_tex, Rect2(_to_strings_space(_bloom_center) - bloom_size * 0.5, bloom_size), false, Color(1.0, 1.0, 1.0, _bloom_alpha))
	if _merge_pair.size() == 2 and is_instance_valid(_merge_pair[0]) and is_instance_valid(_merge_pair[1]):
		var points: PackedVector2Array = _string_points(_to_strings_space(_merge_pair[0].get_pin_global()), _to_strings_space(_merge_pair[1].get_pin_global()))
		strings.draw_polyline(points, Color(1.0, 0.95, 0.7, 0.2 * _merge_glow), 30.0, true)
		strings.draw_polyline(points, Color(1.0, 0.9, 0.55, 0.35 * _merge_glow), 18.0, true)
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

func _string_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var sag: float = clampf(from.distance_to(to) * 0.15, 10.0, 70.0)
	var control: Vector2 = (from + to) * 0.5 + Vector2(0.0, sag)
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(33):
		var t: float = float(i) / 32.0
		points.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return points


# ---------- drawing the case tag and the case notes ----------

# A paper luggage tag tied to a nail on the board's frame. It says which case, and which chapter, the board
# is working on. Everything it shows comes from the board JSON and the chapter file.
func _draw_case_tag() -> void:
	var hole: Vector2 = Vector2(34.0, 40.0)
	var nail: Vector2 = Vector2(11.0, 54.0)
	# The nail head on the frame, and the twine from the hole to the nail.
	case_tag.draw_circle(nail + Vector2(1.0, 2.0), 6.0, Color(0.0, 0.0, 0.0, 0.4))
	case_tag.draw_circle(nail, 5.6, BRASS_DARK)
	case_tag.draw_circle(nail, 4.4, BRASS)
	case_tag.draw_circle(nail + Vector2(-1.2, -1.4), 1.6, Color(1.0, 0.95, 0.75))
	var twine: PackedVector2Array = PackedVector2Array([hole, hole.lerp(nail, 0.5) + Vector2(2.0, 2.0), nail])
	case_tag.draw_polyline(twine, Color(0.0, 0.0, 0.0, 0.3), 3.0, true)
	case_tag.draw_polyline(twine, Color(0.541, 0.416, 0.271), 2.0, true)
	# The tag swings a little around its hole (-2 degrees).
	case_tag.draw_set_transform(hole, deg_to_rad(-2.0))
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(-6.0, -32.0), Vector2(TAG_SIZE.x - 18.0, -32.0), Vector2(TAG_SIZE.x - 18.0, 32.0),
		Vector2(-6.0, 32.0), Vector2(-18.0, 20.0), Vector2(-18.0, -20.0)
	])
	for offset: Vector2 in [Vector2(5.0, 9.0), Vector2(3.0, 5.0)]:
		var shadow: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in body:
			shadow.append(point + offset)
		case_tag.draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.2))
	case_tag.draw_colored_polygon(body, TAG_PAPER)
	case_tag.draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[4], body[5], body[0]]), Color(0.55, 0.45, 0.3, 0.7), 1.3, true)
	# The punched hole with a brass eyelet.
	case_tag.draw_circle(Vector2.ZERO, 6.0, Color(0.1, 0.07, 0.05))
	case_tag.draw_arc(Vector2.ZERO, 7.6, 0.0, TAU, 24, BRASS, 2.0, true)
	# Line 1: the case title in small, letter-spaced capitals. Line 2: the chapter, in ink.
	var x: float = 16.0
	for letter: String in case_title.to_upper():
		case_tag.draw_string(TITLE_FONT, Vector2(x, -10.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, SEPIA)
		x += TITLE_FONT.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 2.2
	var available: float = TAG_SIZE.x - 18.0 - 16.0 - 10.0
	var font_size: int = 20
	while font_size > 13 and TITLE_FONT.get_string_size(chapter_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		font_size -= 1
	case_tag.draw_string(TITLE_FONT, Vector2(16.0, 18.0), chapter_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, NOTES_INK)
	case_tag.draw_set_transform(Vector2.ZERO)


# A hand-drawn underline under the title on the case-notes page.
func _draw_notes_overlay() -> void:
	_draw_notes_paper()
	if _notes_heading == "":
		return
	var font: Font = detail_text.get_theme_font("normal_font")
	var width: float = minf(font.get_string_size(_notes_heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 6.0, detail_text.size.x)
	var drop: float = 46.0
	if detail_text.get_paragraph_count() > 1:
		drop = detail_text.get_paragraph_offset(1) - 4.0
	var origin: Vector2 = detail_text.position + Vector2(0.0, drop)
	var points: PackedVector2Array = PackedVector2Array()
	var x: float = 0.0
	while x <= width:
		points.append(origin + Vector2(x, sin(x * 0.1) * 1.8 + x * 0.006))
		x += 4.0
	if points.size() >= 2:
		detail_panel.draw_polyline(points, Color(NOTES_INK, 0.85), 2.2, true)


# What makes the notes page look like a real sheet: fibres, a shaded edge, tape, a turned corner.
func _draw_notes_paper() -> void:
	var page: Rect2 = Rect2(Vector2.ZERO, detail_panel.size)
	PaperFx.tile(detail_panel, PaperFx.grain(), page.grow(-4.0), Color(0.45, 0.32, 0.18, 0.1))
	# Light from the top left, a little shade at the bottom.
	var shade: Rect2 = page.grow(-3.0)
	detail_panel.draw_polygon(
		PackedVector2Array([shade.position, Vector2(shade.end.x, shade.position.y), shade.end, Vector2(shade.position.x, shade.end.y)]),
		PackedColorArray([Color(1.0, 1.0, 1.0, 0.12), Color(1.0, 1.0, 1.0, 0.0), Color(0.35, 0.22, 0.1, 0.12), Color(0.35, 0.22, 0.1, 0.03)])
	)
	# Two strips of tape hold it to the desk.
	for strip: Array in [[Vector2(46.0, 2.0), -7.0], [Vector2(page.size.x - 46.0, 2.0), 6.0]]:
		detail_panel.draw_set_transform(strip[0], deg_to_rad(strip[1]))
		var tape: Rect2 = Rect2(Vector2(-34.0, -11.0), Vector2(68.0, 22.0))
		detail_panel.draw_rect(Rect2(tape.position + Vector2(1.0, 2.0), tape.size), Color(0.0, 0.0, 0.0, 0.12))
		detail_panel.draw_rect(tape, Color(0.99, 0.95, 0.8, 0.72))
		detail_panel.draw_rect(tape, Color(0.6, 0.5, 0.32, 0.35), false, 1.0)
		detail_panel.draw_line(tape.position + Vector2(4.0, 5.0), tape.position + Vector2(64.0, 5.0), Color(1.0, 1.0, 1.0, 0.35), 2.0)
	detail_panel.draw_set_transform(Vector2.ZERO)
	# The bottom right corner is turned up.
	var corner: Vector2 = page.end - Vector2(3.0, 3.0)
	var fold: float = 30.0
	detail_panel.draw_colored_polygon(PackedVector2Array([corner - Vector2(fold + 6.0, 0.0), corner - Vector2(0.0, fold + 6.0), corner - Vector2(fold, fold) * 0.92]), Color(0.3, 0.2, 0.1, 0.16))
	detail_panel.draw_colored_polygon(PackedVector2Array([corner - Vector2(fold, 0.0), corner - Vector2(0.0, fold), corner - Vector2(fold, fold) * 0.86]), Color(0.99, 0.965, 0.89))
	detail_panel.draw_polyline(PackedVector2Array([corner - Vector2(fold, 0.0), corner - Vector2(fold, fold) * 0.86, corner - Vector2(0.0, fold)]), Color(0.231, 0.165, 0.118, 0.7), 1.5, true)


# The brass counter on the board's top frame.
func _draw_plate() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, plate.size)
	var style: StyleBoxFlat = _brass_style
	var text_color: Color = LEATHER_INK
	if _plate_red:
		style = _flat(OXBLOOD, Color(0.25, 0.06, 0.05), 1, 6)
		text_color = Color(0.99, 0.95, 0.86)
	plate.draw_style_box(style, rect)
	plate.draw_line(Vector2(6.0, 4.0), Vector2(rect.size.x - 6.0, 4.0), Color(1.0, 0.92, 0.65, 0.5), 1.0)
	var text: String = "%d / %d pinned" % [cards.size(), max_pinned]
	var width: float = TITLE_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	plate.draw_string(TITLE_FONT, Vector2((rect.size.x - width) * 0.5, 23.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, text_color)


# ---------- drawing the wall and the board ----------

# The desk the board lies on: dark walnut planks under one warm lamp, slate-blue in the corners.
func _draw_wall() -> void:
	var full: Rect2 = Rect2(Vector2.ZERO, wall.size)
	var top: Color = Color(0.135, 0.088, 0.078)
	var bottom: Color = Color(0.075, 0.052, 0.058)
	wall.draw_polygon(
		PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)
	# Wood grain: the same noise twice, pulled sideways into long streaks.
	PaperFx.tile(wall, PaperFx.streaks(), full, Color(0.62, 0.4, 0.24, 0.16), Vector2(11.0, 0.9))
	PaperFx.tile(wall, PaperFx.grain(), full, Color(0.0, 0.0, 0.0, 0.2), Vector2(14.0, 1.0))
	# Plank seams.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var seam_y: float = 150.0
	while seam_y < full.size.y:
		wall.draw_line(Vector2(0.0, seam_y), Vector2(full.size.x, seam_y), Color(0.0, 0.0, 0.0, 0.42), 2.0)
		wall.draw_line(Vector2(0.0, seam_y + 2.0), Vector2(full.size.x, seam_y + 2.0), Color(1.0, 0.75, 0.5, 0.05), 1.0)
		var butt_x: float = rng.randf_range(200.0, full.size.x - 200.0)
		wall.draw_line(Vector2(butt_x, seam_y), Vector2(butt_x, seam_y + 232.0), Color(0.0, 0.0, 0.0, 0.3), 2.0)
		seam_y += 232.0
	# The lamp: a warm pool over the board, a smaller one over the notebook.
	var board_center: Vector2 = surface.position + surface.size * 0.5
	var warm: Vector2 = Vector2(2300.0, 1500.0)
	wall.draw_texture_rect(_wall_glow, Rect2(board_center - Vector2(0.0, 120.0) - warm * 0.5, warm), false, Color(1.0, 0.92, 0.8, 1.0))
	var pool: Vector2 = Vector2(760.0, 900.0)
	wall.draw_texture_rect(_wall_glow, Rect2(Vector2(198.0, 380.0) - pool * 0.5, pool), false, Color(1.0, 0.9, 0.75, 0.55))
	# Night comes in from the corners (slate blue, never pure black).
	wall.draw_texture_rect(_desk_vignette, full, false)
	# Dust in the lamp light.
	for i: int in range(40):
		var spot: Vector2 = Vector2(rng.randf() * full.size.x, rng.randf() * 820.0)
		wall.draw_circle(spot, rng.randf_range(0.8, 2.2), Color(1.0, 0.86, 0.66, rng.randf_range(0.03, 0.12)))


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
	PaperFx.tile(surface, PaperFx.grain(), inner, Color(0.24, 0.13, 0.05, 0.3), Vector2(1.6, 1.6))
	PaperFx.tile(surface, PaperFx.streaks(), inner, Color(1.0, 0.86, 0.62, 0.1), Vector2(2.0, 2.0))
	surface.draw_texture_rect(_lamp_glow, inner, false)
	surface.draw_texture_rect(_vignette, inner, false)
	# The frame stands above the cork, so it throws a shadow along the top and left.
	surface.draw_polygon(
		PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), Vector2(inner.end.x, inner.position.y + 26.0), Vector2(inner.position.x, inner.position.y + 26.0)]),
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.34), Color(0.0, 0.0, 0.0, 0.34), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0)])
	)
	surface.draw_polygon(
		PackedVector2Array([inner.position, Vector2(inner.position.x + 18.0, inner.position.y), Vector2(inner.position.x + 18.0, inner.end.y), Vector2(inner.position.x, inner.end.y)]),
		PackedColorArray([Color(0.0, 0.0, 0.0, 0.22), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.22)])
	)
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
