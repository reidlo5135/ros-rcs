#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class RcsTfResolver : public RefCounted {
	GDCLASS(RcsTfResolver, RefCounted)

	Dictionary static_edges;
	Dictionary live_edges;

protected:
	static void _bind_methods();

public:
	void clear();
	void merge_static(const Variant &p_tf_static);
	void merge_live(const Variant &p_tf);
	Dictionary resolve(const Variant &p_robot_pose, int32_t p_max_frames) const;

private:
	void merge_edges(Dictionary &p_store, const Variant &p_message);
	String parent_frame_id(const Dictionary &p_transform) const;
	String child_frame_id(const Dictionary &p_transform) const;
	String normalize_frame_id(const String &p_value) const;
	Transform3D transform_from_tf(const Dictionary &p_transform) const;
	Transform3D transform_from_robot_pose(const Variant &p_robot_pose, bool &r_valid) const;
	Variant resolve_frame(const String &p_frame_id, const Dictionary &p_edges, Dictionary &p_cache, int32_t p_depth, int32_t p_max_depth) const;
};

} // namespace godot
