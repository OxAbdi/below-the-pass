extends Control

# The three save slots, drawn as index cards side by side. Used in three places:
#   "new"   the title screen's New Game: pick a slot to start in
#   "load"  the title screen's and the pause menu's Load
#   "save"  the pause menu's Save
#
# It reads the cards from SaveManager, asks before anything is overwritten or deleted, and
# reports the choice with `chosen(slot)`. It never loads or saves by itself (except deleting a
# save and restoring a backup, which both ask first).

signal chosen(slot: int)
signal cancelled

const MenuSlipsScript := preload("res://scripts/ui/menu/MenuSlips.gd")
const ConfirmBoxScript := preload("res://scripts/ui/menu/ConfirmBox.gd")
const PaperFx := preload("res://scripts/ui/PaperFx.gd")
const UiInput := preload("res://scripts/ui/UiInput.gd")
const FONT: Font = preload("res://assets/fonts/KleeOne-SemiBold.ttf")
const FONT_BODY: Font = preload("res://assets/fonts/KleeOne-Regular.ttf")

const CARD_SIZE: Vector2 = Vector2(460.0, 300.0)
const CARD_GAP: float = 50.0
const PAPER: Color = Color(0.965, 0.945, 0.88)
const INK: Color = Color(0.169, 0.114, 0.078)
const PENCIL: Color = Color(0.36, 0.33, 0.3)
const RULE_RED: Color = Color(0.78, 0.3, 0.28, 0.75)
const RULE_BLUE: Color = Color(0.35, 0.5, 0.72, 0.28)
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var mode: String = "load"
var is_open: bool = false
var selected: int = 1   # slot number, 1..3
var texts: Dictionary = {}
var infos: Dictionary = {}   # slot -> SaveManager.slot_info(slot)

var _confirm: ConfirmBoxScript
var _lift: Array[float] = [0.0, 0.0, 0.0]
var _shake: float = 0.0
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	_confirm = ConfirmBoxScript.new()
	add_child(_confirm)


# `menu_texts` is the whole menus.json object.
func open(new_mode: String, menu_texts: Dictionary) -> void:
	mode = new_mode
	texts = menu_texts.get("slots", {})
	_confirm.yes_text = str((menu_texts.get("confirm", {}) as Dictionary).get("yes", "Yes"))
	_confirm.no_text = str((menu_texts.get("confirm", {}) as Dictionary).get("no", "No"))
	refresh()
	# Start on the slot that makes sense: the active one when saving, the newest when loading,
	# the first empty one for a new game.
	selected = 1
	if mode == "save" and SaveManager.active_slot > 0:
		selected = SaveManager.active_slot
	elif mode == "load" and SaveManager.newest_slot() > 0:
		selected = SaveManager.newest_slot()
	elif mode == "new":
		for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
			if str(infos[slot]["status"]) == "empty":
				selected = slot
				break
	is_open = true
	visible = true
	queue_redraw()


func close() -> void:
	is_open = false
	visible = false


func refresh() -> void:
	infos.clear()
	for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
		infos[slot] = SaveManager.slot_info(slot)
	queue_redraw()


func card_rect(slot: int) -> Rect2:
	var total: float = CARD_SIZE.x * 3.0 + CARD_GAP * 2.0
	var left: float = (size.x - total) * 0.5 + float(slot - 1) * (CARD_SIZE.x + CARD_GAP)
	return Rect2(Vector2(left, (size.y - CARD_SIZE.y) * 0.5 + 10.0), CARD_SIZE)


# Returns true when the event was used (always, while open).
func handle_input(event: InputEvent) -> bool:
	if not is_open:
		return false
	if _confirm.handle_input(event) or _busy:
		return true
	if event.is_action_pressed("ui_left"):
		_select(posmod(selected - 2, SaveManager.SLOT_COUNT) + 1)
	elif event.is_action_pressed("ui_right"):
		_select(selected % SaveManager.SLOT_COUNT + 1)
	elif UiInput.is_accept(event):
		_choose(selected)
	elif UiInput.is_cancel(event):
		close()
		cancelled.emit()
	elif _is_delete(event):
		_delete(selected)
	return true


