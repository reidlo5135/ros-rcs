extends RefCounted
class_name RcsBridgeState

var map: Dictionary = {}
var global_costmap: Dictionary = {}
var local_costmap: Dictionary = {}
var robot_pose: Dictionary = {}
var global_path: Dictionary = {}
var local_path: Dictionary = {}
var motion_status: Dictionary = {}
var scan: Dictionary = {}
var tf: Dictionary = {}
var tf_static: Dictionary = {}
var robot_description := ""
var urdf_model: Dictionary = {}
var battery_state: Dictionary = {}


func apply_patch(patch: Dictionary) -> void:
	for key in patch.keys():
		set(key, patch[key])


func clear_live_data() -> void:
	global_costmap.clear()
	local_costmap.clear()
	global_path.clear()
	local_path.clear()
	scan.clear()
	tf.clear()
	motion_status.clear()
