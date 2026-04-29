#include "rcs_core/path_projector.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

void RcsPathProjector::_bind_methods() {
	ClassDB::bind_method(D_METHOD("project", "path_message", "frame_transform"), &RcsPathProjector::project);
}

PackedVector3Array RcsPathProjector::project(const Dictionary &p_path_message, const Transform3D &p_frame_transform) const {
	PackedVector3Array points;
	if (!p_path_message.has("poses")) {
		return points;
	}

	const Array poses = p_path_message["poses"];
	for (int64_t index = 0; index < poses.size(); index++) {
		if (poses[index].get_type() != Variant::DICTIONARY) {
			continue;
		}
		Dictionary wrapper = poses[index];
		Variant nested_pose_value = wrapper.get("pose", wrapper);
		if (nested_pose_value.get_type() == Variant::DICTIONARY) {
			Dictionary nested_pose = nested_pose_value;
			if (nested_pose.has("pose")) {
				nested_pose_value = nested_pose["pose"];
			}
		}
		if (nested_pose_value.get_type() != Variant::DICTIONARY) {
			continue;
		}
		Dictionary pose = nested_pose_value;
		if (!pose.has("position") || Variant(pose["position"]).get_type() != Variant::DICTIONARY) {
			continue;
		}
		Dictionary position = pose["position"];
		const Vector3 point(
			double(position.get("x", 0.0)),
			double(position.get("z", 0.0)),
			-double(position.get("y", 0.0))
		);
		points.append(p_frame_transform.xform(point));
	}
	return points;
}

} // namespace godot
