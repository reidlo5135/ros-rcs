# C++ Migration Priorities

This document ranks the RCS paths that should move from GDScript into
`native/rcs_core` as the Godot runtime stabilizes.

The goal is not to rewrite the app in C++. Keep orchestration, UI state, scene
composition, and operator workflows in GDScript. Move code when it is hot,
deterministic, payload-heavy, or shared by multiple layers.

## Priority Table

| Priority | Target | Current GDScript Surface | Native Shape | Why |
| --- | --- | --- | --- | --- |
| P0 | Occupancy/costmap texture generation | `src/scene/layers/map/map_layer.gd` | `RcsOccupancyCodec` returning `PackedByteArray` or `Image`-ready RGBA data | Largest repeated CPU loop today. Maps and costmaps can contain tens or hundreds of thousands of cells, and every rebuild walks the whole payload. |
| P0 | TF transform resolution | `src/scene/layers/tf/tf_layer.gd` | `RcsTfResolver` storing static/live edges and returning resolved frame transforms | Needed by TF axes, LaserScan, robot links, footprints, and paths. It is correctness-critical and benefits from strict data structures. |
| P1 | LaserScan point generation | planned `ScanLayer`, current `RcsBridgeState.scan` | `RcsLaserScanProjector` returning `PackedVector3Array` | Scan payloads are high frequency and can require hundreds of trig operations per frame. The output should be reusable by rendering, obstacle overlays, and simulation. |
| P1 | Path point extraction and transform | `src/scene/world/world.gd` path helpers | `RcsPathProjector` returning `PackedVector3Array` for global/local paths | Path updates are less expensive than maps, but the logic will be shared by `PathLayer`, route planning previews, and replay. |
| P1 | Hot MQTT codec/parsing paths | `src/domain/transport/mqtt_transport.gd`, `src/domain/telemetry/telemetry_router.gd`, `src/domain/protocol/topic_catalog.gd` | Extend `RcsProtocolCodec` with topic classification, command topic routing, payload diagnostics | Avoids repeated string parsing and centralizes protocol rules. This is also the best place to add parse failure counters and payload diagnostics. |
| P2 | URDF mesh/path resolution | `src/domain/robot_model/urdf_parser.gd`, `src/scene/layers/robot/robot_layer.gd` | `RcsUrdfResolver` for `package://` resolution, mesh metadata, and link/joint transforms | Important for correctness and startup time, but blocked on package roots and imported mesh asset layout. |
| P2 | URDF XML parse acceleration | `src/domain/robot_model/urdf_parser.gd` | Optional native parser returning the same `urdf_model` dictionary shape | Useful after mesh resolution exists. The current parser is acceptable while robot_description updates are infrequent. |
| P3 | Replay and simulation stepping | `src/domain/simulation`, future replay code | `RcsReplayReader`, `RcsDiffDriveSimulator` | Keep later until runtime data contracts are stable. Native code helps determinism once replay files become large. |

## Recommended Order

1. **Occupancy/costmap texture generation**

   Start here because the current map and costmap path is an obvious hot loop:
   `MapLayer._build_occupancy_texture()` iterates the full grid and builds RGBA
   bytes in GDScript. Move only the cell-to-RGBA conversion and Y-flip into C++.
   Keep Godot node creation, materials, layer visibility, and camera framing in
   `MapLayer`.

   Native API draft:

   ```text
   RcsOccupancyCodec.build_rgba(data, width, height, palette) -> PackedByteArray
   RcsOccupancyCodec.build_image(data, width, height, palette) -> Image
   ```

2. **TF transform resolution**

   Move the edge store and graph resolution out of `TfLayer`. The GDScript layer
   should own drawing axes only. Native code should accept `tf_static`, live
   `tf`, URDF joint edges, and optional robot pose fallback, then return a
   compact dictionary or typed arrays of frame names and `Transform3D` values.

   Native API draft:

   ```text
   RcsTfResolver.merge_static(tf_static)
   RcsTfResolver.merge_live(tf)
   RcsTfResolver.merge_urdf(urdf_model)
   RcsTfResolver.resolve(robot_pose, max_frames) -> Dictionary
   ```

3. **LaserScan projection**

   Add this before building a full `ScanLayer`. A native projector can cache
   angle sin/cos tables by `(angle_min, angle_increment, ranges_count)` and
   return `PackedVector3Array` points in ROS coordinates converted to Godot
   coordinates. The scan layer can then focus on rendering points/rays.

   Native API draft:

   ```text
   RcsLaserScanProjector.project(scan, frame_transform) -> PackedVector3Array
   ```

4. **Path point generation**

   Once TF is native, path point extraction can reuse the same frame conversion.
   Keep line rendering in GDScript, but move payload shape handling, optional
   frame transforms, and point packing into C++.

   Native API draft:

   ```text
   RcsPathProjector.project(path_message, frame_transform) -> PackedVector3Array
   ```

5. **MQTT topic and payload codec**

   `RcsProtocolCodec` already exists. Extend it incrementally instead of adding
   another native class. Good early additions are:

   - `classify_topic(topic, fallback_robot_id) -> Dictionary`
   - `semantic_key_for_viz_topic(topic, robot_id) -> String`
   - `command_topic(command_key, robot_id) -> String`
   - `payload_diagnostics(topic, payload_bytes, payload_text) -> Dictionary`

   Do not move WebSocket ownership into native yet. Keep the current Godot
   transport until compatibility and diagnostics are stable.

6. **URDF mesh/path resolution**

   Move `package://` resolution before replacing proxy geometry with real mesh
   assets. The resolver should not load Godot scene nodes. It should resolve
   package URI strings into project-relative resource paths and return mesh
   metadata that `RobotLayer` can consume.

   Native API draft:

   ```text
   RcsUrdfResolver.set_package_roots(Dictionary package_roots)
   RcsUrdfResolver.resolve_mesh_uri(uri) -> String
   RcsUrdfResolver.resolve_model_meshes(urdf_model) -> Dictionary
   ```

## Migration Rules

- Keep native APIs data-oriented. Prefer `PackedByteArray`,
  `PackedVector3Array`, `Dictionary`, and `Array` over Godot node ownership.
- Keep scene node creation in GDScript unless profiling proves otherwise.
- Preserve current dictionary payload shapes until callers are migrated.
- Add a GDScript unit test before swapping each native path into production.
- Keep a GDScript fallback for every native helper until the GDExtension build is
  part of the normal developer workflow.
- Do not move transport encryption, credential storage, or broker policy into
  native during this performance migration. Those are hardening tasks, not hot
  path tasks.

## First Milestone

The first useful C++ milestone should expose these classes:

```text
RcsProtocolCodec      existing, extend in place
RcsOccupancyCodec     new
RcsTfResolver         new
```

That milestone would remove the heaviest map/costmap loop from GDScript and
stabilize the transform graph that later scan, path, footprint, and robot mesh
work will share.
