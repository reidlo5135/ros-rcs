#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class RcsProtocolCodec : public RefCounted {
	GDCLASS(RcsProtocolCodec, RefCounted)

protected:
	static void _bind_methods();

public:
	String normalize_topic(const String &p_topic) const;
	String resolve_robot_topic(const String &p_template, const String &p_robot_id) const;
	String command_topic(const String &p_robot_id, const String &p_command_key) const;
	Dictionary build_command(const String &p_robot_id, const String &p_kind, const Dictionary &p_payload) const;
};

} // namespace godot
