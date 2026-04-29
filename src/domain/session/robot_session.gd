extends RefCounted
class_name RcsRobotSession

const RcsBridgeStateScript := preload("res://src/domain/telemetry/bridge_state/bridge_state.gd")

var robot_id := "burger1"
var bridge_state := RcsBridgeStateScript.new()
var last_seen_at_msec := 0
var connected := false


func _init(p_robot_id := "burger1") -> void:
	robot_id = p_robot_id


func mark_seen() -> void:
	last_seen_at_msec = Time.get_ticks_msec()
	connected = true


func mark_disconnected() -> void:
	connected = false
	bridge_state.clear_live_data()
