extends Node3D

signal waypoint_placed(position: Vector3, yaw: float)

const MapLayerScript: Script = preload("res://src/scene/layers/map_layer.gd")
const RobotLayerScript: Script = preload("res://src/scene/layers/robot_layer.gd")
const ScanLayerScript: Script = preload("res://src/scene/layers/scan_layer.gd")
const TfLayerScript: Script = preload("res://src/scene/layers/tf_layer.gd")

const GRID_SIZE := 24
const GRID_STEP := 1.0
const GRID_Y_OFFSET := 0.075
const CAMERA_MIN_ORTHO_SIZE := 1.2
const CAMERA_MAX_ORTHO_SIZE := 80.0
const CAMERA_MIN_HEIGHT := 4.0
const CAMERA_MAX_HEIGHT := 120.0
const CAMERA_ROLL_LIMIT := deg_to_rad(50.0)
const WAYPOINT_Y_OFFSET := 0.11
const ROBOT_TOP_LAYER_Y := 0.12

var camera: Camera3D
var floor_layer: MeshInstance3D
var metric_grid: MeshInstance3D
var map_layer: Node3D
var global_costmap_layer: Node3D
var local_costmap_layer: Node3D
var global_path_layer: MeshInstance3D
var local_path_layer: MeshInstance3D
var robot_layer: Node3D
var tf_layer: Node3D
var scan_layer: Node3D
var camera_target := Vector3.ZERO
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(-90.0)
var camera_roll := 0.0
var camera_distance := 32.0
var orthographic_size := 18.0
var top_down_mode := true
var orbiting := false
var panning := false
var grabbing := false
var map_auto_framed := false
var waypoint_placement_enabled := false
var waypoint_root: Node3D
var waypoint_line: MeshInstance3D
var waypoints: Array[Vector3] = []
var camera_mode := "aim"
var last_robot_position := Vector3.ZERO
var last_robot_yaw := 0.0


func _ready() -> void:
	_build_camera()
	_build_light()
	_build_floor()
	_build_layers()
	_build_waypoint_layer()
	SessionRegistry.telemetry_updated.connect(_on_telemetry_updated)
	SessionRegistry.active_session_changed.connect(_on_active_session_changed)
	_apply_active_state()


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "OperatorCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = orthographic_size
	camera.current = true
	add_child(camera)
	_update_camera()


func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	add_child(light)


func _build_floor() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(GRID_SIZE, GRID_SIZE)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.125, 0.12)
	material.roughness = 0.8

	floor_layer = MeshInstance3D.new()
	floor_layer.name = "OccupancyFloor"
	floor_layer.mesh = floor_mesh
	floor_layer.material_override = material
	add_child(floor_layer)

	metric_grid = MeshInstance3D.new()
	metric_grid.name = "MetricGrid"
	metric_grid.mesh = _create_grid_mesh()
	metric_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(metric_grid)


func _create_grid_mesh() -> Mesh:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.48, 0.44, 0.55)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 10

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var half := int(GRID_SIZE / 2)
	for i in range(-half, half + 1):
		var offset := float(i) * GRID_STEP
		mesh.surface_add_vertex(Vector3(offset, GRID_Y_OFFSET, -half * GRID_STEP))
		mesh.surface_add_vertex(Vector3(offset, GRID_Y_OFFSET, half * GRID_STEP))
		mesh.surface_add_vertex(Vector3(-half * GRID_STEP, GRID_Y_OFFSET, offset))
		mesh.surface_add_vertex(Vector3(half * GRID_STEP, GRID_Y_OFFSET, offset))
	mesh.surface_end()
	return mesh


