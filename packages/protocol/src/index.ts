export type TargetKind = "robot" | "sim" | "replay";

export const TOPIC_ROBOT_ID_TOKEN = "{robot_id}";

// ---------------------------------------------------------------------------
// Visualization topics  (robot → client, JSON data streams for ros-rcs)
// ---------------------------------------------------------------------------
export const vizTopicDefinitions = [
  { key: "map",               label: "Map",               defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/map` },
  { key: "globalCostmap",     label: "Global Costmap",    defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/global_costmap` },
  { key: "localCostmap",      label: "Local Costmap",     defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/local_costmap` },
  { key: "robotPose",         label: "Robot Pose",        defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/robot_pose` },
  { key: "globalPath",        label: "Global Plan",       defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/global_path` },
  { key: "localPath",         label: "Local Plan",        defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/local_path` },
  { key: "motionStatus",      label: "Motion Status",     defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/motion_status` },
  { key: "scan",              label: "LaserScan",         defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/scan` },
  { key: "batteryState",      label: "Battery State",     defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/battery_state` },
  { key: "tf",                label: "TF",                defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/tf` },
  { key: "tfStatic",          label: "TF Static",         defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/tf_static` },
  { key: "robotDescription",  label: "Robot Description", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/robot_description` },
] as const;

// ---------------------------------------------------------------------------
// Command topics  (client → robot, operator control plane)
// All topics use {robot_id} token – resolve with resolveTopicTemplate().
// ---------------------------------------------------------------------------
export const commandTopicDefinitions = [
  { key: "navigationCommand", label: "Navigation Command", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/command` },
  { key: "navigationCancel",  label: "Navigation Cancel",  defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/navigation/cancel` },
  { key: "poseSet",           label: "Set Initial Pose",   defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/pose/set` },
  { key: "mapSave",           label: "Map Save",           defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/map/save` },
  { key: "motionCommand",     label: "Motion Command",     defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/motion/command` },
  { key: "segmentRequest",    label: "Segment Request",    defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/segment/request` },
  { key: "routeRequest",      label: "Route Request",      defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/route/request` },
  { key: "systemPing",        label: "System Ping",        defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/system/ping` },
  { key: "systemRobot",       label: "System Robot",       defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/system/robot` },
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
  { key: "mapResult",          label: "Map Result",          defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/map/result` },
  { key: "segmentResponse",    label: "Segment Response",    defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/segment/response` },
  { key: "routeResponse",      label: "Route Response",      defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/route/response` },
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
