extends SubViewportContainer

const RcsWorld := preload("res://src/scene/rcs_world.gd")

var viewport: SubViewport
var world: Node3D


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK

	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.size = Vector2i(1024, 768)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	world = RcsWorld.new()
	viewport.add_child(world)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
	if world != null and world.has_method("handle_viewport_input"):
		world.handle_viewport_input(event)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and world != null and world.has_method("release_viewport_input"):
		world.release_viewport_input()
