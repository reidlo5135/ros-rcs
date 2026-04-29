extends RefCounted


var _native_simulator: Variant = null
var _pose: Dictionary = {
	"x": 0.0,
	"y": 0.0,
	"yaw": 0.0,
	"theta": 0.0,
	"linear_x": 0.0,
	"angular_z": 0.0,
}


func _init() -> void:
	if ClassDB.class_exists("RcsDiffDriveSimulator"):
		_native_simulator = ClassDB.instantiate("RcsDiffDriveSimulator")


func reset(pose: Dictionary = {}) -> void:
	if _native_simulator != null:
		_native_simulator.reset(pose)
		_pose = _native_simulator.pose()
		return
	_pose["x"] = float(pose.get("x", 0.0))
	_pose["y"] = float(pose.get("y", 0.0))
	_pose["yaw"] = float(pose.get("yaw", pose.get("theta", 0.0)))
	_pose["theta"] = _pose["yaw"]


func set_command(twist: Dictionary) -> void:
	if _native_simulator != null:
		_native_simulator.set_command(twist)
		_pose = _native_simulator.pose()
		return

	var linear: Dictionary = twist.get("linear", {})
	var angular: Dictionary = twist.get("angular", {})
	_pose["linear_x"] = float(twist.get("linear_x", linear.get("x", _pose.get("linear_x", 0.0))))
	_pose["angular_z"] = float(twist.get("angular_z", angular.get("z", _pose.get("angular_z", 0.0))))


func step(delta_seconds: float) -> Dictionary:
	if _native_simulator != null:
		_pose = _native_simulator.step(delta_seconds)
		return _pose.duplicate(true)

	if delta_seconds > 0.0:
		var yaw: float = float(_pose.get("yaw", 0.0))
		var linear_x: float = float(_pose.get("linear_x", 0.0))
		var angular_z: float = float(_pose.get("angular_z", 0.0))
		_pose["x"] = float(_pose.get("x", 0.0)) + linear_x * cos(yaw) * delta_seconds
		_pose["y"] = float(_pose.get("y", 0.0)) + linear_x * sin(yaw) * delta_seconds
		_pose["yaw"] = yaw + angular_z * delta_seconds
		_pose["theta"] = _pose["yaw"]
	return _pose.duplicate(true)


func pose() -> Dictionary:
	if _native_simulator != null:
		_pose = _native_simulator.pose()
	return _pose.duplicate(true)
