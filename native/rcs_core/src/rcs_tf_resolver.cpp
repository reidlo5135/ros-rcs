#include "rcs_core/rcs_tf_resolver.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

namespace godot {

void RcsTfResolver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("clear"), &RcsTfResolver::clear);
	ClassDB::bind_method(D_METHOD("merge_static", "tf_static"), &RcsTfResolver::merge_static);
	ClassDB::bind_method(D_METHOD("merge_live", "tf"), &RcsTfResolver::merge_live);
	ClassDB::bind_method(D_METHOD("resolve", "robot_pose", "max_frames"), &RcsTfResolver::resolve);
}

void RcsTfResolver::clear() {
	static_edges.clear();
	live_edges.clear();
}

void RcsTfResolver::merge_static(const Variant &p_tf_static) {
	merge_edges(static_edges, p_tf_static);
}

void RcsTfResolver::merge_live(const Variant &p_tf) {
	merge_edges(live_edges, p_tf);
}

Dictionary RcsTfResolver::resolve(const Variant &p_robot_pose, int32_t p_max_frames) const {
	Dictionary edges = static_edges.duplicate(true);
	Array live_keys = live_edges.keys();
	for (int64_t i = 0; i < live_keys.size(); i++) {
		edges[live_keys[i]] = live_edges[live_keys[i]];
	}

	Dictionary cache;
	cache["map"] = Transform3D();
	Array edge_keys = edges.keys();
	for (int64_t i = 0; i < edge_keys.size(); i++) {
		Dictionary edge = edges[edge_keys[i]];
		const String parent = normalize_frame_id(String(edge.get("parent", "")));
		if (!parent.is_empty() && !edges.has(parent) && !cache.has(parent)) {
			cache[parent] = Transform3D();
		}
	}

	Dictionary frames;
	for (int64_t i = 0; i < edge_keys.size() && frames.size() < p_max_frames; i++) {
		const String frame_id = String(edge_keys[i]);
		Variant resolved = resolve_frame(frame_id, edges, cache, 0, p_max_frames);
		if (resolved.get_type() == Variant::TRANSFORM3D) {
			frames[frame_id] = resolved;
		}
	}

	for (const String &root_frame : { String("map"), String("odom"), String("base_footprint"), String("base_link") }) {
		if (cache.has(root_frame) && !frames.has(root_frame)) {
			frames[root_frame] = cache[root_frame];
		}
	}

	bool valid_pose = false;
	Transform3D pose_transform = transform_from_robot_pose(p_robot_pose, valid_pose);
	if (valid_pose) {
		if (!frames.has("base_link")) {
			frames["base_link"] = pose_transform;
		}
		if (!frames.has("base_footprint")) {
			frames["base_footprint"] = pose_transform;
		}
	}

	return frames;
}

void RcsTfResolver::merge_edges(Dictionary &p_store, const Variant &p_message) {
	if (p_message.get_type() != Variant::DICTIONARY) {
		return;
	}
	Dictionary message = p_message;
	if (!message.has("transforms") || Variant(message["transforms"]).get_type() != Variant::ARRAY) {
		return;
	}

	Array transforms = message["transforms"];
	for (int64_t i = 0; i < transforms.size(); i++) {
		if (transforms[i].get_type() != Variant::DICTIONARY) {
			continue;
		}
		Dictionary transform = transforms[i];
		const String parent = parent_frame_id(transform);
		const String child = child_frame_id(transform);
		if (parent.is_empty() || child.is_empty()) {
			continue;
		}
		Dictionary edge;
		edge["parent"] = parent;
		edge["transform"] = transform_from_tf(transform);
		p_store[child] = edge;
	}
}

