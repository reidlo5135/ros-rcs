extends RefCounted
class_name RcsUrdfParser

static var _package_roots: Dictionary = {}


static func set_package_roots(package_roots: Dictionary) -> void:
	_package_roots = package_roots.duplicate(true)


static func parse(xml_text: String) -> Dictionary:
	var result: Dictionary = {
		"name": "",
		"links": {},
		"joints": {},
		"link_order": [],
		"joint_order": [],
		"materials": {},
		"visual_count": 0,
		"collision_count": 0,
		"mesh_count": 0,
		"parse_error": "",
	}

	var clean_xml: String = xml_text.strip_edges()
	if clean_xml.is_empty():
		result["parse_error"] = "robot_description is empty"
		return result

	var parser := XMLParser.new()
	var open_error: int = parser.open_buffer(clean_xml.to_utf8_buffer())
	if open_error != OK:
		result["parse_error"] = "XML open failed: %d" % open_error
		return result

	var current_link := ""
	var current_joint := ""
	var current_visual: Dictionary = {}
	var current_collision := {}
	var in_visual := false
	var in_collision := false

	while true:
		var read_error: int = parser.read()
		if read_error == ERR_FILE_EOF:
			break
		if read_error != OK:
			result["parse_error"] = "XML read failed: %d" % read_error
			return result

		var node_type: int = parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var node_name: String = parser.get_node_name()
			var attrs: Dictionary = _attributes(parser)
			var is_empty: bool = parser.is_empty()

			match node_name:
				"robot":
					result["name"] = str(attrs.get("name", ""))
				"material":
					if not current_link.is_empty() and in_visual:
						current_visual["material"] = attrs
					elif attrs.has("name"):
						result["materials"][attrs["name"]] = attrs
				"link":
					current_link = str(attrs.get("name", ""))
					if not current_link.is_empty():
						result["links"][current_link] = {
							"name": current_link,
							"visuals": [],
							"collisions": [],
						}
						result["link_order"].append(current_link)
				"visual":
					if not current_link.is_empty():
						in_visual = true
						current_visual = {
							"origin": {},
							"geometry": {},
							"material": {},
						}
						result["visual_count"] += 1
				"collision":
					if not current_link.is_empty():
						in_collision = true
						current_collision = {
							"origin": {},
							"geometry": {},
						}
						result["collision_count"] += 1
				"origin":
					if in_visual:
						current_visual["origin"] = attrs
					elif in_collision:
						current_collision["origin"] = attrs
					elif not current_joint.is_empty():
						result["joints"][current_joint]["origin"] = attrs
				"geometry":
					pass
				"mesh":
					if in_visual:
						current_visual["geometry"] = {
							"type": "mesh",
							"filename": str(attrs.get("filename", "")),
							"scale": str(attrs.get("scale", "")),
						}
						result["mesh_count"] += 1
					elif in_collision:
						current_collision["geometry"] = {
							"type": "mesh",
							"filename": str(attrs.get("filename", "")),
							"scale": str(attrs.get("scale", "")),
						}
				"box":
					if in_visual:
						current_visual["geometry"] = {
							"type": "box",
							"size": str(attrs.get("size", "")),
						}
					elif in_collision:
						current_collision["geometry"] = {
							"type": "box",
							"size": str(attrs.get("size", "")),
						}
				"cylinder":
					if in_visual:
						current_visual["geometry"] = {
							"type": "cylinder",
							"radius": str(attrs.get("radius", "")),
							"length": str(attrs.get("length", "")),
						}
					elif in_collision:
						current_collision["geometry"] = {
							"type": "cylinder",
							"radius": str(attrs.get("radius", "")),
							"length": str(attrs.get("length", "")),
						}
				"sphere":
					if in_visual:
						current_visual["geometry"] = {
							"type": "sphere",
							"radius": str(attrs.get("radius", "")),
						}
					elif in_collision:
						current_collision["geometry"] = {
							"type": "sphere",
							"radius": str(attrs.get("radius", "")),
						}
				"joint":
					current_joint = str(attrs.get("name", ""))
					if not current_joint.is_empty():
						result["joints"][current_joint] = {
							"name": current_joint,
							"type": str(attrs.get("type", "")),
							"parent": "",
							"child": "",
							"origin": {},
							"axis": {},
						}
						result["joint_order"].append(current_joint)
				"parent":
					if not current_joint.is_empty():
						result["joints"][current_joint]["parent"] = str(attrs.get("link", ""))
				"child":
					if not current_joint.is_empty():
						result["joints"][current_joint]["child"] = str(attrs.get("link", ""))
				"axis":
					if not current_joint.is_empty():
						result["joints"][current_joint]["axis"] = attrs

			if is_empty:
				if node_name == "visual":
					_commit_visual(result, current_link, current_visual)
					current_visual = {}
					in_visual = false
				elif node_name == "collision":
					_commit_collision(result, current_link, current_collision)
					current_collision = {}
					in_collision = false
				elif node_name == "link":
					current_link = ""
				elif node_name == "joint":
					current_joint = ""

		elif node_type == XMLParser.NODE_ELEMENT_END:
			var end_name: String = parser.get_node_name()
			match end_name:
				"visual":
					_commit_visual(result, current_link, current_visual)
					current_visual = {}
					in_visual = false
				"collision":
					_commit_collision(result, current_link, current_collision)
					current_collision = {}
					in_collision = false
				"link":
					current_link = ""
				"joint":
					current_joint = ""

	return _enrich_model(result)


