extends Control

const TopbarScene := preload("res://src/ui/components/topbar/topbar.tscn")
const OperationsPanelScene := preload("res://src/ui/panels/operation/operation.tscn")
const AIMissionPanelScene := preload("res://src/ui/panels/ai/ai.tscn")
const TelemetryPanelScene := preload("res://src/ui/panels/telemetry/telemetry.tscn")
const SceneViewportScene := preload("res://src/scene/viewport/viewport.tscn")
const RcsMqttTransportScript := preload("res://src/domain/transport/mqtt_transport.gd")
const RcsTelemetryRouterScript := preload("res://src/domain/telemetry/telemetry_router.gd")
const TopicCatalogScript := preload("res://src/domain/protocol/topic_catalog.gd")

var transport: Node
var telemetry_router: RefCounted
var operations_panel: Control
var ai_mission_panel: Control
var telemetry_panel: Control
var scene_shell: Control
var scene_viewport: Control
var active_robot_id := "burger1"
var telemetry_log_counts: Dictionary = {}
var last_telemetry_log_msec := 0
var ping_timer: Timer


func _ready() -> void:
	_build_runtime()
	_build_layout()
	AppState.topic_settings_changed.connect(_on_topic_settings_changed)


func _build_runtime() -> void:
	transport = RcsMqttTransportScript.new()
	transport.disconnected.connect(_on_transport_disconnected)
	transport.connected.connect(_on_transport_connected)
	transport.subscribed.connect(_on_transport_subscribed)
	transport.message_received.connect(_on_mqtt_message_received)
	transport.publish_failed.connect(_on_publish_failed)
	add_child(transport)

	ping_timer = Timer.new()
	ping_timer.wait_time = 1.0
	ping_timer.autostart = false
	ping_timer.timeout.connect(_on_ping_timer_timeout)
	add_child(ping_timer)

	telemetry_router = RcsTelemetryRouterScript.new()
	telemetry_router.fallback_robot_id = active_robot_id
	telemetry_router.telemetry_patch.connect(_on_telemetry_patch)
	telemetry_router.control_event.connect(_on_control_event)
	CommandBus.command_requested.connect(_on_command_requested)


func _build_layout() -> void:
	add_theme_stylebox_override("panel", _panel_style(Color(0.042, 0.044, 0.046), Color(0.042, 0.044, 0.046)))

	var root := VBoxContainer.new()
	root.name = "ConsoleFrame"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var topbar := TopbarScene.instantiate()
	topbar.control_mode_changed.connect(_on_control_mode_changed)
	root.add_child(topbar)

	var workspace := HBoxContainer.new()
	workspace.name = "Workspace"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 6)
	root.add_child(workspace)

	operations_panel = OperationsPanelScene.instantiate()
	operations_panel.connect_requested.connect(_on_connect_requested)
	operations_panel.disconnect_requested.connect(_on_disconnect_requested)
	operations_panel.navigation_requested.connect(_on_navigation_requested)
	operations_panel.cancel_requested.connect(_on_cancel_requested)
	operations_panel.clear_requested.connect(_on_clear_requested)
	operations_panel.initial_pose_requested.connect(_on_initial_pose_requested)
	operations_panel.waypoint_placing_toggled.connect(_on_waypoint_placing_toggled)
	operations_panel.layer_visibility_changed.connect(_on_layer_visibility_changed)
	workspace.add_child(operations_panel)

	ai_mission_panel = AIMissionPanelScene.instantiate()
	ai_mission_panel.visible = false
	ai_mission_panel.prompt_submitted.connect(_on_ai_prompt_submitted)
	ai_mission_panel.connect_requested.connect(_on_connect_requested)
	ai_mission_panel.disconnect_requested.connect(_on_disconnect_requested)
	workspace.add_child(ai_mission_panel)

	scene_shell = _build_scene_shell()
	workspace.add_child(scene_shell)

	telemetry_panel = TelemetryPanelScene.instantiate()
	workspace.add_child(telemetry_panel)

	_on_control_mode_changed("manual")


