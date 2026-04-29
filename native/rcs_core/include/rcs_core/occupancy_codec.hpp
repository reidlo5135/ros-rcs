#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class RcsOccupancyCodec : public RefCounted {
	GDCLASS(RcsOccupancyCodec, RefCounted)

protected:
	static void _bind_methods();

public:
	PackedByteArray build_rgba(const Array &p_data, int32_t p_width, int32_t p_height, const String &p_palette) const;

private:
	PackedByteArray color_for_value(int32_t p_value, const String &p_palette) const;
};

} // namespace godot
