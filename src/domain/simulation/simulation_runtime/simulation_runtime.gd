extends Node
class_name RcsSimulationRuntime

signal world_reset()
signal ticked(delta_seconds: float)
signal pose_updated(pose: Dictionary)

var running: bool = false
var simulated_pose: Dictionary = {
	"x": 0.0,
	"y": 0.0,
	"yaw": 0.0,
	"theta": 0.0,
	"linear_x": 0.0,
	"angular_z": 0.0,
}

const DiffDriveSimulatorScript := preload("res://src/domain/simulation/diff_drive_simulator/diff_drive_simulator.gd")

var _simulator: RefCounted


func _ready() -> void:
	_simulator = DiffDriveSimulatorScript.new()
	_simulator.reset(simulated_pose)


func start() -> void:
	running = true


func stop() -> void:
	running = false


func reset_world() -> void:
	if _simulator != null:
		_simulator.reset({})
		simulated_pose = _simulator.pose()
	world_reset.emit()


func set_command_twist(twist: Dictionary) -> void:
	if _simulator == null:
		return
	_simulator.set_command(twist)
	simulated_pose = _simulator.pose()


func set_simulated_pose(pose: Dictionary) -> void:
	if _simulator == null:
		return
	_simulator.reset(pose)
	simulated_pose = _simulator.pose()
	pose_updated.emit(simulated_pose.duplicate(true))


func _physics_process(delta: float) -> void:
	if not running:
		return
	if _simulator != null:
		simulated_pose = _simulator.step(delta)
		pose_updated.emit(simulated_pose.duplicate(true))
	ticked.emit(delta)
