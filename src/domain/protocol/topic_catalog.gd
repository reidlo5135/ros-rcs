extends RefCounted
class_name RcsTopicCatalog

const ROBOT_ID_TOKEN := "{robot_id}"

const VIZ_TOPICS := {
	"map": "/amr/{robot_id}/viz/map",
	"global_costmap": "/amr/{robot_id}/viz/global_costmap",
	"local_costmap": "/amr/{robot_id}/viz/local_costmap",
	"robot_pose": "/amr/{robot_id}/viz/robot_pose",
	"global_path": "/amr/{robot_id}/viz/global_path",
	"local_path": "/amr/{robot_id}/viz/local_path",
	"motion_status": "/amr/{robot_id}/viz/motion_status",
	"scan": "/amr/{robot_id}/viz/scan",
	"battery_state": "/amr/{robot_id}/viz/battery_state",
	"tf": "/amr/{robot_id}/viz/tf",
	"tf_static": "/amr/{robot_id}/viz/tf_static",
	"robot_description": "/amr/{robot_id}/viz/robot_description",
}

const COMMAND_TOPICS := {
	"navigation_command": "/amr/{robot_id}/navigation/command",
	"navigation_cancel": "/amr/{robot_id}/navigation/cancel",
	"pose_set": "/amr/{robot_id}/pose/set",
	"map_save": "/amr/{robot_id}/map/save",
	"motion_command": "/amr/{robot_id}/motion/command",
	"segment_request": "/amr/{robot_id}/segment/request",
	"route_request": "/amr/{robot_id}/route/request",
	"system_ping": "/amr/{robot_id}/system/ping",
	"system_robot": "/amr/{robot_id}/system/robot",
}

const VIZ_TOPIC_ORDER := [
	"map",
	"global_costmap",
	"local_costmap",
	"robot_pose",
	"global_path",
	"local_path",
	"motion_status",
	"scan",
	"battery_state",
	"tf",
	"tf_static",
	"robot_description",
]

const COMMAND_TOPIC_ORDER := [
	"navigation_command",
	"navigation_cancel",
	"pose_set",
	"map_save",
	"motion_command",
	"segment_request",
	"route_request",
	"system_ping",
	"system_robot",
]

const VIZ_TOPIC_LABELS := {
	"map": "Map",
	"global_costmap": "Global Costmap",
	"local_costmap": "Local Costmap",
	"robot_pose": "Robot Pose",
	"global_path": "Global Plan",
	"local_path": "Local Plan",
	"motion_status": "Motion Status",
	"scan": "LaserScan",
	"battery_state": "Battery State",
	"tf": "TF",
	"tf_static": "TF Static",
	"robot_description": "Robot Description",
}

const COMMAND_TOPIC_LABELS := {
	"navigation_command": "Navigation Command",
	"navigation_cancel": "Navigation Cancel",
	"pose_set": "Set Initial Pose",
	"map_save": "Map Save",
	"motion_command": "Motion Command",
	"segment_request": "Segment Request",
	"route_request": "Route Request",
	"system_ping": "System Ping",
	"system_robot": "System Robot",
}


static func resolve(template: String, robot_id: String) -> String:
	var clean_id := robot_id.strip_edges()
	if clean_id.is_empty():
		clean_id = "burger1"
	return template.replace(ROBOT_ID_TOKEN, clean_id)


static func normalize(topic: String) -> String:
	var trimmed := topic.strip_edges()
	if trimmed.begins_with("amr/"):
		return "/" + trimmed
	return trimmed


