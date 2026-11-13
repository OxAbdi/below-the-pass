extends RefCounted

# "Yes" and "No" for menus, the same on keyboard and controller.
# Godot's built-in ui_accept / ui_cancel only know the keyboard (Enter, Space, Esc), so the
# controller's A and B buttons are added here once, and every menu asks these two functions.

static func is_accept(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		return true
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A


static func is_cancel(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		return true
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