static func _attributes(parser: XMLParser) -> Dictionary:
	var attrs: Dictionary = {}
	for index in range(parser.get_attribute_count()):
		attrs[parser.get_attribute_name(index)] = parser.get_attribute_value(index)
	return attrs


static func _commit_visual(result: Dictionary, link_name: String, visual: Dictionary) -> void:
	if link_name.is_empty():
		return
	if visual.is_empty():
		return
	if not result["links"].has(link_name):
		return
	result["links"][link_name]["visuals"].append(visual.duplicate(true))


static func _commit_collision(result: Dictionary, link_name: String, collision: Dictionary) -> void:
	if link_name.is_empty():
		return
	if collision.is_empty():
		return
	if not result["links"].has(link_name):
		return
	result["links"][link_name]["collisions"].append(collision.duplicate(true))


static func _enrich_model(urdf_model: Dictionary) -> Dictionary:
	var resolver: Variant = _native_resolver()
	if resolver != null:
		resolver.set_package_roots(_package_roots)
		return resolver.resolve_model_meshes(urdf_model)
	return _resolve_model_meshes_gd(urdf_model, _package_roots)


static func _native_resolver() -> Variant:
	if ClassDB.class_exists("RcsUrdfResolver"):
		return ClassDB.instantiate("RcsUrdfResolver")
	return null


static func _resolve_model_meshes_gd(urdf_model: Dictionary, package_roots: Dictionary) -> Dictionary:
	var result: Dictionary = urdf_model.duplicate(true)
	var links: Dictionary = result.get("links", {})
	var resolved_meshes: Dictionary = {}
	var resolved_mesh_count: int = 0
	var joint_transforms: Dictionary = {}
	var link_local_transforms: Dictionary = {}

	for link_name in links.keys():
		var link: Dictionary = links[link_name]
		for key in ["visuals", "collisions"]:
			var parts: Array = link.get(key, [])
			for index in range(parts.size()):
				if typeof(parts[index]) != TYPE_DICTIONARY:
					continue
				var part: Dictionary = parts[index]
				var geometry: Variant = part.get("geometry", {})
				if typeof(geometry) != TYPE_DICTIONARY:
					continue
				var enrich_result: Dictionary = _enrich_geometry(geometry, package_roots)
				part["geometry"] = enrich_result["geometry"]
				parts[index] = part
				var uri: String = str(enrich_result.get("uri", ""))
				if not uri.is_empty():
					resolved_meshes[uri] = enrich_result.get("metadata", {})
				if bool(enrich_result.get("resolved", false)):
					resolved_mesh_count += 1
			link[key] = parts
		links[link_name] = link

	var joints: Dictionary = result.get("joints", {})
	for joint_name in joints.keys():
		var joint: Dictionary = joints[joint_name]
		var transform: Transform3D = _transform_from_origin(joint.get("origin", {}))
		joint_transforms[joint_name] = transform
		var child_link: String = str(joint.get("child", ""))
		if not child_link.is_empty():
			link_local_transforms[child_link] = transform

	result["links"] = links
	result["resolved_meshes"] = resolved_meshes
	result["resolved_mesh_count"] = resolved_mesh_count
	result["joint_transforms"] = joint_transforms
	result["link_local_transforms"] = link_local_transforms
	result["package_roots"] = package_roots.duplicate(true)
	return result


