# amr_mqtt_server

Robot-side MQTT API server for the AMR runtime.

`amr_mqtt_server` is the MQTT contract boundary between the on-robot ROS 2 stack and external clients such as `ros-rcs`. It now runs as an `rclcpp`-based node, accepts operator-facing commands, publishes navigation lifecycle updates, and still forwards parts of the older data plane while that layer is being refactored.

## Role

- expose a robot-scoped MQTT API under `/<root>/<robot_id>/...`
- keep the client-facing contract understandable without ROS-specific topic naming
- translate MQTT commands into ROS publishers, services, and actions
- publish JSON feedback, status, and result messages for route execution
- keep backward-compatible high-volume data streams alive temporarily during the data-plane migration

## Parameter Section

Use the central parameter block in [amr.yaml](/home/reidlo/ws/src/ros-amr-navigation/amr_bringup/params/amr.yaml):

```yaml
/amr/mqtt_server:
```

Current defaults in this repository:

- MQTT root: `/amr`
- `robot_id`: `burger1`
- `raw_telemetry_enabled`: `false`
- broker host: `192.168.61.35`
- broker port: `1883`
- QoS: `0`

## Topic Shape

All MQTT topics are scoped like this:

```text
/<root>/<robot_id>/<domain>/<channel>
```

With the current defaults:

```text
/amr/burger1/<domain>/<channel>
```

Examples:

- `/amr/burger1/navigation/command`
- `/amr/burger1/navigation/result`
- `/amr/burger1/pose/set`
- `/amr/burger1/map/result`

## Canonical Control Plane

These are the current operator-facing topics that `ros-rcs` should treat as canonical.

| Topic | Direction | Payload | Purpose |
| --- | --- | --- | --- |
| `/amr/<robot_id>/navigation/command` | client -> robot | JSON | start `NavigateToPoses` |
| `/amr/<robot_id>/navigation/cancel` | client -> robot | JSON | cancel the active route |
| `/amr/<robot_id>/navigation/feedback` | robot -> client | JSON | live route progress feedback |
| `/amr/<robot_id>/navigation/status` | robot -> client | JSON | action status updates |
| `/amr/<robot_id>/navigation/result` | robot -> client | JSON | navigation command ack, cancel ack, goal acceptance, and final result |
| `/amr/<robot_id>/pose/set` | client -> robot | JSON | publish initial pose |
| `/amr/<robot_id>/pose/result` | robot -> client | JSON | initial pose result |
| `/amr/<robot_id>/map/save` | client -> robot | JSON | save refined map |
| `/amr/<robot_id>/map/result` | robot -> client | JSON | map save result |
| `/amr/<robot_id>/motion/command` | client -> robot | JSON or raw ROS serialized `Twist` | publish `cmd_vel` |
| `/amr/<robot_id>/segment/request` | client -> robot | JSON | dispatch `plan_segment` service request |
| `/amr/<robot_id>/segment/response` | robot -> client | JSON | `plan_segment` dispatch result |
| `/amr/<robot_id>/route/request` | client -> robot | JSON | dispatch `plan_route` service request |
| `/amr/<robot_id>/route/response` | robot -> client | JSON | `plan_route` dispatch result |
| `/amr/<robot_id>/system/ping` | client -> robot | JSON | ping / RTT request |
| `/amr/<robot_id>/system/result` | robot -> client | JSON | ping result or robot-id change result |
| `/amr/<robot_id>/system/robot` | client -> robot | JSON | schedule robot-id change |

## Command Payloads

### `navigation/command`

Single-goal and multi-goal navigation both use `goal_poses[]`.

Required fields:

- `request_id`
- `goal_poses`

Rules:

- `goal_poses` must be a non-empty array
- a single-goal route is still expressed as a one-element array
- if another route is already active, the request is rejected

Example:

```json
{
  "request_id": "route-001",
  "goal_poses": [
    {
      "frame": "map",
      "position": { "x": 1.0, "y": 0.5, "z": 0.0 },
      "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
    },
    {
      "frame": "map",
      "position": { "x": 2.0, "y": 1.2, "z": 0.0 },
      "orientation": { "x": 0.0, "y": 0.0, "z": 0.7071, "w": 0.7071 }
    }
  ]
}
```

### `navigation/cancel`

Required fields:

- `request_id`

Example:

```json
{
  "request_id": "route-001-cancel"
}
```

### `pose/set`

Structured pose payload is supported and should be preferred by clients.

Required fields:

- `request_id`
- `pose.position.x`
- `pose.position.y`
- `pose.orientation`

Optional fields:

- `frame`, default `"map"`
- `frame_id`, still accepted for compatibility
- `covariance_x`, default `0.25`
- `covariance_y`, default `0.25`
- `covariance_yaw`, default `0.06853891945200942`

Example:

```json
{
  "request_id": "init-001",
  "frame": "map",
  "pose": {
    "position": { "x": 0.03, "y": -0.10, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
  }
}
```

Legacy compatibility:

