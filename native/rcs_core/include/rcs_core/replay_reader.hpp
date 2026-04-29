#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class RcsReplayReader : public RefCounted {
	GDCLASS(RcsReplayReader, RefCounted)

protected:
	static void _bind_methods();

public:
	Array parse_text(const String &p_text) const;
	Array parse_lines(const PackedStringArray &p_lines) const;
};

} // namespace godot
