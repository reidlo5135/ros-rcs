export type Header = {
  stamp?: {
    sec?: number;
    nanosec?: number;
  };
  frame_id: string;
};

export type Vector3 = {
  x: number;
  y: number;
  z: number;
};

export type Quaternion = {
  x: number;
  y: number;
  z: number;
  w: number;
  yaw: number;
};

export type Pose = {
  header?: Header;
  position: Vector3;
  orientation: Quaternion;
};

export type PathMessage = {
  header: Header;
  poses: Pose[];
};

export type OccupancyGridMessage = {
  header: Header;
  info: {
    width: number;
    height: number;
    resolution: number;
    origin: Pose;
  };
  data: number[];
};

export type LaserScanMessage = {
  header: Header;
  angle_min: number;
  angle_increment: number;
  range_min: number;
  range_max: number;
  ranges: number[];
  points?: Array<{ x: number; y: number; z?: number }>;
};

export type TransformStampedMessage = {
  header: Header;
  child_frame_id: string;
  transform: {
    translation: Vector3;
    rotation: Quaternion;
  };
};

export type TfMessage = {
  transforms: TransformStampedMessage[];
};

export type RobotDescriptionMessage = {
  data: string;
  footprint_polygon?: number[];
};

export type MotionStatusMessage = {
  motion?: string;
  state?: string;
  active?: boolean;
  goal_reached?: boolean;
  goal_state?: string;
  remaining_distance?: number;
  remaining?: number;
  heading?: number;
  heading_error?: number;
  blocked_source?: string;
  blocked_by?: string;
  blocked_pose?: Pose;
  has_blocked_pose?: boolean;
  costmap_blocked?: boolean;
  safety_gate_blocked?: boolean;
};

export type BatteryStateMessage = {
  percentage?: number;
  battery?: {
    percentage?: number;
  };
};

export type BridgeState = {
  map?: OccupancyGridMessage;
  global_costmap?: OccupancyGridMessage;
  local_costmap?: OccupancyGridMessage;
  robot_pose?: Pose;
  global_path?: PathMessage;
  local_path?: PathMessage;
  motion_status?: MotionStatusMessage;
  scan?: LaserScanMessage;
  tf?: TfMessage;
  tf_static?: TfMessage;
  robot_description?: RobotDescriptionMessage;
  battery_state?: BatteryStateMessage;
};

export type ViewMode = "navigation" | "mapping";