func _build_layers() -> void:
	map_layer = MapLayerScript.new()
	map_layer.name = "MapLayer"
	map_layer.map_layout_changed.connect(_on_map_layout_changed)
	add_child(map_layer)

	global_costmap_layer = MapLayerScript.new()
	global_costmap_layer.name = "GlobalCostmapLayer"
	global_costmap_layer.source_key = "global_costmap"
	global_costmap_layer.palette = "global_costmap"
	global_costmap_layer.y_offset = 0.03
	global_costmap_layer.map_layout_changed.connect(_on_map_layout_changed)
	add_child(global_costmap_layer)

	local_costmap_layer = MapLayerScript.new()
	local_costmap_layer.name = "LocalCostmapLayer"
	local_costmap_layer.source_key = "local_costmap"
	local_costmap_layer.palette = "local_costmap"
	local_costmap_layer.y_offset = 0.045
	local_costmap_layer.map_layout_changed.connect(_on_map_layout_changed)
	add_child(local_costmap_layer)

	global_path_layer = _build_path_layer("GlobalPathLayer")
	add_child(global_path_layer)

	local_path_layer = _build_path_layer("LocalPathLayer")
	add_child(local_path_layer)

	robot_layer = RobotLayerScript.new()
	robot_layer.name = "RobotLayer"
	add_child(robot_layer)

	tf_layer = TfLayerScript.new()
	tf_layer.name = "TfLayer"
	add_child(tf_layer)

	scan_layer = ScanLayerScript.new()
	scan_layer.name = "ScanLayer"
	scan_layer.tf_provider = tf_layer
	add_child(scan_layer)


func _build_waypoint_layer() -> void:
	waypoint_root = Node3D.new()
	waypoint_root.name = "WaypointLayer"
	add_child(waypoint_root)


func _build_path_layer(name: String) -> MeshInstance3D:
	var layer := MeshInstance3D.new()
	layer.name = name
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return layer


func _on_telemetry_updated(session_id: String, patch: Dictionary) -> void:
	if session_id != SessionRegistry.active_session_id:
		return
	_apply_patch_state(patch)


func _on_active_session_changed(_session_id: String) -> void:
	_apply_active_state()


func _apply_active_state() -> void:
	if not SessionRegistry.sessions.has(SessionRegistry.active_session_id):
		return
	var session := SessionRegistry.sessions[SessionRegistry.active_session_id] as Dictionary
	var state: Variant = session.get("state")
	if state == null:
		return
	if map_layer != null and map_layer.has_method("apply_state"):
		map_layer.apply_state(state)
	if global_costmap_layer != null and global_costmap_layer.has_method("apply_state"):
		global_costmap_layer.apply_state(state)
	if local_costmap_layer != null and local_costmap_layer.has_method("apply_state"):
		local_costmap_layer.apply_state(state)
	_apply_path_layer(global_path_layer, state.global_path, Color(0.13, 0.85, 1.0), WAYPOINT_Y_OFFSET + 0.015)
	_apply_path_layer(local_path_layer, state.local_path, Color(0.57, 0.87, 0.12), WAYPOINT_Y_OFFSET + 0.025)
	if robot_layer != null and robot_layer.has_method("apply_state"):
		robot_layer.apply_state(state)
		_update_robot_camera_reference(state.robot_pose)
	if tf_layer != null and tf_layer.has_method("apply_state"):
		tf_layer.apply_state(state)
	if scan_layer != null and scan_layer.has_method("apply_state"):
		scan_layer.apply_state(state)
	_update_camera()


