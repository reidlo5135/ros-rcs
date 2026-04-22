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
	for template in VIZ_TOPICS.values():
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


static func command_topic(command_key: String, robot_id: String) -> String:
	if not COMMAND_TOPICS.has(command_key):
		return ""
	return resolve(COMMAND_TOPICS[command_key], robot_id)


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
