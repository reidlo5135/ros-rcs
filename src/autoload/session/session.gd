extends Node

signal session_added(session_id: String)
signal active_session_changed(session_id: String)
signal telemetry_updated(session_id: String, patch: Dictionary)

const RcsBridgeStateScript := preload("res://src/domain/telemetry/bridge_state.gd")

var sessions: Dictionary = {}
var active_session_id := "robot:burger1"


func _ready() -> void:
	register_robot("burger1")


func register_robot(robot_id: String) -> String:
	var clean_id := robot_id.strip_edges()
	if clean_id.is_empty():
		clean_id = "burger1"
	var session_id := "robot:" + clean_id
	if not sessions.has(session_id):
		sessions[session_id] = {
			"kind": "robot",
			"id": clean_id,
			"state": RcsBridgeStateScript.new(),
			"last_seen_at_msec": 0,
			"connected": false,
		}
		session_added.emit(session_id)
	return session_id


func set_active_session(session_id: String) -> void:
	if not sessions.has(session_id):
		return
	active_session_id = session_id
	AppState.set_active_robot(sessions[session_id].get("id", "burger1"))
	active_session_changed.emit(session_id)


func set_active_robot(robot_id: String) -> void:
	set_active_session(register_robot(robot_id))


func apply_telemetry_patch(robot_id: String, patch: Dictionary) -> void:
	var session_id := register_robot(robot_id)
	var session := sessions[session_id] as Dictionary
	var state = session.get("state")
	if state != null and state.has_method("apply_patch"):
		state.apply_patch(patch)
	session["last_seen_at_msec"] = Time.get_ticks_msec()
	session["connected"] = true
	sessions[session_id] = session
	telemetry_updated.emit(session_id, patch)
