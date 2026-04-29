extends "res://src/scene/layers/base/visualization_layer.gd"
class_name RcsRobotLayer

const ROBOT_RENDER_Y := 0.02
const MIN_MEANINGFUL_MESH_PROXY_SCALE := 0.05
const MIN_PROXY_SCALE := 0.25
const MAX_PROXY_SCALE := 4.0
const ROBOT_MODEL_BASE_COLOR := Color8(54, 60, 68, 255)
const ROBOT_MODEL_DARK_COLOR := Color8(24, 27, 31, 255)
const ROBOT_MODEL_MID_COLOR := Color8(108, 116, 126, 255)
const ROBOT_MODEL_PLATE_COLOR := Color8(152, 160, 170, 255)
const ROBOT_MODEL_LIDAR_COLOR := Color8(72, 80, 90, 255)
const ROBOT_MODEL_SENSOR_COLOR := Color8(79, 208, 233, 255)
const ROBOT_MODEL_NOSE_COLOR := Color8(245, 164, 66, 255)
const LIDAR_PROXY_HEIGHT := 0.035
const LIDAR_PROXY_RADIUS := 0.042
const BASE_PROXY_RADIUS := 0.092
const BASE_PROXY_HEIGHT := 0.022
const TOP_PLATE_RADIUS := 0.076
const TOP_PLATE_HEIGHT := 0.014
const CHASSIS_NOSE_SIZE := Vector3(0.05, 0.012, 0.032)
const SIDE_SKIRT_SIZE := Vector3(0.022, 0.026, 0.104)
const INTEGRATED_LIDAR_OFFSET := Vector3(0.0, 0.066, 0.0)

var body: MeshInstance3D
var heading: MeshInstance3D
var urdf_root: Node3D
var last_urdf_name := ""
var last_urdf_signature := ""


func _init() -> void:
	layer_id = "robot"


func _ready() -> void:
	position.y = ROBOT_RENDER_Y
	_build_proxy_robot()


func apply_state(_state: Variant) -> void:
	_apply_pose(_state.robot_pose)
	_apply_urdf(_state.urdf_model)


func _build_proxy_robot() -> void:
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.34
	body_mesh.bottom_radius = 0.34
	body_mesh.height = 0.22
	body_mesh.radial_segments = 32

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.12, 0.74, 0.68)
	_configure_top_material(body_material)

	body = MeshInstance3D.new()
	body.name = "RobotPoseMarker"
	body.mesh = body_mesh
	body.material_override = body_material
	body.position.y = 0.11
	add_child(body)

	var heading_mesh := BoxMesh.new()
	heading_mesh.size = Vector3(0.28, 0.16, 0.48)

	var heading_material := StandardMaterial3D.new()
	heading_material.albedo_color = Color(1.0, 0.66, 0.16)
	_configure_top_material(heading_material)

	heading = MeshInstance3D.new()
	heading.name = "RobotHeading"
	heading.position = Vector3(0.44, 0.16, 0.0)
	heading.mesh = heading_mesh
	heading.material_override = heading_material
	add_child(heading)


func _apply_pose(robot_pose: Dictionary) -> void:
	if robot_pose.is_empty():
		return

	var pose := _extract_pose(robot_pose)
	position = Vector3(float(pose.get("x", 0.0)), ROBOT_RENDER_Y, -float(pose.get("y", 0.0)))
	rotation.y = float(pose.get("yaw", 0.0))


func _extract_pose(robot_pose: Dictionary) -> Dictionary:
	if robot_pose.has("x") or robot_pose.has("y"):
		return {
			"x": robot_pose.get("x", 0.0),
			"y": robot_pose.get("y", 0.0),
			"yaw": robot_pose.get("yaw", robot_pose.get("theta", 0.0)),
		}

	var pose_value: Variant = robot_pose.get("pose", robot_pose)
	if typeof(pose_value) == TYPE_DICTIONARY and pose_value.has("pose"):
		pose_value = pose_value["pose"]
	if typeof(pose_value) != TYPE_DICTIONARY:
		return {}

	var pose_dict: Dictionary = pose_value
	var position_value: Variant = pose_dict.get("position", {})
	var orientation_value: Variant = pose_dict.get("orientation", {})
	var x := 0.0
	var y := 0.0
	var yaw := 0.0

	if typeof(position_value) == TYPE_DICTIONARY:
		x = float(position_value.get("x", 0.0))
		y = float(position_value.get("y", 0.0))
	if typeof(orientation_value) == TYPE_DICTIONARY:
		yaw = _yaw_from_quaternion(orientation_value)

	return {
		"x": x,
		"y": y,
		"yaw": yaw,
	}


