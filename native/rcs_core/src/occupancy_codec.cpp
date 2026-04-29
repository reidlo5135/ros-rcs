#include "rcs_core/occupancy_codec.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

namespace godot {

void RcsOccupancyCodec::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build_rgba", "data", "width", "height", "palette"), &RcsOccupancyCodec::build_rgba);
}

PackedByteArray RcsOccupancyCodec::build_rgba(const Array &p_data, int32_t p_width, int32_t p_height, const String &p_palette) const {
	PackedByteArray bytes;
	if (p_width <= 0 || p_height <= 0) {
		return bytes;
	}

	bytes.resize(p_width * p_height * 4);
	const int64_t data_size = p_data.size();
	for (int32_t row = 0; row < p_height; row++) {
		for (int32_t column = 0; column < p_width; column++) {
			const int64_t source_index = row * p_width + column;
			const int32_t target_row = p_height - 1 - row;
			const int64_t target_index = ((target_row * p_width) + column) * 4;
			int32_t value = -1;
			if (source_index < data_size) {
				value = int32_t(p_data[source_index]);
			}
			PackedByteArray color = color_for_value(value, p_palette);
			bytes[target_index] = color[0];
			bytes[target_index + 1] = color[1];
			bytes[target_index + 2] = color[2];
			bytes[target_index + 3] = color[3];
		}
	}
	return bytes;
}

PackedByteArray RcsOccupancyCodec::color_for_value(int32_t p_value, const String &p_palette) const {
	PackedByteArray color;
	color.resize(4);
	if (p_palette == "map") {
		if (p_value < 0) {
			color[0] = 201;
			color[1] = 201;
			color[2] = 201;
			color[3] = 255;
			return color;
		}
		if (p_value >= 50) {
			color[0] = 36;
			color[1] = 22;
			color[2] = 48;
			color[3] = 255;
			return color;
		}
		color[0] = 255;
		color[1] = 255;
		color[2] = 255;
		color[3] = 255;
		return color;
	}

	if (p_value <= 0) {
		color[0] = 0;
		color[1] = 0;
		color[2] = 0;
		color[3] = 0;
		return color;
	}

	const double normalized = std::clamp(double(p_value) / 100.0, 0.0, 1.0);
	const uint8_t alpha = uint8_t(45.0 + normalized * 165.0);
	if (p_palette == "local_costmap") {
		color[0] = 188;
		color[1] = 76;
		color[2] = 175;
		color[3] = alpha;
		return color;
	}
	color[0] = 150;
	color[1] = 82;
	color[2] = 185;
	color[3] = alpha;
	return color;
}

} // namespace godot
