extends Control

const TopbarScene := preload("res://src/ui/components/topbar.tscn")
const OperationsPanelScene := preload("res://src/ui/panels/operations_panel.tscn")
const TelemetryPanelScene := preload("res://src/ui/panels/telemetry_panel.tscn")
const SceneViewportScene := preload("res://src/scene/scene_viewport.tscn")
const RcsMqttTransportScript := preload("res://src/domain/transport/mqtt_transport.gd")
const RcsTelemetryRouterScript := preload("res://src/domain/telemetry/telemetry_router.gd")
const TopicCatalogScript := preload("res://src/domain/protocol/topic_catalog.gd")

var transport: Node
var telemetry_router: RefCounted
var active_robot_id := "burger1"
var telemetry_log_counts: Dictionary = {}
var last_telemetry_log_msec := 0


func _ready() -> void:
	_build_runtime()
	_build_layout()


func _build_runtime() -> void:
	transport = RcsMqttTransportScript.new()
	transport.disconnected.connect(_on_transport_disconnected)
	transport.connected.connect(_on_transport_connected)
	transport.subscribed.connect(_on_transport_subscribed)
	transport.message_received.connect(_on_mqtt_message_received)
	transport.publish_failed.connect(_on_publish_failed)
	add_child(transport)

	telemetry_router = RcsTelemetryRouterScript.new()
	telemetry_router.fallback_robot_id = active_robot_id
	telemetry_router.telemetry_patch.connect(_on_telemetry_patch)
	CommandBus.command_requested.connect(_on_command_requested)


func _build_layout() -> void:
	var root := HBoxContainer.new()
	root.name = "Workspace"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var operations_panel := OperationsPanelScene.instantiate()
	operations_panel.connect_requested.connect(_on_connect_requested)
	operations_panel.disconnect_requested.connect(_on_disconnect_requested)
	operations_panel.goal_requested.connect(_on_goal_requested)
	operations_panel.cancel_requested.connect(_on_cancel_requested)
	operations_panel.reset_world_requested.connect(_on_reset_world_requested)
	root.add_child(operations_panel)

	var center := VBoxContainer.new()
	center.name = "CenterColumn"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)

	center.add_child(TopbarScene.instantiate())
	center.add_child(SceneViewportScene.instantiate())

	root.add_child(TelemetryPanelScene.instantiate())


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


func _on_goal_requested() -> void:
	CommandBus.request_goal(Vector3.ZERO, 0.0)


func _on_cancel_requested() -> void:
	CommandBus.request_cancel()


func _on_reset_world_requested() -> void:
	CommandBus.request_reset_world()


func _on_transport_connected() -> void:
	AppState.set_connection_state("Connected")
	AppState.push_event("MQTT connected")
	var topics: PackedStringArray = TopicCatalogScript.build_all_runtime_subscriptions(active_robot_id)
	transport.subscribe(topics)


func _on_transport_disconnected(reason: String) -> void:
	AppState.set_connection_state("Disconnected")
	AppState.push_event("MQTT disconnected: " + reason)


func _on_transport_subscribed(topic_count: int) -> void:
	AppState.push_event("Subscribed topic filters: %d" % topic_count)


func _on_mqtt_message_received(topic: String, payload: Variant) -> void:
	telemetry_router.route(topic, payload)


func _on_telemetry_patch(robot_id: String, patch: Dictionary) -> void:
	SessionRegistry.apply_telemetry_patch(robot_id, patch)
	if patch.has("urdf_model"):
		_push_urdf_event(robot_id, patch["urdf_model"])
	_record_telemetry_log(robot_id, patch)


func _on_command_requested(command: Dictionary) -> void:
	var robot_id := str(command.get("target_robot_id", active_robot_id))
	var command_key := _command_key_for_kind(str(command.get("kind", "")))
	if command_key.is_empty():
		AppState.push_event("Command has no MQTT topic yet: " + str(command.get("kind", "")))
		return

	var topic: String = TopicCatalogScript.command_topic(command_key, robot_id)
	if topic.is_empty():
		AppState.push_event("Command topic missing: " + command_key)
		return
	transport.publish(topic, command)
	AppState.push_event("Published command: %s -> %s" % [command.get("kind", ""), topic])


func _on_publish_failed(topic: String, reason: String) -> void:
	AppState.push_event("Publish failed [%s]: %s" % [topic, reason])


func _command_key_for_kind(kind: String) -> String:
	match kind:
		"navigate_to_pose":
			return "navigation_command"
		"cancel_navigate":
			return "navigation_cancel"
		"set_initial_pose":
			return "pose_set"
		"motion_command":
			return "motion_command"
		_:
			return ""


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