func _yaw_from_quaternion(value: Dictionary) -> float:
	var x := float(value.get("x", 0.0))
	var y := float(value.get("y", 0.0))
	var z := float(value.get("z", 0.0))
	var w := float(value.get("w", 1.0))
	return atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))


func _apply_urdf(urdf_model: Dictionary) -> void:
	if urdf_model.is_empty():
		return

	var robot_name := str(urdf_model.get("name", "robot"))
	var signature := "%s:%s:%s:%s" % [
		robot_name,
		(urdf_model.get("link_order", []) as Array).size(),
		(urdf_model.get("joint_order", []) as Array).size(),
		int(urdf_model.get("mesh_count", 0)),
	]
	if signature == last_urdf_signature:
		return

	last_urdf_name = robot_name
	last_urdf_signature = signature
	_build_urdf_placeholder(urdf_model)


func _build_urdf_placeholder(urdf_model: Dictionary) -> void:
	if urdf_root != null:
		urdf_root.queue_free()
		urdf_root = null

	urdf_root = Node3D.new()
	urdf_root.name = "UrdfModel"
	add_child(urdf_root)

	var links: Dictionary = urdf_model.get("links", {})
	var joints: Dictionary = urdf_model.get("joints", {})
	var link_order: Array = urdf_model.get("link_order", [])
	var joint_order: Array = urdf_model.get("joint_order", [])
	var link_nodes := {}
	var child_links := {}

	for link_name_value in link_order:
		var link_name := str(link_name_value)
		var link_node := Node3D.new()
		link_node.name = _safe_node_name(link_name)
		link_nodes[link_name] = link_node

	for joint_name_value in joint_order:
		var joint_name := str(joint_name_value)
		if not joints.has(joint_name):
			continue
		var joint: Dictionary = joints[joint_name]
		var parent_link := str(joint.get("parent", ""))
		var child_link := str(joint.get("child", ""))
		if child_link.is_empty() or not link_nodes.has(child_link):
			continue
		var parent_node: Node = urdf_root
		if link_nodes.has(parent_link):
			parent_node = link_nodes[parent_link]
		var child_node: Node3D = link_nodes[child_link]
		if child_node.get_parent() != null:
			child_node.get_parent().remove_child(child_node)
		parent_node.add_child(child_node)
		child_node.transform = _transform_from_origin(joint.get("origin", {}))
		child_links[child_link] = true

	for link_name_value in link_order:
		var link_name := str(link_name_value)
		var link_node: Node3D = link_nodes[link_name]
		if link_node.get_parent() == null:
			urdf_root.add_child(link_node)
		var link: Dictionary = links.get(link_name, {})
		_add_link_visuals(link_node, link_name, link.get("visuals", []), link.get("collisions", []))

	if body != null:
		body.visible = link_order.is_empty()
	if heading != null:
		heading.visible = link_order.is_empty()


func _add_link_visuals(link_node: Node3D, link_name: String, visuals: Variant, collisions: Variant) -> void:
	if _should_skip_standalone_link(link_name):
		return

	var special_proxy := _build_special_link_proxy(link_name)
	if special_proxy != null:
		special_proxy.transform = _special_proxy_transform(link_name, visuals, collisions)
		link_node.add_child(special_proxy)
		return

	if typeof(visuals) != TYPE_ARRAY or (visuals as Array).is_empty():
		var marker := _build_link_marker(link_name)
		link_node.add_child(marker)
		return

	var collision_proxy := _first_collision_proxy(collisions)
	for visual_value in visuals:
		if typeof(visual_value) != TYPE_DICTIONARY:
			continue
		var visual: Dictionary = visual_value
		var geometry: Dictionary = visual.get("geometry", {})
		var visual_origin: Variant = visual.get("origin", {})
		if str(geometry.get("type", "")) == "mesh" and not collision_proxy.is_empty():
			geometry = collision_proxy.get("geometry", geometry)
			visual_origin = collision_proxy.get("origin", visual_origin)
		var visual_node := _build_visual_node(geometry, link_name)
		visual_node.name = "visual"
		visual_node.transform = _transform_from_origin(visual_origin)
		link_node.add_child(visual_node)


