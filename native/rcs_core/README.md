# RCS Core GDExtension

This directory contains the native C++ core for RCS.

The extension owns code that should stay strict and stable:

- MQTT/WSS transport binding
- topic normalization and command topic routing
- payload validation and schema version handling
- TF resolution
- occupancy grid texture generation
- lidar raycast and simulation stepping
- replay file parsing

The current migration order is tracked in:

```text
docs/architecture/cpp-migration-priorities.md
```

## Dependencies

Place `godot-cpp` at:

```text
native/third_party/godot-cpp
```

Then build from this directory:

```text
scons platform=windows target=template_debug
```

The built library is expected under:

```text
addons/rcs_core/bin
```

After the library exists, copy:

```text
addons/rcs_core/rcs_core.gdextension.template
```

to:

```text
addons/rcs_core/rcs_core.gdextension
```

The live `.gdextension` file is intentionally not present before the first native build, because Godot tries to load it immediately.
