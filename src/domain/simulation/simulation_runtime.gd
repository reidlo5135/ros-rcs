extends Node
class_name RcsSimulationRuntime

signal world_reset()
signal ticked(delta_seconds: float)

var running := false


func start() -> void:
	running = true


func stop() -> void:
	running = false


func reset_world() -> void:
	world_reset.emit()


func _physics_process(delta: float) -> void:
	if not running:
		return
	ticked.emit(delta)