func _build_special_link_proxy(link_name: String) -> Node3D:
	if _is_primary_base_descriptor(link_name):
		return _build_base_proxy_node(link_name)
	if _is_lidar_descriptor(link_name):
		return _build_lidar_proxy_node(link_name)
	if _is_drive_wheel_descriptor(link_name):
		return _build_wheel_proxy_node(link_name)
	if _is_caster_descriptor(link_name):
		return _build_caster_proxy_node(link_name)
	return null


func _representative_visual_transform(visuals: Variant, collisions: Variant) -> Transform3D:
	if typeof(visuals) == TYPE_ARRAY:
		for visual_value in visuals:
			if typeof(visual_value) != TYPE_DICTIONARY:
				continue
			var visual: Dictionary = visual_value
			return _transform_from_origin(visual.get("origin", {}))

	var collision_proxy := _first_collision_proxy(collisions)
	if not collision_proxy.is_empty():
		return _transform_from_origin(collision_proxy.get("origin", {}))

	return Transform3D.IDENTITY


func _special_proxy_transform(link_name: String, visuals: Variant, collisions: Variant) -> Transform3D:
	if _is_lidar_descriptor(link_name):
		return Transform3D.IDENTITY
	return _representative_visual_transform(visuals, collisions)


func _should_skip_standalone_link(link_name: String) -> bool:
	var descriptor := link_name.to_lower()
	return _is_lidar_descriptor(link_name) or descriptor.contains("base_footprint")


func _first_collision_proxy(collisions: Variant) -> Dictionary:
	if typeof(collisions) != TYPE_ARRAY:
		return {}
	for collision_value in collisions:
		if typeof(collision_value) != TYPE_DICTIONARY:
			continue
		var collision: Dictionary = collision_value
		var geometry: Variant = collision.get("geometry", {})
		if typeof(geometry) == TYPE_DICTIONARY and not (geometry as Dictionary).is_empty():
			return collision
	return {}


func _build_link_marker(link_name: String) -> Node3D:
	var special_proxy := _build_special_link_proxy(link_name)
	if special_proxy != null:
		return special_proxy

	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	var marker := MeshInstance3D.new()
	marker.name = "link_marker"
	marker.mesh = sphere
	marker.material_override = _material_for_link(link_name, {})
	return marker


func _build_visual_node(geometry: Dictionary, link_name: String) -> Node3D:
	var descriptor := (link_name + " " + str(geometry.get("filename", ""))).to_lower()
	if _is_primary_base_descriptor(descriptor):
		return _build_base_proxy_node(link_name)
	if _is_lidar_descriptor(descriptor):
		return _build_lidar_proxy_node(link_name)
	if _is_drive_wheel_descriptor(descriptor):
		return _build_wheel_proxy_node(link_name)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _mesh_for_geometry(geometry, link_name)
	mesh_instance.material_override = _material_for_link(link_name, geometry)
	return mesh_instance


