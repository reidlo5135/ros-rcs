extends SubViewportContainer

signal waypoint_placed(position: Vector3, yaw: float)

const RcsWorld := preload("res://src/scene/world/world.gd")

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
	world.waypoint_placed.connect(func(position: Vector3, yaw: float) -> void:
		waypoint_placed.emit(position, yaw)
	)
	viewport.add_child(world)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
	if world != null and world.has_method("handle_viewport_input"):
		world.handle_viewport_input(_to_viewport_event(event))
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and world != null and world.has_method("release_viewport_input"):
		world.release_viewport_input()


func set_waypoint_placement_enabled(enabled: bool) -> void:
	if world != null and world.has_method("set_waypoint_placement_enabled"):
		world.set_waypoint_placement_enabled(enabled)


func clear_waypoints() -> void:
	if world != null and world.has_method("clear_waypoints"):
		world.clear_waypoints()


func set_visualization_layer_visible(layer_id: String, enabled: bool) -> void:
	if world != null and world.has_method("set_visualization_layer_visible"):
		world.set_visualization_layer_visible(layer_id, enabled)


func set_camera_mode(mode: String) -> void:
	if world != null and world.has_method("set_camera_mode"):
		world.set_camera_mode(mode)


func reset_view_modes() -> void:
	if world != null and world.has_method("reset_view_modes"):
		world.reset_view_modes()


func _to_viewport_event(event: InputEvent) -> InputEvent:
	if viewport == null or size.x <= 0.0 or size.y <= 0.0:
		return event
	if event is InputEventMouseButton:
		var copy := event.duplicate() as InputEventMouseButton
		copy.position = _to_viewport_position(event.position)
		return copy
	if event is InputEventMouseMotion:
		var copy := event.duplicate() as InputEventMouseMotion
		copy.position = _to_viewport_position(event.position)
		copy.relative = Vector2(
			event.relative.x * float(viewport.size.x) / size.x,
			event.relative.y * float(viewport.size.y) / size.y
		)
		return copy
	return event


func _to_viewport_position(local_position: Vector2) -> Vector2:
	return Vector2(
		local_position.x * float(viewport.size.x) / size.x,
		local_position.y * float(viewport.size.y) / size.y
	)
