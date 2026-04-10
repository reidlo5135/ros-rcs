export type DashboardShellProps = {
  productName: string;
};

export type EventEntry = {
  time: string;
  text: string;
};

export type LayerIconKind =
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

export type SceneLayerVisibility = {
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

export type LayerEntry = {
  key: keyof SceneLayerVisibility;
  label: string;
  icon: LayerIconKind;
};

