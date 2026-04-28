extends SceneTree

const CommandBusScript := preload("res://src/autoload/command_bus.gd")

var captured: Array[Dictionary] = []


func _init() -> void:
	var bus := CommandBusScript.new()
	bus.command_requested.connect(func(command: Dictionary) -> void:
		captured.append(command)
	)

	bus.request_navigation([
		{"position": Vector3(1.0, 0.0, 0.5), "yaw": 0.0},
		{"position": Vector3(2.0, 0.0, 1.2), "yaw": PI * 0.5},
	])
	_assert_command_key(0, "navigation_command")
	var route_payload: Dictionary = captured[0].get("payload", {})
	if not route_payload.has("request_id") or (route_payload.get("goal_poses", []) as Array).size() != 2:
		_fail("Navigation payload does not match protocol")
		return
	var second_goal: Dictionary = (route_payload["goal_poses"] as Array)[1]
	var second_orientation: Dictionary = second_goal.get("orientation", {})
	if not is_equal_approx(float(second_orientation.get("z", 0.0)), 0.7071067):
		_fail("Navigation goal yaw was not converted to quaternion")
		return

	bus.request_initial_pose(Vector3(0.03, 0.0, -0.10), 0.0)
	_assert_command_key(1, "pose_set")
	var pose_payload: Dictionary = captured[1].get("payload", {})
	if not pose_payload.has("request_id") or not pose_payload.has("pose") or str(pose_payload.get("frame", "")) != "map":
		_fail("Pose payload does not match protocol")
		return

	bus.request_cancel()
	_assert_command_key(2, "navigation_cancel")
	if not (captured[2].get("payload", {}) as Dictionary).has("request_id"):
		_fail("Cancel payload does not include request_id")
		return

	bus.request_motion(0.1, 0.3)
	_assert_command_key(3, "motion_command")
	var motion_payload: Dictionary = captured[3].get("payload", {})
	if not motion_payload.has("linear") or not motion_payload.has("angular"):
		_fail("Motion payload does not match protocol")
		return

	print("Command protocol test passed")
	quit()


func _assert_command_key(index: int, expected: String) -> void:
	if captured.size() <= index:
		_fail("Missing command at index %d" % index)
		return
	if str(captured[index].get("command_key", "")) != expected:
		_fail("Unexpected command key at index %d" % index)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
