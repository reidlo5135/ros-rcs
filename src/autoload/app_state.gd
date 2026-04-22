extends Node

signal connection_state_changed(next_state: String)
signal event_pushed(entry: Dictionary)

var connection_state := "Booting"
var active_robot_id := "burger1"
var events: Array[Dictionary] = []
var max_events := 160


func set_connection_state(next_state: String) -> void:
	if connection_state == next_state:
		return
	connection_state = next_state
	connection_state_changed.emit(next_state)


func set_active_robot(robot_id: String) -> void:
	active_robot_id = robot_id.strip_edges()
	if active_robot_id.is_empty():
		active_robot_id = "burger1"
	push_event("Active robot: " + active_robot_id)


func push_event(message: String) -> void:
	var entry := {
		"time": Time.get_time_string_from_system(),
		"message": message,
	}
	events.append(entry)
	while events.size() > max_events:
		events.pop_front()
	event_pushed.emit(entry)
