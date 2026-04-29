extends "res://src/scene/layers/base/visualization_layer.gd"
class_name RcsTfLayer

@export var y_offset := 0.02
@export var axis_length := 0.5
@export var max_frames := 80
@export var min_rebuild_interval_msec := 250

var frame_root: Node3D
var static_edge_store: Dictionary = {}
var live_edge_store: Dictionary = {}
var frame_nodes: Dictionary = {}
var last_rebuild_msec := 0
var last_frames: Dictionary = {}


func _init() -> void:
	layer_id = "tf"


func _ready() -> void:
	frame_root = Node3D.new()
	frame_root.name = "TfFrames"
	add_child(frame_root)


func apply_state(_state: Variant) -> void:
	if frame_root == null:
		return

	var now := Time.get_ticks_msec()
	if last_rebuild_msec > 0 and now - last_rebuild_msec < min_rebuild_interval_msec:
		return
	last_rebuild_msec = now

	_merge_edges_into(static_edge_store, _state.get("tf_static"))
	_merge_edges_into(live_edge_store, _state.get("tf"))
	var edges := static_edge_store.duplicate(true)
	for child_frame in live_edge_store.keys():
		edges[child_frame] = live_edge_store[child_frame]
	_merge_urdf_edges(_state.get("urdf_model"), edges)

	var frames := _resolved_frames(edges, _state.get("robot_pose"))
	if frames.is_empty():
		var fallback: Variant = _frame_transform_from_robot_pose(_state.get("robot_pose"))
		if typeof(fallback) == TYPE_TRANSFORM3D:
			frames["base_link"] = fallback
	if frames.is_empty() and not last_frames.is_empty():
		_rebuild_frames(last_frames)
		return

	last_frames = frames.duplicate(true)
	_rebuild_frames(frames)


func _merge_edges_into(store: Dictionary, message: Variant) -> void:
	var transforms := _transforms_from(message)
	for transform_value in transforms:
		if typeof(transform_value) != TYPE_DICTIONARY:
			continue
		var transform: Dictionary = transform_value
		var parent := _parent_frame_id(transform)
		var child := _child_frame_id(transform)
		if parent.is_empty() or child.is_empty():
			continue
		store[child] = {
			"parent": parent,
			"transform": _transform_from_tf(transform),
		}


func _merge_urdf_edges(urdf_model: Variant, edges: Dictionary) -> void:
	if typeof(urdf_model) != TYPE_DICTIONARY:
		return
	var model: Dictionary = urdf_model
	var joints: Dictionary = model.get("joints", {})
	var joint_order: Array = model.get("joint_order", [])
	for joint_name_value in joint_order:
		var joint_name := str(joint_name_value)
		if not joints.has(joint_name):
			continue
		var joint: Dictionary = joints[joint_name]
		var parent := _normalize_frame_id(str(joint.get("parent", "")))
		var child := _normalize_frame_id(str(joint.get("child", "")))
		if parent.is_empty() or child.is_empty() or edges.has(child):
			continue
		edges[child] = {
			"parent": parent,
			"transform": _transform_from_origin(joint.get("origin", {})),
		}


func _transforms_from(message: Variant) -> Array:
	if typeof(message) != TYPE_DICTIONARY:
		return []
	var transforms: Variant = (message as Dictionary).get("transforms", [])
	return transforms if typeof(transforms) == TYPE_ARRAY else []


func _parent_frame_id(transform: Dictionary) -> String:
	var header: Variant = transform.get("header", {})
	if typeof(header) == TYPE_DICTIONARY:
		var header_frame := _normalize_frame_id(str((header as Dictionary).get("frame_id", "")))
		if not header_frame.is_empty():
			return header_frame
	for key in ["parent_frame_id", "parent_frame", "parent", "frame_id", "frame"]:
		var candidate := _normalize_frame_id(str(transform.get(key, "")))
		if not candidate.is_empty():
			return candidate
	return ""


func _child_frame_id(transform: Dictionary) -> String:
	for key in ["child_frame_id", "child_frame", "child"]:
		var candidate := _normalize_frame_id(str(transform.get(key, "")))
		if not candidate.is_empty():
			return candidate
	return ""


