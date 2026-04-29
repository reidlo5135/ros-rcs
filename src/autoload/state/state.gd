extends Node

signal connection_state_changed(next_state: String)
signal event_pushed(entry: Dictionary)
signal topic_settings_changed(group: String)

var connection_state := "Booting"
var active_robot_id := "burger1"
var events: Array[Dictionary] = []
var max_events := 160
var topic_settings := {
	"command": {},
	"viz": {},
}

const TOPIC_SETTINGS_PATH := "user://topic_settings.json"


func _ready() -> void:
	_load_topic_settings()


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


func topic_template(group: String, key: String, fallback: String) -> String:
	var group_settings: Dictionary = topic_settings.get(group, {})
	var override := str(group_settings.get(key, "")).strip_edges()
	return override if not override.is_empty() else fallback


func set_topic_settings(group: String, next_values: Dictionary) -> void:
	var clean := {}
	for key in next_values.keys():
		var value := str(next_values[key]).strip_edges()
		if not value.is_empty():
			clean[str(key)] = value
	topic_settings[group] = clean
	_save_topic_settings()
	topic_settings_changed.emit(group)
	push_event("Saved %s topic settings" % group)


func topic_settings_for(group: String) -> Dictionary:
	var group_settings: Dictionary = topic_settings.get(group, {})
	return group_settings.duplicate(true)


func _load_topic_settings() -> void:
	if not FileAccess.file_exists(TOPIC_SETTINGS_PATH):
		return
	var file := FileAccess.open(TOPIC_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data
	if typeof(data.get("command", {})) == TYPE_DICTIONARY:
		topic_settings["command"] = data["command"]
	if typeof(data.get("viz", {})) == TYPE_DICTIONARY:
		topic_settings["viz"] = data["viz"]


func _save_topic_settings() -> void:
	var file := FileAccess.open(TOPIC_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_event("Failed to save topic settings")
		return
	file.store_string(JSON.stringify(topic_settings, "\t"))
