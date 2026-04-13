export type TargetKind = "robot" | "sim" | "replay";

export const TOPIC_ROBOT_ID_TOKEN = "{robot_id}";

export const rawTelemetryTopicDefinitions = [
  { key: "map", label: "Map", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/map` },
  { key: "tfStatic", label: "TF Static", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/tf_static` },
  { key: "robotDescription", label: "Robot Description", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/robot_description` },
  { key: "scan", label: "Scan", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/scan` },
  { key: "odom", label: "Odom", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/odom` },
  { key: "imu", label: "IMU", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/imu` },
  { key: "tf", label: "TF", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/tf` },
  { key: "jointStates", label: "Joint States", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/joint_states` },
  { key: "robotPose", label: "Robot Pose", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/robot_pose` },
  { key: "globalCostmap", label: "Global Costmap", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/global_costmap` },
  { key: "localCostmap", label: "Local Costmap", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/local_costmap` },
  { key: "globalPath", label: "Global Path", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/global_path` },
  { key: "localPath", label: "Local Path", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/local_path` },
  { key: "motionStatus", label: "Motion Status", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/motion_status` },
  { key: "batteryState", label: "Battery State", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/telemetry/battery_state` },
] as const;

export const vizTopicDefinitions = [
  { key: "map", label: "Map", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/map` },
  { key: "globalCostmap", label: "Global Costmap", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/global_costmap` },
  { key: "localCostmap", label: "Local Costmap", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/local_costmap` },
  { key: "robotPose", label: "Robot Pose", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/robot_pose` },
  { key: "globalPath", label: "Global Plan", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/global_path` },
  { key: "localPath", label: "Local Plan", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/local_path` },
  { key: "motionStatus", label: "Motion Status", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/motion_status` },
  { key: "scan", label: "LaserScan", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/scan` },
  { key: "batteryState", label: "Battery State", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/battery_state` },
  { key: "tf", label: "TF", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/tf` },
  { key: "tfStatic", label: "TF Static", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/tf_static` },
  { key: "robotDescription", label: "Robot Description", defaultTopic: `/amr/${TOPIC_ROBOT_ID_TOKEN}/viz/robot_description` },
] as const;

export const commandTopicDefinitions = [
  { key: "navigateToPose", label: "Navigate To Pose", defaultTopic: "/amr/command/navigate_to_pose" },
  { key: "cancelNavigateToPose", label: "Cancel Navigate To Pose", defaultTopic: "/amr/command/cancel_navigate_to_pose" },
  { key: "navigateToPoses", label: "Navigate To Poses", defaultTopic: "/amr/command/navigate_to_poses" },
  { key: "cancelNavigateToPoses", label: "Cancel Navigate To Poses", defaultTopic: "/amr/command/cancel_navigate_to_poses" },
  { key: "setInitialPose", label: "Set Initial Pose", defaultTopic: "/amr/command/set_initial_pose" },
] as const;

export type RawTelemetryTopicKey = (typeof rawTelemetryTopicDefinitions)[number]["key"];
export type VizTopicKey = (typeof vizTopicDefinitions)[number]["key"];
export type CommandTopicKey = (typeof commandTopicDefinitions)[number]["key"];

export type TopicRecord<Key extends string> = Record<Key, string>;

export const defaultRawTelemetryTopics: TopicRecord<RawTelemetryTopicKey> = Object.fromEntries(
  rawTelemetryTopicDefinitions.map((entry) => [entry.key, entry.defaultTopic]),
) as TopicRecord<RawTelemetryTopicKey>;

export const defaultVizTopics: TopicRecord<VizTopicKey> = Object.fromEntries(
  vizTopicDefinitions.map((entry) => [entry.key, entry.defaultTopic]),
) as TopicRecord<VizTopicKey>;

export const defaultCommandTopics: TopicRecord<CommandTopicKey> = Object.fromEntries(
  commandTopicDefinitions.map((entry) => [entry.key, entry.defaultTopic]),
) as TopicRecord<CommandTopicKey>;

export type SessionTarget = {
  kind: TargetKind;
  id: string;
};

export type TopicChannel = "viz" | "command" | "response" | "feedback" | "status" | "event";

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

export function buildTopicRoot(target: SessionTarget) {
  return `rcs/${target.kind}/${target.id}`;
}

export function buildTopic(target: SessionTarget, channel: TopicChannel, name?: string) {
  const root = buildTopicRoot(target);
  return name ? `${root}/${channel}/${name}` : `${root}/${channel}`;
}

export function createDemoTarget(): SessionTarget {
  return {
    kind: "robot",
    id: "tb3-01",
  };
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
