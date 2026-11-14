extends CanvasLayer

# A small frame meter, hidden until F3 is pressed. It lives on the root window, so it survives scene changes.
#
#   FPS 60   frame 16.7 ms   worst 21.0 ms   draws 31   <graphics card name>  <driver>
#
# "worst" is the slowest frame in the last second: a steady 60 FPS with a high "worst" means hitches (stutter),
# while a low FPS with an even "worst" means the picture is simply too heavy for the machine.

const REFRESH: float = 0.5
const Typo := preload("res://scripts/ui/Typo.gd")

var _label: Label
var _left: float = 0.0
var _slowest: float = 0.0
var _frames: int = 0
var _time: float = 0.0
var _adapter: String = ""


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_label = Label.new()
	_label.position = Vector2(24.0, 16.0)
	_label.add_theme_font_override("font", Typo.hand_bold())
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.75))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_adapter = "%s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name()]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F3:
		visible = not visible
		_left = 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_slowest = maxf(_slowest, delta)
	_time += delta
	_frames += 1
	_left -= delta
	if _left > 0.0:
		return
	_left = REFRESH
	var average_ms: float = _time / maxf(1.0, float(_frames)) * 1000.0
	_label.text = "FPS %d   frame %.1f ms   worst %.1f ms   draws %d\n%s" % [
		roundi(1000.0 / maxf(0.1, average_ms)), average_ms, _slowest * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), _adapter]
	_time = 0.0
	_frames = 0
	if _slowest > 0.0:
		_slowest *= 0.5