static func build_viz_subscriptions(robot_id: String) -> PackedStringArray:
	var topics := PackedStringArray()
	var seen := {}
	var clean_id := robot_id.strip_edges()
	if clean_id.is_empty():
		clean_id = "burger1"

	_add_unique(topics, seen, "/amr/%s/telemetry/#" % clean_id)
	_add_unique(topics, seen, "amr/%s/telemetry/#" % clean_id)
	_add_unique(topics, seen, "/amr/%s/viz/#" % clean_id)
	_add_unique(topics, seen, "amr/%s/viz/#" % clean_id)
	_add_unique(topics, seen, "/amr/%s/#" % clean_id)
	_add_unique(topics, seen, "amr/%s/#" % clean_id)
	_add_unique(topics, seen, "/map")
	_add_unique(topics, seen, "map")
	_add_unique(topics, seen, "/robot_description")
	_add_unique(topics, seen, "robot_description")
	for template in viz_topics().values():
		_add_topic_variants(topics, seen, resolve(template, clean_id))

	return topics


static func build_result_subscriptions(robot_id: String) -> PackedStringArray:
	var topics := PackedStringArray()
	var seen := {}
	var clean_id := robot_id.strip_edges()
	if clean_id.is_empty():
		clean_id = "burger1"

	for suffix in [
		"navigation/feedback",
		"navigation/status",
		"navigation/result",
		"pose/result",
		"map/result",
		"segment/response",
		"route/response",
		"system/result",
	]:
		_add_topic_variants(topics, seen, "/amr/%s/%s" % [clean_id, suffix])

	return topics


static func build_all_runtime_subscriptions(robot_id: String) -> PackedStringArray:
	var topics := PackedStringArray()
	var seen := {}
	for topic in build_viz_subscriptions(robot_id):
		_add_unique(topics, seen, topic)
	for topic in build_result_subscriptions(robot_id):
		_add_unique(topics, seen, topic)
	return topics


static func build_all_runtime_subscriptions_for_robot_ids(robot_ids: Array) -> PackedStringArray:
	var topics := PackedStringArray()
	var seen := {}
	for robot_id_value in robot_ids:
		var robot_id := str(robot_id_value).strip_edges()
		if robot_id.is_empty():
			continue
		for topic in build_all_runtime_subscriptions(robot_id):
			_add_unique(topics, seen, topic)
	if topics.is_empty():
		for topic in build_all_runtime_subscriptions("burger1"):
			_add_unique(topics, seen, topic)
	return topics


static func command_topic(command_key: String, robot_id: String) -> String:
	var topics := command_topics()
	if not topics.has(command_key):
		return ""
	return resolve(topics[command_key], robot_id)


static func command_topics() -> Dictionary:
	return _merged_topic_map("command", COMMAND_TOPICS)


static func viz_topics() -> Dictionary:
	return _merged_topic_map("viz", VIZ_TOPICS)


static func topic_entries(group: String) -> Array:
	var source := command_topics() if group == "command" else viz_topics()
	var labels := COMMAND_TOPIC_LABELS if group == "command" else VIZ_TOPIC_LABELS
	var order := COMMAND_TOPIC_ORDER if group == "command" else VIZ_TOPIC_ORDER
	var entries := []
	for key in order:
		if not source.has(key):
			continue
		entries.append({
			"key": key,
			"label": labels.get(key, key),
			"value": source[key],
		})
	return entries


static func semantic_key_for_viz_topic(topic: String, robot_id: String) -> String:
	var normalized := normalize(topic)
	for key in VIZ_TOPIC_ORDER:
		var template := str(viz_topics().get(key, ""))
		if template.is_empty():
			continue
		var resolved := normalize(resolve(template, robot_id))
		if normalized == resolved:
			return key
	return ""


static func _merged_topic_map(group: String, defaults: Dictionary) -> Dictionary:
	var merged := defaults.duplicate(true)
	for key in defaults.keys():
		merged[key] = AppState.topic_template(group, key, defaults[key])
	return merged


static func _add_topic_variants(target: PackedStringArray, seen: Dictionary, topic: String) -> void:
	var normalized := normalize(topic)
	_add_unique(target, seen, normalized)
	if normalized.begins_with("/"):
		_add_unique(target, seen, normalized.substr(1))
	else:
		_add_unique(target, seen, "/" + normalized)


static func _add_unique(target: PackedStringArray, seen: Dictionary, topic: String) -> void:
	if seen.has(topic):
		return
	seen[topic] = true
	target.append(topic)
