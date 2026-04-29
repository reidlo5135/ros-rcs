extends SceneTree

const ReplayReaderScript := preload("res://src/domain/simulation/replay_reader/replay_reader.gd")
const DiffDriveSimulatorScript := preload("res://src/domain/simulation/diff_drive_simulator/diff_drive_simulator.gd")
const SimulationRuntimeScript := preload("res://src/domain/simulation/simulation_runtime/simulation_runtime.gd")


func _init() -> void:
	var replay_reader: RefCounted = ReplayReaderScript.new()
	var frames: Array = replay_reader.parse_text("""
{"timestamp": 1.5, "topic": "/amr/burger1/viz/robot_pose", "payload": {"x": 1.0}}
{"topic": "/amr/burger1/viz/scan", "payload": {"ranges": [1, 2, 3]}}
not-json
""")
	if frames.size() != 3:
		push_error("Replay reader should emit one frame per non-empty input line")
		quit(1)
		return
	if not bool(frames[0].get("ok", false)):
		push_error("Replay reader should accept JSON object lines")
		quit(1)
		return
	if float(frames[0].get("timestamp", 0.0)) != 1.5:
		push_error("Replay reader should preserve frame timestamps")
		quit(1)
		return
	if bool(frames[2].get("ok", true)):
		push_error("Replay reader should surface malformed replay rows")
		quit(1)
		return

	var simulator: RefCounted = DiffDriveSimulatorScript.new()
	simulator.reset({"x": 0.0, "y": 0.0, "yaw": 0.0})
	simulator.set_command({
		"linear": {"x": 1.0},
		"angular": {"z": 0.5},
	})
	var stepped_pose: Dictionary = simulator.step(2.0)
	if abs(float(stepped_pose.get("x", 0.0)) - 2.0) > 0.0001:
		push_error("Diff-drive simulator should integrate forward distance from linear velocity")
		quit(1)
		return
	if abs(float(stepped_pose.get("yaw", 0.0)) - 1.0) > 0.0001:
		push_error("Diff-drive simulator should integrate angular velocity into yaw")
		quit(1)
		return

	var runtime: Node = SimulationRuntimeScript.new()
	runtime._ready()
	runtime.set_simulated_pose({"x": 0.0, "y": 0.0, "yaw": 0.0})
	runtime.set_command_twist({"linear_x": 0.5, "angular_z": 0.25})
	runtime.start()
	runtime._physics_process(4.0)
	if abs(float(runtime.simulated_pose.get("x", 0.0)) - 2.0) > 0.0001:
		push_error("Simulation runtime should advance pose through the shared diff-drive simulator")
		quit(1)
		return
	if abs(float(runtime.simulated_pose.get("yaw", 0.0)) - 1.0) > 0.0001:
		push_error("Simulation runtime should keep simulated yaw in sync with angular commands")
		quit(1)
		return

	print("Simulation runtime test passed")
	quit()