func _apply_patch_state(patch: Dictionary) -> void:
	if not SessionRegistry.sessions.has(SessionRegistry.active_session_id):
		return
	var session := SessionRegistry.sessions[SessionRegistry.active_session_id] as Dictionary
	var state: Variant = session.get("state")
	if state == null:
		return
	if patch.has("map") and map_layer != null and map_layer.has_method("apply_state"):
		map_layer.apply_state(state)
	if patch.has("global_costmap") and global_costmap_layer != null and global_costmap_layer.has_method("apply_state"):
		global_costmap_layer.apply_state(state)
	if patch.has("local_costmap") and local_costmap_layer != null and local_costmap_layer.has_method("apply_state"):
		local_costmap_layer.apply_state(state)
	if patch.has("global_path"):
		_apply_path_layer(global_path_layer, state.global_path, Color(0.13, 0.85, 1.0), WAYPOINT_Y_OFFSET + 0.015)
	if patch.has("local_path"):
		_apply_path_layer(local_path_layer, state.local_path, Color(0.57, 0.87, 0.12), WAYPOINT_Y_OFFSET + 0.025)
	if _patch_touches_robot(patch) and robot_layer != null and robot_layer.has_method("apply_state"):
		robot_layer.apply_state(state)
		_update_robot_camera_reference(state.robot_pose)
	if _patch_touches_tf(patch) and tf_layer != null and tf_layer.has_method("apply_state"):
		tf_layer.apply_state(state)
	if _patch_touches_scan(patch) and scan_layer != null and scan_layer.has_method("apply_state"):
		scan_layer.apply_state(state)
	if _patch_touches_robot(patch):
		_update_camera()


func _patch_touches_robot(patch: Dictionary) -> bool:
	for key in ["robot_pose", "urdf_model", "robot_description"]:
		if patch.has(key):
			return true
	return false


func _patch_touches_tf(patch: Dictionary) -> bool:
	for key in ["tf", "tf_static", "robot_pose", "urdf_model", "robot_description"]:
		if patch.has(key):
			return true
	return false


func _patch_touches_scan(patch: Dictionary) -> bool:
	for key in ["scan", "tf", "tf_static", "robot_pose"]:
		if patch.has(key):
			return true
	return false


func _on_map_layout_changed(center: Vector3, width_meters: float, height_meters: float) -> void:
	if map_auto_framed:
		return
	map_auto_framed = true
	frame_map(center, width_meters, height_meters)


func handle_viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)


func release_viewport_input() -> void:
	orbiting = false
	panning = false
	grabbing = false
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if waypoint_placement_enabled else Input.CURSOR_ARROW)


func set_waypoint_placement_enabled(enabled: bool) -> void:
	waypoint_placement_enabled = enabled
	orbiting = false
	panning = false
	grabbing = false
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if enabled else Input.CURSOR_ARROW)


func set_visualization_layer_visible(layer_id: String, enabled: bool) -> void:
	match layer_id:
		"grid":
			if floor_layer != null:
				floor_layer.visible = enabled
			if metric_grid != null:
				metric_grid.visible = enabled
		"map":
			if map_layer != null:
				map_layer.visible = enabled
		"global_costmap":
			if global_costmap_layer != null:
				global_costmap_layer.visible = enabled
		"local_costmap":
			if local_costmap_layer != null:
				local_costmap_layer.visible = enabled
		"robot", "exact_footprint":
			if robot_layer != null:
				robot_layer.visible = enabled
		"tf":
			if tf_layer != null:
				tf_layer.visible = enabled
		"scan":
			if scan_layer != null:
				scan_layer.visible = enabled
		"waypoints":
			if waypoint_root != null:
				waypoint_root.visible = enabled
		"global_plan":
			if global_path_layer != null:
				global_path_layer.visible = enabled
		"local_plan":
			if local_path_layer != null:
				local_path_layer.visible = enabled
		_:
			pass


func set_camera_mode(next_mode: String) -> void:
	camera_mode = next_mode
	match camera_mode:
		"aim":
			top_down_mode = true
			camera_yaw = 0.0
			camera_pitch = deg_to_rad(-90.0)
			camera_roll = 0.0
			camera_distance = 32.0
			orthographic_size = 10.0
		"first_person":
			top_down_mode = false
			camera_distance = 0.01
			camera_pitch = deg_to_rad(-8.0)
			camera_roll = 0.0
		_:
			reset_camera()
			return
	_update_camera()


func reset_view_modes() -> void:
	camera_mode = "free"
	waypoint_placement_enabled = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	reset_camera()


