extends PanelContainer

class JoystickControl:
	extends Control

	signal motion_changed(linear_x: float, angular_z: float)

	const MAX_LINEAR_X := 0.45
	const MAX_ANGULAR_Z := 1.2

	var dragging := false
	var knob := Vector2.ZERO

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 170)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				_update_knob(event.position)
			else:
				knob = Vector2.ZERO
				motion_changed.emit(0.0, 0.0)
				queue_redraw()
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			_update_knob(event.position)
			accept_event()

	func _draw() -> void:
		var center := size * 0.5
		var radius: float = min(size.x, size.y) * 0.38
		var knob_radius := 17.0
		draw_circle(center, radius, Color(0.075, 0.088, 0.11))
		draw_arc(center, radius, 0.0, TAU, 64, Color(0.22, 0.27, 0.34), 1.4)
		draw_line(center + Vector2(0, -radius * 0.48), center + Vector2(0, radius * 0.48), Color(0.13, 0.16, 0.2), 1.0)
		draw_line(center + Vector2(-radius * 0.48, 0), center + Vector2(radius * 0.48, 0), Color(0.13, 0.16, 0.2), 1.0)
		draw_circle(center + knob * radius, knob_radius, Color(0.96, 0.57, 0.12))
		draw_arc(center + knob * radius, knob_radius, 0.0, TAU, 32, Color(0.76, 0.43, 0.08), 1.2)

	func _update_knob(local_position: Vector2) -> void:
		var center := size * 0.5
		var radius: float = max(1.0, min(size.x, size.y) * 0.38)
		var delta := (local_position - center) / radius
		if delta.length() > 1.0:
			delta = delta.normalized()
		knob = delta
		motion_changed.emit(-knob.y * MAX_LINEAR_X, -knob.x * MAX_ANGULAR_Z)
		queue_redraw()


var connection_value: Label
var motion_value: Label
var remaining_value: Label
var heading_value: Label
var goal_value: Label
var blocked_source_value: Label
var linear_value: Label
var angular_value: Label
var event_list: ItemList
var last_motion_publish_msec := 0
var last_ping_ms := -1.0


func _ready() -> void:
	_build_ui()
	_sync_connection_state(AppState.connection_state)
	AppState.connection_state_changed.connect(_sync_connection_state)
	AppState.event_pushed.connect(_on_event_pushed)
	SessionRegistry.telemetry_updated.connect(_on_session_updated)
	SessionRegistry.active_session_changed.connect(_on_active_session_changed)
	_sync_from_active_session()


func _build_ui() -> void:
	custom_minimum_size = Vector2(280, 0)
	add_theme_stylebox_override("panel", _panel_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_add_section_header(column, "NAVIGATION STATUS")

	var status := GridContainer.new()
	status.columns = 2
	status.add_theme_constant_override("h_separation", 18)
	status.add_theme_constant_override("v_separation", 8)
	column.add_child(status)

	motion_value = _add_status_row(status, "Motion", "Idle")
	remaining_value = _add_status_row(status, "Remaining", "-- m")
	heading_value = _add_status_row(status, "Heading", "-- rad")
	goal_value = _add_status_row(status, "Goal", "Idle")
	blocked_source_value = _add_status_row(status, "Blocked Source", "Clear")
	connection_value = _add_status_row(status, "Transport", "Disconnected")

	column.add_child(_separator())
	_add_section_header(column, "EVENTS / FEEDBACK")

	event_list = ItemList.new()
	event_list.custom_minimum_size = Vector2(0, 270)
	event_list.size_flags_horizontal = Control.SIZE_FILL
	event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_list.add_theme_stylebox_override("panel", _box_style())
	column.add_child(event_list)

	for entry in AppState.events:
		_add_event_item(entry)

	column.add_child(_separator())
	_add_section_header(column, "JOYSTICK")
	var joystick := JoystickControl.new()
	joystick.motion_changed.connect(_on_joystick_motion_changed)
	column.add_child(joystick)

	var velocity := GridContainer.new()
	velocity.columns = 2
	velocity.add_theme_constant_override("h_separation", 12)
	velocity.add_theme_constant_override("v_separation", 8)
	column.add_child(velocity)
	linear_value = _add_status_row(velocity, "Linear X", "0.000 m/s")
	angular_value = _add_status_row(velocity, "Angular Z", "0.000 rad/s")


func _add_status_row(parent: Control, key_text: String, value_text: String) -> Label:
	var key := Label.new()
	key.text = key_text
	key.add_theme_color_override("font_color", Color(0.58, 0.64, 0.66))
	parent.add_child(key)

	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.clip_text = true
	value.custom_minimum_size = Vector2(120, 0)
	value.add_theme_color_override("font_color", Color(0.9, 0.94, 0.95))
	parent.add_child(value)
	return value


func _sync_connection_state(next_state: String) -> void:
	if connection_value != null:
		connection_value.text = _connection_label(next_state)


func _on_event_pushed(entry: Dictionary) -> void:
	_add_event_item(entry)


func _add_event_item(entry: Dictionary) -> void:
	if event_list == null:
		return
	event_list.add_item("%s  %s" % [entry.get("time", "--:--:--"), entry.get("message", "")])
	while event_list.item_count > AppState.max_events:
		event_list.remove_item(0)
	if event_list.item_count > 0:
		event_list.select(event_list.item_count - 1)
	event_list.ensure_current_is_visible()


func _add_section_header(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.56, 0.62, 0.64))
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)


