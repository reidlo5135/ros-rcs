# RCS Godot

RCS is moving from a shared Web/Electron operator console to a Godot-native robot operation runtime.

Version `0.2.0` resets the product foundation around Godot 4, C++ GDExtension, and a stricter domain model for robot telemetry, commands, simulation, replay, and visualization.

## Goals

- Build the operator console as a native Godot application.
- Keep robot/session/protocol state outside scene scripts.
- Put high-stability core behavior in C++ GDExtension.
- Use Godot scenes for visualization, operation panels, replay, and simulation tooling.
- Preserve the current AMR MQTT contract as the first compatibility target.

## Project Shape

```text
addons/
  rcs_core/             # Runtime GDExtension package loaded by Godot.
assets/                 # Icons, materials, themes, meshes, maps.
docs/
  architecture/         # Product and runtime architecture notes.
  protocol/             # MQTT and payload contract notes.
native/
  rcs_core/             # C++ GDExtension source.
  third_party/          # External native dependencies such as godot-cpp.
project/
  config/               # Runtime defaults and environment templates.
  export/               # Export preset notes and packaging docs.
schemas/                # Stable message schemas.
src/
  app/                  # Main app scene and composition.
  autoload/             # Global Godot services.
  domain/               # Command, telemetry, session, simulation model.
  scene/                # 3D world and visualization layers.
  ui/                   # Operator controls and panels.
tests/                  # GDScript/native unit test entry points.
tools/                  # Developer scripts and build notes.
```

## Core Concepts

- `.tscn` files are Godot scenes. They define UI screens, panels, and 3D scene composition.
- `.gd` files are GDScript source files attached to scenes or used as domain services.
- `.gd.uid` and `.gdextension.uid` files are Godot-generated resource IDs. Keep them in Git so scene/script references stay stable after renames or moves.
- `project.godot` is the project entry point. It defines the main scene and autoload services.
- `src/autoload` contains global services such as `AppState`, `CommandBus`, and `SessionRegistry`.
- `src/domain` contains RCS state, protocol, command, session, transport, and telemetry logic. Raw MQTT payloads should be routed through this layer before reaching UI or scene scripts.
- `src/scene` contains the 3D operator world. `rcs_world.gd` currently creates the camera, grid floor, and temporary robot marker.
- `src/scene/layers` is the visualization layer model. Layers should eventually mirror RViz-style responsibilities such as map, costmap, robot, path, scan, TF, footprint, and goal markers.
- `native/rcs_core` is the C++ GDExtension workspace for behavior that should be strict and stable over time.

## Current Runtime Contract

This branch still treats MQTT like the previous RCS implementation. The first compatibility target is the existing AMR MQTT topic contract under `/amr/{robot_id}/...`.

Transport encryption is not implemented yet. The immediate development path follows the previous RCS behavior with plain MQTT over WebSocket:

```text
AMR MQTT payload -> telemetry router -> RCS bridge state -> Godot scene/UI
Operator command -> command factory -> MQTT publish
```

Default broker during this phase:

```text
ws://192.168.61.35:9001/mqtt
```

The default active robot is currently `burger1`. The operations panel uses a robot selector so `burger2` and other fleet IDs can be added later without changing the connection flow.

The MQTT WebSocket transport uses a 64 MB receive buffer so large RCS payloads such as `robot_description` URDF XML, map, and costmap messages can pass through the same path.

`robot_description` is now routed as XML instead of JSON. The first URDF pass parses robot name, links, joints, visual geometry, and mesh references, stores that model in `RcsBridgeState.urdf_model`, and renders primitive/proxy URDF geometry in the robot scene layer. Mesh loading and `package://` resolution are the next URDF steps.

The scene viewport starts in top-down orthographic mode like the previous RCS. Mouse wheel zooms, left/middle drag pans, right drag rotates around the ROS Z axis, Shift+right drag tilts into 3D, Shift+wheel or `Q`/`E` adjusts vertical height, `T` returns to top-down, `I` switches to isometric, and double-click or `R` resets the view. SLAM map payloads that follow the ROS `OccupancyGrid` shape are rendered as a native Godot texture plane, with global/local costmaps rendered as purple overlays. The map is framed from its `info.origin`, resolution, width, and height rather than from a decorative scene marker.

Godot UI `Control` coordinates start at the top-left with Y increasing downward. The 3D RCS scene uses ROS/RViz-style map semantics instead: ROS map `(x, y)` is mapped to Godot `(X=x, Z=-y)`. Occupancy grid pixels are vertically flipped when written to Godot image data so the displayed map aligns with the previous RCS/RViz view.

URDF mesh references such as `package://.../meshes/base.dae` need a package resolver plus imported mesh assets. Until those assets exist under the Godot project, `RobotLayer` follows the previous RCS behavior by rendering collision geometry or descriptor-based primitive/proxy geometry instead of the final robot meshes. Robot and TF materials are drawn above the map/costmap/grid layers so the active robot model remains inspectable.

`TfLayer` keeps a cumulative transform store from `tf_static` and live `tf`, resolves frames to map-frame positions where possible, and renders red X, green Y, and blue Z axes including the `map` root frame. If TF is unavailable but robot pose exists, it falls back to a single `base_link` frame at the robot pose.

Telemetry event logging is batched and capped so high-frequency topics such as TF, scan, motion status, and costmaps do not flood the Godot debug UI.

## Open In Godot

Open this directory as a Godot 4 project. The main scene is:

```text
res://src/app/main.tscn
```

The first screen is intentionally a native operator shell skeleton rather than a marketing page.

## Native Core

The C++ extension source lives in `native/rcs_core`. To build it, place or clone `godot-cpp` at:

```text
native/third_party/godot-cpp
```

Then run SCons from `native/rcs_core` once the Godot C++ bindings are available.

The GDExtension descriptor is currently stored as `addons/rcs_core/rcs_core.gdextension.template`. Rename or copy it to `rcs_core.gdextension` only after the native library has been built.

## Migration Baseline

The previous React/Electron implementation is preserved by branch history up to `humble/develop/0.1.7`.
The Godot reset starts at `humble/develop/0.2.0`.
