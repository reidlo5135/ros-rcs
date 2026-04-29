#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class RcsDiffDriveSimulator : public RefCounted {
	GDCLASS(RcsDiffDriveSimulator, RefCounted)

protected:
	static void _bind_methods();

public:
	void reset(const Dictionary &p_pose);
	void set_command(const Dictionary &p_twist);
	Dictionary step(double p_delta_seconds);
	Dictionary pose() const;

private:
	double x = 0.0;
	double y = 0.0;
	double yaw = 0.0;
	double linear_x = 0.0;
	double angular_z = 0.0;
};

} // namespace godot
