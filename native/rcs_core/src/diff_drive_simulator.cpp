#include "rcs_core/diff_drive_simulator.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

namespace godot {

void RcsDiffDriveSimulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("reset", "pose"), &RcsDiffDriveSimulator::reset);
	ClassDB::bind_method(D_METHOD("set_command", "twist"), &RcsDiffDriveSimulator::set_command);
	ClassDB::bind_method(D_METHOD("step", "delta_seconds"), &RcsDiffDriveSimulator::step);
	ClassDB::bind_method(D_METHOD("pose"), &RcsDiffDriveSimulator::pose);
}

void RcsDiffDriveSimulator::reset(const Dictionary &p_pose) {
	x = double(p_pose.get("x", 0.0));
	y = double(p_pose.get("y", 0.0));
	yaw = double(p_pose.get("yaw", p_pose.get("theta", 0.0)));
}

void RcsDiffDriveSimulator::set_command(const Dictionary &p_twist) {
	Variant linear_value = p_twist.get("linear", Dictionary());
	Variant angular_value = p_twist.get("angular", Dictionary());
	linear_x = double(p_twist.get("linear_x", 0.0));
	angular_z = double(p_twist.get("angular_z", 0.0));

	if (linear_value.get_type() == Variant::DICTIONARY) {
		Dictionary linear = linear_value;
		linear_x = double(linear.get("x", linear_x));
	}
	if (angular_value.get_type() == Variant::DICTIONARY) {
		Dictionary angular = angular_value;
		angular_z = double(angular.get("z", angular_z));
	}
}

Dictionary RcsDiffDriveSimulator::step(double p_delta_seconds) {
	if (p_delta_seconds > 0.0) {
		x += linear_x * std::cos(yaw) * p_delta_seconds;
		y += linear_x * std::sin(yaw) * p_delta_seconds;
		yaw += angular_z * p_delta_seconds;
	}
	return pose();
}

Dictionary RcsDiffDriveSimulator::pose() const {
	Dictionary current_pose;
	current_pose["x"] = x;
	current_pose["y"] = y;
	current_pose["yaw"] = yaw;
	current_pose["theta"] = yaw;
	current_pose["linear_x"] = linear_x;
	current_pose["angular_z"] = angular_z;
	return current_pose;
}

} // namespace godot
