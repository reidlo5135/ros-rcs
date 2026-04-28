extends RefCounted
class_name RcsAiPromptParser


static func parse(message: String, fallback_robot_id := "burger1") -> Dictionary:
	var text := message.strip_edges()
	if text.is_empty():
		return {}
	var x_match: Variant = _search(text, "(?i)\\bx\\s*=\\s*([-+]?\\d+(?:\\.\\d+)?)")
	var y_match: Variant = _search(text, "(?i)\\by\\s*=\\s*([-+]?\\d+(?:\\.\\d+)?)")
	if x_match == null or y_match == null:
		return {}

	var x := float((x_match as RegExMatch).get_string(1))
	var y := float((y_match as RegExMatch).get_string(1))
	var yaw := 0.0
	var yaw_match: Variant = _search(text, "(?i)\\byaw\\s*=\\s*([-+]?\\d+(?:\\.\\d+)?)")
	if yaw_match != null:
		yaw = float((yaw_match as RegExMatch).get_string(1))

	var frame := "map"
	var frame_match: Variant = _search(text, "(?i)\\bin\\s+([A-Za-z0-9_\\-/]+)")
	if frame_match != null:
		frame = str((frame_match as RegExMatch).get_string(1)).strip_edges().trim_suffix(".")
	if frame.is_empty():
		frame = "map"

	var robot_id := _robot_id_from(text, fallback_robot_id)
	return {
		"kind": "navigation_pose",
		"robot_id": robot_id,
		"x": x,
		"y": y,
		"yaw": yaw,
		"frame": frame,
	}


static func _robot_id_from(text: String, fallback_robot_id: String) -> String:
	var clean_fallback := fallback_robot_id.strip_edges()
	if clean_fallback.is_empty():
		clean_fallback = "burger1"
	var words := text.strip_edges().split(" ", false)
	if words.size() < 2:
		return clean_fallback
	var candidate := str(words[1]).strip_edges().trim_suffix(",").trim_suffix(".")
	var lowered := candidate.to_lower()
	if lowered in ["to", "goal", "x", "y", "yaw", "in"]:
		return clean_fallback
	return candidate if not candidate.is_empty() else clean_fallback


static func _search(text: String, pattern: String) -> Variant:
	var regex := RegEx.new()
	var compile_error := regex.compile(pattern)
	if compile_error != OK:
		return null
	return regex.search(text)