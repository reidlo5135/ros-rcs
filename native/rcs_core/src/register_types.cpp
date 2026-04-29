#include "rcs_core/register_types.hpp"

#include "rcs_core/rcs_laser_scan_projector.hpp"
#include "rcs_core/rcs_occupancy_codec.hpp"
#include "rcs_core/rcs_path_projector.hpp"
#include "rcs_core/rcs_protocol_codec.hpp"
#include "rcs_core/rcs_tf_resolver.hpp"

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_rcs_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	ClassDB::register_class<RcsProtocolCodec>();
	ClassDB::register_class<RcsOccupancyCodec>();
	ClassDB::register_class<RcsTfResolver>();
	ClassDB::register_class<RcsLaserScanProjector>();
	ClassDB::register_class<RcsPathProjector>();
}

void uninitialize_rcs_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT rcs_core_library_init(
	GDExtensionInterfaceGetProcAddress p_get_proc_address,
	GDExtensionClassLibraryPtr p_library,
	GDExtensionInitialization *r_initialization
) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_rcs_core);
	init_obj.register_terminator(uninitialize_rcs_core);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
