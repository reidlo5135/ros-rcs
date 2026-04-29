#include "rcs_core/urdf_resolver.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

void RcsUrdfResolver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_package_roots", "package_roots"), &RcsUrdfResolver::set_package_roots);
	ClassDB::bind_method(D_METHOD("resolve_mesh_uri", "uri"), &RcsUrdfResolver::resolve_mesh_uri);
	ClassDB::bind_method(D_METHOD("resolve_model_meshes", "urdf_model"), &RcsUrdfResolver::resolve_model_meshes);
}

void RcsUrdfResolver::set_package_roots(const Dictionary &p_package_roots) {
	package_roots = p_package_roots.duplicate(true);
}

String RcsUrdfResolver::resolve_mesh_uri(const String &p_uri) const {
	Dictionary metadata = resolve_mesh_metadata(p_uri);
	return String(metadata.get("resolved_path", ""));
}

Dictionary RcsUrdfResolver::resolve_model_meshes(const Dictionary &p_urdf_model) const {
	Dictionary result = p_urdf_model.duplicate(true);
	Dictionary links = result.get("links", Dictionary());
	Dictionary resolved_meshes;
	Dictionary joint_transforms;
	Dictionary link_local_transforms;
	int32_t resolved_count = 0;

	Array link_order = result.get("link_order", Array());
	for (int64_t link_index = 0; link_index < link_order.size(); link_index++) {
		String link_name = String(link_order[link_index]);
		if (!links.has(link_name)) {
			continue;
		}
		Dictionary link = links[link_name];

		Array geometry_keys;
		geometry_keys.append("visuals");
		geometry_keys.append("collisions");
		for (int64_t key_index = 0; key_index < geometry_keys.size(); key_index++) {
			String key = String(geometry_keys[key_index]);
			Array parts = link.get(key, Array());
			for (int64_t part_index = 0; part_index < parts.size(); part_index++) {
				if (parts[part_index].get_type() != Variant::DICTIONARY) {
					continue;
				}
				Dictionary part = parts[part_index];
				if (Variant(part.get("geometry", Dictionary())).get_type() != Variant::DICTIONARY) {
					continue;
				}
				Dictionary geometry = part["geometry"];
				part["geometry"] = enrich_geometry(geometry, resolved_meshes, resolved_count);
				parts[part_index] = part;
			}
			link[key] = parts;
		}

		links[link_name] = link;
	}
	result["links"] = links;

	Dictionary joints = result.get("joints", Dictionary());
	Array joint_order = result.get("joint_order", Array());
	for (int64_t joint_index = 0; joint_index < joint_order.size(); joint_index++) {
		String joint_name = String(joint_order[joint_index]);
		if (!joints.has(joint_name)) {
			continue;
		}
		Dictionary joint = joints[joint_name];
		Transform3D transform = transform_from_origin(joint.get("origin", Dictionary()));
		joint_transforms[joint_name] = transform;
		String child_link = String(joint.get("child", ""));
		if (!child_link.is_empty()) {
			link_local_transforms[child_link] = transform;
		}
	}

	result["resolved_meshes"] = resolved_meshes;
	result["resolved_mesh_count"] = resolved_count;
	result["joint_transforms"] = joint_transforms;
	result["link_local_transforms"] = link_local_transforms;
	result["package_roots"] = package_roots.duplicate(true);
	return result;
}