func _build_base_proxy_node(link_name: String) -> Node3D:
	var root := Node3D.new()

	var lower_body := MeshInstance3D.new()
	var lower_mesh := CylinderMesh.new()
	lower_mesh.top_radius = BASE_PROXY_RADIUS
	lower_mesh.bottom_radius = BASE_PROXY_RADIUS
	lower_mesh.height = BASE_PROXY_HEIGHT
	lower_mesh.radial_segments = 40
	lower_body.mesh = lower_mesh
	lower_body.material_override = _base_material_for_link(link_name)
	lower_body.position.y = 0.036
	root.add_child(lower_body)

	var left_skirt := MeshInstance3D.new()
	var left_skirt_mesh := BoxMesh.new()
	left_skirt_mesh.size = SIDE_SKIRT_SIZE
	left_skirt.mesh = left_skirt_mesh
	left_skirt.material_override = _base_material_for_link(link_name)
	left_skirt.position = Vector3(-0.076, 0.028, 0.0)
	root.add_child(left_skirt)

	var right_skirt := MeshInstance3D.new()
	var right_skirt_mesh := BoxMesh.new()
	right_skirt_mesh.size = SIDE_SKIRT_SIZE
	right_skirt.mesh = right_skirt_mesh
	right_skirt.material_override = _base_material_for_link(link_name)
	right_skirt.position = Vector3(0.076, 0.028, 0.0)
	root.add_child(right_skirt)

	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = CHASSIS_NOSE_SIZE
	nose.mesh = nose_mesh
	nose.material_override = _nose_material()
	nose.position = Vector3(0.084, 0.05, 0.0)
	root.add_child(nose)

	var status_light := MeshInstance3D.new()
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.012
	light_mesh.height = 0.024
	status_light.mesh = light_mesh
	status_light.material_override = _sensor_material(0.62)
	status_light.position = Vector3(0.055, 0.061, 0.0)
	root.add_child(status_light)

	var integrated_lidar := _build_lidar_proxy_node("integrated_lidar")
	integrated_lidar.name = "IntegratedLidar"
	integrated_lidar.position = INTEGRATED_LIDAR_OFFSET
	root.add_child(integrated_lidar)

	return root


func _build_lidar_marker(link_name: String) -> Node3D:
	return _build_lidar_proxy_node(link_name)


func _build_lidar_proxy_node(link_name: String) -> Node3D:
	var root := Node3D.new()
	var lidar := CylinderMesh.new()
	lidar.top_radius = LIDAR_PROXY_RADIUS
	lidar.bottom_radius = LIDAR_PROXY_RADIUS
	lidar.height = LIDAR_PROXY_HEIGHT
	lidar.radial_segments = 32
	var marker := MeshInstance3D.new()
	marker.name = "lidar_marker"
	marker.mesh = lidar
	marker.material_override = _material_for_link(link_name, {})
	marker.position.y = LIDAR_PROXY_HEIGHT * 0.5
	root.add_child(marker)

	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = LIDAR_PROXY_RADIUS * 0.32
	cap_mesh.bottom_radius = LIDAR_PROXY_RADIUS * 0.32
	cap_mesh.height = 0.012
	cap_mesh.radial_segments = 24
	cap.mesh = cap_mesh
	cap.material_override = _sensor_material(0.72)
	cap.position.y = LIDAR_PROXY_HEIGHT + 0.006
	root.add_child(cap)

	return root


func _build_wheel_proxy_node(link_name: String) -> Node3D:
	var root := Node3D.new()
	var tire := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = 0.034
	tire_mesh.bottom_radius = 0.034
	tire_mesh.height = 0.018
	tire_mesh.radial_segments = 24
	tire.mesh = tire_mesh
	tire.material_override = _material_for_link(link_name, {})
	tire.rotation_degrees.x = 90.0
	root.add_child(tire)

	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.014
	hub_mesh.bottom_radius = 0.014
	hub_mesh.height = 0.022
	hub_mesh.radial_segments = 18
	hub.mesh = hub_mesh
	hub.material_override = _rim_material(0.68)
	hub.rotation_degrees.x = 90.0
	root.add_child(hub)
	return root


func _build_caster_proxy_node(link_name: String) -> Node3D:
	var root := Node3D.new()

	var caster_ball := MeshInstance3D.new()
	var caster_ball_mesh := SphereMesh.new()
	caster_ball_mesh.radius = 0.013
	caster_ball_mesh.height = 0.026
	caster_ball.mesh = caster_ball_mesh
	caster_ball.material_override = _rim_material(0.48)
	caster_ball.position.y = 0.012
	root.add_child(caster_ball)

	var caster_stem := MeshInstance3D.new()
	var caster_stem_mesh := CylinderMesh.new()
	caster_stem_mesh.top_radius = 0.007
	caster_stem_mesh.bottom_radius = 0.007
	caster_stem_mesh.height = 0.018
	caster_stem_mesh.radial_segments = 16
	caster_stem.mesh = caster_stem_mesh
	caster_stem.material_override = _rim_material(0.42)
	caster_stem.position.y = 0.028
	root.add_child(caster_stem)

	return root


