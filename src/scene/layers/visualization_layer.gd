extends Node3D
class_name RcsVisualizationLayer

@export var layer_id := ""
@export var enabled := true:
	set(value):
		enabled = value
		visible = value


func apply_state(_state: Variant) -> void:
	pass
