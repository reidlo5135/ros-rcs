extends RefCounted


var _native_reader: Variant = null


func _init() -> void:
	if ClassDB.class_exists("RcsReplayReader"):
		_native_reader = ClassDB.instantiate("RcsReplayReader")


func parse_text(text: String) -> Array:
	if _native_reader != null:
		return _native_reader.parse_text(text)
	return parse_lines(text.split("\n", false))


func parse_lines(lines: PackedStringArray) -> Array:
	if _native_reader != null:
		return _native_reader.parse_lines(lines)

	var frames: Array = []
	for index in range(lines.size()):
		var line: String = lines[index].strip_edges()
		if line.is_empty():
			continue
		var payload: Variant = JSON.parse_string(line)
		if typeof(payload) != TYPE_DICTIONARY:
			frames.append({
				"line": index + 1,
				"ok": false,
				"error": "replay line is not a JSON object",
				"raw": line,
			})
			continue
		var replay_entry: Dictionary = payload
		frames.append({
			"line": index + 1,
			"ok": true,
			"timestamp": replay_entry.get("timestamp", replay_entry.get("time", 0.0)),
			"topic": replay_entry.get("topic", ""),
			"payload": replay_entry.get("payload", replay_entry),
			"meta": replay_entry,
		})
	return frames
