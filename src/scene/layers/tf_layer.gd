extends "res://src/scene/layers/visualization_layer.gd"
class_name RcsTfLayer

@export var y_offset := 0.28
@export var axis_length := 0.32
@export var max_frames := 80
@export var min_rebuild_interval_msec := 250

var frame_root: Node3D
var edge_store: Dictionary = {}
var last_rebuild_msec := 0


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

	_merge_edges(_state.get("tf_static"))
	_merge_edges(_state.get("tf"))

	var frames := _resolved_frames(edge_store)
	if frames.is_empty():
		var fallback := _frame_from_robot_pose(_state.get("robot_pose"))
		if not fallback.is_empty():
			frames["base_link"] = fallback

	_rebuild_frames(frames)


func _merge_edges(message: Variant) -> void:
	var transforms := _transforms_from(message)
	for transform_value in transforms:
		if typeof(transform_value) != TYPE_DICTIONARY:
			continue
		var transform: Dictionary = transform_value
		var parent := _parent_frame_id(transform)
		var child := _normalize_frame_id(str(transform.get("child_frame_id", "")))
		if parent.is_empty() or child.is_empty():
			continue
		var pose := _pose_from_transform(transform.get("transform", {}))
		pose["parent"] = parent
		edge_store[child] = pose


func _transforms_from(message: Variant) -> Array:
	if typeof(message) != TYPE_DICTIONARY:
		return []
	var transforms: Variant = (message as Dictionary).get("transforms", [])
	return transforms if typeof(transforms) == TYPE_ARRAY else []


func _parent_frame_id(transform: Dictionary) -> String:
	var header: Variant = transform.get("header", {})
	if typeof(header) == TYPE_DICTIONARY:
		return _normalize_frame_id(str((header as Dictionary).get("frame_id", "")))
	return ""


