Changelog
=========

2026-04-10
----------

- Started the ``0.1.7`` iteration:

  - began multi-robot fleet visualization on a single MQTT broker and shared scene canvas
  - scoped control actions to one selected active robot while allowing multiple robot topics to be displayed together

- Started the ``0.1.2`` iteration:

  - merged the shared ``scene3d`` viewer package back into ``packages/ui`` to simplify the workspace structure
  - kept the Scene viewport, protocol types, and viz feature code together inside the UI package
  - removed the extra package boundary so dashboard work can evolve in one place

- Started the ``0.1.1`` iteration:

  - aligned the ``packages/ui/src/features/viz`` directory layout with the upstream-style ``layout``, ``panels``, ``scene``, ``hooks``, ``pages``, and ``styles`` slices
  - moved the dashboard page entry under ``features/viz/pages/VizDashboardPage.tsx`` and kept ``packages/ui/src/index.tsx`` as a thin export surface
  - added panel, topbar, scene wrapper, and hook placeholder files to prepare the next round of component-level extraction

- Started the ``0.1.0`` planning branch:

  - defined the initial RCS product direction as a shared web core with an Electron desktop shell
  - documented the first MQTT/WS topic model for robot, simulation, and replay targets
  - set the operator-console scope around 3D visualization, command flow, and session-oriented control

- Documented the first simulation direction:

  - scoped the simulator as a navigation-contract runtime instead of a full Gazebo replacement
  - chose ``pgm + yaml`` world loading as the first environment model
  - recorded TF, pose, scan, map, and costmap emulation as the required MVP outputs

- Added the initial project planning documents:

  - created the root ``README.md`` with architecture, MQTT model, and repository direction
  - created ``TODO.md`` with roadmap, implementation phases, protocol design, and simulation design notes
  - established this changelog as the baseline for future RCS milestones
