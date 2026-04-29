#include "rcs_core/register_types.hpp"

#include "rcs_core/laser_scan_projector.hpp"
#include "rcs_core/occupancy_codec.hpp"
#include "rcs_core/path_projector.hpp"
#include "rcs_core/protocol_codec.hpp"
#include "rcs_core/replay_reader.hpp"
#include "rcs_core/diff_drive_simulator.hpp"
#include "rcs_core/tf_resolver.hpp"
#include "rcs_core/urdf_resolver.hpp"

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
	ClassDB::register_class<RcsUrdfResolver>();
	ClassDB::register_class<RcsReplayReader>();
	ClassDB::register_class<RcsDiffDriveSimulator>();
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