func _mesh_for_geometry(geometry: Dictionary, link_name: String) -> Mesh:
	match str(geometry.get("type", "")):
		"box":
			var box := BoxMesh.new()
			var size := _parse_triplet(str(geometry.get("size", "")), Vector3(0.08, 0.08, 0.08))
			box.size = Vector3(max(size.x, 0.01), max(size.z, 0.01), max(size.y, 0.01))
			return box
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = max(float(geometry.get("radius", 0.04)), 0.01)
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = max(float(geometry.get("length", 0.08)), 0.01)
			cylinder.radial_segments = 24
			return cylinder
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = max(float(geometry.get("radius", 0.04)), 0.01)
			sphere.height = sphere.radius * 2.0
			return sphere
		"mesh":
			return _mesh_proxy_geometry(str(geometry.get("filename", "")), str(geometry.get("scale", "")), link_name)
		_:
			var fallback := BoxMesh.new()
			fallback.size = _mesh_proxy_size("", "", link_name)
			return fallback


func _mesh_proxy_geometry(filename: String, scale_text: String, link_name: String) -> Mesh:
	var descriptor := (filename + " " + link_name).to_lower()
	if _is_lidar_descriptor(descriptor):
		var laser := CylinderMesh.new()
		laser.top_radius = LIDAR_PROXY_RADIUS
		laser.bottom_radius = LIDAR_PROXY_RADIUS
		laser.height = LIDAR_PROXY_HEIGHT
		laser.radial_segments = 32
		return laser
	if _is_drive_wheel_descriptor(descriptor):
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.033
		wheel.bottom_radius = 0.033
		wheel.height = 0.018
		wheel.radial_segments = 24
		return wheel
	if _is_caster_descriptor(descriptor):
		var caster := SphereMesh.new()
		caster.radius = 0.013
		caster.height = 0.026
		return caster

	var proxy := BoxMesh.new()
	proxy.size = _mesh_proxy_size(filename, scale_text, link_name)
	return proxy


func _mesh_proxy_size(filename: String, scale_text: String, link_name: String) -> Vector3:
	var descriptor := (filename + " " + link_name).to_lower()
	var base_size := Vector3(0.12, 0.08, 0.12)
	if _is_drive_wheel_descriptor(descriptor):
		base_size = Vector3(0.066, 0.018, 0.066)
	elif _is_lidar_descriptor(descriptor):
		base_size = Vector3(LIDAR_PROXY_RADIUS * 2.0, LIDAR_PROXY_HEIGHT, LIDAR_PROXY_RADIUS * 2.0)
	elif _is_caster_descriptor(descriptor):
		base_size = Vector3(0.026, 0.026, 0.026)
	elif descriptor.contains("base_link"):
		base_size = Vector3(0.165, 0.022, 0.145)
	elif descriptor.contains("plate"):
		base_size = Vector3(0.14, 0.012, 0.118)
	elif descriptor.contains("chassis") or descriptor.contains("burger_base"):
		base_size = Vector3(0.15, 0.016, 0.13)
	return _scaled_proxy_size(base_size, scale_text)


func _scaled_proxy_size(base_size: Vector3, scale_text: String) -> Vector3:
	if scale_text.strip_edges().is_empty():
		return base_size

	var ros_scale := _parse_triplet(scale_text, Vector3.ONE).abs()
	var largest_axis: float = max(ros_scale.x, max(ros_scale.y, ros_scale.z))
	if largest_axis < MIN_MEANINGFUL_MESH_PROXY_SCALE:
		return base_size

	var godot_scale := Vector3(
		clamp(ros_scale.x, MIN_PROXY_SCALE, MAX_PROXY_SCALE),
		clamp(ros_scale.z, MIN_PROXY_SCALE, MAX_PROXY_SCALE),
		clamp(ros_scale.y, MIN_PROXY_SCALE, MAX_PROXY_SCALE)
	)
	return base_size * godot_scale