func _build_scene_shell() -> PanelContainer:
	var shell := PanelContainer.new()
	shell.name = "SceneShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_stylebox_override("panel", _panel_style(Color(0.058, 0.061, 0.063), Color(0.19, 0.24, 0.23)))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(column)

	var header_margin := MarginContainer.new()
	header_margin.custom_minimum_size = Vector2(0, 34)
	header_margin.add_theme_constant_override("margin_left", 10)
	header_margin.add_theme_constant_override("margin_right", 8)
	column.add_child(header_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header_margin.add_child(header)

	var tabs := [
		["Scene", true, 44],
		["Map", false, 34],
		["Global 0 pts", false, 76],
		["Local 0 pts", false, 68],
		["Scan 0 rays", false, 72],
		["TF 0 frames", false, 72],
	]
	for tab in tabs:
		header.add_child(_scene_tab(tab[0], tab[1], tab[2]))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	header.add_child(_scene_tool_button("Aim", func() -> void:
		if scene_viewport != null and scene_viewport.has_method("set_camera_mode"):
			scene_viewport.set_camera_mode("aim")
	))
	header.add_child(_scene_tool_button("View", func() -> void:
		if scene_viewport != null and scene_viewport.has_method("set_camera_mode"):
			scene_viewport.set_camera_mode("first_person")
	))
	header.add_child(_scene_tool_button("Reset", func() -> void:
		if scene_viewport != null and scene_viewport.has_method("reset_view_modes"):
			scene_viewport.reset_view_modes()
		if operations_panel != null and operations_panel.has_method("set_placing_enabled"):
			operations_panel.set_placing_enabled(false)
	))

	scene_viewport = SceneViewportScene.instantiate()
	scene_viewport.waypoint_placed.connect(_on_waypoint_placed)
	column.add_child(scene_viewport)
	scene_viewport.call_deferred("set_camera_mode", "aim")
	return shell


func _on_control_mode_changed(mode: String) -> void:
	var ai_enabled := mode == "ai"
	operations_panel.visible = not ai_enabled
	ai_mission_panel.visible = ai_enabled
	telemetry_panel.visible = not ai_enabled
	if ai_enabled:
		ai_mission_panel.custom_minimum_size = Vector2(800, 0)
		scene_shell.custom_minimum_size = Vector2(520, 0)
	else:
		scene_shell.custom_minimum_size = Vector2(0, 0)


func _on_connect_requested(broker_url: String, robot_id: String) -> void:
	active_robot_id = robot_id.strip_edges()
	if active_robot_id.is_empty():
		active_robot_id = "burger1"
	telemetry_router.fallback_robot_id = active_robot_id
	SessionRegistry.set_active_robot(active_robot_id)

	transport.broker_url = broker_url.strip_edges()
	AppState.set_connection_state("Connecting")
	AppState.push_event("Connecting: %s [%s]" % [transport.broker_url, active_robot_id])
	transport.connect_transport()


func _on_disconnect_requested() -> void:
	transport.disconnect_transport()


func _on_navigation_requested(goals: Array) -> void:
	CommandBus.request_navigation(goals)


func _on_cancel_requested() -> void:
	CommandBus.request_cancel()


func _on_clear_requested() -> void:
	if scene_viewport != null and scene_viewport.has_method("clear_waypoints"):
		scene_viewport.clear_waypoints()
	AppState.push_event("Waypoint list cleared")


func _on_initial_pose_requested(position: Vector3, yaw: float) -> void:
	CommandBus.request_initial_pose(position, yaw)


func _on_waypoint_placing_toggled(enabled: bool) -> void:
	if scene_viewport != null and scene_viewport.has_method("set_waypoint_placement_enabled"):
		scene_viewport.set_waypoint_placement_enabled(enabled)
	AppState.push_event("Waypoint placing " + ("enabled" if enabled else "disabled"))


func _on_waypoint_placed(world_position: Vector3, yaw: float) -> void:
	if operations_panel != null and operations_panel.has_method("add_waypoint"):
		operations_panel.add_waypoint(Vector3(world_position.x, 0.0, -world_position.z), yaw)


func _on_layer_visibility_changed(layer_id: String, enabled: bool) -> void:
	if scene_viewport != null and scene_viewport.has_method("set_visualization_layer_visible"):
		scene_viewport.set_visualization_layer_visible(layer_id, enabled)


func _on_ai_prompt_submitted(message: String, submission: Dictionary) -> void:
	var parsed_value: Variant = submission.get("parsed_command", {})
	if typeof(parsed_value) == TYPE_DICTIONARY:
		var parsed_command: Dictionary = parsed_value
		if str(parsed_command.get("kind", "")) == "navigation_pose" and ai_mission_panel != null and ai_mission_panel.has_method("begin_navigation_session"):
			var robot_id := str(parsed_command.get("robot_id", active_robot_id)).strip_edges()
			if robot_id.is_empty():
				robot_id = active_robot_id
			ai_mission_panel.begin_navigation_session(robot_id, str(submission.get("request_id", "")).strip_edges())

	var target := str(submission.get("target", "MCP_SERVER")).strip_edges()
	if target.is_empty():
		target = "MCP_SERVER"
	var provider := str(submission.get("provider_label", "")).strip_edges()
	var summary := _summarize_prompt(message)
	if provider.is_empty():
		AppState.push_event("AI prompt sent to %s over WebSocket: %s" % [target, summary])
	else:
		AppState.push_event("AI prompt sent to %s via %s: %s" % [target, provider, summary])


func _on_transport_connected() -> void:
	AppState.set_connection_state("Connected")
	AppState.push_event("MQTT connected")
	var topics: PackedStringArray = TopicCatalogScript.build_all_runtime_subscriptions(active_robot_id)
	transport.subscribe(topics)
	CommandBus.request_system_ping()
	if ping_timer != null:
		ping_timer.start()


func _on_transport_disconnected(reason: String) -> void:
	AppState.set_connection_state("Disconnected")
	AppState.push_event("MQTT disconnected: " + reason)
	if ping_timer != null:
		ping_timer.stop()


func _on_ping_timer_timeout() -> void:
	CommandBus.request_system_ping()


func _on_transport_subscribed(topic_count: int) -> void:
	AppState.push_event("Subscribed topic filters: %d" % topic_count)


func _on_topic_settings_changed(group: String) -> void:
	if group != "viz" or transport == null or not transport.connected_state:
		return
	var topics: PackedStringArray = TopicCatalogScript.build_all_runtime_subscriptions(active_robot_id)
	transport.subscribe(topics)


func _on_mqtt_message_received(topic: String, payload: Variant) -> void:
	telemetry_router.route(topic, payload)


func _on_telemetry_patch(robot_id: String, patch: Dictionary) -> void:
	SessionRegistry.apply_telemetry_patch(robot_id, patch)
	if patch.has("navigation_feedback") and ai_mission_panel != null and ai_mission_panel.has_method("note_navigation_feedback"):
		var feedback_value: Variant = patch.get("navigation_feedback", {})
		if typeof(feedback_value) == TYPE_DICTIONARY:
			ai_mission_panel.note_navigation_feedback(robot_id, feedback_value as Dictionary)
	if patch.has("urdf_model"):
		_push_urdf_event(robot_id, patch["urdf_model"])
	_record_telemetry_log(robot_id, patch)


func _on_control_event(robot_id: String, domain: String, channel: String, payload: Variant) -> void:
	var patch := _control_patch_for(domain, channel, payload)
	if not patch.is_empty():
		SessionRegistry.apply_telemetry_patch(robot_id, patch)

	var label := "%s/%s" % [domain, channel]
	if typeof(payload) == TYPE_DICTIONARY:
		var data: Dictionary = payload
		if ai_mission_panel != null:
			if domain == "navigation" and channel == "status" and ai_mission_panel.has_method("add_navigation_status_event"):
				ai_mission_panel.add_navigation_status_event(robot_id, data)
			elif domain == "navigation" and channel == "result" and ai_mission_panel.has_method("add_navigation_result_event"):
				ai_mission_panel.add_navigation_result_event(robot_id, data)
		if domain == "navigation" and channel == "result":
			_handle_navigation_result_completion(robot_id, data)
		var message := str(data.get("message", ""))
		var request_id := str(data.get("request_id", ""))
		var success_text := ""
		if data.has("success"):
			success_text = " success=%s" % str(data.get("success"))
		if not message.is_empty():
			AppState.push_event("[%s] %s%s %s" % [robot_id, label, success_text, message])
		elif not request_id.is_empty():
			AppState.push_event("[%s] %s%s request=%s" % [robot_id, label, success_text, request_id])
		else:
			AppState.push_event("[%s] %s" % [robot_id, label])
		return
	AppState.push_event("[%s] %s" % [robot_id, label])


func _handle_navigation_result_completion(robot_id: String, payload: Dictionary) -> void:
	if not bool(payload.get("completed", false)) or not bool(payload.get("success", false)):
		return
	var queued_goals := 0
	if operations_panel != null and operations_panel.has_method("waypoint_count"):
		queued_goals = int(operations_panel.waypoint_count())
	if queued_goals <= 0:
		return
	var completed_goals := int(payload.get("completed_goals", 0))
	if completed_goals <= 0 and queued_goals == 1:
		completed_goals = 1
	if completed_goals < queued_goals:
		return
	if scene_viewport != null and scene_viewport.has_method("clear_waypoints"):
		scene_viewport.clear_waypoints()
	if operations_panel != null and operations_panel.has_method("clear_waypoints"):
		operations_panel.clear_waypoints()
	AppState.push_event("[%s] route completed; cleared %d waypoint(s)" % [robot_id, queued_goals])


func _control_patch_for(domain: String, channel: String, payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = payload
	match "%s/%s" % [domain, channel]:
		"navigation/feedback":
			return {"navigation_feedback": data}
		"navigation/status":
			return {"navigation_status": data}
		"navigation/result":
			return {"navigation_result": data}
		"pose/result":
			return {"pose_result": data}
		"map/result":
			return {"map_result": data}
		"segment/response":
			return {"segment_response": data}
		"route/response":
			return {"route_response": data}
		"system/result":
			return {"system_result": data}
		_:
			return {}


func _on_command_requested(command: Dictionary) -> void:
	var robot_id := str(command.get("target_robot_id", active_robot_id))
	var command_key := str(command.get("command_key", ""))
	if command_key.is_empty():
		AppState.push_event("Command has no MQTT topic yet")
		return

	var topic: String = TopicCatalogScript.command_topic(command_key, robot_id)
	if topic.is_empty():
		AppState.push_event("Command topic missing: " + command_key)
		return
	transport.publish(topic, command.get("payload", {}))
	AppState.push_event("Published command: %s -> %s" % [command.get("channel", command_key), topic])


func _on_publish_failed(topic: String, reason: String) -> void:
	AppState.push_event("Publish failed [%s]: %s" % [topic, reason])


func _format_patch_keys(patch: Dictionary) -> String:
	var labels := []
	for key in patch.keys():
		labels.append(str(key))
	return ", ".join(labels)


func _record_telemetry_log(robot_id: String, patch: Dictionary) -> void:
	for key in patch.keys():
		var log_key := "%s:%s" % [robot_id, key]
		telemetry_log_counts[log_key] = int(telemetry_log_counts.get(log_key, 0)) + 1

	var now := Time.get_ticks_msec()
	if now - last_telemetry_log_msec < 1000:
		return
	last_telemetry_log_msec = now

	var labels := []
	for log_key in telemetry_log_counts.keys():
		labels.append("%s x%d" % [log_key, telemetry_log_counts[log_key]])
	telemetry_log_counts.clear()
	if labels.is_empty():
		return
	AppState.push_event("Telemetry batch: " + ", ".join(labels))


func _summarize_prompt(message: String, max_length := 88) -> String:
	var clean := message.strip_edges().replace("\n", " ")
	if clean.length() <= max_length:
		return clean
	return clean.substr(0, max_length - 3) + "..."


func _push_urdf_event(robot_id: String, urdf_model: Variant) -> void:
	if typeof(urdf_model) != TYPE_DICTIONARY:
		return
	var model: Dictionary = urdf_model
	var parse_error := str(model.get("parse_error", ""))
	if not parse_error.is_empty():
		AppState.push_event("[%s] URDF parse failed: %s" % [robot_id, parse_error])
		return
	var link_count := (model.get("link_order", []) as Array).size()
	var joint_count := (model.get("joint_order", []) as Array).size()
	AppState.push_event("[%s] URDF loaded: %s (%d links, %d joints)" % [
		robot_id,
		model.get("name", "robot"),
		link_count,
		joint_count,
	])


func _scene_tab(text: String, active: bool, min_width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 32)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.96) if active else Color(0.56, 0.62, 0.64))
	label.add_theme_font_size_override("font_size", 11)
	return label


func _scene_tool_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.custom_minimum_size = Vector2(48, 32)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", Color(0.67, 0.74, 0.76))
	button.add_theme_color_override("font_hover_color", Color(0.93, 0.96, 0.97))
	button.add_theme_color_override("font_pressed_color", Color(0.95, 0.74, 0.29))
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _tool_button_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", _tool_button_style(Color(0.07, 0.09, 0.12), Color(0.18, 0.22, 0.28)))
	button.add_theme_stylebox_override("pressed", _tool_button_style(Color(0.09, 0.11, 0.14), Color(0.28, 0.34, 0.42)))
	button.pressed.connect(callback)
	return button


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	return style


func _tool_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style
