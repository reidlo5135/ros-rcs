extends Control

const OperatorConsoleScene := preload("res://src/ui/screens/operator/operator.tscn")


func _ready() -> void:
	var console := OperatorConsoleScene.instantiate()
	console.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(console)

	AppState.set_connection_state("Disconnected")
	AppState.push_event("RCS Godot runtime ready")