func _pose_from_transform(transform_value: Variant) -> Dictionary:
	if typeof(transform_value) != TYPE_DICTIONARY:
		return {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
	var transform: Dictionary = transform_value
	var translation: Variant = transform.get("translation", {})
	var rotation: Variant = transform.get("rotation", {})
	var x := 0.0
	var y := 0.0
	var z := 0.0
	if typeof(translation) == TYPE_DICTIONARY:
		x = float((translation as Dictionary).get("x", 0.0))
		y = float((translation as Dictionary).get("y", 0.0))
		z = float((translation as Dictionary).get("z", 0.0))
	return {
		"x": x,
		"y": y,
		"z": z,
		"yaw": _yaw_from_rotation(rotation),
	}


func _resolved_frames(edges: Dictionary) -> Dictionary:
	var frames := {}
	var cache := {
		"map": {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0},
	}
	var frame_names := edges.keys()
	frame_names.sort()
	for frame_id in frame_names:
		if frames.size() >= max_frames:
			break
		var resolved: Variant = _resolve_frame(str(frame_id), edges, cache, 0)
		if typeof(resolved) == TYPE_DICTIONARY:
			frames[str(frame_id)] = resolved
	if not frames.is_empty():
		frames["map"] = cache["map"]
	return frames


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
	var parent_pose: Variant = _resolve_frame(parent, edges, cache, depth + 1)
	if typeof(parent_pose) != TYPE_DICTIONARY:
		return null

	var parent_yaw := float((parent_pose as Dictionary).get("yaw", 0.0))
	var local_x := float(edge.get("x", 0.0))
	var local_y := float(edge.get("y", 0.0))
	var cos_yaw := cos(parent_yaw)
	var sin_yaw := sin(parent_yaw)
	var resolved := {
		"x": float((parent_pose as Dictionary).get("x", 0.0)) + (local_x * cos_yaw) - (local_y * sin_yaw),
		"y": float((parent_pose as Dictionary).get("y", 0.0)) + (local_x * sin_yaw) + (local_y * cos_yaw),
		"z": float((parent_pose as Dictionary).get("z", 0.0)) + float(edge.get("z", 0.0)),
		"yaw": parent_yaw + float(edge.get("yaw", 0.0)),
	}
	cache[clean_frame] = resolved
	return resolved


func _frame_from_robot_pose(robot_pose: Variant) -> Dictionary:
	if typeof(robot_pose) != TYPE_DICTIONARY or (robot_pose as Dictionary).is_empty():
		return {}
	var pose_dict: Dictionary = robot_pose
	if pose_dict.has("x") or pose_dict.has("y"):
		return {
			"x": float(pose_dict.get("x", 0.0)),
			"y": float(pose_dict.get("y", 0.0)),
			"z": 0.0,
			"yaw": float(pose_dict.get("yaw", pose_dict.get("theta", 0.0))),
		}

	var pose_value: Variant = pose_dict.get("pose", pose_dict)
	if typeof(pose_value) == TYPE_DICTIONARY and (pose_value as Dictionary).has("pose"):
		pose_value = (pose_value as Dictionary)["pose"]
	if typeof(pose_value) != TYPE_DICTIONARY:
		return {}

	var nested_pose: Dictionary = pose_value
	var position_value: Variant = nested_pose.get("position", {})
	var orientation_value: Variant = nested_pose.get("orientation", {})
	return {
		"x": float((position_value as Dictionary).get("x", 0.0)) if typeof(position_value) == TYPE_DICTIONARY else 0.0,
		"y": float((position_value as Dictionary).get("y", 0.0)) if typeof(position_value) == TYPE_DICTIONARY else 0.0,
		"z": float((position_value as Dictionary).get("z", 0.0)) if typeof(position_value) == TYPE_DICTIONARY else 0.0,
		"yaw": _yaw_from_rotation(orientation_value),
	}


func _rebuild_frames(frames: Dictionary) -> void:
	for child in frame_root.get_children():
		child.queue_free()

	var frame_names := frames.keys()
	frame_names.sort()
	for frame_id in frame_names:
		var pose: Dictionary = frames[frame_id]
		_add_frame_axes(str(frame_id), pose)


func _add_frame_axes(frame_id: String, pose: Dictionary) -> void:
	var frame := Node3D.new()
	frame.name = _safe_node_name(frame_id)
	frame.position = Vector3(
		float(pose.get("x", 0.0)),
		y_offset + float(pose.get("z", 0.0)),
		-float(pose.get("y", 0.0))
	)
	frame.rotation.y = -float(pose.get("yaw", 0.0))
	frame_root.add_child(frame)

	var x_axis := _axis_mesh(Color(0.95, 0.22, 0.18), Vector3(axis_length, 0.018, 0.018))
	x_axis.position.x = axis_length * 0.5
	frame.add_child(x_axis)

	var y_axis := _axis_mesh(Color(0.18, 0.78, 0.26), Vector3(0.018, 0.018, axis_length))
	y_axis.position.z = -axis_length * 0.5
	frame.add_child(y_axis)

	var z_axis := _axis_mesh(Color(0.18, 0.46, 1.0), Vector3(0.018, axis_length, 0.018))
	z_axis.position.y = axis_length * 0.5
	frame.add_child(z_axis)

	var center_mesh := SphereMesh.new()
	center_mesh.radius = 0.028
	center_mesh.height = 0.056
	var center := MeshInstance3D.new()
	center.name = "origin"
	center.mesh = center_mesh
	center.material_override = _axis_material(Color(1.0, 0.76, 0.18))
	center.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	frame.add_child(center)


func _axis_mesh(color: Color, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _axis_material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _axis_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material


func _yaw_from_rotation(value: Variant) -> float:
	if typeof(value) != TYPE_DICTIONARY:
		return 0.0
	var rotation: Dictionary = value
	if rotation.has("yaw"):
		return float(rotation.get("yaw", 0.0))
	var x := float(rotation.get("x", 0.0))
	var y := float(rotation.get("y", 0.0))
	var z := float(rotation.get("z", 0.0))
	var w := float(rotation.get("w", 1.0))
	return atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))


func _normalize_frame_id(value: String) -> String:
	var clean := value.strip_edges()
	return clean.substr(1) if clean.begins_with("/") else clean


func _safe_node_name(value: String) -> String:
	var clean := value.replace("/", "_").replace(":", "_").replace(" ", "_")
	return clean if not clean.is_empty() else "frame"
