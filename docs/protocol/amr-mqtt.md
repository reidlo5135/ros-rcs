# AMR MQTT Compatibility

The Godot reset keeps the existing AMR topic contract as the initial compatibility target.

## Visualization Topics

```text
/amr/{robot_id}/viz/map
/amr/{robot_id}/viz/global_costmap
/amr/{robot_id}/viz/local_costmap
/amr/{robot_id}/viz/robot_pose
/amr/{robot_id}/viz/global_path
/amr/{robot_id}/viz/local_path
/amr/{robot_id}/viz/motion_status
/amr/{robot_id}/viz/scan
/amr/{robot_id}/viz/battery_state
/amr/{robot_id}/viz/tf
/amr/{robot_id}/viz/tf_static
/amr/{robot_id}/viz/robot_description
```

## Command Topics

```text
/amr/{robot_id}/navigation/command
/amr/{robot_id}/navigation/cancel
/amr/{robot_id}/pose/set
/amr/{robot_id}/map/save
/amr/{robot_id}/motion/command
/amr/{robot_id}/segment/request
/amr/{robot_id}/route/request
/amr/{robot_id}/system/ping
/amr/{robot_id}/system/robot
```

## Security Direction

The current compatibility target is plain MQTT over WebSocket, matching the previous RCS behavior.

Production hardening should later move operator-to-broker transport to `wss://` and reject plaintext broker URLs in production builds.
