#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class RcsUrdfResolver : public RefCounted {
	GDCLASS(RcsUrdfResolver, RefCounted)

protected:
	static void _bind_methods();

public:
	void set_package_roots(const Dictionary &p_package_roots);
	String resolve_mesh_uri(const String &p_uri) const;
	Dictionary resolve_model_meshes(const Dictionary &p_urdf_model) const;

private:
	Dictionary package_roots;

	Dictionary resolve_mesh_metadata(const String &p_uri) const;
	Dictionary enrich_geometry(const Dictionary &p_geometry, Dictionary &r_resolved_meshes, int32_t &r_resolved_count) const;
	Transform3D transform_from_origin(const Variant &p_origin_value) const;
	Vector3 parse_triplet(const String &p_text, const Vector3 &p_fallback) const;
	String normalize_path(const String &p_value) const;
};

} // namespace godot
