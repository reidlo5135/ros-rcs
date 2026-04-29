extends "res://src/scene/layers/visualization_layer.gd"
class_name RcsMapLayer

signal map_layout_changed(center: Vector3, width_meters: float, height_meters: float)

@export var palette := "map"
@export var source_key := "map"
@export var y_offset := 0.005
@export var show_debug_origin := false
@export var min_rebuild_interval_msec := 120

var map_mesh: MeshInstance3D
var origin_marker: Node3D
var border_mesh: MeshInstance3D
var last_signature := ""
var last_rebuild_msec := 0
var native_occupancy_codec: Object = null


func _init() -> void:
	layer_id = "map"


func _ready() -> void:
	if ClassDB.class_exists("RcsOccupancyCodec"):
		native_occupancy_codec = ClassDB.instantiate("RcsOccupancyCodec")


func apply_state(_state: Variant) -> void:
	var grid: Variant = _state.get(source_key)
	if typeof(grid) != TYPE_DICTIONARY:
		return
	if (grid as Dictionary).is_empty():
		return

	var now := Time.get_ticks_msec()
	if last_rebuild_msec > 0 and now - last_rebuild_msec < min_rebuild_interval_msec:
		return

	var signature := _grid_signature(grid)
	if signature == last_signature:
		return
	last_signature = signature
	last_rebuild_msec = now
	_rebuild_grid(grid)


func _rebuild_grid(grid: Dictionary) -> void:
	if map_mesh != null:
		map_mesh.queue_free()
		map_mesh = null
	if origin_marker != null:
		origin_marker.queue_free()
		origin_marker = null
	if border_mesh != null:
		border_mesh.queue_free()
		border_mesh = null

	var info := _grid_info(grid)
	var width := int(info.get("width", 0))
	var height := int(info.get("height", 0))
	var resolution := float(info.get("resolution", 0.05))
	if width <= 0 or height <= 0 or resolution <= 0.0:
		return

	var texture := _build_occupancy_texture(grid, width, height)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.no_depth_test = palette != "map"
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if palette == "map" else BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = -10 if palette == "map" else -5

	var plane := PlaneMesh.new()
	plane.size = Vector2(width * resolution, height * resolution)

	map_mesh = MeshInstance3D.new()
	map_mesh.name = "SlamMap"
	map_mesh.mesh = plane
	map_mesh.material_override = material

	var origin := _origin(info)
	var origin_position := _position_dict(origin)
	var origin_yaw := _yaw_from_pose(origin)
	var center := _rotate_2d(width * resolution * 0.5, height * resolution * 0.5, origin_yaw)
	map_mesh.position = Vector3(
		float(origin_position.get("x", 0.0)) + center.x,
		y_offset,
		-(float(origin_position.get("y", 0.0)) + center.y)
	)
	map_mesh.rotation.y = -origin_yaw
	add_child(map_mesh)
	_build_border(width * resolution, height * resolution, map_mesh.position, origin_yaw)
	if show_debug_origin:
		_build_origin_marker(origin_position, origin_yaw)
	map_layout_changed.emit(map_mesh.position, width * resolution, height * resolution)


func _build_occupancy_texture(grid: Dictionary, width: int, height: int) -> ImageTexture:
	var data := _grid_data(grid)
	var bytes := _build_rgba_bytes(data, width, height)
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(image)


func _build_rgba_bytes(data: Array, width: int, height: int) -> PackedByteArray:
	if native_occupancy_codec != null and native_occupancy_codec.has_method("build_rgba"):
		var native_bytes: Variant = native_occupancy_codec.call("build_rgba", data, width, height, palette)
		if typeof(native_bytes) == TYPE_PACKED_BYTE_ARRAY and (native_bytes as PackedByteArray).size() == width * height * 4:
			return native_bytes

	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	for row in range(height):
		for column in range(width):
			var source_index := row * width + column
			var target_row := height - 1 - row
			var target_index := ((target_row * width) + column) * 4
			var value := -1
			if source_index < data.size():
				value = int(data[source_index])
			var color := _occupancy_color(value)
			bytes[target_index] = color[0]
			bytes[target_index + 1] = color[1]
			bytes[target_index + 2] = color[2]
			bytes[target_index + 3] = color[3]
	return bytes


