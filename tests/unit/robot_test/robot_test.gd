extends SceneTree

const RobotLayerScript := preload("res://src/scene/layers/robot/robot_layer.gd")


func _init() -> void:
	var layer := RobotLayerScript.new()
	var tiny_scaled_base: Vector3 = layer._mesh_proxy_size(
		"package://turtlebot3_description/meshes/bases/burger_base.dae",
		"0.001 0.001 0.001",
		"base_link"
	)
	if tiny_scaled_base.x < 0.14 or tiny_scaled_base.z < 0.11:
		push_error("URDF mesh proxy was incorrectly shrunk by tiny mesh scale")
		layer.free()
		quit(1)
		return

	var double_scaled_base: Vector3 = layer._mesh_proxy_size(
		"package://turtlebot3_description/meshes/bases/burger_base.dae",
		"2 1 1",
		"base_link"
	)
	if double_scaled_base.x <= tiny_scaled_base.x:
		push_error("URDF mesh proxy ignored meaningful mesh scale")
		layer.free()
		quit(1)
		return

	var wheel_mesh := layer._mesh_proxy_geometry(
		"package://turtlebot3_description/meshes/wheels/left_wheel.dae",
		"0.001 0.001 0.001",
		"wheel_left_link"
	)
	if not wheel_mesh is CylinderMesh:
		push_error("URDF wheel mesh proxy should use a cylinder")
		layer.free()
		quit(1)
		return

	var lidar_mesh := layer._mesh_proxy_geometry(
		"package://turtlebot3_description/meshes/sensors/hlds_lfcd_lds.dae",
		"0.001 0.001 0.001",
		"base_scan"
	)
	if not lidar_mesh is CylinderMesh:
		push_error("URDF lidar mesh proxy should use a cylinder")
		layer.free()
		quit(1)
		return
	if lidar_mesh.height < 0.03:
		push_error("URDF lidar mesh proxy should stay visibly tall")
		layer.free()
		quit(1)
		return

	var base_marker := layer._build_link_marker("base_link")
	if base_marker.get_child_count() < 3:
		push_error("URDF base proxy should expose a composed robot silhouette")
		layer.free()
		quit(1)
		return
	if not base_marker.has_node("IntegratedLidar"):
		push_error("URDF base proxy should carry the integrated lidar silhouette")
		layer.free()
		quit(1)
		return

	if layer._build_special_link_proxy("plate_1_link") != null:
		push_error("URDF burger plate links should not collapse into the base silhouette")
		layer.free()
		quit(1)
		return

	var lidar_marker := layer._build_link_marker("base_scan")
	if lidar_marker.get_child_count() < 2:
		push_error("URDF lidar proxy should include a readable top cap")
		layer.free()
		quit(1)
		return

	var lidar_proxy_transform := layer._special_proxy_transform("base_scan", [
		{"origin": {"xyz": "0 0 0.12", "rpy": "0 0 0"}, "geometry": {"type": "mesh", "filename": "package://turtlebot3_description/meshes/sensors/hlds_lfcd_lds.dae"}},
	], [])
	if lidar_proxy_transform != Transform3D.IDENTITY:
		push_error("URDF lidar proxy should not apply visual origin twice")
		layer.free()
		quit(1)
		return

	var lidar_link := Node3D.new()
	layer._add_link_visuals(lidar_link, "base_scan", [], [])
	if lidar_link.get_child_count() != 0:
		push_error("URDF lidar link should not render as a detached standalone proxy")
		lidar_link.free()
		layer.free()
		quit(1)
		return
	lidar_link.free()

	var footprint_link := Node3D.new()
	layer._add_link_visuals(footprint_link, "base_footprint", [], [])
	if footprint_link.get_child_count() != 0:
		push_error("URDF base_footprint should not render as a second robot silhouette")
		footprint_link.free()
		layer.free()
		quit(1)
		return
	footprint_link.free()

	var wheel_link := Node3D.new()
	layer._add_link_visuals(wheel_link, "wheel_left_link", [
		{"origin": {}, "geometry": {"type": "mesh", "filename": "package://turtlebot3_description/meshes/wheels/left_wheel.dae"}},
		{"origin": {}, "geometry": {"type": "mesh", "filename": "package://turtlebot3_description/meshes/wheels/left_wheel.dae"}},
	], [])
	if wheel_link.get_child_count() != 1:
		push_error("URDF wheel proxy should collapse repeated visuals into one integrated wheel")
		wheel_link.free()
		layer.free()
		quit(1)
		return
	wheel_link.free()

	var base_material: StandardMaterial3D = layer._material_for_link("base_link", {})
	if base_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		push_error("URDF base material should render opaque for RViz-like part colors")
		layer.free()
		quit(1)
		return
	if base_material.albedo_color.a < 0.99:
		push_error("URDF base material should stay fully opaque")
		layer.free()
		quit(1)
		return

	var plate_material: StandardMaterial3D = layer._material_for_link("plate_1_link", {})
	if plate_material.albedo_color == base_material.albedo_color:
		push_error("URDF plate material should use a distinct part color")
		layer.free()
		quit(1)
		return

	print("Robot layer test passed")
	layer.free()
	quit()
