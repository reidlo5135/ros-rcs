extends SceneTree

const UrdfParserScript := preload("res://src/domain/robot_model/urdf_parser.gd")


func _init() -> void:
	var xml := """
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
	var model := UrdfParserScript.parse(xml)
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
	print("URDF parser test passed")
	quit()