- flat `x`, `y`, `yaw` payloads are still accepted

### `map/save`

Required fields:

- `request_id`
- `basename`

Example:

```json
{
  "request_id": "map-save-001",
  "basename": "warehouse_a_001"
}
```

### `motion/command`

Two payload styles are accepted.

1. Structured JSON:

```json
{
  "linear": { "x": 0.1, "y": 0.0, "z": 0.0 },
  "angular": { "x": 0.0, "y": 0.0, "z": 0.3 }
}
```

2. Flat JSON:

```json
{
  "linear_x": 0.1,
  "angular_z": 0.3
}
```

3. Raw ROS serialized `geometry_msgs/msg/Twist`

`motion/command` does not emit a result topic.

### `segment/request`

Required fields:

- `request_id`
- `start`
- `goal`

Example:

```json
{
  "request_id": "segment-001",
  "start": {
    "frame": "map",
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
  },
  "goal": {
    "frame": "map",
    "position": { "x": 1.0, "y": 0.5, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
  }
}
```

### `route/request`

Required fields:

- `request_id`
- `start`
- `waypoints`

Example:

```json
{
  "request_id": "route-plan-001",
  "start": {
    "frame": "map",
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
  },
  "waypoints": [
    {
      "frame": "map",
      "position": { "x": 1.0, "y": 0.5, "z": 0.0 },
      "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
    }
  ]
}
```

### `system/ping`

Required fields:

- `request_id`

Optional fields:

- `sent_at_ms`

Example:

```json
{
  "request_id": "ping-001",
  "sent_at_ms": 1776068466406.0
}
```

### `system/robot`

Required fields:

- `request_id`
- `robot_id`

Allowed characters:

- letters
- digits
- `_`
- `-`

Example:

```json
{
  "request_id": "robot-001",
  "robot_id": "burger2"
}
```

## Response and Stream Payloads

### Simple result shape

Used by:

- `pose/result`
- `map/result`
- `segment/response`
- `route/response`
- some `navigation/result` phases
- some `system/result` phases

Shape:

```json
{
  "request_id": "req-001",
  "success": true,
  "message": "ok"
}
```

### `navigation/feedback`

Published while a route is active.

Notes:

- response payloads no longer expose ROS `header`
- when frame context matters, a flat `frame` field is used instead

Shape:

```json
{
  "goal_id": "hexuuid",
  "current_goal_index": 0,
  "goal_count": 2,
  "distance_remaining": 1.234,
  "number_of_recoveries": 0,
  "navigation_time": { "sec": 12, "nanosec": 0 },
  "estimated_time_remaining": { "sec": 7, "nanosec": 0 },
  "current_pose": {
    "frame": "map",
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0, "yaw": 0.0 }
  }
}
```

### `navigation/status`

Published from the ROS action status stream.

Shape:

```json
{
  "status_list": [
    {
      "goal_id": "hexuuid",
      "status": 2
    }
  ]
}
```

Status codes come from `action_msgs/msg/GoalStatus`.

### `navigation/result`

This topic is multiplexed and clients should treat it as the navigation lifecycle result channel.

It may publish:

- invalid request result
- active-goal rejection
- cancel dispatch result
- goal accepted or rejected result
- final action result

Final route result shape:

```json
{
  "request_id": "route-001",
  "success": true,
  "accepted": true,
  "completed": true,
  "status_code": 4,
  "completed_goals": 3,
  "message": "succeeded"
}
```

Notes:

- `accepted` indicates whether the action goal was accepted
- `completed` indicates whether the route reached a terminal result
- `status_code` is the ROS action terminal status code
- cancel dispatch currently also returns through this topic using the simple result shape

### `system/result`

This topic is also multiplexed.

It may publish:

- ping response:

```json
{
  "request_id": "ping-001",
  "success": true,
  "sent_at_ms": 1776068466406.0,
  "bridge_time_ms": 123456789,
  "message": "pong"
}
```

- robot-id change scheduling result:

```json
{
  "request_id": "robot-001",
  "success": true,
  "message": "robot_id change scheduled"
}
```

## Legacy Data Plane

The heavy data plane is still in transition from the old `telemetry/*` plus `viz/*` mirror model.

Compatibility note:

- TF payloads keep ROS-like `header.frame_id` and `child_frame_id` fields for client compatibility
- newer control-plane payloads still use the flatter non-ROS schema described above
- raw binary `telemetry/*` publish is now gated by `mqtt.raw_telemetry_enabled`
- default repository setting is `false`, which suppresses raw `telemetry/*` binary publish entirely

The current implementation still emits high-volume MQTT topics such as:

- `telemetry/map`
- `telemetry/robot_pose`
- `telemetry/global_path`
- `telemetry/local_path`
- `telemetry/global_costmap`
- `telemetry/local_costmap`
- `telemetry/scan`
- `telemetry/tf`
- `telemetry/temp_map/raw`
- `telemetry/temp_map/refined`
- `telemetry/observation/runtime/summary`
- `telemetry/observation/runtime/events`