func _build_origin_marker(origin_position: Dictionary, origin_yaw: float) -> void:
	origin_marker = Node3D.new()
	origin_marker.name = "MapOrigin"
	origin_marker.position = Vector3(
		float(origin_position.get("x", 0.0)),
		y_offset + 0.04,
		-float(origin_position.get("y", 0.0))
	)
	origin_marker.rotation.y = -origin_yaw
	add_child(origin_marker)

	var x_axis := _axis_mesh(Color(0.95, 0.22, 0.18), Vector3(0.35, 0.012, 0.012))
	x_axis.position.x = 0.175
	origin_marker.add_child(x_axis)

	var y_axis := _axis_mesh(Color(0.18, 0.55, 1.0), Vector3(0.012, 0.012, 0.35))
	y_axis.position.z = -0.175
	origin_marker.add_child(y_axis)

	var center := SphereMesh.new()
	center.radius = 0.035
	center.height = 0.07
	var center_node := MeshInstance3D.new()
	center_node.name = "OriginDot"
	center_node.mesh = center
	center_node.material_override = _axis_material(Color(1.0, 0.9, 0.15))
	origin_marker.add_child(center_node)


func _build_border(width_meters: float, height_meters: float, center_position: Vector3, origin_yaw: float) -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.05, 0.05, 0.06)

	var half_width := width_meters * 0.5
	var half_height := height_meters * 0.5
	var corners := [
		Vector3(-half_width, 0.0, -half_height),
		Vector3(half_width, 0.0, -half_height),
		Vector3(half_width, 0.0, half_height),
		Vector3(-half_width, 0.0, half_height),
	]

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(corners.size()):
		mesh.surface_add_vertex(corners[index])
		mesh.surface_add_vertex(corners[(index + 1) % corners.size()])
	mesh.surface_end()

	border_mesh = MeshInstance3D.new()
	border_mesh.name = "MapBorder"
	border_mesh.mesh = mesh
	border_mesh.position = center_position + Vector3(0.0, 0.035, 0.0)
	border_mesh.rotation.y = -origin_yaw
	add_child(border_mesh)


func _axis_mesh(color: Color, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _axis_material(color)
	return node


func _axis_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


func _occupancy_color(value: int) -> PackedInt32Array:
	if palette == "map":
		if value < 0:
			return PackedInt32Array([201, 201, 201, 255])
		if value >= 50:
			return PackedInt32Array([36, 22, 48, 255])
		return PackedInt32Array([255, 255, 255, 255])

	if value <= 0:
		return PackedInt32Array([0, 0, 0, 0])
	var normalized: float = clamp(float(value) / 100.0, 0.0, 1.0)
	var alpha := int(45.0 + (normalized * 165.0))
	if palette == "local_costmap":
		return PackedInt32Array([188, 76, 175, alpha])
	return PackedInt32Array([150, 82, 185, alpha])


func _grid_signature(grid: Dictionary) -> String:
	var info := _grid_info(grid)
	var data := _grid_data(grid)
	var checksum := 0
	for value in data:
		checksum = int((checksum + int(value)) % 1000003)
	return "%s:%s:%s:%s:%s" % [
		info.get("width", 0),
		info.get("height", 0),
		info.get("resolution", 0.0),
		data.size(),
		checksum,
	]


func _grid_info(grid: Dictionary) -> Dictionary:
	var info: Variant = grid.get("info", {})
	return info if typeof(info) == TYPE_DICTIONARY else {}


func _grid_data(grid: Dictionary) -> Array:
	var data: Variant = grid.get("data", [])
	if typeof(data) == TYPE_ARRAY:
		return data
	if typeof(data) == TYPE_PACKED_BYTE_ARRAY:
		var values := []
		for value in data:
			values.append(int(value))
		return values
	if typeof(data) == TYPE_PACKED_INT32_ARRAY:
		var values := []
		for value in data:
			values.append(int(value))
		return values
	return []


func _origin(info: Dictionary) -> Dictionary:
	var origin: Variant = info.get("origin", {})
	return origin if typeof(origin) == TYPE_DICTIONARY else {}


func _position_dict(pose: Dictionary) -> Dictionary:
	var position: Variant = pose.get("position", {})
	return position if typeof(position) == TYPE_DICTIONARY else {}


func _yaw_from_pose(pose: Dictionary) -> float:
	var orientation: Variant = pose.get("orientation", {})
	if typeof(orientation) != TYPE_DICTIONARY:
		return 0.0
	if (orientation as Dictionary).has("yaw"):
		return float((orientation as Dictionary).get("yaw", 0.0))
	var x := float((orientation as Dictionary).get("x", 0.0))
	var y := float((orientation as Dictionary).get("y", 0.0))
	var z := float((orientation as Dictionary).get("z", 0.0))
	var w := float((orientation as Dictionary).get("w", 1.0))
	return atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))


func _rotate_2d(x: float, y: float, yaw: float) -> Vector2:
	var cos_yaw := cos(yaw)
	var sin_yaw := sin(yaw)
	return Vector2(
		(x * cos_yaw) - (y * sin_yaw),
		(x * sin_yaw) + (y * cos_yaw)
	)