func _transform_from_tf(transform_value: Variant) -> Transform3D:
	if typeof(transform_value) != TYPE_DICTIONARY:
		return Transform3D.IDENTITY
	var transform: Dictionary = transform_value
	var source_value: Variant = transform.get("transform", transform)
	var source: Dictionary = source_value as Dictionary if typeof(source_value) == TYPE_DICTIONARY else transform
	var translation: Variant = source.get("translation", transform.get("translation", {}))
	var rotation: Variant = source.get("rotation", transform.get("rotation", {}))
	var x := 0.0
	var y := 0.0
	var z := 0.0
	if typeof(translation) == TYPE_DICTIONARY:
		x = float((translation as Dictionary).get("x", 0.0))
		y = float((translation as Dictionary).get("y", 0.0))
		z = float((translation as Dictionary).get("z", 0.0))
	return Transform3D(
		Basis.from_euler(_rotation_from_quaternion(rotation)),
		Vector3(x, z, -y)
	)


func _resolved_frames(edges: Dictionary, robot_pose: Variant) -> Dictionary:
	var frames := {}
	var cache := _root_frame_cache(edges)
	var frame_names := edges.keys()
	frame_names.sort()
	for frame_id in frame_names:
		if frames.size() >= max_frames:
			break
		var resolved: Variant = _resolve_frame(str(frame_id), edges, cache, 0)
		if typeof(resolved) == TYPE_TRANSFORM3D:
			frames[str(frame_id)] = resolved
	for root_frame in ["map", "odom", "base_footprint", "base_link"]:
		if cache.has(root_frame) and not frames.has(root_frame):
			frames[root_frame] = cache[root_frame]
	var fallback: Variant = _frame_transform_from_robot_pose(robot_pose)
	if typeof(fallback) == TYPE_TRANSFORM3D:
		if not frames.has("base_link"):
			frames["base_link"] = fallback
		if not frames.has("base_footprint"):
			frames["base_footprint"] = fallback
	return frames


func _root_frame_cache(edges: Dictionary) -> Dictionary:
	var cache := {
		"map": Transform3D.IDENTITY,
	}
	for child_frame in edges.keys():
		var edge_value: Variant = edges.get(child_frame, {})
		if typeof(edge_value) != TYPE_DICTIONARY:
			continue
		var parent := _normalize_frame_id(str((edge_value as Dictionary).get("parent", "")))
		if parent.is_empty() or edges.has(parent) or cache.has(parent):
			continue
		cache[parent] = Transform3D.IDENTITY
	return cache


func _resolve_frame(frame_id: String, edges: Dictionary, cache: Dictionary, depth: int) -> Variant:
	var clean_frame := _normalize_frame_id(frame_id)
	if clean_frame.is_empty() or depth > max_frames:
		return null
	if cache.has(clean_frame):
		return cache[clean_frame]
	if not edges.has(clean_frame):
		return null

	var edge: Dictionary = edges[clean_frame]
	var parent := _normalize_frame_id(str(edge.get("parent", "")))
	var parent_transform: Variant = _resolve_frame(parent, edges, cache, depth + 1)
	if typeof(parent_transform) != TYPE_TRANSFORM3D:
		return null

	var local_transform: Variant = edge.get("transform", Transform3D.IDENTITY)
	if typeof(local_transform) != TYPE_TRANSFORM3D:
		local_transform = Transform3D.IDENTITY
	var resolved: Transform3D = (parent_transform as Transform3D) * (local_transform as Transform3D)
	cache[clean_frame] = resolved
	return resolved


func _frame_transform_from_robot_pose(robot_pose: Variant) -> Variant:
	if typeof(robot_pose) != TYPE_DICTIONARY or (robot_pose as Dictionary).is_empty():
		return null
	var pose_dict: Dictionary = robot_pose
	if pose_dict.has("x") or pose_dict.has("y"):
		var yaw := float(pose_dict.get("yaw", pose_dict.get("theta", 0.0)))
		return Transform3D(
			Basis.from_euler(Vector3(0.0, yaw, 0.0)),
			Vector3(float(pose_dict.get("x", 0.0)), 0.0, -float(pose_dict.get("y", 0.0)))
		)

	var pose_value: Variant = pose_dict.get("pose", pose_dict)
	if typeof(pose_value) == TYPE_DICTIONARY and (pose_value as Dictionary).has("pose"):
		pose_value = (pose_value as Dictionary)["pose"]
	if typeof(pose_value) != TYPE_DICTIONARY:
		return null

	var nested_pose: Dictionary = pose_value
	var position_value: Variant = nested_pose.get("position", {})
	var orientation_value: Variant = nested_pose.get("orientation", {})
	var position := Vector3.ZERO
	if typeof(position_value) == TYPE_DICTIONARY:
		var source_position := position_value as Dictionary
		position = Vector3(
			float(source_position.get("x", 0.0)),
			float(source_position.get("z", 0.0)),
			-float(source_position.get("y", 0.0))
		)
	return Transform3D(Basis.from_euler(_rotation_from_quaternion(orientation_value)), position)


