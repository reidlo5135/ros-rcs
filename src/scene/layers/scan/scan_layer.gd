extends "res://src/scene/layers/base/visualization_layer.gd"
class_name RcsScanLayer

@export var y_offset := 0.02
@export var max_points := 720
@export var min_rebuild_interval_msec := 80

var scan_mesh: MeshInstance3D
var tf_provider: Node = null
var native_projector: Object = null
var last_signature := ""
var last_rebuild_msec := 0


func _init() -> void:
	layer_id = "scan"


func _ready() -> void:
	if ClassDB.class_exists("RcsLaserScanProjector"):
		native_projector = ClassDB.instantiate("RcsLaserScanProjector")


func apply_state(_state: Variant) -> void:
	var scan: Variant = _state.get("scan")
	if typeof(scan) != TYPE_DICTIONARY or (scan as Dictionary).is_empty():
		return

	var now := Time.get_ticks_msec()
	if last_rebuild_msec > 0 and now - last_rebuild_msec < min_rebuild_interval_msec:
		return

	var signature := _scan_signature(scan)
	if signature == last_signature:
		return
	last_signature = signature
	last_rebuild_msec = now
	_rebuild_scan(scan as Dictionary, _state.get("robot_pose"))


func _rebuild_scan(scan: Dictionary, robot_pose: Variant) -> void:
	var frame_transform := _scan_frame_transform(scan, robot_pose)
	var points := _project_points(scan, frame_transform)
	if points.is_empty():
		return

	if scan_mesh != null:
		scan_mesh.queue_free()
		scan_mesh = null

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _scan_material())
	var stride = maxi(1, int(ceil(float(points.size()) / float(max_points))))
	const CROSS := 0.025
	for index in range(0, points.size(), stride):
		var pt := points[index] + Vector3(0.0, y_offset, 0.0)
		mesh.surface_add_vertex(pt + Vector3(-CROSS, 0.0, 0.0))
		mesh.surface_add_vertex(pt + Vector3(CROSS, 0.0, 0.0))
		mesh.surface_add_vertex(pt + Vector3(0.0, 0.0, -CROSS))
		mesh.surface_add_vertex(pt + Vector3(0.0, 0.0, CROSS))
	mesh.surface_end()

	scan_mesh = MeshInstance3D.new()
	scan_mesh.name = "LaserScanPoints"
	scan_mesh.mesh = mesh
	scan_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scan_mesh)


func _project_points(scan: Dictionary, frame_transform: Transform3D) -> PackedVector3Array:
	if native_projector != null and native_projector.has_method("project"):
		var native_points: Variant = native_projector.call("project", scan, frame_transform)
		if typeof(native_points) == TYPE_PACKED_VECTOR3_ARRAY:
			return native_points

	var points := PackedVector3Array()
	var ranges: Array = _ranges(scan)
	if ranges.is_empty():
		return points
	var angle_min := float(scan.get("angle_min", 0.0))
	var angle_increment := float(scan.get("angle_increment", 0.0))
	var range_min := float(scan.get("range_min", 0.0))
	var range_max := float(scan.get("range_max", 100.0))
	for index in range(ranges.size()):
		var value: Variant = ranges[index]
		if value == null:
			continue
		var distance := float(value)
		if distance <= range_min or distance > range_max or is_nan(distance) or is_inf(distance):
			continue
		var angle := angle_min + angle_increment * float(index)
		var local_point := Vector3(cos(angle) * distance, 0.0, -sin(angle) * distance)
		points.append(frame_transform * local_point)
	return points


func _scan_frame_transform(scan: Dictionary, robot_pose: Variant) -> Transform3D:
	var frame_id := _scan_frame_id(scan)
	if tf_provider != null and tf_provider.has_method("frame_transform"):
		var resolved: Variant = tf_provider.call("frame_transform", frame_id)
		if typeof(resolved) == TYPE_TRANSFORM3D:
			return resolved as Transform3D
		for fallback_frame in ["base_scan", "base_link", "base_footprint"]:
			resolved = tf_provider.call("frame_transform", fallback_frame)
			if typeof(resolved) == TYPE_TRANSFORM3D:
				return resolved as Transform3D
	var pose_transform: Variant = _frame_transform_from_robot_pose(robot_pose)
	return pose_transform if typeof(pose_transform) == TYPE_TRANSFORM3D else Transform3D.IDENTITY


func _scan_frame_id(scan: Dictionary) -> String:
	var frame := str(scan.get("frame", "")).strip_edges()
	if not frame.is_empty():
		return frame
	var header: Variant = scan.get("header", {})
	if typeof(header) == TYPE_DICTIONARY:
		frame = str((header as Dictionary).get("frame_id", "")).strip_edges()
		if not frame.is_empty():
			return frame
	return "base_scan"


func _ranges(scan: Dictionary) -> Array:
	var value: Variant = scan.get("ranges", [])
	if typeof(value) == TYPE_ARRAY:
		return value
	if typeof(value) == TYPE_PACKED_FLOAT32_ARRAY or typeof(value) == TYPE_PACKED_FLOAT64_ARRAY:
		var result := []
		for item in value:
			result.append(float(item))
		return result
	return []


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


func _scan_signature(scan: Dictionary) -> String:
	var ranges := _ranges(scan)
	var checksum := 0
	for index in range(0, ranges.size(), maxi(1, int(ranges.size() / 64))):
		var value: Variant = ranges[index]
		if value != null:
			checksum = int((checksum + int(float(value) * 1000.0)) % 1000003)
	return "%s:%s:%s:%s:%s:%s" % [
		_scan_frame_id(scan),
		scan.get("angle_min", 0.0),
		scan.get("angle_increment", 0.0),
		ranges.size(),
		scan.get("range_min", 0.0),
		checksum,
	]


func _scan_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 1.0, 0.46, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 42
	return material
