#include "rcs_core/rcs_laser_scan_projector.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <cmath>

namespace godot {

void RcsLaserScanProjector::_bind_methods() {
	ClassDB::bind_method(D_METHOD("project", "scan", "frame_transform"), &RcsLaserScanProjector::project);
}

PackedVector3Array RcsLaserScanProjector::project(const Dictionary &p_scan, const Transform3D &p_frame_transform) const {
	PackedVector3Array points;
	if (!p_scan.has("ranges")) {
		return points;
	}

	const Array ranges = p_scan["ranges"];
	const double angle_min = double(p_scan.get("angle_min", 0.0));
	const double angle_increment = double(p_scan.get("angle_increment", 0.0));
	const double range_min = double(p_scan.get("range_min", 0.0));
	const double range_max = double(p_scan.get("range_max", 100.0));

	for (int64_t index = 0; index < ranges.size(); index++) {
		const Variant value = ranges[index];
		if (value.get_type() == Variant::NIL) {
			continue;
		}
		const double range = double(value);
		if (range <= range_min || range > range_max || !std::isfinite(range)) {
			continue;
		}
		const double angle = angle_min + angle_increment * double(index);
		const Vector3 local_point(std::cos(angle) * range, 0.0, -std::sin(angle) * range);
		points.append(p_frame_transform.xform(local_point));
	}

	return points;
}

} // namespace godot
