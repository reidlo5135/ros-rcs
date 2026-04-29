extends Node

signal connection_state_changed(next_state: String)
signal event_pushed(entry: Dictionary)
signal topic_settings_changed(group: String)

var connection_state := "Booting"
var active_robot_id := "burger1"
var runtime_config: Dictionary = {}
var events: Array[Dictionary] = []
var max_events := 160
var topic_settings := {
	"command": {},
	"viz": {},
}

const DEFAULT_RUNTIME_CONFIG_PATH := "res://project/config/default_runtime.json"
const TOPIC_SETTINGS_PATH := "user://topic_settings.json"


func _ready() -> void:
	_load_runtime_config()
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


func app_version() -> String:
	return str(runtime_config.get("version", ProjectSettings.get_setting("application/config/version", "0.0.0")))


func default_broker_url() -> String:
	var transport: Dictionary = runtime_config.get("transport", {})
	return str(transport.get("broker_url", "ws://192.168.61.35:9001/mqtt"))


func default_robot_id() -> String:
	var session: Dictionary = runtime_config.get("session", {})
	return str(session.get("default_robot_id", "burger1"))


func ai_prompt_config() -> Dictionary:
	var ai: Dictionary = runtime_config.get("ai", {})
	return ai.duplicate(true)


func _load_runtime_config() -> void:
	runtime_config = {}
	if not FileAccess.file_exists(DEFAULT_RUNTIME_CONFIG_PATH):
		_apply_runtime_defaults()
		return
	var file := FileAccess.open(DEFAULT_RUNTIME_CONFIG_PATH, FileAccess.READ)
	if file == null:
		_apply_runtime_defaults()
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_apply_runtime_defaults()
		return
	if typeof(json.data) == TYPE_DICTIONARY:
		runtime_config = (json.data as Dictionary).duplicate(true)
	_apply_runtime_defaults()


func _apply_runtime_defaults() -> void:
	if not runtime_config.has("version"):
		runtime_config["version"] = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if typeof(runtime_config.get("transport", {})) != TYPE_DICTIONARY:
		runtime_config["transport"] = {}
	if typeof(runtime_config.get("session", {})) != TYPE_DICTIONARY:
		runtime_config["session"] = {}
	if typeof(runtime_config.get("ai", {})) != TYPE_DICTIONARY:
		runtime_config["ai"] = {}
	active_robot_id = default_robot_id()


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