static func _enrich_geometry(geometry_value: Variant, package_roots: Dictionary) -> Dictionary:
	if typeof(geometry_value) != TYPE_DICTIONARY:
		return {"geometry": geometry_value, "uri": "", "metadata": {}, "resolved": false}

	var geometry: Dictionary = (geometry_value as Dictionary).duplicate(true)
	if str(geometry.get("type", "")) != "mesh":
		return {"geometry": geometry, "uri": "", "metadata": {}, "resolved": false}

	var uri: String = str(geometry.get("filename", ""))
	var metadata: Dictionary = _resolve_mesh_metadata(uri, package_roots)
	geometry["package_name"] = str(metadata.get("package_name", ""))
	geometry["package_relative_path"] = str(metadata.get("relative_path", ""))
	geometry["resolved_filename"] = str(metadata.get("resolved_path", ""))
	geometry["mesh_resource_path"] = str(metadata.get("resource_path", ""))
	geometry["mesh_extension"] = str(metadata.get("extension", ""))
	geometry["mesh_uri_resolved"] = bool(metadata.get("resolved", false))
	geometry["mesh_resolution_error"] = str(metadata.get("error", ""))
	return {
		"geometry": geometry,
		"uri": uri,
		"metadata": metadata,
		"resolved": bool(metadata.get("resolved", false)),
	}


static func _resolve_mesh_metadata(uri: String, package_roots: Dictionary) -> Dictionary:
	var metadata: Dictionary = {
		"uri": uri,
		"package_name": "",
		"relative_path": "",
		"resolved_path": "",
		"resource_path": "",
		"extension": "",
		"resolved": false,
		"error": "",
	}

	if not uri.begins_with("package://"):
		metadata["resolved_path"] = uri
		metadata["resource_path"] = uri
		metadata["resolved"] = not uri.is_empty()
		metadata["extension"] = uri.get_extension().to_lower()
		return metadata

	var without_scheme: String = uri.trim_prefix("package://")
	var separator_index: int = without_scheme.find("/")
	if separator_index < 0:
		metadata["error"] = "package uri missing relative path"
		return metadata

	var package_name: String = without_scheme.substr(0, separator_index)
	var relative_path: String = without_scheme.substr(separator_index + 1)
	metadata["package_name"] = package_name
	metadata["relative_path"] = relative_path

	if not package_roots.has(package_name):
		metadata["error"] = "package root not configured"
		return metadata

	var root: String = _normalize_path(str(package_roots[package_name]))
	if root.is_empty():
		metadata["error"] = "package root is empty"
		return metadata

	var resolved_path: String = root
	if not resolved_path.ends_with("/"):
		resolved_path += "/"
	resolved_path += relative_path
	resolved_path = _normalize_path(resolved_path)
	metadata["resolved_path"] = resolved_path
	metadata["resolved"] = true
	metadata["extension"] = relative_path.get_extension().to_lower()
	if resolved_path.begins_with("res://") or resolved_path.begins_with("user://"):
		metadata["resource_path"] = resolved_path
	return metadata


static func _normalize_path(value: String) -> String:
	return value.replace("\\", "/").strip_edges()


static func _transform_from_origin(origin_value: Variant) -> Transform3D:
	if typeof(origin_value) != TYPE_DICTIONARY:
		return Transform3D.IDENTITY
	var origin: Dictionary = origin_value
	var xyz: Vector3 = _parse_triplet(str(origin.get("xyz", "")), Vector3.ZERO)
	var rpy: Vector3 = _parse_triplet(str(origin.get("rpy", "")), Vector3.ZERO)
	var position: Vector3 = Vector3(xyz.x, xyz.z, -xyz.y)
	var rotation: Vector3 = Vector3(rpy.x, rpy.z, -rpy.y)
	return Transform3D(Basis.from_euler(rotation), position)


static func _parse_triplet(text: String, fallback: Vector3) -> Vector3:
	var tokens: PackedStringArray = text.strip_edges().split(" ", false)
	if tokens.size() < 3:
		return fallback
	return Vector3(
		float(tokens[0]) if tokens[0].is_valid_float() else fallback.x,
		float(tokens[1]) if tokens[1].is_valid_float() else fallback.y,
		float(tokens[2]) if tokens[2].is_valid_float() else fallback.z
	)