func clear_waypoints() -> void:
	waypoints.clear()
	if waypoint_root != null:
		for child in waypoint_root.get_children():
			child.queue_free()
	waypoint_line = null


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				if event.shift_pressed:
					_move_vertical_axis(0.25)
				else:
					_zoom_camera(0.88)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				if event.shift_pressed:
					_move_vertical_axis(-0.25)
				else:
					_zoom_camera(1.14)
		MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed
			Input.set_default_cursor_shape(Input.CURSOR_DRAG if orbiting else Input.CURSOR_ARROW)
		MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			Input.set_default_cursor_shape(Input.CURSOR_DRAG if panning else Input.CURSOR_ARROW)
		MOUSE_BUTTON_LEFT:
			if waypoint_placement_enabled and event.pressed and not event.double_click:
				_place_waypoint_from_screen(event.position)
				return
			if event.double_click and event.pressed:
				reset_camera()
			else:
				grabbing = event.pressed
				Input.set_default_cursor_shape(Input.CURSOR_DRAG if grabbing else Input.CURSOR_ARROW)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if orbiting:
		_enter_perspective_from_top_down()
		camera_yaw -= event.relative.x * 0.006
		camera_pitch = clamp(camera_pitch - event.relative.y * 0.006, deg_to_rad(-82.0), deg_to_rad(-18.0))
		_update_camera()
	elif grabbing and event.shift_pressed:
		_enter_perspective_from_top_down()
		camera_yaw -= event.relative.x * 0.006
		camera_pitch = clamp(camera_pitch - event.relative.y * 0.004, deg_to_rad(-82.0), deg_to_rad(-18.0))
		_update_camera()
	elif panning or grabbing:
		_pan_camera(event.relative)


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_T:
			set_top_down_camera()
		KEY_I:
			set_isometric_camera()
		KEY_R:
			reset_camera()
		KEY_Q:
			_move_vertical_axis(0.25)
		KEY_E:
			_move_vertical_axis(-0.25)
		KEY_PLUS, KEY_EQUAL:
			_zoom_camera(0.88)
		KEY_MINUS:
			_zoom_camera(1.14)


func _place_waypoint_from_screen(screen_position: Vector2) -> void:
	var world_position := _screen_to_ground(screen_position)
	var yaw := 0.0
	if not waypoints.is_empty():
		var previous := waypoints[waypoints.size() - 1]
		var delta := world_position - previous
		if Vector2(delta.x, delta.z).length() > 0.001:
			yaw = atan2(-delta.z, delta.x)
	waypoints.append(world_position)
	_add_waypoint_marker(world_position, yaw, waypoints.size())
	_rebuild_waypoint_line()
	waypoint_placed.emit(world_position, yaw)


func _screen_to_ground(screen_position: Vector2) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if abs(direction.y) < 0.0001:
		return Vector3(origin.x, 0.0, origin.z)
	var distance := -origin.y / direction.y
	var hit := origin + (direction * distance)
	return Vector3(hit.x, 0.0, hit.z)


func _add_waypoint_marker(position: Vector3, yaw: float, index: int) -> void:
	if waypoint_root == null:
		return
	var marker_root := Node3D.new()
	marker_root.name = "Waypoint%d" % index
	marker_root.position = Vector3(position.x, WAYPOINT_Y_OFFSET, position.z)
	marker_root.rotation.y = -yaw
	waypoint_root.add_child(marker_root)

	var marker_mesh := _location_marker_mesh()
	var marker := MeshInstance3D.new()
	marker.name = "LocationMarker"
	marker.mesh = marker_mesh
	marker.rotation_degrees.x = -90.0
	marker.material_override = _waypoint_material(Color(1.0, 0.62, 0.08))
	marker_root.add_child(marker)

	var center_dot := MeshInstance3D.new()
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.032
	dot_mesh.bottom_radius = 0.032
	dot_mesh.height = 0.008
	dot_mesh.radial_segments = 24
	center_dot.name = "LocationMarkerCenter"
	center_dot.mesh = dot_mesh
	center_dot.position = Vector3(0.0, 0.002, 0.0)
	center_dot.material_override = _waypoint_material(Color(0.045, 0.055, 0.068))
	marker_root.add_child(center_dot)


