extends RefCounted
class_name RcsUrdfParser


static func parse(xml_text: String) -> Dictionary:
	var result := {
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

	var clean_xml := xml_text.strip_edges()
	if clean_xml.is_empty():
		result["parse_error"] = "robot_description is empty"
		return result

	var parser := XMLParser.new()
	var open_error := parser.open_buffer(clean_xml.to_utf8_buffer())
	if open_error != OK:
		result["parse_error"] = "XML open failed: %d" % open_error
		return result

	var current_link := ""
	var current_joint := ""
	var current_visual := {}
	var current_collision := {}
	var in_visual := false
	var in_collision := false

	while true:
		var read_error := parser.read()
		if read_error == ERR_FILE_EOF:
			break
		if read_error != OK:
			result["parse_error"] = "XML read failed: %d" % read_error
			return result

		var node_type := parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()
			var attrs := _attributes(parser)
			var is_empty := parser.is_empty()

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
			var end_name := parser.get_node_name()
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

	return result


static func _attributes(parser: XMLParser) -> Dictionary:
	var attrs := {}
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
