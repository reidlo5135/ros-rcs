import {
  commandTopicDefinitions,
  createDemoTarget,
  defaultCommandTopics,
  defaultVizTopics,
  vizTopicDefinitions,
} from "@rcs/protocol";
import type { BridgeState, MotionStatusMessage, Pose } from "./lib/protocol";

import type { EventEntry, LayerEntry } from "./types";

export const target = createDemoTarget();
export const PAD_RADIUS = 66;
export const KNOB_RADIUS = 17;
export const MAX_LINEAR_X = 0.18;
export const MAX_ANGULAR_Z = 1.2;
export const RESPONSE_EXPONENT = 1.35;
export const PREVIEW_LINEAR_SCALE = 1.8;
export const DEFAULT_BATTERY_LABEL = "--%";

export function createScenePose(x: number, y: number, yaw: number): Pose {
  return {
    header: { frame_id: "map" },
    position: { x, y, z: 0 },
    orientation: {
      x: 0,
      y: 0,
      z: Math.sin(yaw / 2),
      w: Math.cos(yaw / 2),
      yaw,
    },
  };
}

export const DEFAULT_ROBOT_POSE = createScenePose(-0.4, -0.1, 0);

export const INITIAL_MOTION_STATUS: MotionStatusMessage = {
  motion: "Idle",
  remaining_distance: undefined,
  heading: undefined,
  goal_state: "Idle",
  blocked_source: "Clear",
};

export const INITIAL_BRIDGE_STATE: BridgeState = {
  robot_pose: DEFAULT_ROBOT_POSE,
};

export const initialEvents: EventEntry[] = [
  { time: "--:--:--", text: "RCS MQTT client ready" },
  { time: "--:--:--", text: "Connect to the broker WebSocket endpoint" },
];

export const layerEntries: ReadonlyArray<LayerEntry> = [
  { key: "grid", label: "Grid", icon: "grid" },
  { key: "map", label: "Map", icon: "map" },
  { key: "globalCostmap", label: "Global Costmap", icon: "costmap-global" },
  { key: "localCostmap", label: "Local Costmap", icon: "costmap-local" },
  { key: "footprint", label: "Exact Footprint", icon: "footprint" },
  { key: "robot", label: "Robot", icon: "robot" },
  { key: "globalPlan", label: "Global Plan", icon: "path-global" },
  { key: "localPlan", label: "Local Plan", icon: "path-local" },
  { key: "scan", label: "LaserScan", icon: "scan" },
  { key: "tf", label: "TF", icon: "tf" },
];

export const commandTopicModalEntries = commandTopicDefinitions.map(({ key, label }) => ({ key, label }));
export const displayTopicModalEntries = vizTopicDefinitions.map(({ key, label }) => ({ key, label }));

export { defaultCommandTopics, defaultVizTopics };