func _on_joystick_motion_changed(linear_x: float, angular_z: float) -> void:
	if linear_value != null:
		linear_value.text = "%.3f m/s" % linear_x
	if angular_value != null:
		angular_value.text = "%.3f rad/s" % angular_z

	var now := Time.get_ticks_msec()
	var is_stop := is_zero_approx(linear_x) and is_zero_approx(angular_z)
	if not is_stop and now - last_motion_publish_msec < 80:
		return
	last_motion_publish_msec = now
	CommandBus.request_motion(linear_x, angular_z)


func _on_session_updated(session_id: String, _patch: Dictionary) -> void:
	if session_id != SessionRegistry.active_session_id:
		return
	_sync_from_active_session()


func _on_active_session_changed(_session_id: String) -> void:
	_sync_from_active_session()


func _sync_from_active_session() -> void:
	if not SessionRegistry.sessions.has(SessionRegistry.active_session_id):
		return
	var session := SessionRegistry.sessions[SessionRegistry.active_session_id] as Dictionary
	var state = session.get("state")
	if state == null:
		return
	_apply_runtime_state(state)


func _apply_runtime_state(state: Variant) -> void:
	if state == null:
		return
	_apply_motion_status(state.motion_status)
	_apply_navigation_feedback(state.navigation_feedback)
	_apply_navigation_status(state.navigation_status)
	_apply_navigation_result(state.navigation_result)
	_apply_system_result(state.system_result)


func _apply_motion_status(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	if motion_value != null:
		motion_value.text = "Active" if bool(payload.get("active", false)) else "Idle"
	if remaining_value != null and payload.has("remaining_distance"):
		remaining_value.text = "%.2f m" % float(payload.get("remaining_distance", 0.0))
	if heading_value != null and payload.has("heading_error"):
		heading_value.text = "%.3f rad" % float(payload.get("heading_error", 0.0))
	if goal_value != null and bool(payload.get("goal_reached", false)):
		goal_value.text = "Reached"
	if blocked_source_value != null:
		blocked_source_value.text = _blocked_source_from_motion_status(payload)


func _apply_navigation_feedback(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	if motion_value != null:
		motion_value.text = "Executing"
	if remaining_value != null and payload.has("distance_remaining"):
		remaining_value.text = "%.2f m" % float(payload.get("distance_remaining", 0.0))
	if goal_value != null:
		var current_index := int(payload.get("current_goal_index", -1))
		var goal_count := int(payload.get("goal_count", 0))
		if current_index >= 0 and goal_count > 0:
			goal_value.text = "%d / %d" % [current_index + 1, goal_count]


func _apply_navigation_status(payload: Dictionary) -> void:
	if payload.is_empty() or motion_value == null:
		return
	var status_list := payload.get("status_list", []) as Array
	if status_list.is_empty():
		return
	var first_entry: Variant = status_list[0]
	if typeof(first_entry) != TYPE_DICTIONARY:
		return
	var first := first_entry as Dictionary
	motion_value.text = _navigation_status_label(int(first.get("status", 0)))


func _apply_navigation_result(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	if motion_value != null:
		if bool(payload.get("completed", false)):
			motion_value.text = "Succeeded" if bool(payload.get("success", false)) else "Failed"
		elif payload.has("accepted"):
			motion_value.text = "Accepted" if bool(payload.get("accepted", false)) else "Rejected"
	if goal_value != null:
		if payload.has("completed_goals"):
			goal_value.text = "%d complete" % int(payload.get("completed_goals", 0))
		elif payload.has("request_id"):
			goal_value.text = str(payload.get("request_id", "Idle"))


func _apply_system_result(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	var next_ping_ms := _extract_ping_ms(payload)
	if next_ping_ms >= 0.0:
		last_ping_ms = next_ping_ms
		_sync_connection_state(AppState.connection_state)


func _connection_label(next_state: String) -> String:
	return next_state


func _extract_ping_ms(payload: Dictionary) -> float:
	for key in ["ping_ms", "latency_ms", "rtt_ms"]:
		if payload.has(key):
			return maxf(0.0, float(payload.get(key, -1.0)))
	if payload.has("sent_at_ms"):
		var sent_at_ms := float(payload.get("sent_at_ms", -1.0))
		if sent_at_ms > 0.0:
			var now_ms := float(Time.get_unix_time_from_system() * 1000.0)
			return maxf(0.0, now_ms - sent_at_ms)
	if payload.has("bridge_time_ms"):
		var bridge_time_ms := float(payload.get("bridge_time_ms", -1.0))
		if bridge_time_ms >= 0.0 and bridge_time_ms < 600000.0:
			return bridge_time_ms
	return -1.0


func _blocked_source_from_motion_status(payload: Dictionary) -> String:
	if bool(payload.get("safety_gate_blocked", false)):
		return "Safety Gate"
	if bool(payload.get("costmap_blocked", false)):
		return "Costmap"
	if bool(payload.get("obstacle_detected", false)):
		return "Obstacle"
	if bool(payload.get("blocked", false)):
		return "Blocked"
	if bool(payload.get("stalled", false)):
		return "Stalled"
	return "Clear"


func _navigation_status_label(status: int) -> String:
	match status:
		1:
			return "Accepted"
		2:
			return "Executing"
		3:
			return "Canceling"
		4:
			return "Succeeded"
		5:
			return "Canceled"
		6:
			return "Aborted"
		_:
			return "Idle"


func _separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	return separator


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.058, 0.06)
	style.border_color = Color(0.2, 0.24, 0.23)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.038, 0.041, 0.043)
	style.border_color = Color(0.17, 0.22, 0.21)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style