func _is_delete(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).keycode == KEY_DELETE or (event as InputEventKey).physical_keycode == KEY_DELETE
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_X


func _gui_input(event: InputEvent) -> void:
	if not is_open or _busy or _confirm.is_open:
		return
	if event is InputEventMouseMotion:
		for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
			if card_rect(slot).has_point((event as InputEventMouseMotion).position):
				_select(slot)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button: InputEventMouseButton = event
		accept_event()
		if button.button_index == MOUSE_BUTTON_RIGHT:
			close()
			cancelled.emit()
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
			if card_rect(slot).has_point(button.position):
				_select(slot)
				_choose(slot)
				return


func _select(slot: int) -> void:
	if slot == selected:
		return
	selected = slot
	Audio.play("choice_hover", 0.08)
	queue_redraw()


func _choose(slot: int) -> void:
	var status: String = str(infos[slot]["status"])
	_busy = true
	if status == "damaged":
		# A damaged save can only be restored from its backup (or started over, in "new" and "save").
		if mode == "load":
			if bool(infos[slot]["has_backup"]) and await _confirm.ask(str(texts.get("restore_confirm", "Restore this save from its backup?"))):
				SaveManager.restore_backup(slot)
				refresh()
			else:
				_shake = 1.0
			_busy = false
			return
	match mode:
		"new":
			if status == "empty" or await _confirm.ask(str(texts.get("overwrite_confirm", "Overwrite this save?"))):
				_pick(slot)
		"load":
			if status == "ok":
				_pick(slot)
			else:
				_shake = 1.0
		"save":
			if status == "empty" or slot == SaveManager.active_slot or await _confirm.ask(str(texts.get("overwrite_confirm", "Overwrite this save?"))):
				_pick(slot)
	_busy = false


func _pick(slot: int) -> void:
	Audio.play("choice_pick")
	chosen.emit(slot)


func _delete(slot: int) -> void:
	if str(infos[slot]["status"]) == "empty":
		return
	_busy = true
	if await _confirm.ask(str(texts.get("delete_confirm", "Delete this save?"))):
		SaveManager.delete_slot(slot)
		refresh()
	_busy = false


func _process(delta: float) -> void:
	if not is_open:
		return
	var moving: bool = false
	for index: int in range(3):
		var target: float = 1.0 if index + 1 == selected else 0.0
		if not is_equal_approx(_lift[index], target):
			_lift[index] = move_toward(_lift[index], target, delta / 0.14)
			moving = true
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta / 0.3)
		moving = true
	if moving:
		queue_redraw()