Dictionary RcsUrdfResolver::resolve_mesh_metadata(const String &p_uri) const {
	Dictionary metadata;
	metadata["uri"] = p_uri;
	metadata["package_name"] = "";
	metadata["relative_path"] = "";
	metadata["resolved_path"] = "";
	metadata["resource_path"] = "";
	metadata["extension"] = "";
	metadata["resolved"] = false;
	metadata["error"] = "";

	if (!p_uri.begins_with("package://")) {
		metadata["resolved_path"] = p_uri;
		metadata["resource_path"] = p_uri;
		metadata["resolved"] = !p_uri.is_empty();
		int64_t extension_index = p_uri.rfind(".");
		if (extension_index >= 0) {
			metadata["extension"] = p_uri.substr(extension_index + 1).to_lower();
		}
		return metadata;
	}

	String without_scheme = p_uri.trim_prefix("package://");
	int64_t separator_index = without_scheme.find("/");
	if (separator_index < 0) {
		metadata["error"] = "package uri missing relative path";
		return metadata;
	}

	String package_name = without_scheme.substr(0, separator_index);
	String relative_path = without_scheme.substr(separator_index + 1);
	metadata["package_name"] = package_name;
	metadata["relative_path"] = relative_path;

	if (!package_roots.has(package_name)) {
		metadata["error"] = "package root not configured";
		return metadata;
	}

	String root = normalize_path(String(package_roots[package_name]));
	if (root.is_empty()) {
		metadata["error"] = "package root is empty";
		return metadata;
	}

	String resolved_path = root;
	if (!resolved_path.ends_with("/")) {
		resolved_path += "/";
	}
	resolved_path += relative_path;
	resolved_path = normalize_path(resolved_path);

	metadata["resolved_path"] = resolved_path;
	metadata["resolved"] = true;
	if (resolved_path.begins_with("res://") || resolved_path.begins_with("user://")) {
		metadata["resource_path"] = resolved_path;
	}

	int64_t extension_index = relative_path.rfind(".");
	if (extension_index >= 0) {
		metadata["extension"] = relative_path.substr(extension_index + 1).to_lower();
	}
	return metadata;
}

Dictionary RcsUrdfResolver::enrich_geometry(const Dictionary &p_geometry, Dictionary &r_resolved_meshes, int32_t &r_resolved_count) const {
	Dictionary geometry = p_geometry.duplicate(true);
	if (String(geometry.get("type", "")) != "mesh") {
		return geometry;
	}

	String filename = String(geometry.get("filename", ""));
	Dictionary metadata = resolve_mesh_metadata(filename);
	geometry["package_name"] = metadata.get("package_name", "");
	geometry["package_relative_path"] = metadata.get("relative_path", "");
	geometry["resolved_filename"] = metadata.get("resolved_path", "");
	geometry["mesh_resource_path"] = metadata.get("resource_path", "");
	geometry["mesh_extension"] = metadata.get("extension", "");
	geometry["mesh_uri_resolved"] = metadata.get("resolved", false);
	geometry["mesh_resolution_error"] = metadata.get("error", "");

	if (!filename.is_empty()) {
		r_resolved_meshes[filename] = metadata;
	}
	if (bool(metadata.get("resolved", false))) {
		r_resolved_count += 1;
	}
	return geometry;
}

Transform3D RcsUrdfResolver::transform_from_origin(const Variant &p_origin_value) const {
	if (p_origin_value.get_type() != Variant::DICTIONARY) {
		return Transform3D();
	}

	Dictionary origin = p_origin_value;
	Vector3 xyz = parse_triplet(String(origin.get("xyz", "")), Vector3());
	Vector3 rpy = parse_triplet(String(origin.get("rpy", "")), Vector3());
	Vector3 position(xyz.x, xyz.z, -xyz.y);
	Vector3 rotation(rpy.x, rpy.z, -rpy.y);
	return Transform3D(Basis::from_euler(rotation), position);
}

Vector3 RcsUrdfResolver::parse_triplet(const String &p_text, const Vector3 &p_fallback) const {
	PackedStringArray tokens = p_text.strip_edges().split(" ", false);
	if (tokens.size() < 3) {
		return p_fallback;
	}
	return Vector3(
		tokens[0].is_valid_float() ? double(tokens[0]) : p_fallback.x,
		tokens[1].is_valid_float() ? double(tokens[1]) : p_fallback.y,
		tokens[2].is_valid_float() ? double(tokens[2]) : p_fallback.z
	);
}

String RcsUrdfResolver::normalize_path(const String &p_value) const {
	return p_value.replace("\\", "/").strip_edges();
}

} // namespace godot