func _rebuild_waypoint_line() -> void:
	if waypoint_line != null:
		waypoint_line.queue_free()
		waypoint_line = null
	if waypoints.size() < 2 or waypoint_root == null:
		return

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _waypoint_material(Color(0.2, 0.85, 0.95)))
	for index in range(waypoints.size() - 1):
		var start := waypoints[index]
		var end := waypoints[index + 1]
		mesh.surface_add_vertex(Vector3(start.x, WAYPOINT_Y_OFFSET + 0.01, start.z))
		mesh.surface_add_vertex(Vector3(end.x, WAYPOINT_Y_OFFSET + 0.01, end.z))
	mesh.surface_end()

	waypoint_line = MeshInstance3D.new()
	waypoint_line.name = "WaypointPath"
	waypoint_line.mesh = mesh
	waypoint_root.add_child(waypoint_line)


func _waypoint_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 35
	return material


func _apply_path_layer(layer: MeshInstance3D, path_message: Variant, color: Color, y_offset: float) -> void:
	if layer == null:
		return
	var points := _path_points(path_message)
	if points.size() < 2:
		layer.mesh = null
		return

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _path_material(color))
	for index in range(points.size() - 1):
		mesh.surface_add_vertex(points[index] + Vector3(0.0, y_offset, 0.0))
		mesh.surface_add_vertex(points[index + 1] + Vector3(0.0, y_offset, 0.0))
	mesh.surface_end()
	layer.mesh = mesh


func _path_points(path_message: Variant) -> PackedVector3Array:
	var points := PackedVector3Array()
	if typeof(path_message) != TYPE_DICTIONARY:
		return points
	var message: Dictionary = path_message
	var poses_value: Variant = message.get("poses", [])
	if typeof(poses_value) != TYPE_ARRAY:
		return points
	for pose_value in poses_value:
		var point: Variant = _path_point_from_pose(pose_value)
		if point != null:
			points.append(point)
	return points


func _path_point_from_pose(pose_value: Variant) -> Variant:
	if typeof(pose_value) != TYPE_DICTIONARY:
		return null
	var wrapper: Dictionary = pose_value
	var nested_pose: Variant = wrapper.get("pose", wrapper)
	if typeof(nested_pose) == TYPE_DICTIONARY and (nested_pose as Dictionary).has("pose"):
		nested_pose = (nested_pose as Dictionary).get("pose", {})
	if typeof(nested_pose) != TYPE_DICTIONARY:
		return null
	var pose: Dictionary = nested_pose
	var position_value: Variant = pose.get("position", {})
	if typeof(position_value) != TYPE_DICTIONARY:
		return null
	var position: Dictionary = position_value
	return Vector3(
		float(position.get("x", 0.0)),
		float(position.get("z", 0.0)),
		-float(position.get("y", 0.0))
	)


func _path_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 30
	return material


func _location_marker_mesh() -> Mesh:
	var mesh := ImmediateMesh.new()
	var material := _waypoint_material(Color(1.0, 0.62, 0.08))
	var radius := 0.095
	var center := Vector3(0.0, 0.12, 0.0)
	var tip := Vector3(0.0, -0.12, 0.0)

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for index in range(24):
		var a0 := TAU * float(index) / 24.0
		var a1 := TAU * float(index + 1) / 24.0
		var p0 := center + Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := center + Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(p0)
		mesh.surface_add_vertex(p1)
		mesh.surface_add_vertex(tip)
		mesh.surface_add_vertex(p1)
		mesh.surface_add_vertex(p0)
	mesh.surface_end()
	return mesh