func _transform_from_origin(origin_value: Variant) -> Transform3D:
	if typeof(origin_value) != TYPE_DICTIONARY:
		return Transform3D.IDENTITY
	var origin: Dictionary = origin_value
	var xyz := _parse_triplet(str(origin.get("xyz", "")), Vector3.ZERO)
	var rpy := _parse_triplet(str(origin.get("rpy", "")), Vector3.ZERO)
	var position := Vector3(xyz.x, xyz.z, -xyz.y)
	var rotation := Vector3(rpy.x, rpy.z, -rpy.y)
	return Transform3D(Basis.from_euler(rotation), position)


func _parse_triplet(text: String, fallback: Vector3) -> Vector3:
	var tokens := text.strip_edges().split(" ", false)
	if tokens.size() < 3:
		return fallback
	return Vector3(
		float(tokens[0]) if tokens[0].is_valid_float() else fallback.x,
		float(tokens[1]) if tokens[1].is_valid_float() else fallback.y,
		float(tokens[2]) if tokens[2].is_valid_float() else fallback.z
	)


func _material_for_link(link_name: String, geometry: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.82
	material.metallic = 0.0
	material.albedo_color = _color_for_link(link_name, str(geometry.get("filename", "")))
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_configure_top_material(material)
	return material


func _plate_material_for_link(link_name: String) -> StandardMaterial3D:
	var material := _material_for_link(link_name, {})
	material.albedo_color = ROBOT_MODEL_PLATE_COLOR
	return material


func _base_material_for_link(link_name: String) -> StandardMaterial3D:
	var material := _material_for_link(link_name, {})
	material.albedo_color = ROBOT_MODEL_BASE_COLOR
	return material


func _rim_material(_alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.42
	material.metallic = 0.0
	material.albedo_color = ROBOT_MODEL_MID_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_configure_top_material(material)
	return material


func _nose_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.38
	material.metallic = 0.0
	material.albedo_color = ROBOT_MODEL_NOSE_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_configure_top_material(material)
	return material


func _sensor_material(_alpha := 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.24
	material.metallic = 0.0
	material.albedo_color = ROBOT_MODEL_SENSOR_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_configure_top_material(material)
	return material


func _configure_top_material(material: StandardMaterial3D) -> void:
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 80


func _color_for_link(link_name: String, filename: String) -> Color:
	var descriptor := (link_name + " " + filename).to_lower()
	if _is_drive_wheel_descriptor(descriptor):
		return ROBOT_MODEL_DARK_COLOR
	if _is_lidar_descriptor(descriptor):
		return ROBOT_MODEL_LIDAR_COLOR
	if _is_caster_descriptor(descriptor):
		return ROBOT_MODEL_MID_COLOR
	if descriptor.contains("plate"):
		return ROBOT_MODEL_PLATE_COLOR
	if _is_base_descriptor(descriptor):
		return ROBOT_MODEL_BASE_COLOR
	return ROBOT_MODEL_BASE_COLOR


func _is_drive_wheel_descriptor(value: String) -> bool:
	var descriptor := value.to_lower()
	return descriptor.contains("wheel") and not _is_caster_descriptor(descriptor)


func _is_caster_descriptor(value: String) -> bool:
	var descriptor := value.to_lower()
	return descriptor.contains("caster") or descriptor.contains("roller")


func _is_lidar_descriptor(value: String) -> bool:
	var descriptor := value.to_lower()
	return (
		descriptor.contains("laser")
		or descriptor.contains("lidar")
		or descriptor.contains("scan")
		or descriptor.contains("lds")
		or descriptor.contains("hokuyo")
		or descriptor.contains("rplidar")
	)


func _is_primary_base_descriptor(value: String) -> bool:
	var descriptor := value.to_lower()
	return (
		descriptor.contains("base_link")
		or descriptor.contains("chassis")
		or descriptor.contains("burger_base")
	)


func _is_base_descriptor(value: String) -> bool:
	return _is_primary_base_descriptor(value) or value.to_lower().contains("plate")


func _safe_node_name(value: String) -> String:
	var clean := value.replace("/", "_").replace(":", "_").replace(" ", "_")
	return clean if not clean.is_empty() else "link"