func _rebuild_frames(frames: Dictionary) -> void:
	for frame_id in frame_nodes.keys():
		if not frames.has(frame_id):
			frame_nodes[frame_id].queue_free()
			frame_nodes.erase(frame_id)

	for frame_id in frames.keys():
		var frame_transform: Transform3D = frames[frame_id]
		var adjusted := frame_transform
		adjusted.origin += Vector3(0.0, y_offset, 0.0)
		if frame_nodes.has(frame_id):
			frame_nodes[frame_id].transform = adjusted
		else:
			_add_frame_axes(str(frame_id), frame_transform)


func frame_transform(frame_id: String) -> Variant:
	var clean := _normalize_frame_id(frame_id)
	if clean.is_empty():
		return null
	if last_frames.has(clean):
		return last_frames[clean]
	var alias := _frame_alias(clean)
	if last_frames.has(alias):
		return last_frames[alias]
	if clean == "map":
		return Transform3D.IDENTITY
	return null


func has_frame(frame_id: String) -> bool:
	return typeof(frame_transform(frame_id)) == TYPE_TRANSFORM3D


func _add_frame_axes(frame_id: String, frame_transform: Transform3D) -> void:
	var frame := Node3D.new()
	frame.name = _safe_node_name(frame_id)
	var adjusted := frame_transform
	adjusted.origin += Vector3(0.0, y_offset, 0.0)
	frame.transform = adjusted
	frame_root.add_child(frame)
	frame_nodes[frame_id] = frame

	var x_axis := _cylinder_axis_node(Color(0.95, 0.22, 0.18), axis_length)
	x_axis.position.x = axis_length * 0.5
	x_axis.rotation_degrees.z = -90.0
	frame.add_child(x_axis)

	var y_axis := _cylinder_axis_node(Color(0.18, 0.78, 0.26), axis_length)
	y_axis.position.z = -axis_length * 0.5
	y_axis.rotation_degrees.x = -90.0
	frame.add_child(y_axis)

	var z_axis := _cylinder_axis_node(Color(0.18, 0.46, 1.0), axis_length)
	z_axis.position.y = axis_length * 0.5
	frame.add_child(z_axis)

	var center_mesh := SphereMesh.new()
	center_mesh.radius = 0.038
	center_mesh.height = 0.076
	var center := MeshInstance3D.new()
	center.name = "origin"
	center.mesh = center_mesh
	center.material_override = _axis_material(Color(1.0, 0.76, 0.18))
	center.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.add_child(center)


func _cylinder_axis_node(color: Color, length: float) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.022
	cylinder.bottom_radius = 0.022
	cylinder.height = length
	cylinder.radial_segments = 8
	var node := MeshInstance3D.new()
	node.mesh = cylinder
	node.material_override = _axis_material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _axis_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 55
	return material


func _rotation_from_quaternion(value: Variant) -> Vector3:
	if typeof(value) != TYPE_DICTIONARY:
		return Vector3.ZERO
	var rotation: Dictionary = value
	if rotation.has("yaw"):
		return Vector3(0.0, float(rotation.get("yaw", 0.0)), 0.0)
	var x := float(rotation.get("x", 0.0))
	var y := float(rotation.get("y", 0.0))
	var z := float(rotation.get("z", 0.0))
	var w := float(rotation.get("w", 1.0))
	var roll := atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
	var sin_pitch := 2.0 * (w * y - z * x)
	var pitch := asin(clamp(sin_pitch, -1.0, 1.0))
	var yaw := atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
	return Vector3(roll, yaw, pitch)


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


func _normalize_frame_id(value: String) -> String:
	var clean := value.strip_edges()
	return clean.substr(1) if clean.begins_with("/") else clean


func _frame_alias(frame_id: String) -> String:
	var clean := frame_id.strip_edges().to_lower()
	match clean:
		"basefootprint":
			return "base_footprint"
		"baselink":
			return "base_link"
		"basescan":
			return "base_scan"
		_:
			return frame_id


func _safe_node_name(value: String) -> String:
	var clean := value.replace("/", "_").replace(":", "_").replace(" ", "_")
	return clean if not clean.is_empty() else "frame"
