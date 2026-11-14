extends SceneTree

var scene: Node
var board: Control
var gs: Node
var passed: int = 0
var failed: int = 0
var link_events: Array = []
var answered_events: Array = []
var line_count: int = 0

const SHADOW := "ch01_shadow_directions"
const SNOW := "ch01_snowbank_depth"
const LOGO := "ch01_logo_patch"
const LEAFLET := "ch01_anniversary_leaflet"
const D_STAGED := "ch01_ded_staged"
const D_RETOUCHED := "ch01_ded_retouched"
const D_LIES := "ch01_ded_two_lies"

func frames(n: int) -> void:
	for i in n:
		await process_frame

func secs(t: float) -> void:
	await create_timer(t).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/home/claude/shots/m4_%s.png" % name)

func check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		passed += 1
		print("PASS  ", label)
	else:
		failed += 1
		print("FAIL  ", label, "  ", extra)

func key(code: Key, pressed: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	root.push_input(ev)

func tap(code: Key) -> void:
	key(code, true)
	key(code, false)

func mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)

func mouse_btn(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(ev)

func drag(from: Vector2, to: Vector2) -> void:
	mouse_move(from)
	await frames(1)
	mouse_btn(from, true)
	await frames(1)
	var steps := 6
	for i in range(1, steps + 1):
		mouse_move(from.lerp(to, float(i) / steps))
		await frames(1)
	mouse_btn(to, false)
	await frames(1)

func click(pos: Vector2) -> void:
	mouse_move(pos)
	await frames(1)
	mouse_btn(pos, true)
	await frames(1)
	mouse_btn(pos, false)
	await frames(1)

func card(id: String) -> Control:
	return board.cards.get(id)

func card_center(id: String) -> Vector2:
	return card(id).get_global_transform() * (card(id).size * 0.5)

func pin_of(id: String) -> Vector2:
	return card(id).get_pin_global()

func tray_center(id: String) -> Vector2:
	var t: Control = board.tray_cards[id]
	return t.get_global_transform() * (t.size * 0.5)

func pinned_ids() -> Array:
	return gs.board_pinned.duplicate()

func all_clear() -> bool:
	var list: Array = board.cards.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			if Rect2(list[i].position, list[i].size).intersects(Rect2(list[j].position, list[j].size)):
				return false
	return true

func min_gap() -> float:
	var list: Array = board.cards.values()
	var best := 9999.0
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a := Rect2(list[i].position, list[i].size)
			var b := Rect2(list[j].position, list[j].size)
			var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
			var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
			best = minf(best, maxf(dx, dy))
	return best

func cover_center() -> Vector2:
	return board.notebook.body_global_rect().get_center()

# The wire binding of the open notebook (clicking it closes the notebook).
func binding_point() -> Vector2:
	return board.notebook.get_global_transform() * (board.notebook.OPEN_CENTER - Vector2(0.0, board.notebook.OPEN_SIZE.y * 0.5) + Vector2(0.0, 8.0))

func open_drawer() -> void:
	if not board.notebook.is_open:
		await click(cover_center())
		await secs(0.9)

func pin_drag(id: String, at: Vector2) -> void:
	await open_drawer()
	await drag(tray_center(id), at)
	await secs(0.45)

# Link two board cards with the mouse and wait for the merge to finish.
func link_drag(a: String, b: String, wait: float = 2.0) -> void:
	await drag(pin_of(a), card_center(b))
	await secs(wait)

func fresh_open() -> void:
	if board.visible:
		board.close()
	gs.reset()
	for id in [SHADOW, SNOW, LOGO, LEAFLET]:
		gs.collect_evidence(id)
	line_count = 0
	board.open()
	await secs(0.8)

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("/home/claude/shots")
	gs.link_made.connect(func(id: String) -> void: link_events.append(id))
	gs.question_answered.connect(func(id: String) -> void: answered_events.append(id))
	scene = load("res://scenes/mechanics/case_board_test.tscn").instantiate()
	root.add_child(scene)
	board = scene.get_node("BoardLayer/CaseBoard")
	await frames(5)
	board.dialogue.line_started.connect(func(_i: int) -> void: line_count += 1)
	check("board hidden at start", not board.visible)

	# ---- 1. opening with 4 clues ----
	tap(KEY_B)
	await secs(0.7)
	check("1 B opens the board", board.visible)
	check("1 tray shows 4 clues", board.tray_cards.size() == 4, str(board.tray_cards.size()))
	check("1 board is empty", board.cards.is_empty() and gs.board_pinned.is_empty())
	check("1 the 2 clue questions are visible", board.question_nodes.has("ch01_q_real") and board.question_nodes.has("ch01_q_changed") and board.question_nodes.size() == 2, str(board.question_nodes.keys()))
	check("1 the deduction question is not", not board.question_nodes.has("ch01_q_lie"))
	check("1 tray cards show the new dot", board.tray_cards[SHADOW].is_new)
	check("1 empty-board label points to the notebook", board.empty_label.visible and board.empty_label.text.contains("notebook"))
	await secs(0.6)
	check("1 James said a question line", line_count >= 1, str(line_count))
	await shot("01_open")

	check("1 notebook starts held up (clues waiting, board empty)", board.notebook.is_open and board.notebook.lift > 0.99)
	var folder: Rect2 = board.notebook.body_global_rect()
	check("1 notebook and board never overlap", not folder.intersects(board.BOARD_RECT), str(folder))
	check("1 only the dialogue box is below y=790", folder.end.y <= 790.0 and board.BOARD_RECT.end.y <= 790.0 and board.detail_panel.get_global_rect().end.y <= 790.0 and board.solved_strip.get_global_rect().end.y <= 790.0)
	var first_q: Control = board.question_nodes.values()[0]
	check("1 first question sits in the question list, off the board", board.solved_strip.get_global_rect().encloses(first_q.get_global_rect()) and not board.BOARD_RECT.intersects(first_q.get_global_rect()), str(first_q.get_global_rect()))
	check("1 no question cards are left on the board", board.get_node_or_null("Questions") == null)
	await shot("01b_notebook_open")
	# Clicking the wire binding closes it. Sample the rectangle all through the animation.
	await click(binding_point())
	var overlap_seen: bool = false
	for i in range(40):
		await frames(1)
		if board.notebook.body_global_rect().intersects(board.BOARD_RECT):
			overlap_seen = true
	await secs(0.5)
	check("1 columns never overlap while the notebook closes", not overlap_seen)
	check("1 clicking the binding closes the notebook", not board.notebook.is_open and board.notebook.lift < 0.01 and not board.notebook.items.visible)
	check("1 closed notebook knows something is new", board.notebook.unseen_count() == 4)
	await secs(0.3)
	await shot("01c_notebook_closed")
	overlap_seen = false
	await click(cover_center())
	for i in range(40):
		await frames(1)
		if board.notebook.body_global_rect().intersects(board.BOARD_RECT):
			overlap_seen = true
	await secs(0.5)
	check("1 columns never overlap while the notebook opens", not overlap_seen)
	check("1 clicking the cover opens the notebook", board.notebook.is_open and board.notebook.lift > 0.99 and board.notebook.items.visible)
	tap(KEY_T)
	await secs(0.8)
	check("1 T closes the notebook", not board.notebook.is_open)
	tap(KEY_T)
	await secs(0.8)
	check("1 T opens the notebook", board.notebook.is_open)

	# ---- 2. drag tray -> board and back ----
	await pin_drag(SHADOW, Vector2(560, 340))
	check("2 shadow is pinned on the board", board.cards.has(SHADOW))
	check("2 saved in board_pinned", pinned_ids() == [SHADOW], str(pinned_ids()))
	check("2 gone from the tray", not board.tray_cards.has(SHADOW) and board.tray_cards.size() == 3)
	var landed: Vector2 = card_center(SHADOW)
	check("2 card landed where it was dropped", landed.distance_to(Vector2(560, 340)) < 60.0, str(landed))
	check("2 pinned card is no longer 'new'", gs.has_seen(SHADOW))
	await shot("02_one_pinned")
	await drag(card_center(SHADOW), cover_center())
	await secs(0.4)
	check("2 dragged back onto the folder: unpinned", not board.cards.has(SHADOW) and gs.board_pinned.is_empty() and board.tray_cards.has(SHADOW))
	await pin_drag(SHADOW, Vector2(560, 340))
	check("2 pinned again", board.cards.has(SHADOW))

	# drop onto a spot that is already taken: lands on a free spot, never overlapping
	await pin_drag(SNOW, card_center(SHADOW) + Vector2(20, 10))
	check("2 drop on top of a card still gives a free spot", board.cards.has(SNOW) and all_clear(), str(min_gap()))
	check("2 gap between cards is kept (>= 40)", min_gap() >= 39.0, str(min_gap()))

	# a drop outside the board does nothing
	await open_drawer()
	await drag(tray_center(LOGO), Vector2(1500, 880))
	await secs(0.3)
	check("2 drop outside the board cancels", not board.cards.has(LOGO) and board.tray_cards.has(LOGO))

	# ---- 3. the 7th pin is refused ----
	board.max_pinned = 2
	var before_lines: int = line_count
	await open_drawer()
	await drag(tray_center(LOGO), Vector2(920, 600))
	await secs(0.4)
	check("3 third pin refused at the limit", not board.cards.has(LOGO) and board.tray_cards.has(LOGO) and gs.board_pinned.size() == 2)
	check("3 James said the board-full line", line_count > before_lines)
	board.max_pinned = 6
	check("3 notebook stays open after a refused pin", board.notebook.is_open)
	tap(KEY_T)
	await secs(0.8)

	# ---- 4. correct pair merges ----
	var answered_before: int = answered_events.size()
	await drag(pin_of(SHADOW), card_center(SNOW))
	await secs(0.2)
	await shot("03_merging")
	await secs(1.3)
	check("4 link locked in GameState", gs.has_link("ch01_link_staged"))
	check("4 deduction card is on the board", board.cards.has(D_STAGED))
	check("4 both clues left the board", not board.cards.has(SHADOW) and not board.cards.has(SNOW))
	check("4 clues are not in the tray either", not board.tray_cards.has(SHADOW) and not board.tray_cards.has(SNOW))
	check("4 clues stay collected", gs.has_evidence(SHADOW) and gs.has_evidence(SNOW))
	check("4 pinned list is just the deduction", pinned_ids() == [D_STAGED], str(pinned_ids()))
	check("4 question became a solved chip", board.chip_nodes.has("ch01_q_real") and not board.question_nodes.has("ch01_q_real"))
	check("4 question_answered fired once", answered_events.size() - answered_before == 1 and answered_events.back() == "ch01_q_real", str(answered_events))
	check("4 link_made fired once", link_events.count("ch01_link_staged") == 1)
	check("4 deduction card has the deduction look", card(D_STAGED).card_style == "lead")
	await shot("04_merged")

	# ---- 5. read the deduction ----
	await secs(0.3)
	check("5 panel opened for the new deduction", board.selected_link_id == "ch01_link_staged")
	var panel_text: String = board.detail_text.text
	check("5 panel shows the deduction, James's line and both clues", panel_text.contains("The scene was built") and panel_text.contains("Someone built this scene") and panel_text.contains("Shadows") and panel_text.contains("Snow"), panel_text.substr(0, 200))
	click(Vector2(1020, 700))
	await secs(0.4)
	check("5 clicking empty board clears the notes page", board.selected_link_id == "" and board.detail_text.text.contains("Nothing worked out yet"))
	await click(card_center(D_STAGED))
	await secs(0.4)
	check("5 clicking the deduction reads it again", board.selected_link_id == "ch01_link_staged")
	check("5 the deduction glows", card(D_STAGED).selected)

	# ---- 7. clue + deduction is a wrong link ----
	await pin_drag(LOGO, Vector2(1020, 340))
	var tries_before: int = gs.get_wrong_tries("ch01_q_real")
	var q_changed_tries: int = gs.get_wrong_tries("ch01_q_changed")
	await drag(pin_of(LOGO), card_center(D_STAGED))
	await secs(0.5)
	check("7 clue + deduction does not merge", not gs.has_link("ch01_link_retouched") and board.cards.has(LOGO) and board.cards.has(D_STAGED))
	check("7 it counts as a wrong try for the open question", gs.get_wrong_tries("ch01_q_changed") == q_changed_tries + 1 and gs.get_wrong_tries("ch01_q_real") == tries_before)

	# ---- 6. both deductions held: the big question ----
	check("6 big question not shown after only one deduction", not board.question_nodes.has("ch01_q_lie"))
	await pin_drag(LEAFLET, Vector2(1020, 580))
	await link_drag(LOGO, LEAFLET)
	check("6 second deduction made", board.cards.has(D_RETOUCHED) and gs.has_link("ch01_link_retouched"))
	check("6 the big question appears", board.question_nodes.has("ch01_q_lie") and board.chip_nodes.size() == 2, str(board.question_nodes.keys()))
	await shot("05_two_deductions")
	await link_drag(D_STAGED, D_RETOUCHED, 1.8)
	check("6 deductions link into 'A lie, told twice'", gs.has_link("ch01_link_two_lies") and board.cards.has(D_LIES), str(pinned_ids()))
	check("6 the two small deductions folded away", not board.cards.has(D_STAGED) and not board.cards.has(D_RETOUCHED))
	check("6 the big question is solved", board.chip_nodes.size() == 3 and board.question_nodes.is_empty(), str(board.chip_nodes.keys()))
	check("6 all 3 questions answered once each", answered_events.size() == 3 and answered_events.has("ch01_q_lie"), str(answered_events))
	check("6 big deduction panel names its source deductions", board.detail_text.text.contains("The scene was built") and board.detail_text.text.contains("Retouched after 2016"))
	await shot("06_all_solved")

	# ---- 10. close / reopen / save / load / reset ----
	var pos_before: Vector2 = card(D_LIES).position
	var pinned_before: Array = pinned_ids()
	board.close()
	await frames(3)
	board.open()
	await secs(0.5)
	check("10 reopen: same pinned cards and position", pinned_ids() == pinned_before and card(D_LIES) != null and card(D_LIES).position.distance_to(pos_before) < 0.5)
	check("10 reopen: 3 solved chips, no open questions", board.chip_nodes.size() == 3 and board.question_nodes.is_empty())
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.get_save_data()))
	gs.reset()
	await secs(0.2)
	check("10 reset clears the board state", gs.board_pinned.is_empty() and gs.board_seen.is_empty() and gs.board_wrong_tries.is_empty() and gs.board_links.is_empty() and gs.board_layout.is_empty())
	check("10 reset empties the screen", board.cards.is_empty() and board.tray_cards.is_empty() and board.chip_nodes.is_empty() and board.question_nodes.is_empty())
	gs.load_save_data(saved)
	board.rebuild()
	await secs(0.5)
	check("10 load: pinned deduction comes back", pinned_ids() == pinned_before and card(D_LIES) != null and card(D_LIES).position.distance_to(pos_before) < 0.5, str(pinned_ids()))
	check("10 load: solved chips come back", board.chip_nodes.size() == 3)
	check("10 load: used clues are not in the tray", board.tray_cards.is_empty(), str(board.tray_order))

	# ---- 8. soft hint ----
	await fresh_open()
	await pin_drag(SHADOW, Vector2(560, 340))
	await pin_drag(LOGO, Vector2(920, 340))
	for i in range(3):
		await drag(pin_of(SHADOW), card_center(LOGO))
		await secs(0.5)
		check("8 wrong try %d counted" % (i + 1), gs.get_wrong_tries("ch01_q_real") == i + 1, str(gs.board_wrong_tries))
		if i < 2:
			check("8 no hint yet after %d tries" % (i + 1), not card(SHADOW).hinted)
	check("8 after 3 wrong tries the answer cards glow (board)", card(SHADOW).hinted)
	check("8 ... and in the tray", board.tray_cards[SNOW].hinted)
	check("8 other cards do not glow", not card(LOGO).hinted and not board.tray_cards[LEAFLET].hinted)
	await secs(5.0)
	await shot("07_hint")
	await pin_drag(SNOW, Vector2(560, 600))
	check("8 hint moves with the card onto the board", card(SNOW).hinted)
	await link_drag(SHADOW, SNOW)
	var any_hint := false
	for c in board.cards.values():
		if c.hinted:
			any_hint = true
	for t in board.tray_cards.values():
		if t.hinted:
			any_hint = true
	check("8 glow stops once the question is answered", not any_hint)

	# ---- 9. keyboard only ----
	await fresh_open()
	var owner: Control = root.gui_get_focus_owner()
	check("9 opening focuses the first tray card", owner != null and owner.get_script() == board.TrayCardScript, str(owner))
	tap(KEY_ENTER)
	await secs(0.45)
	check("9 Enter pins the focused tray card", board.cards.has(SHADOW) and pinned_ids() == [SHADOW], str(pinned_ids()))
	check("9 focus moves to the pinned card", root.gui_get_focus_owner() == card(SHADOW))
	check("9 notebook stays open after a pin", board.notebook.is_open)
	tap(KEY_T)
	await secs(0.8)
	check("9 T closed the notebook", not board.notebook.is_open and board.tray_cards[SNOW].focus_mode == Control.FOCUS_NONE)
	tap(KEY_T)
	await secs(0.8)
	check("9 T opens the notebook and focuses a row", board.notebook.is_open and root.gui_get_focus_owner() != null and root.gui_get_focus_owner().get_script() == board.TrayCardScript, str(root.gui_get_focus_owner()))
	board.tray_cards[SNOW].grab_focus()
	tap(KEY_ENTER)
	await secs(0.45)
	check("9 second card pinned by keyboard", board.cards.has(SNOW))
	card(SHADOW).grab_focus()
	tap(KEY_ENTER)
	await frames(2)
	check("9 Enter starts a link", board.link_source == card(SHADOW))
	card(SNOW).grab_focus()
	await frames(2)
	tap(KEY_ENTER)
	await secs(1.6)
	check("9 Enter on the second card merges them", board.cards.has(D_STAGED) and gs.has_link("ch01_link_staged"))
	card(D_STAGED).grab_focus()
	tap(KEY_Q)
	await secs(0.4)
	check("9 Q reads the focused deduction", board.selected_link_id == "ch01_link_staged")
	tap(KEY_BACKSPACE)
	await secs(0.4)
	check("9 Backspace unpins the focused card", not board.cards.has(D_STAGED) and board.tray_cards.has(D_STAGED), str(pinned_ids()))
	check("9 focus follows it into the tray", root.gui_get_focus_owner() == board.tray_cards[D_STAGED])
	await secs(5.0)
	await shot("09_tray_deduction")
	check("9 the question stays solved after unpinning", board.chip_nodes.has("ch01_q_real"))
	tap(KEY_ENTER)
	await secs(0.45)
	check("9 Enter pins the deduction again", board.cards.has(D_STAGED))
	board._set_tray_open(true, false)
	await secs(0.1)
	board.tray_cards[LOGO].grab_focus()
	tap(KEY_ENTER)
	await secs(0.45)
	board._set_tray_open(true, false)
	await secs(0.1)
	board.tray_cards[LEAFLET].grab_focus()
	tap(KEY_ENTER)
	await secs(0.45)
	card(LOGO).grab_focus()
	tap(KEY_ENTER)
	await frames(2)
	card(LEAFLET).grab_focus()
	await frames(2)
	tap(KEY_ENTER)
	await secs(1.6)
	check("9 second pair merged by keyboard", board.cards.has(D_RETOUCHED))
	card(D_STAGED).grab_focus()
	tap(KEY_ENTER)
	await frames(2)
	card(D_RETOUCHED).grab_focus()
	await frames(2)
	tap(KEY_ENTER)
	await secs(1.8)
	check("9 deductions linked by keyboard", board.cards.has(D_LIES) and gs.has_link("ch01_link_two_lies"))

	# ---- 11. Milestone 3 rules ----
	await fresh_open()
	await pin_drag(SHADOW, Vector2(560, 340))
	await pin_drag(SNOW, Vector2(920, 340))
	await pin_drag(LOGO, Vector2(1220, 340))
	await pin_drag(LEAFLET, Vector2(560, 600))
	check("11 four pinned cards do not overlap", all_clear() and board.cards.size() == 4, str(min_gap()))
	var moved_from: Vector2 = card(SHADOW).position
	await drag(card_center(SHADOW), card_center(SNOW))
	check("11 a card cannot be dragged onto another", all_clear() and min_gap() >= 39.0, str(min_gap()))
	var moved_to: Vector2 = card(LEAFLET).position
	await drag(card_center(LEAFLET), card_center(LEAFLET) + Vector2(80, 40))
	check("11 dragging moves a card", card(LEAFLET).position.distance_to(moved_to) > 20.0)
	var remembered: Vector2 = card(LEAFLET).position
	board.close()
	board.open()
	await secs(0.5)
	check("11 card position is remembered after reopening", card(LEAFLET).position.distance_to(remembered) < 0.5)
	check("11 wrong pair with its own line", board._wrong_line(board._pair_key(SHADOW, LOGO)).contains("Both say fake"))
	check("11 other wrong pair uses the fallback lines", board._wrong_line(board._pair_key(SHADOW, LEAFLET)) != "")
	board.max_pinned = 6
	await secs(5.0)
	await shot("08_four_pinned")

	# ---- 12. Milestone 4.1 ----
	await fresh_open()
	await pin_drag(SHADOW, Vector2(560, 340))
	await pin_drag(SNOW, Vector2(920, 340))
	await pin_drag(LOGO, Vector2(1220, 340))
	await pin_drag(LEAFLET, Vector2(560, 600))
	check("12 notebook stays open while pinning four clues", board.notebook.is_open and board.cards.size() == 4)
	check("12 all four clues left the notebook", board.notebook.order.is_empty())
	var rel: Array = gs.board_layout[SHADOW]
	check("12 positions are saved relative to the board", Vector2(rel[0], rel[1]).distance_to(card(SHADOW).position - board.BOARD_RECT.position) < 0.5, str(rel))
	var data: Dictionary = gs.get_save_data()
	var before_pos: Vector2 = card(SNOW).position
	gs.load_save_data(data)
	board.close()
	board.open()
	await secs(0.5)
	check("12 positions survive save and load", card(SNOW).position.distance_to(before_pos) < 0.5)
	# Keyboard: Left from the left column goes into the folder, Right comes back.
	await fresh_open()
	await pin_drag(SHADOW, Vector2(560, 340))
	card(SHADOW).grab_focus()
	await frames(2)
	tap(KEY_LEFT)
	await frames(3)
	var focus_now: Control = root.gui_get_focus_owner()
	check("12 Left from the left column enters the folder", focus_now != null and focus_now.get_script() == board.TrayCardScript, str(focus_now))
	tap(KEY_RIGHT)
	await frames(3)
	check("12 Right from a row returns to the board", root.gui_get_focus_owner() == card(SHADOW))
	# Dropping on the closed cover unpins.
	tap(KEY_T)
	await secs(0.8)
	await drag(card_center(SHADOW), cover_center())
	await secs(0.4)
	check("12 dropping a card on the closed notebook unpins it", not board.cards.has(SHADOW) and board.tray_cards.has(SHADOW))
	# A refused pin flashes the counter.
	await open_drawer()
	board.max_pinned = 1
	await pin_drag(SHADOW, Vector2(560, 340))
	await open_drawer()
	await drag(tray_center(SNOW), Vector2(920, 340))
	await secs(0.3)
	check("12 refused pin flashes the counter", board._plate_red)
	board.max_pinned = 6
	# The merged card is ivory, not navy.
	await fresh_open()
	await pin_drag(SHADOW, Vector2(560, 340))
	await pin_drag(SNOW, Vector2(920, 340))
	await link_drag(SHADOW, SNOW, 2.0)
	await secs(1.5)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var ded: Control = card(D_STAGED)
	var brightest: Color = Color(0, 0, 0)
	for local_point in [Vector2(40, 130), Vector2(200, 128), Vector2(150, 60), Vector2(60, 100), Vector2(190, 90)]:
		var probe: Vector2 = ded.get_global_transform() * local_point
		var sample: Color = image.get_pixelv(Vector2i(probe))
		if sample.get_luminance() > brightest.get_luminance():
			brightest = sample
	var pixel: Color = brightest
	check("12 merged card is ivory (no navy)", pixel.r > 0.85 and pixel.g > 0.8 and pixel.b > 0.6 and pixel.b < pixel.r, str(pixel))
	await shot("12_merged_ivory")
	check("12 board stays in place (no nudge)", board.surface.position.y == 56.0 and board.cards_root.position.y == 0.0, str(board.surface.position))

	# ================= Milestone 4.2 =================
	var aud: Node = root.get_node("Audio")

	# ---- 13. layout, case tag, intro ----
	gs.reset()
	if board.visible:
		board.close()
	aud.played_log.clear()
	gs.collect_evidence(SHADOW)
	gs.collect_evidence(SNOW)
	var lines_before_intro: int = line_count
	board.open()
	await secs(0.6)
	check("13 no Title / Controls / Hint labels", board.get_node_or_null("Title") == null and board.get_node_or_null("Controls") == null and board.get_node_or_null("Hint") == null)
	check("13 case tag text comes from JSON", board.case_title == "The Last Crossing" and board.chapter_text == "Chapter 1 · Developed in Silence", board.chapter_text)
	var nb_rect: Rect2 = board.notebook.get_global_rect()
	check("13 columns start at y 56 and end at y 790", nb_rect.position.y == 56.0 and nb_rect.end.y == 790.0 and board.BOARD_RECT.position.y == 56.0 and board.BOARD_RECT.end.y == 790.0 and board.solved_strip.get_global_rect().position.y == 56.0 and board.detail_panel.get_global_rect().end.y == 790.0, str(nb_rect))
	check("13 case notes page is always visible, with pencil text", board.detail_panel.visible and board.detail_text.text.contains("Nothing worked out yet"))
	check("13 intro: first open says the intro line", gs.board_intro_seen and line_count > lines_before_intro and str(board.dialogue.lines[0].get("text", "")).contains("Pin what"), str(board.dialogue.lines))
	await secs(1.0)
	board.close()
	var lines_before_second: int = line_count
	board.open()
	await secs(0.5)
	check("13 intro does not play a second time", line_count == lines_before_second, str(line_count - lines_before_second))
	gs.reset()
	board.close()
	board.open()
	await secs(0.5)
	check("13 intro plays again after a reset", gs.board_intro_seen and str(board.dialogue.lines[0].get("text", "")).contains("Pin what"))
	await secs(1.0)
	check("13 notebook empty-board start: held up", board.notebook.is_open)
	gs.reset()
	gs.collect_evidence(SHADOW)
	gs.collect_evidence(SNOW)
	board.close()
	board.open()
	await secs(1.0)

	# ---- 14. notebook: geometry, animations, sound ----
	var open_rect: Rect2 = board.notebook.body_global_rect()
	check("14 held up: about 260 x 480, no tilt, top at y 130", board.notebook.body_size().distance_to(Vector2(260, 480)) < 1.0 and absf(board.notebook.body_rotation_degrees()) < 0.1 and absf(open_rect.position.y - 130.0) < 1.0, str(open_rect))
	var anim_player: AnimationPlayer = board.notebook._anim
	check("14 open and close are AnimationPlayer animations", anim_player.has_animation("open") and anim_player.has_animation("close") and absf(anim_player.get_animation("open").length - 0.62) < 0.001 and absf(anim_player.get_animation("close").length - 0.48) < 0.001)
	var open_keys: Array = []
	var close_keys: Array = []
	for pair in [["open", open_keys], ["close", close_keys]]:
		var a: Animation = anim_player.get_animation(pair[0])
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_METHOD:
				for k in a.track_get_key_count(i):
					pair[1].append([snappedf(a.track_get_key_time(i, k), 0.001), str(a.track_get_key_value(i, k)["args"][0]), str(a.method_track_get_name(i, k))])
		pair[1].sort()
	check("14 open: method track calls the listed sounds at the listed times", open_keys == [[0.0, "notebook_pickup", "play_sound"], [0.14, "band_snap", "play_sound"], [0.2, "cover_open", "play_sound"], [0.42, "page_settle", "play_sound"]], str(open_keys))
	check("14 close: cover_close then notebook_down", close_keys.size() == 2 and close_keys[0][1] == "cover_close" and close_keys[1][1] == "notebook_down", str(close_keys))
	aud.played_log.clear()
	tap(KEY_T)
	await secs(0.2)
	check("14 mid-close sounds already played", aud.played_log == [] or aud.played_log.size() <= 1)
	await secs(0.7)
	check("14 closing played its two sounds in order", aud.played_log == ["cover_close", "notebook_down"], str(aud.played_log))
	var closed_rect: Rect2 = board.notebook.body_global_rect()
	check("14 set down: about 190 x 300, tilted -5 degrees", board.notebook.body_size().distance_to(Vector2(190, 300)) < 1.0 and absf(board.notebook.body_rotation_degrees() + 5.0) < 0.1, str(board.notebook.body_size()))
	check("14 closed notebook is centred near (198, 600)", closed_rect.get_center().distance_to(Vector2(198, 600)) < 12.0, str(closed_rect.get_center()))
	check("14 sticky tab counts the unseen clues", board.notebook.unseen_count() == 2)
	await shot("m42_01_closed_2_new")
	aud.played_log.clear()
	tap(KEY_T)
	var mid_seen: bool = false
	var shot_taken: bool = false
	var last_flip: float = 0.0
	var monotonic: bool = true
	for i in range(80):
		await frames(1)
		var f: float = board.notebook.flip
		if f < last_flip - 0.01:
			monotonic = false
		last_flip = f
		if f > 50.0 and f < 140.0:
			mid_seen = true
			if not shot_taken:
				shot_taken = true
				anim_player.pause()
				await shot("m42_02_mid_flip")
				anim_player.play()
	check("14 mid-flip: cover passes through about 90 degrees, smoothly", mid_seen and monotonic and last_flip > 179.0, str(last_flip))
	await secs(0.5)
	check("14 opening played its four sounds in order", aud.played_log == ["notebook_pickup", "band_snap", "cover_open", "page_settle"], str(aud.played_log))
	# With no sound files, each missing id warned once and nothing broke.
	var unique_ids: Dictionary = {}
	for id in aud.played_log:
		unique_ids[id] = true
	check("14 silent fallback: one warning per missing id", aud.warning_count() >= unique_ids.size() and aud.warning_count() == aud._warned.size())
	var warns_before: int = aud.warning_count()
	tap(KEY_T)
	await secs(0.8)
	tap(KEY_T)
	await secs(0.8)
	check("14 repeating the animations adds no new warnings", aud.warning_count() == warns_before)
	# Hover lifts a closed notebook 4 px.
	tap(KEY_T)
	await secs(0.8)
	var rest_y: float = board.notebook.body_global_rect().position.y
	mouse_move(cover_center())
	await secs(0.4)
	check("14 hovering the closed notebook lifts it 4 px", absf((rest_y - board.notebook.body_global_rect().position.y) - 4.0) < 0.6, str(rest_y - board.notebook.body_global_rect().position.y))
	check("14 and shows a pointing hand", board.notebook.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	mouse_move(Vector2(900, 700))
	await secs(0.3)
	# A new clue arrives while the notebook is set down: the tab wiggles.
	var wiggle_seen: float = 0.0
	gs.collect_evidence(LOGO)
	var wiggle_t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - wiggle_t0 < 700:
		await frames(1)
		wiggle_seen = maxf(wiggle_seen, absf(board.notebook.tab_wiggle_degrees()))
	check("14 new clue: tab shows 3 and wiggles", board.notebook.unseen_count() == 3 and wiggle_seen > 1.0, str(wiggle_seen))
	tap(KEY_T)
	await secs(0.9)

	# ---- 15. entries, sections, scrolling ----
	var fake: Array = []
	for index in range(9):
		fake.append({ "id": "fake_%d" % index, "name": "Fake entry %d" % index, "style": "note", "accent": Color(0.5, 0.6, 0.9), "section": "clue", "is_new": false })
	board.notebook.set_entries(fake, "")
	await frames(3)
	check("15 long list: scrolls (overflow arrow state)", board.notebook._max_scroll() > 0.0)
	aud.played_log.clear()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = board.notebook.get_global_transform() * Vector2(158.0, 300.0)
	wheel.global_position = wheel.position
	root.push_input(wheel)
	await frames(2)
	check("15 wheel scrolls one entry", absf(board.notebook._scroll - 60.0) < 0.5 and aud.played_log.has("page_rustle"), str(board.notebook._scroll))
	await shot("m42_03_scroll_overflow")
	board.rebuild()
	await frames(3)
	check("15 sections: only clues so far", board._notebook_entries().all(func(e: Dictionary) -> bool: return e["section"] == "clue"))

	# ---- 16. Leads, Conclusions, ink ticks ----
	await fresh_open()
	await secs(1.0)
	await pin_drag(SHADOW, Vector2(560, 340))
	await pin_drag(SNOW, Vector2(920, 340))
	aud.played_log.clear()
	var q_real: Control = board.question_nodes["ch01_q_real"]
	await drag(pin_of(SHADOW), card_center(SNOW))
	var waited: float = 0.0
	while is_instance_valid(q_real) and q_real._strike_progress < 0.99 and waited < 4.0:
		await frames(1)
		waited += 0.016
	check("16 ink tick and strike-through are drawn on the answered question", is_instance_valid(q_real) and q_real._tick_progress > 0.99 and q_real._strike_progress > 0.99)
	await shot("m42_04_ticked_question")
	await secs(2.0)
	check("16 then the question moves to a chip", board.chip_nodes.has("ch01_q_real") and not board.question_nodes.has("ch01_q_real"))
	var lead: Control = card(D_STAGED)
	check("16 the new card is a Lead: torn top, loose end, linkable", lead.card_style == "lead" and lead.linkable and lead._torn_edge().size() == 19 and lead._loose_amount > 0.99)
	check("16 the Lead keeps swaying (redraws every frame)", lead.is_processing())
	check("16 appear sounds: string_tie, pencil_write, pin_push, ink_tick", aud.played_log.has("string_tie") and aud.played_log.has("pencil_write") and aud.played_log.has("pin_push") and aud.played_log.has("ink_tick"), str(aud.played_log))
	await shot("m42_05_lead_loose_end")
	check("16 the Lead's pin carries the blended link colour", lead.accent.is_equal_approx(board._link_accent(board.link_by_id["ch01_link_staged"])))
	# Second Lead, then combine the two Leads into a Conclusion.
	await pin_drag(LOGO, Vector2(560, 600))
	await pin_drag(LEAFLET, Vector2(920, 600))
	await link_drag(LOGO, LEAFLET)
	check("16 both deductions are Leads", card(D_RETOUCHED).card_style == "lead" and card(D_RETOUCHED).linkable)
	# Park one Lead in the notebook: the page shows Leads.
	card(D_RETOUCHED).grab_focus()
	tap(KEY_BACKSPACE)
	await secs(1.0)
	var sections: Array = []
	for e in board._notebook_entries():
		sections.append(e["section"])
	check("16 an unpinned Lead is filed under Leads", sections == ["lead"], str(sections))
	await shot("m42_06_notebook_leads")
	await pin_drag(D_RETOUCHED, Vector2(920, 600))
	aud.played_log.clear()
	await link_drag(D_STAGED, D_RETOUCHED, 2.5)
	var conclusion: Control = card(D_LIES)
	check("16 combining two Leads gives a Conclusion", conclusion != null and conclusion.card_style == "conclusion" and not conclusion.linkable)
	check("16 the Conclusion says which question it answers", conclusion.answers_text == "What is The Last Crossing?", conclusion.answers_text)
	check("16 conclusion_chime played", aud.played_log.has("conclusion_chime"), str(aud.played_log))
	await shot("m42_07_conclusion")
	# No string can start from a Conclusion; James says it is settled.
	var said_before: int = line_count
	mouse_move(pin_of(D_LIES))
	await frames(3)
	check("16 cursor stays an arrow over the tack", conclusion.mouse_default_cursor_shape == Control.CURSOR_ARROW)
	mouse_btn(pin_of(D_LIES), true)
	await frames(1)
	mouse_move(pin_of(D_LIES) + Vector2(60, 40))
	await frames(2)
	check("16 pressing the tack starts no string", board.link_source == null)
	mouse_btn(pin_of(D_LIES) + Vector2(60, 40), false)
	await secs(0.3)
	check("16 James says the settled line", line_count > said_before and str(board.dialogue.lines[0].get("text", "")) == board.settled_line, str(board.dialogue.lines))
	mouse_move(card_center(D_LIES))
	await frames(3)
	check("16 the Conclusion body still shows a hand cursor (it can be moved and read)", conclusion.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND)
	said_before = line_count
	conclusion.grab_focus()
	tap(KEY_ENTER)
	await frames(3)
	check("16 Enter on a Conclusion also says the settled line and starts no link", board.link_source == null and line_count > said_before)
	# Park it: it goes under Proven.
	tap(KEY_BACKSPACE)
	await secs(1.0)
	var proven: Array = []
	for e in board._notebook_entries():
		proven.append(e["section"])
	check("16 an unpinned Conclusion is filed under Proven", proven == ["proven"], str(proven))
	await shot("m42_08_notebook_proven")
	var script_text: String = FileAccess.get_file_as_string("res://scripts/mechanics/EvidenceCard.gd").to_lower() + FileAccess.get_file_as_string("res://scripts/mechanics/QuestionCard.gd").to_lower()
	check("16 no stamp or seal code is left in EvidenceCard.gd / QuestionCard.gd", not script_text.contains("stamp") and not script_text.contains("seal"))

	# ---- 17. prompt bar ----
	await fresh_open()
	await secs(5.0)
	await pin_drag(SHADOW, Vector2(560, 340))
	await pin_drag(SNOW, Vector2(920, 340))
	mouse_move(Vector2(1000, 650))
	await frames(4)
	var bar: Control = board.prompt_bar
	var labels: Array = []
	for p in bar.visible_prompts():
		labels.append(p["label"])
	check("17 default set: Notebook and Back", bar.context_id == "default" and labels == ["Notebook", "Back"], str(labels))
	var wait_bar: float = 0.0
	while bar.is_suppressed() and wait_bar < 12.0:
		await secs(0.5)
		wait_bar += 0.5
	await shot("m42_09_prompt_default")
	mouse_move(tray_center(LOGO))
	await frames(4)
	check("17 over a notebook entry", bar.context_id == "notebook_entry", bar.context_id)
	mouse_move(card_center(SHADOW))
	await frames(4)
	check("17 over a board clue", bar.context_id == "board_card", bar.context_id)
	await secs(0.4)
	await shot("m42_10_prompt_card")
	mouse_move(board.notebook.get_global_transform() * (board.notebook.OPEN_CENTER - Vector2(0.0, board.notebook.OPEN_SIZE.y * 0.5) + Vector2(60.0, 8.0)))
	await frames(4)
	check("17 over the wire binding", bar.context_id == "notebook_binding" and board.notebook.is_binding_hovered(), bar.context_id)
	mouse_move(pin_of(SHADOW))
	await frames(2)
	mouse_btn(pin_of(SHADOW), true)
	await frames(1)
	mouse_move(pin_of(SHADOW) + Vector2(80, 40))
	await frames(3)
	check("17 while dragging a string", bar.context_id == "dragging_string", bar.context_id)
	mouse_btn(pin_of(SHADOW) + Vector2(80, 40), false)
	await secs(0.6)
	board.dialogue.show_notice("Test", "Someone is talking.", 1.5)
	await secs(0.7)
	check("17 hidden while the dialogue box is showing", bar.is_suppressed() and bar.modulate.a < 0.05, str(bar.modulate.a))
	await secs(3.0)
	check("17 and back afterwards", not bar.is_suppressed() and bar.modulate.a > 0.95, str(bar.modulate.a))
	var pad_press := InputEventJoypadButton.new()
	pad_press.button_index = JOY_BUTTON_A
	pad_press.pressed = true
	root.push_input(pad_press)
	await frames(2)
	var pad_ok: bool = bar.use_pad
	for p in bar.visible_prompts():
		if str(p.get("pad", "")) == "":
			pad_ok = false
	check("17 after a gamepad press the bar shows pad glyphs", pad_ok)
	tap(KEY_SHIFT)
	await frames(2)
	check("17 and keyboard glyphs again after a key", not bar.use_pad)
	check("17 the prompt text comes from data/ui/board_prompts.json", FileAccess.file_exists("res://data/ui/board_prompts.json") and not bar.prompts_for("conclusion").is_empty())

	# ---- 18. the Conclusion prompt set ----
	await fresh_open()
	await secs(5.0)
	for id in [SHADOW, SNOW]:
		await pin_drag(id, Vector2(560, 340) if id == SHADOW else Vector2(920, 340))
	await link_drag(SHADOW, SNOW)
	await pin_drag(LOGO, Vector2(560, 600))
	await pin_drag(LEAFLET, Vector2(920, 600))
	await link_drag(LOGO, LEAFLET)
	await link_drag(D_STAGED, D_RETOUCHED, 2.5)
	await secs(5.0)
	mouse_move(card_center(D_LIES))
	await frames(4)
	var set_labels: Array = []
	for p in board.prompt_bar.visible_prompts():
		set_labels.append(p["label"])
	check("18 over a Conclusion: Read / Move / Unpin", board.prompt_bar.context_id == "conclusion" and set_labels == ["Read", "Move", "Unpin"], str(set_labels))
	var wait_c: float = 0.0
	while board.prompt_bar.is_suppressed() and wait_c < 12.0:
		await secs(0.5)
		wait_c += 0.5
	await shot("m42_11_prompt_conclusion")
	await shot("m42_12_case_tag")

	print("")
	print("M4.2 RESULT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
