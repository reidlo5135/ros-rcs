extends Node

signal command_requested(command: Dictionary)


func request_goal(position: Vector3, yaw: float) -> void:
	_emit_command("navigate_to_pose", {
		"frame_id": "map",
		"goal": {
			"x": position.x,
			"y": position.z,
			"yaw": yaw,
		},
	})


func request_cancel() -> void:
	_emit_command("cancel_navigate", {})


func request_reset_world() -> void:
	_emit_command("reset_world", {})


func _emit_command(kind: String, payload: Dictionary) -> void:
	var command := {
		"request_id": _create_request_id(),
		"schema_version": 1,
		"kind": kind,
		"target_robot_id": AppState.active_robot_id,
		"payload": payload,
	}
	command_requested.emit(command)
	AppState.push_event("Command requested: " + kind)


func _create_request_id() -> String:
	return "rcs-%d-%d" % [Time.get_ticks_msec(), randi() % 100000]
