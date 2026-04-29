extends SceneTree

const TfLayerScript := preload("res://src/scene/layers/tf_layer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var layer := TfLayerScript.new()
	layer.min_rebuild_interval_msec = 0
	root.add_child(layer)
	await process_frame

	layer.apply_state({
		"tf_static": {
			"transforms": [
				{
					"header": {"frame_id": "map"},
					"child_frame_id": "odom",
					"translation": {"x": 1.0, "y": 2.0, "z": 0.0},
					"rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
				},
			],
		},
		"tf": {},
		"robot_pose": {},
	})
	layer.apply_state({
		"tf_static": {},
		"tf": {
			"transforms": [
				{
					"header": {"frame_id": "odom"},
					"child_frame_id": "base_footprint",
					"translation": {"x": 0.2, "y": 0.1, "z": 0.0},
					"rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
				},
			],
		},
		"robot_pose": {},
	})
	layer.apply_state({
		"tf_static": {},
		"tf": {
			"transforms": [
				{
					"header": {"frame_id": "base_footprint"},
					"child_frame_id": "base_link",
					"translation": {"x": 0.0, "y": 0.0, "z": 0.0},
					"rotation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0},
				},
			],
		},
		"robot_pose": {},
	})

	var frame_root := layer.get_node_or_null("TfFrames")
	if frame_root == null or not frame_root.has_node("map") or not frame_root.has_node("odom") or not frame_root.has_node("base_footprint") or not frame_root.has_node("base_link"):
		push_error("TF layer did not preserve incremental map -> odom -> base_footprint -> base_link frames")
		layer.queue_free()
		quit(1)
		return

	print("TF layer test passed")
	layer.queue_free()
	await process_frame
	quit()
