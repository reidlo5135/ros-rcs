extends RefCounted
class_name RcsTelemetryRouter

signal telemetry_patch(robot_id: String, patch: Dictionary)

const UrdfParserScript := preload("res://src/domain/robot_model/urdf_parser.gd")

var fallback_robot_id := "burger1"


func route(topic: String, payload: Variant) -> void:
	var robot_id := _extract_robot_id(topic)
	if robot_id.is_empty():
		return

	var semantic_key := _semantic_key(topic)
	var patch := {}
	match semantic_key:
		"map":
			patch["map"] = payload
		"global_costmap":
			patch["global_costmap"] = payload
		"local_costmap":
			patch["local_costmap"] = payload
		"robot_pose":
			patch["robot_pose"] = payload
		"global_path":
			patch["global_path"] = payload
		"local_path":
			patch["local_path"] = payload
		"motion_status":
			patch["motion_status"] = payload
		"scan":
			patch["scan"] = payload
		"battery_state":
			patch["battery_state"] = payload
		"tf":
			patch["tf"] = payload
		"tf_static":
			patch["tf_static"] = payload
		"robot_description":
			var robot_description := _robot_description_text(payload)
			patch["robot_description"] = robot_description
			if not robot_description.is_empty():
				patch["urdf_model"] = UrdfParserScript.parse(robot_description)
		_:
			return

	telemetry_patch.emit(robot_id, patch)


func _extract_robot_id(topic: String) -> String:
	var parts := topic.split("/", false)
	var index := parts.find("amr")
	if index < 0 or parts.size() <= index + 1:
		return fallback_robot_id
	return parts[index + 1]


func _semantic_key(topic: String) -> String:
	var parts := topic.split("/", false)
	for topic_group in ["viz", "telemetry"]:
		var namespace_index := parts.find(topic_group)
		if namespace_index >= 0 and parts.size() > namespace_index + 1:
			return parts[namespace_index + 1]
	if parts.is_empty():
		var stripped := topic.strip_edges()
		return stripped.substr(1) if stripped.begins_with("/") else stripped
	return parts[parts.size() - 1]


func _robot_description_text(payload: Variant) -> String:
	if typeof(payload) == TYPE_STRING:
		return payload
	if typeof(payload) == TYPE_DICTIONARY:
		for key in ["robot_description", "description", "xml", "data", "msg", "value"]:
			if payload.has(key):
				return str(payload[key])
	return str(payload)
