#include "rcs_core/protocol_codec.hpp"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

void RcsProtocolCodec::_bind_methods() {
	ClassDB::bind_method(D_METHOD("normalize_topic", "topic"), &RcsProtocolCodec::normalize_topic);
	ClassDB::bind_method(D_METHOD("resolve_robot_topic", "topic_template", "robot_id"), &RcsProtocolCodec::resolve_robot_topic);
	ClassDB::bind_method(D_METHOD("command_topic", "robot_id", "command_key"), &RcsProtocolCodec::command_topic);
	ClassDB::bind_method(D_METHOD("build_command", "robot_id", "kind", "payload"), &RcsProtocolCodec::build_command);
}

String RcsProtocolCodec::normalize_topic(const String &p_topic) const {
	String topic = p_topic.strip_edges();
	if (topic.begins_with("amr/")) {
		return "/" + topic;
	}
	return topic;
}

String RcsProtocolCodec::resolve_robot_topic(const String &p_template, const String &p_robot_id) const {
	String robot_id = p_robot_id.strip_edges();
	if (robot_id.is_empty()) {
		robot_id = "burger1";
	}
	String resolved = p_template;
	return normalize_topic(resolved.replace("{robot_id}", robot_id));
}

String RcsProtocolCodec::command_topic(const String &p_robot_id, const String &p_command_key) const {
	if (p_command_key == "navigation_command") {
		return resolve_robot_topic("/amr/{robot_id}/navigation/command", p_robot_id);
	}
	if (p_command_key == "navigation_cancel") {
		return resolve_robot_topic("/amr/{robot_id}/navigation/cancel", p_robot_id);
	}
	if (p_command_key == "pose_set") {
		return resolve_robot_topic("/amr/{robot_id}/pose/set", p_robot_id);
	}
	if (p_command_key == "motion_command") {
		return resolve_robot_topic("/amr/{robot_id}/motion/command", p_robot_id);
	}
	if (p_command_key == "system_ping") {
		return resolve_robot_topic("/amr/{robot_id}/system/ping", p_robot_id);
	}
	return String();
}

Dictionary RcsProtocolCodec::build_command(const String &p_robot_id, const String &p_kind, const Dictionary &p_payload) const {
	String robot_id = p_robot_id.strip_edges();
	if (robot_id.is_empty()) {
		robot_id = "burger1";
	}

	Dictionary command;
	command["request_id"] = "rcs-native-" + String::num_int64(Time::get_singleton()->get_ticks_msec());
	command["schema_version"] = 1;
	command["kind"] = p_kind;
	command["target_robot_id"] = robot_id;
	command["payload"] = p_payload;
	command["source"] = "operator";
	return command;
}

} // namespace godot
