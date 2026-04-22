extends RefCounted
class_name RcsCommandFactory


static func navigate_to_pose(robot_id: String, x: float, y: float, yaw: float) -> Dictionary:
	return _base(robot_id, "navigate_to_pose", {
		"frame_id": "map",
		"goal": {
			"x": x,
			"y": y,
			"yaw": yaw,
		},
	})


static func cancel(robot_id: String) -> Dictionary:
	return _base(robot_id, "cancel_navigate", {})


static func _base(robot_id: String, kind: String, payload: Dictionary) -> Dictionary:
	return {
		"request_id": "rcs-%d-%d" % [Time.get_ticks_msec(), randi() % 100000],
		"schema_version": 1,
		"kind": kind,
		"target_robot_id": robot_id,
		"payload": payload,
		"source": "operator",
	}
