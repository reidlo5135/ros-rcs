#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {

class RcsLaserScanProjector : public RefCounted {
	GDCLASS(RcsLaserScanProjector, RefCounted)

protected:
	static void _bind_methods();

public:
	PackedVector3Array project(const Dictionary &p_scan, const Transform3D &p_frame_transform) const;
};

} // namespace godot
