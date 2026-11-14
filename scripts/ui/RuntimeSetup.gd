extends RefCounted

# Small things every screen of the game needs once, however the game was started (boot screens, F6 on one scene...).
# Each screen's _ready() calls RuntimeSetup.apply(get_tree()); doing it twice is harmless.
#
#   black clear colour   Godot paints one frame of its default grey between two scenes (the old one is gone,
#                        the new one is not drawn yet). That grey was the "white flash". Black hides it.
#   frame meter          F3 shows FPS and frame times (see FpsOverlay.gd). Off until you press F3.

const FpsOverlay := preload("res://scripts/ui/FpsOverlay.gd")


static func apply(tree: SceneTree) -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	if tree.root.has_node("FpsOverlay"):
		return
	var meter: CanvasLayer = FpsOverlay.new()
	meter.name = "FpsOverlay"
	tree.root.add_child.call_deferred(meter)
