extends Node3D

const MapLayerScript: Script = preload("res://src/scene/layers/map_layer.gd")
const RobotLayerScript: Script = preload("res://src/scene/layers/robot_layer.gd")
const TfLayerScript: Script = preload("res://src/scene/layers/tf_layer.gd")

const GRID_SIZE := 24
const GRID_STEP := 1.0
const GRID_Y_OFFSET := 0.075
const CAMERA_MIN_ORTHO_SIZE := 1.2
const CAMERA_MAX_ORTHO_SIZE := 80.0
const CAMERA_MIN_HEIGHT := 4.0
const CAMERA_MAX_HEIGHT := 120.0
const CAMERA_ROLL_LIMIT := deg_to_rad(50.0)

var camera: Camera3D
var map_layer: Node3D
var global_costmap_layer: Node3D
var local_costmap_layer: Node3D
var robot_layer: Node3D
var tf_layer: Node3D
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


func _ready() -> void:
	_build_camera()
	_build_light()
	_build_floor()
	_build_layers()
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
	material.albedo_color = Color(0.08, 0.10, 0.11)
	material.roughness = 0.8

	var floor := MeshInstance3D.new()
	floor.name = "OccupancyFloor"
	floor.mesh = floor_mesh
	floor.material_override = material
	add_child(floor)

	var grid := MeshInstance3D.new()
	grid.name = "MetricGrid"
	grid.mesh = _create_grid_mesh()
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)


func _create_grid_mesh() -> Mesh:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.43, 0.46, 0.72)
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

	robot_layer = RobotLayerScript.new()
	robot_layer.name = "RobotLayer"
	add_child(robot_layer)

	tf_layer = TfLayerScript.new()
	tf_layer.name = "TfLayer"
	add_child(tf_layer)


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
	if robot_layer != null and robot_layer.has_method("apply_state"):
		robot_layer.apply_state(state)
	if tf_layer != null and tf_layer.has_method("apply_state"):
		tf_layer.apply_state(state)


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
	if _patch_touches_robot(patch) and robot_layer != null and robot_layer.has_method("apply_state"):
		robot_layer.apply_state(state)
	if _patch_touches_tf(patch) and tf_layer != null and tf_layer.has_method("apply_state"):
		tf_layer.apply_state(state)


func _patch_touches_robot(patch: Dictionary) -> bool:
	for key in ["robot_pose", "urdf_model", "robot_description"]:
		if patch.has(key):
			return true
	return false


func _patch_touches_tf(patch: Dictionary) -> bool:
	for key in ["tf", "tf_static", "robot_pose"]:
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
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


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
			if event.double_click and event.pressed:
				reset_camera()
			else:
				grabbing = event.pressed
				Input.set_default_cursor_shape(Input.CURSOR_DRAG if grabbing else Input.CURSOR_ARROW)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if orbiting:
		top_down_mode = false
		camera_yaw -= event.relative.x * 0.006
		camera_pitch = clamp(camera_pitch - event.relative.y * 0.006, deg_to_rad(-82.0), deg_to_rad(-18.0))
		_update_camera()
	elif grabbing and event.shift_pressed:
		top_down_mode = false
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


func _zoom_camera(factor: float) -> void:
	if top_down_mode:
		orthographic_size = clamp(orthographic_size * factor, CAMERA_MIN_ORTHO_SIZE, CAMERA_MAX_ORTHO_SIZE)
	else:
		camera_distance = clamp(camera_distance * factor, 1.8, 90.0)
	_update_camera()


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
	top_down_mode = true
	camera_yaw = 0.0
	camera_pitch = deg_to_rad(-90.0)
	camera_roll = 0.0
	camera_distance = 32.0
	orthographic_size = 18.0
	_update_camera()


func set_isometric_camera() -> void:
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