These are still present for compatibility and migration, but they are not the preferred operator-facing control contract.

When `mqtt.raw_telemetry_enabled` is `false`:

- raw binary `telemetry/*` messages are not published
- JSON `viz/*` messages continue to publish
- control-plane topics such as `navigation/*`, `pose/*`, `map/*`, `system/*` are unaffected

## Viz Payload Schemas

`viz/*` topics are derived from `telemetry/*` topics by replacing the `/telemetry/` path segment with `/viz/`.

Example:

```text
/amr/burger1/telemetry/scan -> /amr/burger1/viz/scan
```

The sections below describe the current JSON payload shapes emitted by `amr_mqtt_server` for visualization consumers such as `ros-rcs`.

### `viz/robot_pose`

```json
{
  "frame": "map",
  "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
  "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0, "yaw": 0.0 }
}
```

### `viz/global_path` and `viz/local_path`

```json
{
  "frame": "map",
  "pose_count": 2,
  "poses": [
    {
      "frame": "map",
      "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
      "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0, "yaw": 0.0 }
    }
  ]
}
```

### `viz/map`, `viz/global_costmap`, `viz/local_costmap`, `viz/temp_map/raw`, `viz/temp_map/refined`

```json
{
  "frame": "map",
  "info": {
    "width": 311,
    "height": 320,
    "resolution": 0.05,
    "origin": {
      "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
      "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0, "yaw": 0.0 }
    }
  },
  "data": [0, 0, 100]
}
```

### `viz/motion_status`

```json
{
  "frame": "map",
  "command_id": 12,
  "active": true,
  "goal_reached": false,
  "obstacle_detected": false,
  "blocked": false,
  "stalled": false,
  "local_plan_valid": true,
  "costmap_blocked": false,
  "safety_gate_blocked": false,
  "has_blocked_pose": false,
  "remaining_distance": 1.25,
  "heading_error": 0.05,
  "current_pose": {
    "frame": "map",
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0, "yaw": 0.0 }
  },
  "blocked_pose": {
    "frame": "map",
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0, "yaw": 0.0 }
  }
}
```

### `viz/scan`

```json
{
  "frame": "base_scan",
  "angle_min": 0.0,
  "angle_max": 6.283185,
  "angle_increment": 0.01563,
  "range_min": 0.1,
  "range_max": 100.0,
  "ranges_count": 401,
  "ranges": [1.23, null, 0.0]
}
```

Notes:

- `frame` is the sensor frame, typically `base_scan`
- angles follow ROS `LaserScan` semantics
- visualization clients must transform scan points from the scan frame into the fixed frame using TF

### `viz/odom`

```json
{
  "frame": "odom",
  "child_frame": "base_link",
  "pose": {
    "position": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "orientation": { "x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0 }
  },
  "twist": {
    "linear": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "angular": { "x": 0.0, "y": 0.0, "z": 0.0 }
  }
}
```

### `viz/tf` and `viz/tf_static`

TF payloads intentionally keep ROS-style frame fields for compatibility.

```json
{
  "transforms": [
    {
      "header": {
        "stamp": { "sec": 1776131971, "nanosec": 971017774 },
        "frame_id": "map"
      },
      "child_frame_id": "odom",
      "translation": { "x": -0.23, "y": 0.02, "z": 0.0 },
      "rotation": { "x": 0.0, "y": 0.0, "z": -0.012, "w": 0.999, "yaw": -0.0245 }
    }
  ]
}
```

Notes:

- `viz/tf` is incremental and may contain partial updates
- clients should merge transforms by `child_frame_id`
- `viz/tf_static` should be treated as persistent static transforms

### `viz/battery_state`

```json
{
  "frame": "base_link",
  "voltage": 11.9,
  "current": -0.4,
  "percentage": 70.0,
  "power_supply_status": 2,
  "power_supply_health": 1,
  "power_supply_technology": 3,
  "present": true
}
```

### `viz/robot_description`

```json
{
  "data": "<robot ... />",
  "footprint_polygon": [-0.1, -0.09, 0.1, -0.09, 0.1, 0.09, -0.1, 0.09]
}
```

### `viz/slam_graph`, `viz/observation/runtime/summary`, `viz/observation/runtime/events`

These topics forward JSON strings produced by the corresponding ROS publishers.

For these topics, `amr_mqtt_server` does not reshape the payload. Consumers should parse the message body as-is.

## Recommended `ros-rcs` Usage

For current `ros-rcs` integration, treat these as primary:

- `navigation/command`
- `navigation/cancel`
- `navigation/feedback`
- `navigation/status`
- `navigation/result`
- `pose/set`
- `pose/result`
- `map/save`
- `map/result`
- `system/ping`
- `system/result`

Treat the legacy `telemetry/*` streams as transitional data sources only where the UI still needs them.

## Current Direction

- keep MQTT as the only external protocol
- keep the client-facing contract non-ROS-friendly
- move control and lifecycle traffic to compact JSON request/result topics
- refactor the heavy state and map streams separately for performance
