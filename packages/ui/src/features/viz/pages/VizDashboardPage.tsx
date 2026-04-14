import {
  startTransition,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import mqtt, { type MqttClient } from "mqtt";

import {
  buildResultTopics,
  commandTopicDefinitions,
  createDemoTarget,
  defaultCommandTopics,
  defaultVizTopics,
  resolveTopicTemplate,
  type TopicRecord,
  type VizTopicKey,
  vizTopicDefinitions,
} from "@rcs/protocol";
import {
  type BatteryStateMessage,
  type BridgeState,
  type LaserScanMessage,
  type MotionStatusMessage,
  type NavigateToPosesFeedbackMessage,
  type NavigateToPosesResponseMessage,
  type OccupancyGridMessage,
  type PathMessage,
  type Pose,
  type RobotDescriptionMessage,
  type TfMessage,
  type ViewMode,
} from "../lib/protocol";
import { TopicSettingsModal } from "../../../TopicSettingsModal";
import { Topbar } from "../components/layout/Topbar";
import { EventsPanel } from "../components/panels/EventsPanel";
import { CommandPanel } from "../components/panels/CommandPanel";
import { JoystickPanel } from "../components/panels/JoystickPanel";
import { VisualizationPanel } from "../components/panels/VisualizationPanel";
import { MqttPanel } from "../components/panels/MqttPanel";
import { NavigationStatusPanel } from "../components/panels/NavigationStatusPanel";
import { SceneViewport } from "../components/scene/SceneViewport";

type DashboardShellProps = {
  productName: string;
};

type JoystickPadProps = {
  linearX: number;
  angularZ: number;
  onCommandChange: (linearX: number, angularZ: number) => void;
  onCommandStop: () => void;
};

type EventEntry = {
  time: string;
  text: string;
};

type LayerIconKind =
  | "grid"
  | "map"
  | "costmap-global"
  | "costmap-local"
  | "footprint"
  | "robot"
  | "path-global"
  | "path-local"
  | "scan"
  | "tf";

type SceneLayerVisibility = {
  grid: boolean;
  map: boolean;
  globalCostmap: boolean;
  localCostmap: boolean;
  footprint: boolean;
  robot: boolean;
  globalPlan: boolean;
  localPlan: boolean;
  scan: boolean;
  tf: boolean;
};

type PoseInteractionMode = "idle" | "goal" | "initial_pose";

const target = createDemoTarget();
const PAD_RADIUS = 66;
const KNOB_RADIUS = 17;
const MAX_LINEAR_X = 0.18;
const MAX_ANGULAR_Z = 1.2;
const RESPONSE_EXPONENT = 1.35;
const PREVIEW_LINEAR_SCALE = 1.8;
function createScenePose(x: number, y: number, yaw: number): Pose {
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

const DEFAULT_ROBOT_POSE = createScenePose(-0.4, -0.1, 0);
const INITIAL_MOTION_STATUS: MotionStatusMessage = {
  motion: "Idle",
  remaining_distance: undefined,
  heading: null,
  goal_state: "Idle",
  blocked_source: "Clear",
};
const DEFAULT_BATTERY_LABEL = "--%";
const INITIAL_BRIDGE_STATE: BridgeState = {
  robot_pose: DEFAULT_ROBOT_POSE,
};

const initialEvents: EventEntry[] = [
  { time: "--:--:--", text: "RCS MQTT client ready" },
  { time: "--:--:--", text: "Connect to the broker WebSocket endpoint" },
];

const layerEntries: ReadonlyArray<{ key: keyof SceneLayerVisibility; label: string; icon: LayerIconKind }> = [
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

const commandTopicModalEntries = commandTopicDefinitions.map(({ key, label }) => ({ key, label }));
const displayTopicModalEntries = vizTopicDefinitions.map(({ key, label }) => ({ key, label }));

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function shapeNormalized(value: number) {
  const magnitude = Math.abs(value);
  return Math.sign(value) * (magnitude ** RESPONSE_EXPONENT);
}

function createEvent(text: string): EventEntry {
  const now = new Date();
  return {
    time: now.toLocaleTimeString("en-GB", { hour12: false }),
    text,
  };
}

function SettingsIconButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button type="button" className="rcs-icon-button" aria-label={label} title={label} onClick={onClick}>
      <svg viewBox="0 0 16 16" aria-hidden="true">
        <path d="M6.1 1.8h3.8l.4 1.7c.3.1.6.2.9.4l1.6-.8 1.9 1.9-.8 1.6c.1.3.3.6.4.9l1.7.4v3.8l-1.7.4c-.1.3-.2.6-.4.9l.8 1.6-1.9 1.9-1.6-.8c-.3.1-.6.3-.9.4l-.4 1.7H6.1l-.4-1.7c-.3-.1-.6-.2-.9-.4l-1.6.8-1.9-1.9.8-1.6a4 4 0 0 1-.4-.9L.2 9.9V6.1l1.7-.4c.1-.3.2-.6.4-.9l-.8-1.6L3.4 1.3l1.6.8c.3-.1.6-.3.9-.4z" />
        <circle cx="8" cy="8" r="2.2" />
      </svg>
    </button>
  );
}

function LayerIcon({ kind }: { kind: LayerIconKind }) {
  return (
    <span className={`rcs-layer-icon rcs-layer-icon-${kind}`} aria-hidden="true">
      {kind === "grid" && (
        <svg viewBox="0 0 16 16">
          <path d="M1 5.5h14M1 10.5h14M5.5 1v14M10.5 1v14" />
        </svg>
      )}
      {kind === "map" && (
        <svg viewBox="0 0 16 16">
          <path d="M2 3.5 5.5 2l5 1.5L14 2.5v10L10.5 14l-5-1.5L2 13.5z" />
        </svg>
      )}
      {kind === "costmap-global" && (
        <svg viewBox="0 0 16 16">
          <rect x="2" y="2" width="12" height="12" rx="1.2" />
          <path d="M2 8h12M8 2v12" />
        </svg>
      )}
      {kind === "costmap-local" && (
        <svg viewBox="0 0 16 16">
          <rect x="3" y="3" width="10" height="10" rx="1.2" />
          <circle cx="8" cy="8" r="2.4" />
        </svg>
      )}
      {kind === "footprint" && (
        <svg viewBox="0 0 16 16">
          <path d="M3 5.5 7.2 3.5 13 5.3 11.2 12.5 4.2 11.2z" />
        </svg>
      )}
      {kind === "robot" && (
        <svg viewBox="0 0 16 16">
          <rect x="4" y="4.5" width="8" height="7" rx="1" />
          <path d="M6 13v2M10 13v2M3 7H1M15 7h-2M6 2h4" />
        </svg>
      )}
      {(kind === "path-global" || kind === "path-local") && (
        <svg viewBox="0 0 16 16">
          <circle cx="3" cy="12" r="1.2" />
          <circle cx="13" cy="4" r="1.2" />
          <path d="M4.5 11 7.2 8.2 9 9.1 11.5 6.4" />
        </svg>
      )}
      {kind === "scan" && (
        <svg viewBox="0 0 16 16">
          <path d="M3 12a6 6 0 0 1 10-4.2" />
          <path d="M3 12a6 6 0 0 0 4.6 1.8" />
          <circle cx="8" cy="8" r="1.2" />
        </svg>
      )}
      {kind === "tf" && (
        <svg viewBox="0 0 16 16">
          <path d="M8 8V2M8 8H14M8 8 3 13" />
        </svg>
      )}
    </span>
  );
}

function sanitizeTopicRecord<Key extends string>(
  defaults: TopicRecord<Key>,
  nextValues?: Partial<Record<Key, string>> | Record<string, string>,
): TopicRecord<Key> {
  const sanitized = { ...defaults } as TopicRecord<Key>;

  if (!nextValues) {
    return sanitized;
  }

  for (const key of Object.keys(defaults) as Key[]) {
    const rawValue = nextValues[key];
    sanitized[key] = typeof rawValue === "string" && rawValue.trim() ? normalizeTopic(rawValue.trim()) : defaults[key];
  }

  return sanitized;
}

function normalizeTopic(topic: string) {
  const trimmed = topic.trim();
  if (!trimmed) {
    return trimmed;
  }

  const migratedTopic = trimmed
    .replace(/^\/?amr\/robot\/turtlebot3\//, "/amr/{robot_id}/")
    .replace(/^\/?amr\/turtlebot3\//, "/amr/{robot_id}/");

  if (migratedTopic.startsWith("/amr/")) {
    return migratedTopic;
  }

  if (migratedTopic.startsWith("amr/")) {
    return `/${migratedTopic}`;
  }

  return migratedTopic;
}

function buildTopicVariants(topic: string) {
  const normalized = normalizeTopic(topic);
  if (!normalized) {
    return [];
  }

  if (normalized.startsWith("/")) {
    return [normalized, normalized.slice(1)];
  }

  return [normalized, `/${normalized}`];
}

function resolveConfiguredTopic(topic: string, robotId: string) {
  return normalizeTopic(resolveTopicTemplate(topic, robotId.trim() || "robot1"));
}

function readStoredTopicRecord<Key extends string>(storageKey: string, defaults: TopicRecord<Key>) {
  if (typeof window === "undefined") {
    return defaults;
  }

  try {
    const storedValue = window.localStorage.getItem(storageKey);
    if (!storedValue) {
      return defaults;
    }

    const parsedValue = JSON.parse(storedValue) as Record<string, string>;
    return sanitizeTopicRecord(defaults, parsedValue);
  } catch {
    return defaults;
  }
}

function useStoredTopicRecord<Key extends string>(storageKey: string, defaults: TopicRecord<Key>) {
  const [value, setValue] = useState<TopicRecord<Key>>(() => readStoredTopicRecord(storageKey, defaults));

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    window.localStorage.setItem(storageKey, JSON.stringify(value));
  }, [storageKey, value]);

  return [value, setValue] as const;
}

function createCommandId() {
  return `rcs-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`;
}

function createQuaternionFromYaw(yaw: number) {
  return {
    x: 0,
    y: 0,
    z: Math.sin(yaw / 2),
    w: Math.cos(yaw / 2),
  };
}

function quaternionToYaw(quaternion: { x?: number; y?: number; z?: number; w?: number }) {
  const x = quaternion.x ?? 0;
  const y = quaternion.y ?? 0;
  const z = quaternion.z ?? 0;
  const w = quaternion.w ?? 1;
  return Math.atan2(2 * ((w * z) + (x * y)), 1 - (2 * ((y * y) + (z * z))));
}

function formatPoseChip(x: number, y: number, yaw: number) {
  return `Pose ${x.toFixed(2)}, ${y.toFixed(2)}, ${yaw.toFixed(2)}`;
}

function formatDistance(value: number | null) {
  return value == null ? "-- m" : `${value.toFixed(2)} m`;
}

function formatHeading(value: number | null) {
  return value == null ? "-- rad" : `${value.toFixed(2)} rad`;
}

function formatBatteryLabel(value: number | null) {
  return value == null ? DEFAULT_BATTERY_LABEL : `${Math.round(value)}%`;
}

function coerceNumber(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function safeParseJsonPayload(text: string) {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

function extractRecord(value: unknown) {
  return value && typeof value === "object" ? value as Record<string, unknown> : null;
}

function parseHeader(payload: unknown) {
  const record = extractRecord(payload);
  return {
    frame_id: typeof record?.frame_id === "string"
      ? record.frame_id
      : typeof record?.frameId === "string"
        ? record.frameId
        : "map",
    stamp: extractRecord(record?.stamp) != null
      ? {
        sec: coerceNumber(extractRecord(record?.stamp)?.sec) ?? undefined,
        nanosec: coerceNumber(extractRecord(record?.stamp)?.nanosec) ?? undefined,
      }
      : undefined,
  };
}

function parsePose(payload: unknown): Pose | null {
  const record = extractRecord(payload);
  if (!record) {
    return null;
  }

  if (record.pose) {
    const nestedPose = parsePose(record.pose);
    if (nestedPose) {
      if (record.header && !nestedPose.header) {
        nestedPose.header = parseHeader(record.header);
      }
      return nestedPose;
    }
  }

  const positionRecord = extractRecord(record.position);
  if (positionRecord) {
    const orientationRecord = extractRecord(record.orientation);
    const yaw = orientationRecord ? quaternionToYaw(orientationRecord) : 0;
    const pose = createScenePose(
      coerceNumber(positionRecord.x) ?? 0,
      coerceNumber(positionRecord.y) ?? 0,
      yaw,
    );
    pose.position.z = coerceNumber(positionRecord.z) ?? 0;
    pose.header = parseHeader(record.header);
    if (orientationRecord) {
      pose.orientation = {
        x: coerceNumber(orientationRecord.x) ?? 0,
        y: coerceNumber(orientationRecord.y) ?? 0,
        z: coerceNumber(orientationRecord.z) ?? Math.sin(yaw / 2),
        w: coerceNumber(orientationRecord.w) ?? Math.cos(yaw / 2),
        yaw,
      };
    }
    return pose;
  }

  const x = coerceNumber(record.x);
  const y = coerceNumber(record.y);
  const yaw = coerceNumber(record.yaw) ?? coerceNumber(record.theta) ?? coerceNumber(record.heading);
  if (x != null && y != null) {
    const pose = createScenePose(x, y, yaw ?? 0);
    pose.position.z = coerceNumber(record.z) ?? 0;
    pose.header = parseHeader(record.header);
    return pose;
  }

  return null;
}

function parseOccupancyGrid(payload: unknown): OccupancyGridMessage | null {
  const record = extractRecord(payload);
  const info = extractRecord(record?.info);
  const data = Array.isArray(record?.data) ? record.data : null;
  const width = coerceNumber(info?.width);
  const height = coerceNumber(info?.height);
  const resolution = coerceNumber(info?.resolution);
  const originPose = parsePose(info?.origin);

  if (!data || width == null || height == null || resolution == null || !originPose) {
    return null;
  }

  return {
    header: parseHeader(record?.header),
    info: {
      width,
      height,
      resolution,
      origin: originPose,
    },
    data: data.map((value) => (typeof value === "number" ? value : -1)),
  };
}

function parsePathMessage(payload: unknown): PathMessage | null {
  const record = extractRecord(payload);
  const poses = Array.isArray(record?.poses) ? record.poses : null;
  if (!poses) {
    return null;
  }

  const parsedPoses = poses
    .map((entry) => parsePose(entry))
    .filter((pose): pose is Pose => pose != null);

  return {
    header: parseHeader(record?.header),
    poses: parsedPoses,
  };
}

function parseLaserScan(payload: unknown): LaserScanMessage | null {
  const record = extractRecord(payload);
  const points = Array.isArray(record?.points) ? record.points : null;
  const ranges = Array.isArray(record?.ranges) ? record.ranges : null;
  const angleMin = coerceNumber(record?.angle_min);
  const angleIncrement = coerceNumber(record?.angle_increment);
  const parsedPoints = points
    ?.map((entry) => {
      const point = extractRecord(entry);
      const x = coerceNumber(point?.x);
      const y = coerceNumber(point?.y);
      const z = coerceNumber(point?.z) ?? 0;
      return x != null && y != null ? { x, y, z } : null;
    })
    .filter((point): point is { x: number; y: number; z: number } => point != null);

  if (!parsedPoints?.length && (!ranges || angleMin == null || angleIncrement == null)) {
    return null;
  }

  return {
    header: parseHeader(record?.header),
    angle_min: angleMin ?? 0,
    angle_increment: angleIncrement ?? 0,
    range_min: coerceNumber(record?.range_min) ?? 0,
    range_max: coerceNumber(record?.range_max)
      ?? Math.max(...(ranges ?? []).filter((value): value is number => typeof value === "number" && Number.isFinite(value)), 0),
    ranges: (ranges ?? []).map((value) => (typeof value === "number" ? value : Number.NaN)),
    points: parsedPoints,
  };
}

function parseTfMessage(payload: unknown): TfMessage | null {
  const record = extractRecord(payload);
  const transforms = Array.isArray(record?.transforms) ? record.transforms : null;
  if (!transforms) {
    return null;
  }

  return {
    transforms: transforms
      .map((entry) => {
        const transform = extractRecord(entry);
        const transformBody = extractRecord(transform?.transform);
        const translation = extractRecord(transformBody?.translation) ?? extractRecord(transform?.translation);
        const rotation = extractRecord(transformBody?.rotation) ?? extractRecord(transform?.rotation);
        if (!transform || !translation || !rotation) {
          return null;
        }

        return {
          header: parseHeader(transform.header),
          child_frame_id:
            typeof transform.child_frame_id === "string"
              ? transform.child_frame_id
              : typeof transform.childFrameId === "string"
                ? transform.childFrameId
                : "",
          transform: {
            translation: {
              x: coerceNumber(translation.x) ?? 0,
              y: coerceNumber(translation.y) ?? 0,
              z: coerceNumber(translation.z) ?? 0,
            },
            rotation: {
              x: coerceNumber(rotation.x) ?? 0,
              y: coerceNumber(rotation.y) ?? 0,
              z: coerceNumber(rotation.z) ?? 0,
              w: coerceNumber(rotation.w) ?? 1,
              yaw: quaternionToYaw(rotation),
            },
          },
        };
      })
      .filter((transform): transform is TfMessage["transforms"][number] => transform != null),
  };
}

function mergeTfMessages(current: TfMessage | undefined, incoming: TfMessage): TfMessage {
  const byChildFrame = new Map<string, TfMessage["transforms"][number]>();

  for (const transform of current?.transforms ?? []) {
    if (!transform.child_frame_id) {
      continue;
    }
    byChildFrame.set(transform.child_frame_id, transform);
  }

  for (const transform of incoming.transforms) {
    if (!transform.child_frame_id) {
      continue;
    }
    byChildFrame.set(transform.child_frame_id, transform);
  }

  return {
    transforms: Array.from(byChildFrame.values()),
  };
}

function parseRobotDescription(payload: unknown): RobotDescriptionMessage | null {
  if (typeof payload === "string" && payload.trim()) {
    return { data: payload };
  }

  const record = extractRecord(payload);
  if (!record) {
    return null;
  }

  const data = typeof record.data === "string"
    ? record.data
    : typeof record.robot_description === "string"
      ? record.robot_description
      : typeof record.urdf === "string"
        ? record.urdf
        : "";

  const footprintPolygon = Array.isArray(record.footprint_polygon)
    ? record.footprint_polygon.filter((value): value is number => typeof value === "number")
    : undefined;

  if (!data && !footprintPolygon?.length) {
    return null;
  }

  return {
    data,
    footprint_polygon: footprintPolygon,
  };
}

function parseMotionStatus(payload: unknown) {
  const record = extractRecord(payload);
  if (!record) {
    return null;
  }

  const blockedPose = parsePose(record.blocked_pose);

  return {
    motion: typeof record.motion === "string"
      ? record.motion
      : typeof record.state === "string"
        ? record.state
        : INITIAL_MOTION_STATUS.motion,
    state: typeof record.state === "string" ? record.state : undefined,
    active: typeof record.active === "boolean" ? record.active : undefined,
    goal_reached: typeof record.goal_reached === "boolean" ? record.goal_reached : undefined,
    remaining_distance: coerceNumber(record.remaining_distance) ?? coerceNumber(record.remaining) ?? undefined,
    heading: coerceNumber(record.heading) ?? coerceNumber(record.heading_error),
    goal_state: typeof record.goal === "string"
      ? record.goal
      : typeof record.goal_state === "string"
        ? record.goal_state
        : INITIAL_MOTION_STATUS.goal_state,
    blocked_source: typeof record.blocked_source === "string"
      ? record.blocked_source
      : typeof record.blocked_by === "string"
        ? record.blocked_by
        : INITIAL_MOTION_STATUS.blocked_source,
    blocked_by: typeof record.blocked_by === "string" ? record.blocked_by : undefined,
    blocked_pose: blockedPose ?? undefined,
    has_blocked_pose: typeof record.has_blocked_pose === "boolean"
      ? record.has_blocked_pose
      : blockedPose != null,
    costmap_blocked: typeof record.costmap_blocked === "boolean" ? record.costmap_blocked : undefined,
    safety_gate_blocked: typeof record.safety_gate_blocked === "boolean" ? record.safety_gate_blocked : undefined,
  } satisfies MotionStatusMessage;
}

function parseBatteryState(payload: unknown): BatteryStateMessage | null {
  const record = extractRecord(payload);
  if (!record) {
    return null;
  }

  return {
    percentage: coerceNumber(record.percentage) ?? undefined,
    battery: extractRecord(record.battery)
      ? {
        percentage: coerceNumber(extractRecord(record.battery)?.percentage) ?? undefined,
      }
      : undefined,
  };
}

function extractTopicSuffix(topic: string) {
  const parts = topic.split("/").filter(Boolean);
  return parts.slice(-2).join("/");
}

function buildVizSubscriptions(topics: TopicRecord<VizTopicKey>, robotId: string) {
  const normalizedRobotId = robotId.trim() || "robot1";
  const subscriptions = new Set<string>();
  // Wildcard covers all telemetry/* streams from this robot
  subscriptions.add(`/amr/${normalizedRobotId}/telemetry/#`);

  for (const topic of Object.values(topics)) {
    for (const variant of buildTopicVariants(resolveConfiguredTopic(topic, normalizedRobotId))) {
      subscriptions.add(variant);
    }
  }

  return Array.from(subscriptions);
}

/** Returns the canonical control-plane result topics for a given robotId. */
function buildControlSubscriptions(robotId: string) {
  const resolved = buildResultTopics(robotId.trim() || "robot1");
  const subscriptions = new Set<string>();
  for (const topic of Object.values(resolved)) {
    for (const variant of buildTopicVariants(topic)) {
      subscriptions.add(variant);
    }
  }
  return Array.from(subscriptions);
}

function extractTopicRobotId(topic: string) {
  const parts = topic.split("/").filter(Boolean);
  const amrIndex = parts.indexOf("amr");
  if (amrIndex >= 0 && parts.length > (amrIndex + 1)) {
    return parts[amrIndex + 1];
  }

  return "robot1";
}

function findMatchingVizKey(topic: string, topics: TopicRecord<VizTopicKey>) {
  const topicRobotId = extractTopicRobotId(topic);

  for (const definition of vizTopicDefinitions) {
    if (buildTopicVariants(resolveConfiguredTopic(topics[definition.key], topicRobotId)).includes(topic)) {
      return definition.key;
    }
  }

  const topicSuffix = extractTopicSuffix(topic);
  for (const definition of vizTopicDefinitions) {
    if (buildTopicVariants(resolveConfiguredTopic(topics[definition.key], topicRobotId)).some((candidate) => extractTopicSuffix(candidate) === topicSuffix)) {
      return definition.key;
    }
  }

  return null;
}

function JoystickPad({ linearX, angularZ, onCommandChange, onCommandStop }: JoystickPadProps) {
  const padRef = useRef<HTMLDivElement | null>(null);
  const [dragVector, setDragVector] = useState({ x: 0, y: 0 });

  const knobStyle = useMemo(
    () => ({
      transform: `translate(${dragVector.x}px, ${dragVector.y}px)`,
    }),
    [dragVector.x, dragVector.y],
  );

  const updateFromPointer = (clientX: number, clientY: number) => {
    const pad = padRef.current;
    if (!pad) {
      return;
    }

    const rect = pad.getBoundingClientRect();
    const offsetX = clientX - (rect.left + (rect.width / 2));
    const offsetY = clientY - (rect.top + (rect.height / 2));
    const magnitude = Math.hypot(offsetX, offsetY);
    const limitedScale = magnitude > (PAD_RADIUS - KNOB_RADIUS)
      ? (PAD_RADIUS - KNOB_RADIUS) / magnitude
      : 1;

    const limitedX = offsetX * limitedScale;
    const limitedY = offsetY * limitedScale;
    const normalizedX = clamp(limitedX / (PAD_RADIUS - KNOB_RADIUS), -1, 1);
    const normalizedY = clamp(limitedY / (PAD_RADIUS - KNOB_RADIUS), -1, 1);
    const nextLinearX = -shapeNormalized(normalizedY) * MAX_LINEAR_X;
    const nextAngularZ = shapeNormalized(normalizedX) * MAX_ANGULAR_Z;

    setDragVector({ x: limitedX, y: limitedY });
    onCommandChange(nextLinearX, nextAngularZ);
  };

  const handlePointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    event.currentTarget.setPointerCapture(event.pointerId);
    updateFromPointer(event.clientX, event.clientY);
  };

  const handlePointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!event.currentTarget.hasPointerCapture(event.pointerId)) {
      return;
    }

    updateFromPointer(event.clientX, event.clientY);
  };

  const stop = () => {
    setDragVector({ x: 0, y: 0 });
    onCommandStop();
  };

  const handlePointerUp = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    stop();
  };

  return (
    <>
      <div className="rcs-joystick">
        <div
          ref={padRef}
          className="rcs-joystick__base"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={handlePointerUp}
        >
          <div className="rcs-joystick__cross rcs-joystick__cross--horizontal" />
          <div className="rcs-joystick__cross rcs-joystick__cross--vertical" />
          <div className="rcs-joystick__knob" style={knobStyle} />
        </div>
      </div>

      <div className="rcs-status-list rcs-status-list--compact">
        <div className="rcs-status-row"><span>Linear X</span><strong>{linearX.toFixed(3)} m/s</strong></div>
        <div className="rcs-status-row"><span>Angular Z</span><strong>{angularZ.toFixed(3)} rad/s</strong></div>
      </div>
    </>
  );
}

