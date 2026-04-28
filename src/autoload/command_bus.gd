extends Node

signal command_requested(command: Dictionary)


func request_goal(position: Vector3, yaw: float) -> void:
	request_navigation([{
		"position": position,
		"yaw": yaw,
	}])


func request_navigation(goals: Array) -> void:
	var goal_poses := []
	for goal in goals:
		if typeof(goal) != TYPE_DICTIONARY:
			continue
		var position: Vector3 = goal.get("position", Vector3.ZERO)
		var yaw := float(goal.get("yaw", 0.0))
		goal_poses.append(_pose_stamped(position, yaw))
	if goal_poses.is_empty():
		AppState.push_event("Navigation command skipped: no goals")
		return

	_emit_command("navigation_command", "navigation/command", {
		"request_id": _create_request_id("route"),
		"goal_poses": goal_poses,
	})


func request_initial_pose(position: Vector3, yaw: float) -> void:
	_emit_command("pose_set", "pose/set", {
		"request_id": _create_request_id("init"),
		"frame": "map",
		"pose": _pose(position, yaw),
		"covariance_x": 0.25,
		"covariance_y": 0.25,
		"covariance_yaw": 0.06853891945200942,
	})


func request_motion(linear_x: float, angular_z: float) -> void:
	_emit_command("motion_command", "motion/command", {
		"linear": {
			"x": linear_x,
			"y": 0.0,
			"z": 0.0,
		},
		"angular": {
			"x": 0.0,
			"y": 0.0,
			"z": angular_z,
		},
	}, false)


func request_cancel() -> void:
	_emit_command("navigation_cancel", "navigation/cancel", {
		"request_id": _create_request_id("cancel"),
	})


func request_reset_world() -> void:
	AppState.push_event("Reset world is local-only; no MQTT command emitted")


func request_map_save(basename: String) -> void:
	var clean_name := basename.strip_edges()
	if clean_name.is_empty():
		AppState.push_event("Map save skipped: basename is empty")
		return
	_emit_command("map_save", "map/save", {
		"request_id": _create_request_id("map-save"),
		"basename": clean_name,
	})


func request_system_ping() -> void:
	_emit_command("system_ping", "system/ping", {
		"request_id": _create_request_id("ping"),
		"sent_at_ms": float(Time.get_unix_time_from_system() * 1000.0),
	})


func request_robot_id_change(robot_id: String) -> void:
	var clean_id := robot_id.strip_edges()
	if clean_id.is_empty():
		AppState.push_event("Robot ID change skipped: id is empty")
		return
	_emit_command("system_robot", "system/robot", {
		"request_id": _create_request_id("robot"),
		"robot_id": clean_id,
	})


func _emit_command(command_key: String, channel: String, payload: Dictionary, announce := true) -> void:
	var command := {
		"command_key": command_key,
		"channel": channel,
		"target_robot_id": AppState.active_robot_id,
		"payload": payload,
	}
	command_requested.emit(command)
	if announce:
		AppState.push_event("Command requested: " + channel)


func _pose_stamped(position: Vector3, yaw: float) -> Dictionary:
	var pose := _pose(position, yaw)
	pose["frame"] = "map"
	return pose


func _pose(position: Vector3, yaw: float) -> Dictionary:
	return {
		"position": {
			"x": position.x,
			"y": position.z,
			"z": 0.0,
		},
		"orientation": _orientation_from_yaw(yaw),
	}


func _orientation_from_yaw(yaw: float) -> Dictionary:
	var half_yaw := yaw * 0.5
	return {
		"x": 0.0,
		"y": 0.0,
		"z": sin(half_yaw),
		"w": cos(half_yaw),
	}


func _create_request_id(prefix := "rcs") -> String:
	return "%s-%d-%d" % [prefix, Time.get_ticks_msec(), randi() % 100000]
