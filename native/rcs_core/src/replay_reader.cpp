#include "rcs_core/replay_reader.hpp"

#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

void RcsReplayReader::_bind_methods() {
	ClassDB::bind_method(D_METHOD("parse_text", "text"), &RcsReplayReader::parse_text);
	ClassDB::bind_method(D_METHOD("parse_lines", "lines"), &RcsReplayReader::parse_lines);
}

Array RcsReplayReader::parse_text(const String &p_text) const {
	PackedStringArray lines = p_text.split("\n", false);
	return parse_lines(lines);
}

Array RcsReplayReader::parse_lines(const PackedStringArray &p_lines) const {
	Array frames;
	for (int64_t index = 0; index < p_lines.size(); index++) {
		String line = p_lines[index].strip_edges();
		if (line.is_empty()) {
			continue;
		}

		Dictionary frame;
		frame["line"] = int32_t(index + 1);
		Variant parsed = JSON::parse_string(line);
		if (parsed.get_type() != Variant::DICTIONARY) {
			frame["ok"] = false;
			frame["error"] = "replay line is not a JSON object";
			frame["raw"] = line;
			frames.append(frame);
			continue;
		}

		Dictionary payload = parsed;
		frame["ok"] = true;
		frame["timestamp"] = payload.get("timestamp", payload.get("time", 0.0));
		frame["topic"] = payload.get("topic", "");
		frame["payload"] = payload.get("payload", payload);
		frame["meta"] = payload;
		frames.append(frame);
	}
	return frames;
}

} // namespace godot
