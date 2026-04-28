extends RefCounted
class_name RcsCommandFactory


static func navigate_to_pose(robot_id: String, x: float, y: float, yaw: float) -> Dictionary:
	return _base(robot_id, "navigation_command", {
		"request_id": _request_id("route"),
		"goal_poses": [_pose_stamped(Vector3(x, 0.0, y), yaw)],
	})


static func cancel(robot_id: String) -> Dictionary:
	return _base(robot_id, "navigation_cancel", {
		"request_id": _request_id("cancel"),
	})


static func _base(robot_id: String, command_key: String, payload: Dictionary) -> Dictionary:
	return {
		"command_key": command_key,
		"target_robot_id": robot_id,
		"payload": payload,
	}


static func _pose_stamped(position: Vector3, yaw: float) -> Dictionary:
	return {
		"frame": "map",
		"position": {
			"x": position.x,
			"y": position.z,
			"z": 0.0,
		},
		"orientation": {
			"x": 0.0,
			"y": 0.0,
			"z": sin(yaw * 0.5),
			"w": cos(yaw * 0.5),
		},
	}


static func _request_id(prefix: String) -> String:
	return "%s-%d-%d" % [prefix, Time.get_ticks_msec(), randi() % 100000]