func _zoom_camera(factor: float) -> void:
	if top_down_mode:
		orthographic_size = clamp(orthographic_size * factor, CAMERA_MIN_ORTHO_SIZE, CAMERA_MAX_ORTHO_SIZE)
	else:
		camera_distance = clamp(camera_distance * factor, 1.8, 90.0)
	_update_camera()


func _enter_perspective_from_top_down() -> void:
	if not top_down_mode:
		return
	camera_distance = clamp(orthographic_size * 1.25, 1.8, 90.0)
	top_down_mode = false


func _pan_camera(relative: Vector2) -> void:
	if camera == null:
		return
	var pan_scale := (orthographic_size if top_down_mode else camera_distance) * 0.0018
	var right := camera.global_transform.basis.x
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	camera_target += (-right * relative.x + forward * relative.y) * pan_scale
	_update_camera()


func reset_camera() -> void:
	camera_target = Vector3.ZERO
	map_auto_framed = false
	camera_mode = "free"
	set_top_down_camera()


func frame_map(center: Vector3, width_meters: float, height_meters: float) -> void:
	top_down_mode = true
	camera_yaw = 0.0
	camera_pitch = deg_to_rad(-90.0)
	camera_roll = 0.0
	camera_distance = 32.0
	camera_target = Vector3(center.x, 0.0, center.z)
	orthographic_size = clamp(max(width_meters, height_meters) * 1.08, CAMERA_MIN_ORTHO_SIZE, CAMERA_MAX_ORTHO_SIZE)
	_update_camera()


func set_top_down_camera() -> void:
	camera_mode = "free"
	top_down_mode = true
	camera_yaw = 0.0
	camera_pitch = deg_to_rad(-90.0)
	camera_roll = 0.0
	camera_distance = 32.0
	orthographic_size = 18.0
	_update_camera()


func set_isometric_camera() -> void:
	camera_mode = "free"
	top_down_mode = false
	camera_yaw = deg_to_rad(38.0)
	camera_pitch = deg_to_rad(-50.0)
	camera_roll = 0.0
	camera_distance = 24.0
	_update_camera()


func _move_vertical_axis(delta: float) -> void:
	camera_target.y = clamp(camera_target.y + delta, -4.0, 12.0)
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	if camera_mode == "aim":
		camera_target = last_robot_position
	elif camera_mode == "first_person":
		_update_first_person_camera()
		return
	if top_down_mode:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = orthographic_size
		camera.position = camera_target + Vector3(0.0, clamp(camera_distance, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT), 0.0)
		var screen_up := Vector3(-sin(camera_yaw), 0.0, -cos(camera_yaw))
		camera.look_at(camera_target, screen_up)
		return

	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 35.0
	var horizontal := cos(camera_pitch) * camera_distance
	var offset := Vector3(
		sin(camera_yaw) * horizontal,
		-sin(camera_pitch) * camera_distance,
		cos(camera_yaw) * horizontal
	)
	camera.position = camera_target + offset
	var forward := (camera_target - camera.position).normalized()
	var up := Vector3.UP.rotated(forward, camera_roll)
	camera.look_at(camera_target, up)


func _update_first_person_camera() -> void:
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 72.0
	var forward := Vector3(cos(last_robot_yaw), 0.0, -sin(last_robot_yaw)).normalized()
	var eye := last_robot_position + Vector3(0.0, 0.34, 0.0) - (forward * 0.08)
	camera.position = eye
	camera.look_at(eye + forward + Vector3(0.0, -0.08, 0.0), Vector3.UP)


func _update_robot_camera_reference(robot_pose: Dictionary) -> void:
	if robot_pose.is_empty():
		return
	var pose := _extract_robot_pose(robot_pose)
	last_robot_position = Vector3(float(pose.get("x", 0.0)), ROBOT_TOP_LAYER_Y, -float(pose.get("y", 0.0)))
	last_robot_yaw = float(pose.get("yaw", 0.0))


func _extract_robot_pose(robot_pose: Dictionary) -> Dictionary:
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