# ---------- drawing ----------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.025, 0.9))
	var heading: String = str(texts.get("heading_" + mode, ""))
	var heading_width: float = FONT.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var heading_at: Vector2 = Vector2((size.x - heading_width) * 0.5, card_rect(1).position.y - 70.0)
	draw_string(FONT, heading_at, heading, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 40, Color(0.96, 0.93, 0.84))
	PaperFx.draw_wavy(self, heading_at + Vector2(0.0, 12.0), heading_width, Color(0.96, 0.93, 0.84, 0.6), 2.0)
	for slot: int in range(1, SaveManager.SLOT_COUNT + 1):
		_draw_card(slot)
	draw_set_transform(Vector2.ZERO)
	var hint: String = "Enter / A  %s      Delete / X  %s      Esc / B  %s" % [str(texts.get("hint_choose", "Choose")), str(texts.get("hint_delete", "Delete")), str(texts.get("hint_back", "Back"))]
	var hint_width: float = FONT_BODY.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(FONT_BODY, Vector2((size.x - hint_width) * 0.5, card_rect(1).end.y + 80.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(0.96, 0.93, 0.84, 0.6))


func _draw_card(slot: int) -> void:
	var rect: Rect2 = card_rect(slot)
	var lift: float = 1.0 - pow(1.0 - _lift[slot - 1], 2.0)
	var wobble: float = sin(_shake * 28.0) * 8.0 * _shake if slot == selected else 0.0
	var tilt: float = deg_to_rad([-1.2, 0.6, -0.5][slot - 1] * (1.0 - lift * 0.6))
	draw_set_transform(rect.get_center() + Vector2(wobble, -10.0 * lift), tilt, Vector2.ONE * (1.0 + 0.03 * lift))
	var local: Rect2 = Rect2(-CARD_SIZE * 0.5, CARD_SIZE)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = INK if slot == selected else Color(INK, 0.55)
	style.set_border_width_all(3 if slot == selected else 2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = int(10.0 + 10.0 * lift)
	style.shadow_offset = Vector2(2.0, 6.0 + 6.0 * lift)
	draw_style_box(style, local)
	draw_texture_rect(PaperFx.grain(), local.grow(-3.0), true, Color(0.45, 0.32, 0.18, 0.09))
	# An index card: one red rule under the heading, faint blue lines below it.
	var left: float = local.position.x + 28.0
	var right: float = local.end.x - 28.0
	var rule_y: float = local.position.y + 64.0
	draw_line(Vector2(local.position.x + 6.0, rule_y), Vector2(local.end.x - 6.0, rule_y), RULE_RED, 2.0)
	var line_y: float = rule_y + 44.0
	while line_y < local.end.y - 16.0:
		draw_line(Vector2(local.position.x + 6.0, line_y), Vector2(local.end.x - 6.0, line_y), RULE_BLUE, 1.0)
		line_y += 44.0
	draw_string(FONT, Vector2(left, rule_y - 16.0), str(texts.get("slot", "Slot %d")) % slot, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, INK)

	var info: Dictionary = infos.get(slot, {})
	var status: String = str(info.get("status", "empty"))
	if status == "empty":
		_centered(str(texts.get("empty", "Empty")), local, 20.0, 30, Color(PENCIL, 0.6), FONT_BODY)
		return
	if status == "damaged":
		_centered(str(texts.get("damaged", "Damaged save")), local, 0.0, 28, Color(0.6, 0.18, 0.15), FONT)
		var note: String = str(texts.get("restore_backup", "Restore backup")) if bool(info.get("has_backup", false)) else str(texts.get("no_backup", "No backup to restore"))
		_centered(note, local, 46.0, 20, PENCIL, FONT_BODY)
		return
	var summary: Dictionary = info.get("summary", {})
	if slot == SaveManager.active_slot and mode == "save":
		var mark: String = "●"
		draw_string(FONT, Vector2(right - 18.0, rule_y - 18.0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, RULE_RED)
	var width: float = right - left
	draw_string(FONT, Vector2(left, rule_y + 36.0), "%s: %s" % [str(texts.get("chapter", "Chapter %d")) % int(summary.get("chapter", 1)), str(summary.get("chapter_title", ""))], HORIZONTAL_ALIGNMENT_LEFT, width, 22, INK)
	var place: String = str(summary.get("map_name", ""))
	if str(summary.get("phase_name", "")) != "":
		place += ", " + str(summary.get("phase_name", ""))
	draw_string(FONT_BODY, Vector2(left, rule_y + 80.0), place, HORIZONTAL_ALIGNMENT_LEFT, width, 21, INK)
	draw_string(FONT_BODY, Vector2(left, rule_y + 124.0), format_play_time(float(summary.get("play_seconds", 0.0))), HORIZONTAL_ALIGNMENT_LEFT, width, 21, PENCIL)
	draw_string(FONT_BODY, Vector2(left, rule_y + 168.0), format_date(int(info.get("saved_at", 0))), HORIZONTAL_ALIGNMENT_LEFT, width, 21, PENCIL)


func _centered(text: String, local: Rect2, offset_y: float, font_size: int, color: Color, font: Font) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(-width * 0.5, local.get_center().y + 30.0 + offset_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


# 2140 seconds -> "0:35"
static func format_play_time(seconds: float) -> String:
	var minutes: int = int(seconds) / 60
	return "%d:%02d" % [minutes / 60, minutes % 60]


# Unix time -> "14 Nov 2026, 04:12" in the player's own time zone.
static func format_date(unix_time: int) -> String:
	if unix_time <= 0:
		return ""
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%d %s %d, %02d:%02d" % [int(d["day"]), MONTHS[int(d["month"]) - 1], int(d["year"]), int(d["hour"]), int(d["minute"])]
