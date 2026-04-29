# Godot Runtime Architecture

RCS 0.2.0 treats Godot as the product runtime, not only as a renderer.

## Runtime Layers

```text
Godot Control UI
  Operator panels, commands, event log, settings

Godot Scene Runtime
  Map, costmap, path, scan, TF, robot, goal interaction

Domain Services
  AppState, CommandBus, SessionRegistry, TelemetryRouter, MqttTransport

C++ GDExtension Core
  Transport, protocol validation, TF, occupancy, raycast, replay, simulation
```

## Rule

Raw MQTT payloads must not flow directly into scene scripts.

```text
MQTT payload -> parser -> RCS domain model -> scene/UI binding
```

This is the main stability boundary for the Godot migration.

## Native Migration

Performance-sensitive GDScript paths should move into `native/rcs_core`
incrementally. The current priority list is maintained in
[`cpp-migration-priorities.md`](cpp-migration-priorities.md).
