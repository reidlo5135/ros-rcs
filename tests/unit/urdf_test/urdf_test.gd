extends SceneTree

const UrdfParserScript := preload("res://src/domain/robot_model/urdf_parser.gd")


func _init() -> void:
	UrdfParserScript.set_package_roots({
		"turtlebot3_description": "res://assets/robots/turtlebot3_description",
	})
	var xml: String = """
<robot name="burger_test">
  <link name="base_link">
    <visual>
      <origin xyz="0 0 0" rpy="0 0 0"/>
      <geometry>
        <mesh filename="package://turtlebot3_description/meshes/base.dae" scale="1 1 1"/>
      </geometry>
    </visual>
    <collision>
      <origin xyz="0 0 0.02" rpy="0 0 0"/>
      <geometry>
        <box size="0.16 0.14 0.02"/>
      </geometry>
    </collision>
  </link>
  <link name="laser_link"/>
  <joint name="base_to_laser" type="fixed">
    <parent link="base_link"/>
    <child link="laser_link"/>
    <origin xyz="0 0 0.2" rpy="0 0 0"/>
  </joint>
</robot>
"""
	var model: Dictionary = UrdfParserScript.parse(xml)
	if not str(model.get("parse_error", "")).is_empty():
		push_error("URDF parse failed: " + str(model["parse_error"]))
		quit(1)
		return
	if model.get("name", "") != "burger_test":
		push_error("Unexpected URDF robot name")
		quit(1)
		return
	if (model.get("link_order", []) as Array).size() != 2:
		push_error("Unexpected URDF link count")
		quit(1)
		return
	if (model.get("joint_order", []) as Array).size() != 1:
		push_error("Unexpected URDF joint count")
		quit(1)
		return
	if int(model.get("mesh_count", 0)) != 1:
		push_error("Unexpected URDF mesh count")
		quit(1)
		return
	if int(model.get("collision_count", 0)) != 1:
		push_error("Unexpected URDF collision count")
		quit(1)
		return
	var base_link: Dictionary = model.get("links", {}).get("base_link", {})
	if (base_link.get("collisions", []) as Array).size() != 1:
		push_error("Unexpected URDF collision storage")
		quit(1)
		return
	var visuals: Array = base_link.get("visuals", [])
	if visuals.is_empty():
		push_error("Expected URDF visual metadata")
		quit(1)
		return
	var mesh_geometry: Dictionary = visuals[0].get("geometry", {})
	if str(mesh_geometry.get("resolved_filename", "")) != "res://assets/robots/turtlebot3_description/meshes/base.dae":
		push_error("URDF mesh resolver did not annotate the expected resource path")
		quit(1)
		return
	if not bool(mesh_geometry.get("mesh_uri_resolved", false)):
		push_error("URDF mesh resolver should mark configured package meshes as resolved")
		quit(1)
		return
	if str(mesh_geometry.get("mesh_extension", "")) != "dae":
		push_error("URDF mesh resolver should preserve mesh extension metadata")
		quit(1)
		return
	var joint_transforms: Dictionary = model.get("joint_transforms", {})
	if not joint_transforms.has("base_to_laser"):
		push_error("URDF parser should emit joint transforms for downstream layers")
		quit(1)
		return
	var link_local_transforms: Dictionary = model.get("link_local_transforms", {})
	if not link_local_transforms.has("laser_link"):
		push_error("URDF parser should expose link-local transforms keyed by child link")
		quit(1)
		return
	print("URDF parser test passed")
	quit()
