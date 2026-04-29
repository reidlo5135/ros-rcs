extends SceneTree

const ScanLayerScript := preload("res://src/scene/layers/scan/scan_layer.gd")
const TfLayerScript := preload("res://src/scene/layers/tf/tf_layer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Scan layer test: build TF provider")
	var tf_layer := TfLayerScript.new()
	tf_layer.min_rebuild_interval_msec = 0
	root.add_child(tf_layer)
	await process_frame

	print("Scan layer test: apply TF")
	tf_layer.apply_state({
		"tf_static": {
			"transforms": [
				{
					"header": {"frame_id": "map"},
					"child_frame_id": "base_scan",
					"translation": {"x": 1.0, "y": 0.0, "z": 0.0},
					"rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
				},
			],
		},
		"tf": {},
		"robot_pose": {},
	})

	print("Scan layer test: build scan layer")
	var scan_layer := ScanLayerScript.new()
	scan_layer.min_rebuild_interval_msec = 0
	scan_layer.tf_provider = tf_layer
	root.add_child(scan_layer)
	await process_frame

	print("Scan layer test: apply scan")
	scan_layer.apply_state({
		"scan": {
			"frame": "base_scan",
			"angle_min": 0.0,
			"angle_increment": PI * 0.5,
			"range_min": 0.05,
			"range_max": 5.0,
			"ranges": [1.0, 2.0, null, 0.01],
		},
		"robot_pose": {},
	})

	var mesh := scan_layer.get_node_or_null("LaserScanRays")
	if mesh == null:
		push_error("Scan layer did not render LaserScan rays")
		scan_layer.queue_free()
		tf_layer.queue_free()
		quit(1)
		return

	print("Scan layer test passed")
	scan_layer.queue_free()
	tf_layer.queue_free()
	await process_frame
	quit()