export function VizDashboardPage({ productName }: DashboardShellProps) {
  const [viewMode, setViewMode] = useState<"nav" | "mapping">("nav");
  const [mqttUrl, setMqttUrl] = useState("ws://192.168.61.35:9001/mqtt");
  const [robotId, setRobotId] = useState("burger1");
  const [connectionLabel, setConnectionLabel] = useState("Disconnected");
  const [events, setEvents] = useState<EventEntry[]>(initialEvents);
  const [teleopLinearX, setTeleopLinearX] = useState(0);
  const [teleopAngularZ, setTeleopAngularZ] = useState(0);
  const [goalX, setGoalX] = useState("2.5");
  const [goalY, setGoalY] = useState("0.0");
  const [goalYaw, setGoalYaw] = useState("0.0");
  const [routeWaypoints, setRouteWaypoints] = useState<ReadonlyArray<{ x: number; y: number; yaw: number }>>([]);
  const [activeGoalIndex, setActiveGoalIndex] = useState(-1);
  const [poseInteractionMode, setPoseInteractionMode] = useState<PoseInteractionMode>("idle");
  const [sceneGoalMarker, setSceneGoalMarker] = useState<{
    x: number;
    y: number;
    yaw: number;
    kind: "goal" | "initial_pose";
  } | null>(null);
  const [commandSettingsOpen, setCommandSettingsOpen] = useState(false);
  const [visualizationSettingsOpen, setVisualizationSettingsOpen] = useState(false);
  const [sceneResetToken, setSceneResetToken] = useState(0);
  const [layerVisibility, setLayerVisibility] = useState<SceneLayerVisibility>({
    grid: true,
    map: true,
    globalCostmap: true,
    localCostmap: true,
    footprint: true,
    robot: true,
    globalPlan: true,
    localPlan: true,
    scan: true,
    tf: true,
  });
  const [commandTopics, setCommandTopics] = useStoredTopicRecord("rcs.topicSettings.commands", defaultCommandTopics);
  const [vizTopics, setVizTopics] = useStoredTopicRecord("rcs.topicSettings.viz", defaultVizTopics);
  const [bridgeState, setBridgeState] = useState<BridgeState>(INITIAL_BRIDGE_STATE);
  const [signalRttMs, setSignalRttMs] = useState<number | null>(null);
  const [signalLastSeenAt, setSignalLastSeenAt] = useState<number | null>(null);

  const clientRef = useRef<MqttClient | null>(null);
  const bridgeStateRef = useRef<BridgeState>(INITIAL_BRIDGE_STATE);
  const seenTopicKeysRef = useRef(new Set<VizTopicKey>());
  const livePoseActiveRef = useRef(false);
  const vizTopicsRef = useRef(vizTopics);
  const robotIdRef = useRef(robotId);
  const pendingBridgePatchRef = useRef<Partial<BridgeState>>({});
  const flushBridgeFrameRef = useRef<number | null>(null);
  const routeActiveRef = useRef(false);
  const autoClearTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const activePingRequestIdRef = useRef<string | null>(null);
  const lastPingSentAtRef = useRef<number | null>(null);
  const modeLabel: ViewMode = viewMode === "nav" ? "navigation" : "mapping";
  const activeTarget = useMemo(() => ({ ...target, id: robotId.trim() || target.id }), [robotId]);
  const robotPose = bridgeState.robot_pose ?? DEFAULT_ROBOT_POSE;
  const motionStatus = bridgeState.motion_status ?? INITIAL_MOTION_STATUS;
  const connectedRobotId = connectionLabel.startsWith("MQTT connected:")
    ? (robotId.trim() || "robot1")
    : undefined;
  const batteryPercentage = (() => {
    const percentage = bridgeState.battery_state?.percentage ?? bridgeState.battery_state?.battery?.percentage ?? null;
    if (percentage == null || !Number.isFinite(percentage)) {
      return null;
    }
    return Math.max(0, Math.min(100, percentage <= 1 ? percentage * 100 : percentage));
  })();
  const signalBars = (() => {
    const client = clientRef.current;
    if (!client?.connected || signalRttMs === null || signalLastSeenAt === null) {
      return 0;
    }
    if ((Date.now() - signalLastSeenAt) > 6000) {
      return 0;
    }
    if (signalRttMs <= 120) {
      return 4;
    }
    if (signalRttMs <= 250) {
      return 3;
    }
    if (signalRttMs <= 500) {
      return 2;
    }
    return 1;
  })();

  const scheduleBridgePatch = (patch: Partial<BridgeState>) => {
    pendingBridgePatchRef.current = {
      ...pendingBridgePatchRef.current,
      ...patch,
    };

    if (flushBridgeFrameRef.current != null) {
      return;
    }

    flushBridgeFrameRef.current = window.requestAnimationFrame(() => {
      flushBridgeFrameRef.current = null;
      const nextPatch = pendingBridgePatchRef.current;
      pendingBridgePatchRef.current = {};
      if (Object.keys(nextPatch).length === 0) {
        return;
      }
      startTransition(() => {
        setBridgeState((current: BridgeState) => {
          const nextState = { ...current, ...nextPatch };
          bridgeStateRef.current = nextState;
          return nextState;
        });
      });
    });
  };

  useEffect(() => {
    bridgeStateRef.current = bridgeState;
  }, [bridgeState]);

  useEffect(() => {
    vizTopicsRef.current = vizTopics;
  }, [vizTopics]);

  useEffect(() => {
    const previousRobotId = robotIdRef.current;
    robotIdRef.current = robotId;

    const client = clientRef.current;
    if (!client || !client.connected || previousRobotId === robotId) {
      return;
    }

    const previousSubs = [
      ...buildVizSubscriptions(vizTopicsRef.current, previousRobotId),
      ...buildControlSubscriptions(previousRobotId),
    ];
    const nextSubs = Array.from(new Set([
      ...buildVizSubscriptions(vizTopicsRef.current, robotId),
      ...buildControlSubscriptions(robotId),
    ]));
    if (previousSubs.length > 0) {
      client.unsubscribe(previousSubs, () => {
        client.subscribe(nextSubs, (error) => {
          if (error) {
            pushEvent(`Robot topic scope update failed: ${error.message}`);
            return;
          }
          pushEvent(`Robot topic scope updated: ${robotId.trim() || "robot1"}`);
        });
      });
    }
  }, [robotId]);

  const pushEvent = (text: string) => {
    setEvents((current) => [createEvent(text), ...current].slice(0, 24));
  };

  const publishCommand = (topic: string, payload: unknown, label: string) => {
    const client = clientRef.current;
    if (!client || !client.connected) {
      pushEvent(`${label} blocked: MQTT is not connected`);
      return;
    }

    const resolvedTopic = resolveConfiguredTopic(topic, robotId);
    client.publish(resolvedTopic, JSON.stringify(payload), (error) => {
      if (error) {
        pushEvent(`${label} failed: ${error.message}`);
        return;
      }

      pushEvent(`${label} published: ${resolvedTopic}`);
    });
  };

  const handlePoseSelection = (x: number, y: number, yaw: number) => {
    setGoalX(x.toFixed(2));
    setGoalY(y.toFixed(2));
    setGoalYaw(yaw.toFixed(2));
  };

  const handlePosePlacement = (mode: "goal" | "initial_pose", x: number, y: number, yaw: number) => {
    if (mode === "goal") {
      setRouteWaypoints((current) => [...current, { x, y, yaw }]);
      pushEvent(`Waypoint added: (${x.toFixed(2)}, ${y.toFixed(2)}, ${yaw.toFixed(2)})`);
      return;
    }

    setPoseInteractionMode("idle");
    setSceneGoalMarker({
      x,
      y,
      yaw,
      kind: mode,
    });

    publishCommand(commandTopics.poseSet, {
      request_id: createCommandId(),
      frame: "map",
      pose: {
        position: { x, y, z: 0 },
        orientation: createQuaternionFromYaw(yaw),
      },
    }, "Set Initial Pose");
  };

  const handleSendRoute = () => {
    if (routeWaypoints.length === 0) {
      return;
    }

    publishCommand(commandTopics.navigationCommand, {
      request_id: createCommandId(),
      goal_poses: routeWaypoints.map(({ x, y, yaw }) => ({
        frame: "map",
        position: { x, y, z: 0 },
        orientation: createQuaternionFromYaw(yaw),
      })),
    }, "Navigate To Poses");
    setActiveGoalIndex(-1);
    routeActiveRef.current = true;
    setPoseInteractionMode("idle");
  };

  useEffect(() => {
    if (
      routeActiveRef.current &&
      routeWaypoints.length > 0 &&
      activeGoalIndex >= routeWaypoints.length
    ) {
      routeActiveRef.current = false;
      if (autoClearTimerRef.current != null) {
        clearTimeout(autoClearTimerRef.current);
      }
      autoClearTimerRef.current = setTimeout(() => {
        autoClearTimerRef.current = null;
        setRouteWaypoints([]);
        setActiveGoalIndex(-1);
        pushEvent("Route completed – waypoints cleared automatically");
      }, 1500);
    }
  }, [activeGoalIndex, routeWaypoints.length]);

  const syncVizSubscriptions = (
    previousTopics: TopicRecord<VizTopicKey>,
    nextTopics: TopicRecord<VizTopicKey>,
  ) => {
    const client = clientRef.current;
    if (!client || !client.connected) {
      return;
    }

    const previousList = buildVizSubscriptions(previousTopics, robotId);
    const nextList = buildVizSubscriptions(nextTopics, robotId);
    const topicsToUnsubscribe = previousList.filter((topic) => !nextList.includes(topic));

    if (topicsToUnsubscribe.length > 0) {
      client.unsubscribe(topicsToUnsubscribe, (error) => {
        if (error) {
          pushEvent(`Unsubscribe failed: ${error.message}`);
        }
      });
    }

    if (nextList.length === 0) {
      pushEvent("No viz topics configured");
      return;
    }

    client.subscribe(nextList, (error) => {
      if (error) {
        pushEvent(`Subscribe failed: ${error.message}`);
        return;
      }

      pushEvent(`Viz topic subscriptions refreshed: ${nextList.length}`);
    });
  };

  const disconnectMqtt = (message?: string) => {
    const client = clientRef.current;
    if (client) {
      client.removeAllListeners();
      client.end(true);
      clientRef.current = null;
    }

    livePoseActiveRef.current = false;
    seenTopicKeysRef.current.clear();
    activePingRequestIdRef.current = null;
    lastPingSentAtRef.current = null;
    setSignalRttMs(null);
    setSignalLastSeenAt(null);
    setConnectionLabel("Disconnected");
    pushEvent(message ?? `MQTT disconnected: ${mqttUrl}`);
  };

  const connectMqtt = () => {
    if (!mqttUrl.trim()) {
      pushEvent("MQTT URL is empty");
      setConnectionLabel("MQTT URL required");
      return;
    }

    if (clientRef.current) {
      disconnectMqtt("MQTT session reset");
    }

    setConnectionLabel(`Connecting: ${mqttUrl}`);
    pushEvent(`Connecting: ${mqttUrl}`);

    const client = mqtt.connect(mqttUrl, {
      reconnectPeriod: 0,
      connectTimeout: 5000,
      keepalive: 30,
    });
    clientRef.current = client;

    client.on("connect", () => {
      setConnectionLabel(`MQTT connected: ${mqttUrl}`);
      pushEvent(`MQTT connected: ${mqttUrl}`);

      const vizSubs = buildVizSubscriptions(vizTopicsRef.current, robotId);
      const controlSubs = buildControlSubscriptions(robotId);
      const allSubs = Array.from(new Set([...vizSubs, ...controlSubs]));

      client.subscribe(allSubs, (error) => {
        if (error) {
          pushEvent(`Subscribe failed: ${error.message}`);
          return;
        }
        pushEvent(`Subscribed: ${vizSubs.length} telemetry + ${controlSubs.length} control topics`);
      });
    });

    client.on("error", (error) => {
      activePingRequestIdRef.current = null;
      lastPingSentAtRef.current = null;
      setSignalRttMs(null);
      setSignalLastSeenAt(null);
      setConnectionLabel("Connection error");
      pushEvent(`MQTT error: ${error.message}`);
    });

    client.on("close", () => {
      if (clientRef.current === client) {
        clientRef.current = null;
      }

      livePoseActiveRef.current = false;
      activePingRequestIdRef.current = null;
      lastPingSentAtRef.current = null;
      setSignalRttMs(null);
      setSignalLastSeenAt(null);
      setConnectionLabel("Disconnected");
      pushEvent(`MQTT closed: ${mqttUrl}`);
    });

    client.on("message", (topic, payload) => {
      const rid = robotId.trim() || "robot1";
      const text = payload.toString("utf8").trim();

      // ── system/result  (ping response + other system ACKs) ──────────────
      if (buildTopicVariants(`/amr/${rid}/system/result`).includes(topic)) {
        const rec = extractRecord(safeParseJsonPayload(text));
        const requestId = typeof rec?.request_id === "string" ? rec.request_id : "";
        const sentAtMs = coerceNumber(rec?.sent_at_ms) ?? lastPingSentAtRef.current;
        if (requestId && requestId === activePingRequestIdRef.current && sentAtMs != null) {
          setSignalRttMs(Math.max(0, Date.now() - sentAtMs));
          setSignalLastSeenAt(Date.now());
          activePingRequestIdRef.current = null;
        }
        return;
      }

      // ── navigation/feedback ─────────────────────────────────────────────
      if (buildTopicVariants(`/amr/${rid}/navigation/feedback`).includes(topic)) {
        if (routeActiveRef.current) {
          const rec = extractRecord(safeParseJsonPayload(text));
          if (rec && typeof rec.current_goal_index === "number") {
            const fb = rec as NavigateToPosesFeedbackMessage;
            setActiveGoalIndex(fb.current_goal_index);
          }
        }
        return;
      }

      // ── navigation/status  (GoalStatusArray) ────────────────────────────
      if (buildTopicVariants(`/amr/${rid}/navigation/status`).includes(topic)) {
        const rec = extractRecord(safeParseJsonPayload(text));
        if (rec && Array.isArray(rec.status_list) && rec.status_list.length > 0) {
          const latest = rec.status_list[rec.status_list.length - 1] as { status?: number };
          const code = typeof latest.status === "number" ? latest.status : -1;
          const GOAL_STATUS_LABEL: Record<number, string> = {
            1: "Idle", 2: "Executing", 3: "Canceling", 4: "Succeeded", 5: "Canceled", 6: "Aborted",
          };
          const label = GOAL_STATUS_LABEL[code] ?? "Idle";
          scheduleBridgePatch({
            motion_status: {
              ...(bridgeStateRef.current.motion_status ?? INITIAL_MOTION_STATUS),
              goal_state: label,
            },
          });
          // Auto-clear waypoints on terminal states (Canceled or Aborted)
          if ((code === 5 || code === 6) && routeActiveRef.current) {
            routeActiveRef.current = false;
            if (autoClearTimerRef.current != null) clearTimeout(autoClearTimerRef.current);
            autoClearTimerRef.current = setTimeout(() => {
              autoClearTimerRef.current = null;
              setRouteWaypoints([]);
              setActiveGoalIndex(-1);
              pushEvent(`Route ${label.toLowerCase()} – waypoints cleared automatically`);
            }, 1500);
          }
        }
        return;
      }

      // ── navigation/result  (multiplexed: accepted / completed / cancel ack)
      if (buildTopicVariants(`/amr/${rid}/navigation/result`).includes(topic)) {
        const rec = extractRecord(safeParseJsonPayload(text));
        if (rec) {
          const res = rec as NavigateToPosesResponseMessage;
          if (res.completed && routeActiveRef.current) {
            // Final route result – mark all waypoints done; useEffect auto-clears
            setActiveGoalIndex(res.completed_goals ?? Number.MAX_SAFE_INTEGER);
          }
          if (res.accepted === false && typeof res.message === "string") {
            pushEvent(`Navigation rejected: ${res.message}`);
            routeActiveRef.current = false;
          }
        }
        return;
      }

      // ── pose/result ─────────────────────────────────────────────────────
      if (buildTopicVariants(`/amr/${rid}/pose/result`).includes(topic)) {
        const rec = extractRecord(safeParseJsonPayload(text));
        if (rec) {
          const ok = rec.success !== false;
          pushEvent(`Initial pose ${ok ? "accepted" : `rejected: ${rec.message ?? "unknown"}`}`);
        }
        return;
      }

      const matchingKey = findMatchingVizKey(topic, vizTopicsRef.current);
      if (!matchingKey) {
        return;
      }

      const parsedPayload = safeParseJsonPayload(text);
      const effectivePayload = matchingKey === "robotDescription" && parsedPayload == null ? text : parsedPayload;
      if (effectivePayload == null) {
        if (!seenTopicKeysRef.current.has(matchingKey)) {
          seenTopicKeysRef.current.add(matchingKey);
          pushEvent(`${vizTopicDefinitions.find((entry) => entry.key === matchingKey)?.label ?? matchingKey} payload is not JSON`);
        }
        return;
      }

      if (!seenTopicKeysRef.current.has(matchingKey)) {
        seenTopicKeysRef.current.add(matchingKey);
        pushEvent(`${vizTopicDefinitions.find((entry) => entry.key === matchingKey)?.label ?? matchingKey} stream online`);
      }

      switch (matchingKey) {
        case "map": {
          const nextMap = parseOccupancyGrid(effectivePayload);
          if (nextMap) {
            scheduleBridgePatch({ map: nextMap });
          }
          break;
        }
        case "globalCostmap": {
          const nextGrid = parseOccupancyGrid(effectivePayload);
          if (nextGrid) {
            scheduleBridgePatch({ global_costmap: nextGrid });
          }
          break;
        }
        case "localCostmap": {
          const nextGrid = parseOccupancyGrid(effectivePayload);
          if (nextGrid) {
            scheduleBridgePatch({ local_costmap: nextGrid });
          }
          break;
        }
        case "robotPose": {
          const nextPose = parsePose(effectivePayload);
          if (nextPose) {
            livePoseActiveRef.current = true;
            scheduleBridgePatch({ robot_pose: nextPose });
          }
          break;
        }
        case "globalPath": {
          const nextPath = parsePathMessage(effectivePayload);
          if (nextPath) {
            scheduleBridgePatch({ global_path: nextPath });
          }
          break;
        }
        case "localPath": {
          const nextPath = parsePathMessage(effectivePayload);
          if (nextPath) {
            scheduleBridgePatch({ local_path: nextPath });
          }
          break;
        }
        case "scan": {
          const nextScan = parseLaserScan(effectivePayload);
          if (nextScan) {
            scheduleBridgePatch({ scan: nextScan });
          }
          break;
        }
        case "motionStatus": {
          const nextStatus = parseMotionStatus(effectivePayload);
          if (nextStatus) {
            scheduleBridgePatch({ motion_status: nextStatus });
          }
          break;
        }
        case "batteryState": {
          const nextBattery = parseBatteryState(effectivePayload);
          if (nextBattery) {
            scheduleBridgePatch({ battery_state: nextBattery });
          }
          break;
        }
        case "tf": {
          const nextTf = parseTfMessage(effectivePayload);
          if (nextTf) {
            const pendingTf = pendingBridgePatchRef.current.tf ?? bridgeStateRef.current.tf;
            scheduleBridgePatch({ tf: mergeTfMessages(pendingTf, nextTf) });
          }
          break;
        }
        case "tfStatic": {
          const nextTfStatic = parseTfMessage(effectivePayload);
          if (nextTfStatic) {
            const pendingTfStatic = pendingBridgePatchRef.current.tf_static ?? bridgeStateRef.current.tf_static;
            scheduleBridgePatch({ tf_static: mergeTfMessages(pendingTfStatic, nextTfStatic) });
          }
          break;
        }
        case "robotDescription": {
          const nextDescription = parseRobotDescription(effectivePayload);
          if (nextDescription) {
            scheduleBridgePatch({ robot_description: nextDescription });
          }
          break;
        }
      }
    });
  };

  useEffect(() => {
    return () => {
      if (flushBridgeFrameRef.current != null) {
        window.cancelAnimationFrame(flushBridgeFrameRef.current);
        flushBridgeFrameRef.current = null;
      }
      const client = clientRef.current;
      if (!client) {
        return;
      }

      client.removeAllListeners();
      client.end(true);
      clientRef.current = null;
    };
  }, []);

  useEffect(() => {
    const client = clientRef.current;
    if (!client?.connected) {
      return;
    }

    const publishPing = () => {
      const requestId = createCommandId();
      const sentAtMs = Date.now();
      activePingRequestIdRef.current = requestId;
      lastPingSentAtRef.current = sentAtMs;
      publishCommand(commandTopics.systemPing, {
        request_id: requestId,
        sent_at_ms: sentAtMs,
      }, "System Ping");
    };

    publishPing();
    const intervalId = window.setInterval(publishPing, 2500);
    return () => window.clearInterval(intervalId);
  }, [connectionLabel, robotId]);

  useEffect(() => {
    // When both axes are zero there is nothing to integrate – skip the loop entirely.
    if (Math.abs(teleopLinearX) < 0.0001 && Math.abs(teleopAngularZ) < 0.0001) {
      return;
    }

    let previousTime = performance.now();
    let animationFrame = 0;

    const tick = (now: number) => {
      const deltaSeconds = Math.min((now - previousTime) / 1000, 0.05);
      previousTime = now;

      if (!livePoseActiveRef.current) {
        setBridgeState((current: BridgeState) => {
          const currentPose = current.robot_pose ?? DEFAULT_ROBOT_POSE;
          if (Math.abs(teleopLinearX) < 0.0001 && Math.abs(teleopAngularZ) < 0.0001) {
            return current;
          }

          const nextYaw = currentPose.orientation.yaw + (teleopAngularZ * deltaSeconds);
          const nextX = currentPose.position.x + (Math.cos(nextYaw) * teleopLinearX * PREVIEW_LINEAR_SCALE * deltaSeconds);
          const nextY = currentPose.position.y + (Math.sin(nextYaw) * teleopLinearX * PREVIEW_LINEAR_SCALE * deltaSeconds);

          return {
            ...current,
            robot_pose: createScenePose(
              clamp(nextX, -5.5, 5.5),
              clamp(nextY, -5.5, 5.5),
              nextYaw,
            ),
          };
        });
      }

      animationFrame = window.requestAnimationFrame(tick);
    };

    animationFrame = window.requestAnimationFrame(tick);
    return () => window.cancelAnimationFrame(animationFrame);
  }, [teleopAngularZ, teleopLinearX]);

  return (
    <main className="rcs-shell">
      <Topbar
        productName={productName}
        connectionLabel={connectionLabel}
        poseLabel={formatPoseChip(robotPose.position.x, robotPose.position.y, robotPose.orientation.yaw)}
        viewMode={viewMode}
        onViewModeChange={setViewMode}
        signalBars={signalBars}
        signalLabel={signalRttMs !== null ? `${Math.round(signalRttMs)} ms` : "--"}
        batteryPercentage={batteryPercentage}
        batteryLabel={batteryPercentage !== null ? `${Math.round(batteryPercentage)}%` : DEFAULT_BATTERY_LABEL}
      />

      <section className="rcs-workspace">
        <aside className="rcs-sidebar rcs-sidebar--left">
          <MqttPanel
            mqttUrl={mqttUrl}
            robotId={robotId}
            onMqttUrlChange={setMqttUrl}
            onRobotIdChange={setRobotId}
            onConnect={connectMqtt}
            onDisconnect={() => disconnectMqtt()}
          />

          <CommandPanel
            poseInteractionMode={poseInteractionMode}
            routeWaypoints={routeWaypoints}
            activeGoalIndex={activeGoalIndex}
            onAddWaypoint={() => {
              setPoseInteractionMode((current) => {
                if (current === "goal") {
                  return "idle";
                }
                pushEvent("Route mode: drag on the map to place waypoints");
                return "goal";
              });
            }}
            onRemoveWaypoint={(index) => {
              setRouteWaypoints((current) => current.filter((_, i) => i !== index));
            }}
            onClearWaypoints={() => {
              if (autoClearTimerRef.current != null) { clearTimeout(autoClearTimerRef.current); autoClearTimerRef.current = null; }
              routeActiveRef.current = false;
              setActiveGoalIndex(-1);
              setRouteWaypoints([]);
              pushEvent("Route waypoints cleared");
            }}
            onSendRoute={handleSendRoute}
            onCancelRoute={() => {
              if (autoClearTimerRef.current != null) { clearTimeout(autoClearTimerRef.current); autoClearTimerRef.current = null; }
              routeActiveRef.current = false;
              setActiveGoalIndex(-1);
              setPoseInteractionMode("idle");
              publishCommand(commandTopics.navigationCancel, {
                request_id: createCommandId(),
              }, "Navigation Cancel");
            }}
            onSetInitialPose={() => {
              setPoseInteractionMode((current) => {
                const nextMode = current === "initial_pose" ? "idle" : "initial_pose";
                if (nextMode === "initial_pose") {
                  setSceneGoalMarker(null);
                  pushEvent("Set Initial Pose armed: drag on the map to place the pose");
                }
                return nextMode;
              });
            }}
            onOpenSettings={() => setCommandSettingsOpen(true)}
          />

          <VisualizationPanel
            layerVisibility={layerVisibility}
            onLayerVisibilityChange={(key, checked) => {
              setLayerVisibility((current) => ({
                ...current,
                [key]: checked,
              }));
            }}
            onOpenSettings={() => setVisualizationSettingsOpen(true)}
          />
        </aside>

        <div className="rcs-center-column">
          <SceneViewport
            target={activeTarget}
            state={bridgeState}
            viewMode={modeLabel}
            onResetView={() => setSceneResetToken((current) => current + 1)}
            resetViewToken={sceneResetToken}
            goalMarker={sceneGoalMarker}
            interactionMode={poseInteractionMode}
            onPoseSelection={handlePoseSelection}
            onPosePlacement={handlePosePlacement}
            routeWaypoints={routeWaypoints}
            layerVisibility={layerVisibility}
          />
        </div>

        <aside className="rcs-sidebar rcs-sidebar--right">
          <NavigationStatusPanel
            motion={motionStatus.motion}
            remainingLabel={formatDistance(motionStatus.remaining_distance ?? null)}
            headingLabel={formatHeading(motionStatus.heading)}
            goalLabel={motionStatus.goal_state ?? "Idle"}
            blockedSourceLabel={motionStatus.blocked_source ?? "Clear"}
          />

          <EventsPanel events={events} />

          <JoystickPanel
            linearX={teleopLinearX}
            angularZ={teleopAngularZ}
            onCommandChange={(linearX, angularZ) => {
              setTeleopLinearX(linearX);
              setTeleopAngularZ(angularZ);
            }}
            onCommandStop={() => {
              setTeleopLinearX(0);
              setTeleopAngularZ(0);
            }}
          />
        </aside>
      </section>

      <TopicSettingsModal
        open={commandSettingsOpen}
        title="Command Topic Settings"
        description="Edit the command topics used by the operator controls and save them locally."
        topics={commandTopicModalEntries}
        values={commandTopics}
        previewRobotId={connectedRobotId}
        onClose={() => setCommandSettingsOpen(false)}
        onSave={(nextValues) => {
          setCommandTopics(sanitizeTopicRecord(defaultCommandTopics, nextValues));
          setCommandSettingsOpen(false);
          pushEvent("Command topic settings saved");
        }}
      />

      <TopicSettingsModal
        open={visualizationSettingsOpen}
        title="Visualization Topic Settings"
        description="Edit the viz topics bound to the Visualization list and save them locally."
        topics={displayTopicModalEntries}
        values={vizTopics}
        previewRobotId={connectedRobotId}
        onClose={() => setVisualizationSettingsOpen(false)}
        onSave={(nextValues) => {
          const nextTopics = sanitizeTopicRecord(defaultVizTopics, nextValues);
          setVizTopics(nextTopics);
          syncVizSubscriptions(vizTopicsRef.current, nextTopics);
          setVisualizationSettingsOpen(false);
          pushEvent("Visualization topic settings saved");
        }}
      />
    </main>
  );
}
