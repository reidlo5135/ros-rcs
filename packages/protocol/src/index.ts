export type TargetKind = "robot" | "sim" | "replay";

export const TOPIC_ROBOT_ID_TOKEN = "{robot_id}";

// ---------------------------------------------------------------------------
// Telemetry topics  (robot → client, high-volume data streams)
// Legacy name "vizTopicDefinitions" kept for backward compatibility.
// ---------------------------------------------------------------------------
export const vizTopicDefinitions = [
  { key: "map",               label: "Map",              defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/map` },
  { key: "globalCostmap",     label: "Global Costmap",   defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/global_costmap` },
  { key: "localCostmap",      label: "Local Costmap",    defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/local_costmap` },
  { key: "robotPose",         label: "Robot Pose",       defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/robot_pose` },
  { key: "globalPath",        label: "Global Plan",      defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/global_path` },
  { key: "localPath",         label: "Local Plan",       defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/local_path` },
  { key: "motionStatus",      label: "Motion Status",    defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/motion_status` },
  { key: "scan",              label: "LaserScan",        defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/scan` },
  { key: "batteryState",      label: "Battery State",    defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/battery_state` },
  { key: "tf",                label: "TF",               defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/tf` },
  { key: "tfStatic",          label: "TF Static",        defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/tf_static` },
  { key: "robotDescription",  label: "Robot Description", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/robot_description` },
] as const;

// ---------------------------------------------------------------------------
// Command topics  (client → robot, operator control plane)
// All topics use {robot_id} token – resolve with resolveTopicTemplate().
// ---------------------------------------------------------------------------
export const commandTopicDefinitions = [
  { key: "navigationCommand", label: "Navigation Command", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/command` },
  { key: "navigationCancel",  label: "Navigation Cancel",  defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/cancel` },
  { key: "poseSet",           label: "Set Initial Pose",   defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/pose/set` },
  { key: "systemPing",        label: "System Ping",        defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/system/ping` },
] as const;

// ---------------------------------------------------------------------------
// Result / feedback topics  (robot → client, control plane responses)
// Fixed topics – not user-configurable, built from robot_id at connect time.
// ---------------------------------------------------------------------------
export const resultTopicDefinitions = [
  { key: "navigationFeedback", label: "Navigation Feedback", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/feedback` },
  { key: "navigationStatus",   label: "Navigation Status",   defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/status` },
  { key: "navigationResult",   label: "Navigation Result",   defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/result` },
  { key: "poseResult",         label: "Pose Result",         defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/pose/result` },
  { key: "systemResult",       label: "System Result",       defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/system/result` },
] as const;

export type VizTopicKey       = (typeof vizTopicDefinitions)[number]["key"];
export type CommandTopicKey   = (typeof commandTopicDefinitions)[number]["key"];
export type ResultTopicKey    = (typeof resultTopicDefinitions)[number]["key"];

export type TopicRecord<Key extends string> = Record<Key, string>;

export const defaultVizTopics: TopicRecord<VizTopicKey> = Object.fromEntries(
  vizTopicDefinitions.map((e) => [e.key, e.defaultTopic]),
) as TopicRecord<VizTopicKey>;

export const defaultCommandTopics: TopicRecord<CommandTopicKey> = Object.fromEntries(
  commandTopicDefinitions.map((e) => [e.key, e.defaultTopic]),
) as TopicRecord<CommandTopicKey>;

export const defaultResultTopics: TopicRecord<ResultTopicKey> = Object.fromEntries(
  resultTopicDefinitions.map((e) => [e.key, e.defaultTopic]),
) as TopicRecord<ResultTopicKey>;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
export type SessionTarget = {
  kind: TargetKind;
  id: string;
};

export type RuntimeSnapshot = {
  connectionLabel: string;
  robotLabel: string;
  mode: "navigation" | "mapping" | "simulation";
  battery: string;
  latencyMs: number;
  goalState: string;
  pose: string;
};

export function resolveTopicTemplate(topic: string, robotId: string) {
  return topic.replaceAll(TOPIC_ROBOT_ID_TOKEN, robotId);
}

/** Resolves all result topic templates for a given robotId. */
export function buildResultTopics(robotId: string): TopicRecord<ResultTopicKey> {
  const id = robotId.trim() || "robot1";
  return Object.fromEntries(
    resultTopicDefinitions.map((e) => [e.key, e.defaultTopic.replaceAll(TOPIC_ROBOT_ID_TOKEN, id)]),
  ) as TopicRecord<ResultTopicKey>;
}

export function createDemoTarget(): SessionTarget {
  return { kind: "robot", id: "tb3-01" };
}

export function createDemoSnapshot(): RuntimeSnapshot {
  return {
    connectionLabel: "MQTT connected via WS",
    robotLabel: "TurtleBot3 / Hall A",
    mode: "navigation",
    battery: "84%",
    latencyMs: 28,
    goalState: "Running",
    pose: "3.42, -1.18, 0.12 rad",
  };
}