String RcsTfResolver::parent_frame_id(const Dictionary &p_transform) const {
	if (p_transform.has("header") && Variant(p_transform["header"]).get_type() == Variant::DICTIONARY) {
		Dictionary header = p_transform["header"];
		const String frame = normalize_frame_id(String(header.get("frame_id", "")));
		if (!frame.is_empty()) {
			return frame;
		}
	}
	for (const String &key : { String("parent_frame_id"), String("parent_frame"), String("parent"), String("frame_id"), String("frame") }) {
		const String frame = normalize_frame_id(String(p_transform.get(key, "")));
		if (!frame.is_empty()) {
			return frame;
		}
	}
	return String();
}

String RcsTfResolver::child_frame_id(const Dictionary &p_transform) const {
	for (const String &key : { String("child_frame_id"), String("child_frame"), String("child") }) {
		const String frame = normalize_frame_id(String(p_transform.get(key, "")));
		if (!frame.is_empty()) {
			return frame;
		}
	}
	return String();
}

String RcsTfResolver::normalize_frame_id(const String &p_value) const {
	String clean = p_value.strip_edges();
	return clean.begins_with("/") ? clean.substr(1) : clean;
}

Transform3D RcsTfResolver::transform_from_tf(const Dictionary &p_transform) const {
	Dictionary source = p_transform;
	if (p_transform.has("transform") && Variant(p_transform["transform"]).get_type() == Variant::DICTIONARY) {
		source = p_transform["transform"];
	}
	Dictionary translation;
	if (source.has("translation") && Variant(source["translation"]).get_type() == Variant::DICTIONARY) {
		translation = source["translation"];
	}
	Dictionary rotation;
	if (source.has("rotation") && Variant(source["rotation"]).get_type() == Variant::DICTIONARY) {
		rotation = source["rotation"];
	}

	const double x = double(translation.get("x", 0.0));
	const double y = double(translation.get("y", 0.0));
	const double z = double(translation.get("z", 0.0));
	const double yaw = double(rotation.get("yaw", 0.0));
	return Transform3D(Basis::from_euler(Vector3(0.0, yaw, 0.0)), Vector3(x, z, -y));
}

Transform3D RcsTfResolver::transform_from_robot_pose(const Variant &p_robot_pose, bool &r_valid) const {
	r_valid = false;
	if (p_robot_pose.get_type() != Variant::DICTIONARY) {
		return Transform3D();
	}
	Dictionary pose = p_robot_pose;
	if (pose.is_empty()) {
		return Transform3D();
	}
	if (pose.has("x") || pose.has("y")) {
		const double yaw = double(pose.get("yaw", pose.get("theta", 0.0)));
		r_valid = true;
		return Transform3D(
			Basis::from_euler(Vector3(0.0, yaw, 0.0)),
			Vector3(double(pose.get("x", 0.0)), 0.0, -double(pose.get("y", 0.0)))
		);
	}
	return Transform3D();
}

Variant RcsTfResolver::resolve_frame(const String &p_frame_id, const Dictionary &p_edges, Dictionary &p_cache, int32_t p_depth, int32_t p_max_depth) const {
	const String clean = normalize_frame_id(p_frame_id);
	if (clean.is_empty() || p_depth > p_max_depth) {
		return Variant();
	}
	if (p_cache.has(clean)) {
		return p_cache[clean];
	}
	if (!p_edges.has(clean) || Variant(p_edges[clean]).get_type() != Variant::DICTIONARY) {
		return Variant();
	}

	Dictionary edge = p_edges[clean];
	const String parent = normalize_frame_id(String(edge.get("parent", "")));
	Variant parent_transform = resolve_frame(parent, p_edges, p_cache, p_depth + 1, p_max_depth);
	if (parent_transform.get_type() != Variant::TRANSFORM3D) {
		return Variant();
	}

	Transform3D local_transform;
	if (edge.has("transform") && Variant(edge["transform"]).get_type() == Variant::TRANSFORM3D) {
		local_transform = edge["transform"];
	}
	Transform3D resolved = Transform3D(parent_transform) * local_transform;
	p_cache[clean] = resolved;
	return resolved;
}

} // namespace godot
