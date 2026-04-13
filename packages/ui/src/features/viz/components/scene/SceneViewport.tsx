import { useEffect, useRef } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

import type { SessionTarget } from "@rcs/protocol";

import type {
  BridgeState,
  LaserScanMessage,
  OccupancyGridMessage,
  Pose,
  TfMessage,
  ViewMode,
} from "../../lib/protocol";

type SceneViewportProps = {
  target: SessionTarget;
  state: BridgeState;
  viewMode: ViewMode;
  onResetView?: () => void;
  resetViewToken?: number;
  goalMarker?: {
    x: number;
    y: number;
    yaw: number;
    kind: "goal" | "initial_pose";
  } | null;
  interactionMode?: "idle" | "goal" | "initial_pose";
  onPoseSelection?: (x: number, y: number, yaw: number) => void;
  onPosePlacement?: (mode: "goal" | "initial_pose", x: number, y: number, yaw: number) => void;
  routeWaypoints?: ReadonlyArray<{ x: number; y: number; yaw: number }>;
  layerVisibility: {
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
};

type ResolvedFrame = {
  x: number;
  y: number;
  z: number;
  roll: number;
  pitch: number;
  yaw: number;
};

type FrameEdge = {
  parent: string;
  translation: { x: number; y: number; z: number };
  roll: number;
  pitch: number;
  yaw: number;
};

type UrdfVisual = {
  linkName: string;
  xyz: THREE.Vector3;
  rpy: THREE.Vector3;
  geometry:
    | { type: "box"; size: THREE.Vector3 }
    | { type: "cylinder"; radius: number; length: number }
    | { type: "sphere"; radius: number }
    | { type: "mesh"; scale: THREE.Vector3; filename: string };
  color: THREE.Color;
  opacity: number;
};

type UrdfProxyGeometry =
  | { type: "box"; size: THREE.Vector3 }
  | { type: "cylinder"; radius: number; length: number }
  | { type: "sphere"; radius: number };

type Bounds2D = {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
};

const ROBOT_LOCAL_ORIGIN_POSE: Pose = {
  header: { frame_id: "map" },
  position: { x: 0, y: 0, z: 0 },
  orientation: {
    x: 0,
    y: 0,
    z: 0,
    w: 1,
    yaw: 0,
  },
};

const urdfVisualCache = new Map<string, UrdfVisual[]>();
const urdfFrameLookupCache = new Map<string, Map<string, FrameEdge>>();

function rotate2d(x: number, y: number, yaw: number) {
  const cosYaw = Math.cos(yaw);
  const sinYaw = Math.sin(yaw);
  return {
    x: (x * cosYaw) - (y * sinYaw),
    y: (x * sinYaw) + (y * cosYaw),
  };
}

function createEmptyBounds(): Bounds2D {
  return {
    minX: Number.POSITIVE_INFINITY,
    maxX: Number.NEGATIVE_INFINITY,
    minY: Number.POSITIVE_INFINITY,
    maxY: Number.NEGATIVE_INFINITY,
  };
}

function expandBounds(bounds: Bounds2D, x: number, y: number) {
  bounds.minX = Math.min(bounds.minX, x);
  bounds.maxX = Math.max(bounds.maxX, x);
  bounds.minY = Math.min(bounds.minY, y);
  bounds.maxY = Math.max(bounds.maxY, y);
}

function isFiniteBounds(bounds: Bounds2D) {
  return Number.isFinite(bounds.minX)
    && Number.isFinite(bounds.maxX)
    && Number.isFinite(bounds.minY)
    && Number.isFinite(bounds.maxY);
}

function boundsFromGrid(grid: OccupancyGridMessage) {
  const bounds = createEmptyBounds();
  const widthMeters = grid.info.width * grid.info.resolution;
  const heightMeters = grid.info.height * grid.info.resolution;
  const origin = grid.info.origin.position;
  const yaw = grid.info.origin.orientation.yaw;

  for (const corner of [
    rotate2d(0, 0, yaw),
    rotate2d(widthMeters, 0, yaw),
    rotate2d(widthMeters, heightMeters, yaw),
    rotate2d(0, heightMeters, yaw),
  ]) {
    expandBounds(bounds, origin.x + corner.x, origin.y + corner.y);
  }

  return bounds;
}

function parseTriplet(value: string | null | undefined, fallback = 0) {
  const tokens = (value ?? "").trim().split(/\s+/).map((token) => Number(token));
  return new THREE.Vector3(
    Number.isFinite(tokens[0]) ? tokens[0] : fallback,
    Number.isFinite(tokens[1]) ? tokens[1] : fallback,
    Number.isFinite(tokens[2]) ? tokens[2] : fallback,
  );
}

function parseUrdfVisuals(robotDescription?: string) {
  if (!robotDescription) {
    return [] as UrdfVisual[];
  }

  const cached = urdfVisualCache.get(robotDescription);
  if (cached) {
    return cached;
  }

  const parser = new DOMParser();
  const documentNode = parser.parseFromString(robotDescription, "application/xml");
  const robotNode = documentNode.querySelector("robot");
  if (!robotNode) {
    return [] as UrdfVisual[];
  }

  const materialTable = new Map<string, { color: THREE.Color; opacity: number }>();
  for (const materialNode of Array.from(robotNode.querySelectorAll(":scope > material"))) {
    const materialName = materialNode.getAttribute("name");
    const colorNode = materialNode.querySelector("color");
    if (!materialName || !colorNode) {
      continue;
    }

    const rgba = (colorNode.getAttribute("rgba") ?? "").trim().split(/\s+/).map(Number);
    if (rgba.length < 3) {
      continue;
    }

    materialTable.set(materialName, {
      color: new THREE.Color(rgba[0] ?? 0.15, rgba[1] ?? 0.15, rgba[2] ?? 0.15),
      opacity: Number.isFinite(rgba[3]) ? (rgba[3] ?? 1) : 1,
    });
  }

  const visuals: UrdfVisual[] = [];

  for (const linkNode of Array.from(robotNode.querySelectorAll("link"))) {
    const linkName = linkNode.getAttribute("name");
    if (!linkName) {
      continue;
    }

    let collisionProxy:
      | {
          xyz: THREE.Vector3;
          rpy: THREE.Vector3;
          geometry: UrdfProxyGeometry;
        }
      | null = null;

    const collisionNode = linkNode.querySelector(":scope > collision");
    if (collisionNode) {
      const collisionOriginNode = collisionNode.querySelector(":scope > origin");
      const collisionGeometryNode = collisionNode.querySelector(":scope > geometry");
      if (collisionGeometryNode) {
        const boxNode = collisionGeometryNode.querySelector("box");
        const cylinderNode = collisionGeometryNode.querySelector("cylinder");
        const sphereNode = collisionGeometryNode.querySelector("sphere");
        let geometry: UrdfProxyGeometry | null = null;

        if (boxNode) {
          geometry = { type: "box", size: parseTriplet(boxNode.getAttribute("size"), 0.06) };
        } else if (cylinderNode) {
          geometry = {
            type: "cylinder",
            radius: Number(cylinderNode.getAttribute("radius") ?? 0.03),
            length: Number(cylinderNode.getAttribute("length") ?? 0.06),
          };
        } else if (sphereNode) {
          geometry = {
            type: "sphere",
            radius: Number(sphereNode.getAttribute("radius") ?? 0.04),
          };
        }

        if (geometry) {
          collisionProxy = {
            xyz: parseTriplet(collisionOriginNode?.getAttribute("xyz"), 0),
            rpy: parseTriplet(collisionOriginNode?.getAttribute("rpy"), 0),
            geometry,
          };
        }
      }
    }

    for (const visualNode of Array.from(linkNode.querySelectorAll(":scope > visual"))) {
      const originNode = visualNode.querySelector(":scope > origin");
      const geometryNode = visualNode.querySelector(":scope > geometry");
      if (!geometryNode) {
        continue;
      }

      let xyz = parseTriplet(originNode?.getAttribute("xyz"), 0);
      let rpy = parseTriplet(originNode?.getAttribute("rpy"), 0);
      let color = new THREE.Color("#202020");
      let opacity = 1;

      const materialNode = visualNode.querySelector(":scope > material");
      const materialColorNode = materialNode?.querySelector("color");
      const materialName = materialNode?.getAttribute("name") ?? "";
      if (materialColorNode) {
        const rgba = (materialColorNode.getAttribute("rgba") ?? "").trim().split(/\s+/).map(Number);
        color = new THREE.Color(rgba[0] ?? 0.15, rgba[1] ?? 0.15, rgba[2] ?? 0.15);
        opacity = Number.isFinite(rgba[3]) ? (rgba[3] ?? 1) : 1;
      } else if (materialName && materialTable.has(materialName)) {
        const resolved = materialTable.get(materialName)!;
        color = resolved.color.clone();
        opacity = resolved.opacity;
      }

      const boxNode = geometryNode.querySelector("box");
      const cylinderNode = geometryNode.querySelector("cylinder");
      const sphereNode = geometryNode.querySelector("sphere");
      const meshNode = geometryNode.querySelector("mesh");
      let geometry: UrdfVisual["geometry"] | null = null;

      if (boxNode) {
        geometry = { type: "box", size: parseTriplet(boxNode.getAttribute("size"), 0.06) };
      } else if (cylinderNode) {
        geometry = {
          type: "cylinder",
          radius: Number(cylinderNode.getAttribute("radius") ?? 0.03),
          length: Number(cylinderNode.getAttribute("length") ?? 0.06),
        };
      } else if (sphereNode) {
        geometry = {
          type: "sphere",
          radius: Number(sphereNode.getAttribute("radius") ?? 0.04),
        };
      } else if (meshNode) {
        if (collisionProxy) {
          xyz.copy(collisionProxy.xyz);
          geometry = collisionProxy.geometry;
        } else {
          geometry = {
            type: "mesh",
            scale: parseTriplet(meshNode.getAttribute("scale"), 1),
            filename: meshNode.getAttribute("filename") ?? "",
          };
        }
      }

      if (geometry) {
        visuals.push({ linkName, xyz, rpy, geometry, color, opacity });
      }
    }
  }

  urdfVisualCache.set(robotDescription, visuals);
  return visuals;
}

function parseUrdfFrameLookup(robotDescription?: string) {
  if (!robotDescription) {
    return new Map<string, FrameEdge>();
  }

  const cached = urdfFrameLookupCache.get(robotDescription);
  if (cached) {
    return new Map(cached);
  }

  const parser = new DOMParser();
  const documentNode = parser.parseFromString(robotDescription, "application/xml");
  const robotNode = documentNode.querySelector("robot");
  const lookup = new Map<string, FrameEdge>();

  if (!robotNode) {
    urdfFrameLookupCache.set(robotDescription, lookup);
    return new Map(lookup);
  }

  for (const jointNode of Array.from(robotNode.querySelectorAll("joint"))) {
    const parent = jointNode.querySelector(":scope > parent")?.getAttribute("link");
    const child = jointNode.querySelector(":scope > child")?.getAttribute("link");
    const originNode = jointNode.querySelector(":scope > origin");
    if (!parent || !child) {
      continue;
    }

    const xyz = parseTriplet(originNode?.getAttribute("xyz"), 0);
    const rpy = parseTriplet(originNode?.getAttribute("rpy"), 0);
    lookup.set(child, {
      parent,
      translation: { x: xyz.x, y: xyz.y, z: xyz.z },
      roll: rpy.x,
      pitch: rpy.y,
      yaw: rpy.z,
    });
  }

  urdfFrameLookupCache.set(robotDescription, lookup);
  return new Map(lookup);
}

function addRobotOutline(object: THREE.Object3D) {
  if (!(object instanceof THREE.Mesh)) {
    return;
  }

  const edges = new THREE.EdgesGeometry(object.geometry);
  const outline = new THREE.LineSegments(
    edges,
    new THREE.LineBasicMaterial({
      color: "#1f2430",
      transparent: true,
      opacity: 0.24,
      depthTest: false,
      depthWrite: false,
    }),
  );
  outline.renderOrder = 43;
  object.add(outline);
}

function disposeObject(object: THREE.Object3D | null) {
  if (!object) {
    return;
  }

  object.traverse((child) => {
    const mesh = child as THREE.Mesh & { material?: THREE.Material | THREE.Material[] };
    if ("geometry" in mesh && mesh.geometry) {
      mesh.geometry.dispose();
    }
    if (mesh.material) {
      const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      for (const material of materials) {
        const textureMaterial = material as THREE.Material & {
          map?: THREE.Texture | null;
          alphaMap?: THREE.Texture | null;
        };
        textureMaterial.map?.dispose();
        textureMaterial.alphaMap?.dispose();
        material.dispose();
      }
    }
  });
}

function buildPathLine(points: Array<{ x: number; y: number }>, color: string, yOffset: number) {
  if (points.length < 2) {
    return null;
  }

  const curvePoints = points.map((point) => new THREE.Vector3(point.x, yOffset, -point.y));
  const curve = new THREE.CatmullRomCurve3(curvePoints, false, "catmullrom", 0.05);
  const tubeGeometry = new THREE.TubeGeometry(curve, Math.max(points.length * 4, 32), 0.018, 8, false);
  const tube = new THREE.Mesh(
    tubeGeometry,
    new THREE.MeshBasicMaterial({
      color,
      transparent: true,
      opacity: 0.96,
      depthTest: false,
      depthWrite: false,
    }),
  );
  tube.renderOrder = 20;

  const pointGeometry = new THREE.BufferGeometry().setFromPoints(
    points.map((point) => new THREE.Vector3(point.x, yOffset + 0.01, -point.y)),
  );
  const pointCloud = new THREE.Points(
    pointGeometry,
    new THREE.PointsMaterial({
      color,
      size: 0.12,
      transparent: true,
      opacity: 1,
      sizeAttenuation: true,
      depthTest: false,
      depthWrite: false,
    }),
  );
  pointCloud.renderOrder = 21;

  const group = new THREE.Group();
  group.add(tube, pointCloud);
  return group;
}

function buildArrowPoseMarker(
  goalMarker: { x: number; y: number; yaw: number },
  colors: { primary: string; accent: string },
  options?: {
    originFillRadius?: number;
    originRingInnerRadius?: number;
    originRingOuterRadius?: number;
  },
) {
  const group = new THREE.Group();
  group.position.set(goalMarker.x, 0, -goalMarker.y);
  group.rotation.y = -goalMarker.yaw;

  const tail = new THREE.Mesh(
    new THREE.CylinderGeometry(0.022, 0.022, 0.22, 20),
    new THREE.MeshBasicMaterial({ color: colors.accent, depthTest: false, depthWrite: false }),
  );
  tail.rotation.z = -Math.PI / 2;
  tail.position.set(0.16, 0.06, 0);
  tail.renderOrder = 24;

  const head = new THREE.Mesh(
    new THREE.ConeGeometry(0.07, 0.16, 3),
    new THREE.MeshBasicMaterial({ color: colors.primary, depthTest: false, depthWrite: false }),
  );
  head.rotation.x = Math.PI / 2;
  head.rotation.z = -Math.PI / 2;
  head.position.set(0.36, 0.062, 0);
  head.renderOrder = 25;

  const fillRadius = options?.originFillRadius ?? 0.05;
  const ringInner = options?.originRingInnerRadius ?? 0.06;
  const ringOuter = options?.originRingOuterRadius ?? 0.082;
  const origin = new THREE.Mesh(
    new THREE.CircleGeometry(fillRadius, 24),
    new THREE.MeshBasicMaterial({ color: colors.primary, depthTest: false, depthWrite: false }),
  );
  origin.rotation.x = -Math.PI / 2;
  origin.position.y = 0.062;
  origin.renderOrder = 24;

  const ring = new THREE.Mesh(
    new THREE.RingGeometry(ringInner, ringOuter, 28),
    new THREE.MeshBasicMaterial({ color: colors.accent, side: THREE.DoubleSide, depthTest: false, depthWrite: false }),
  );
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.061;
  ring.renderOrder = 23;

  group.add(tail, head, origin, ring);
  return group;
}

function buildGoalMarker(goalMarker: { x: number; y: number; yaw: number; kind: "goal" | "initial_pose" }) {
  return goalMarker.kind === "initial_pose"
    ? buildArrowPoseMarker(goalMarker, { primary: "#2aa84a", accent: "#d9f7df" }, {
      originFillRadius: 0.043,
      originRingInnerRadius: 0.05,
      originRingOuterRadius: 0.075,
    })
    : buildArrowPoseMarker(goalMarker, { primary: "#d62828", accent: "#ffe3e3" });
}

function buildGridOutline(grid: OccupancyGridMessage, color: string, yOffset: number) {
  const widthMeters = grid.info.width * grid.info.resolution;
  const heightMeters = grid.info.height * grid.info.resolution;
  const origin = grid.info.origin.position;
  const yaw = grid.info.origin.orientation.yaw;

  const corners = [
    new THREE.Vector3(origin.x, yOffset, -origin.y),
    (() => {
      const point = rotate2d(widthMeters, 0, yaw);
      return new THREE.Vector3(origin.x + point.x, yOffset, -(origin.y + point.y));
    })(),
    (() => {
      const point = rotate2d(widthMeters, heightMeters, yaw);
      return new THREE.Vector3(origin.x + point.x, yOffset, -(origin.y + point.y));
    })(),
    (() => {
      const point = rotate2d(0, heightMeters, yaw);
      return new THREE.Vector3(origin.x + point.x, yOffset, -(origin.y + point.y));
    })(),
  ];

  const geometry = new THREE.BufferGeometry().setFromPoints([...corners, corners[0].clone()]);
  const outline = new THREE.Line(
    geometry,
    new THREE.LineBasicMaterial({
      color,
      transparent: true,
      opacity: 0.95,
      depthTest: false,
      depthWrite: false,
    }),
  );
  outline.renderOrder = 18;
  return outline;
}

function buildRobotPoseMarker(robotPose: Pose | undefined) {
  if (!robotPose) {
    return null;
  }

  const marker = new THREE.Group();
  marker.position.set(robotPose.position.x, 0, -robotPose.position.y);
  marker.rotation.y = -robotPose.orientation.yaw;

  const body = new THREE.Mesh(
    new THREE.CircleGeometry(0.14, 28),
    new THREE.MeshBasicMaterial({
      color: "#1c2a39",
      transparent: true,
      opacity: 0.92,
      depthTest: false,
      depthWrite: false,
    }),
  );
  body.rotation.x = -Math.PI / 2;
  body.position.y = 0.07;
  body.renderOrder = 44;

  const heading = new THREE.Mesh(
    new THREE.ConeGeometry(0.08, 0.2, 3),
    new THREE.MeshBasicMaterial({ color: "#ffad33", depthTest: false, depthWrite: false }),
  );
  heading.rotation.x = Math.PI / 2;
  heading.rotation.z = -Math.PI / 2;
  heading.position.set(0.16, 0.075, 0);
  heading.renderOrder = 45;

  marker.add(body, heading);
  return marker;
}

type OverlayProjection = {
  size: number;
  padding: number;
  scale: number;
  offsetX: number;
  offsetY: number;
  bounds: Bounds2D;
};

function createOverlayProjection(bounds: Bounds2D, size = 1000, padding = 48): OverlayProjection {
  const spanX = Math.max(bounds.maxX - bounds.minX, 1);
  const spanY = Math.max(bounds.maxY - bounds.minY, 1);
  const scale = Math.min((size - (padding * 2)) / spanX, (size - (padding * 2)) / spanY);
  const offsetX = (size - (spanX * scale)) / 2;
  const offsetY = (size - (spanY * scale)) / 2;

  return {
    size,
    padding,
    scale,
    offsetX,
    offsetY,
    bounds,
  };
}

function projectOverlayPoint(projection: OverlayProjection, x: number, y: number) {
  return {
    x: projection.offsetX + ((x - projection.bounds.minX) * projection.scale),
    y: projection.size - (projection.offsetY + ((y - projection.bounds.minY) * projection.scale)),
  };
}

function buildOverlayGridPolygon(grid: OccupancyGridMessage, projection: OverlayProjection) {
  const widthMeters = grid.info.width * grid.info.resolution;
  const heightMeters = grid.info.height * grid.info.resolution;
  const origin = grid.info.origin.position;
  const yaw = grid.info.origin.orientation.yaw;
  const corners = [
    { x: origin.x, y: origin.y },
    (() => {
      const rotated = rotate2d(widthMeters, 0, yaw);
      return { x: origin.x + rotated.x, y: origin.y + rotated.y };
    })(),
    (() => {
      const rotated = rotate2d(widthMeters, heightMeters, yaw);
      return { x: origin.x + rotated.x, y: origin.y + rotated.y };
    })(),
    (() => {
      const rotated = rotate2d(0, heightMeters, yaw);
      return { x: origin.x + rotated.x, y: origin.y + rotated.y };
    })(),
  ];

  return corners
    .map((corner) => {
      const projected = projectOverlayPoint(projection, corner.x, corner.y);
      return `${projected.x},${projected.y}`;
    })
    .join(" ");
}

function resolveScanWorldPoints(
  scan: LaserScanMessage | undefined,
  tf: TfMessage | undefined,
  tfStatic: TfMessage | undefined,
  robotPose: Pose | undefined,
) {
  if (!scan) {
    return [] as Array<{ x: number; y: number }>;
  }

  const lookup = buildFrameLookup(tf, tfStatic);
  const scanFrame = resolveFrame(scan.header.frame_id, lookup, robotPose);
  const basePose = scanFrame ?? (robotPose
    ? {
      x: robotPose.position.x,
      y: robotPose.position.y,
      z: robotPose.position.z,
      yaw: robotPose.orientation.yaw,
    }
    : { x: 0, y: 0, z: 0, yaw: 0 });

  if (scan.points?.length) {
    return scan.points.map((point) => ({ x: point.x, y: point.y }));
  }

  const points: Array<{ x: number; y: number }> = [];
  for (let index = 0; index < scan.ranges.length; index += 1) {
    const range = scan.ranges[index];
    if (!Number.isFinite(range) || range < scan.range_min || range > scan.range_max) {
      continue;
    }

    const angle = scan.angle_min + (index * scan.angle_increment);
    const localX = Math.cos(angle) * range;
    const localY = Math.sin(angle) * range;
    const rotated = rotate2d(localX, localY, basePose.yaw);
    points.push({ x: basePose.x + rotated.x, y: basePose.y + rotated.y });
  }

  return points;
}

function SceneDataOverlay({ state, layerVisibility }: { state: BridgeState; layerVisibility: SceneViewportProps["layerVisibility"] }) {
  const robotPose = state.robot_pose;
  const scanPoints = resolveScanWorldPoints(state.scan, state.tf, state.tf_static, robotPose);
  const bounds = createEmptyBounds();

  for (const grid of [state.map, state.global_costmap, state.local_costmap]) {
    if (!grid) {
      continue;
    }
    const gridBounds = boundsFromGrid(grid);
    expandBounds(bounds, gridBounds.minX, gridBounds.minY);
    expandBounds(bounds, gridBounds.maxX, gridBounds.maxY);
  }

  if (robotPose) {
    expandBounds(bounds, robotPose.position.x, robotPose.position.y);
  }

  for (const pose of state.global_path?.poses ?? []) {
    expandBounds(bounds, pose.position.x, pose.position.y);
  }
  for (const pose of state.local_path?.poses ?? []) {
    expandBounds(bounds, pose.position.x, pose.position.y);
  }
  for (const point of scanPoints) {
    expandBounds(bounds, point.x, point.y);
  }

  if (!isFiniteBounds(bounds)) {
    return null;
  }

  const projection = createOverlayProjection(bounds);
  const globalPath = (state.global_path?.poses ?? [])
    .map((pose) => projectOverlayPoint(projection, pose.position.x, pose.position.y))
    .map((point) => `${point.x},${point.y}`)
    .join(" ");
  const localPath = (state.local_path?.poses ?? [])
    .map((pose) => projectOverlayPoint(projection, pose.position.x, pose.position.y))
    .map((point) => `${point.x},${point.y}`)
    .join(" ");
  const projectedRobot = robotPose ? projectOverlayPoint(projection, robotPose.position.x, robotPose.position.y) : null;
  const headingLength = 26;
  const headingX = projectedRobot ? projectedRobot.x + (Math.cos(robotPose!.orientation.yaw) * headingLength) : 0;
  const headingY = projectedRobot ? projectedRobot.y - (Math.sin(robotPose!.orientation.yaw) * headingLength) : 0;

  return (
    <svg className="rcs-scene__overlay" viewBox={`0 0 ${projection.size} ${projection.size}`} preserveAspectRatio="xMidYMid meet">
      <defs>
        <pattern id="rcs-scene-overlay-grid" width="36" height="36" patternUnits="userSpaceOnUse">
          <path d="M 36 0 L 0 0 0 36" fill="none" stroke="rgba(120,120,120,0.22)" strokeWidth="1" />
        </pattern>
      </defs>
      <rect x="0" y="0" width={projection.size} height={projection.size} fill="url(#rcs-scene-overlay-grid)" opacity="0.55" />

      {layerVisibility.map && state.map ? (
        <polygon points={buildOverlayGridPolygon(state.map, projection)} fill="rgba(250,250,250,0.82)" stroke="#444b55" strokeWidth="2.2" />
      ) : null}
      {layerVisibility.globalCostmap && state.global_costmap ? (
        <polygon points={buildOverlayGridPolygon(state.global_costmap, projection)} fill="rgba(232,112,182,0.18)" stroke="#985260" strokeWidth="2" />
      ) : null}
      {layerVisibility.localCostmap && state.local_costmap ? (
        <polygon points={buildOverlayGridPolygon(state.local_costmap, projection)} fill="rgba(232,168,72,0.18)" stroke="#8f6a2c" strokeWidth="2" />
      ) : null}

      {layerVisibility.globalPlan && globalPath ? (
        <polyline points={globalPath} fill="none" stroke="#23d9ff" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round" />
      ) : null}
      {layerVisibility.localPlan && localPath ? (
        <polyline points={localPath} fill="none" stroke="#95dd00" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round" />
      ) : null}

      {layerVisibility.scan
        ? scanPoints.map((point, index) => {
          const projected = projectOverlayPoint(projection, point.x, point.y);
          return <circle key={`scan-${index}`} cx={projected.x} cy={projected.y} r="1.6" fill="#2fcf54" opacity="0.9" />;
        })
        : null}

      {layerVisibility.robot && projectedRobot ? (
        <g>
          <circle cx={projectedRobot.x} cy={projectedRobot.y} r="12" fill="#1c2a39" opacity="0.92" />
          <line x1={projectedRobot.x} y1={projectedRobot.y} x2={headingX} y2={headingY} stroke="#ffad33" strokeWidth="4" strokeLinecap="round" />
        </g>
      ) : null}
    </svg>
  );
}

function buildFootprintOverlay(
  footprintPolygon: number[] | undefined,
  robotPose: Pose | undefined,
  options?: {
    fillColor?: string;
    outlineColor?: string;
    fillOpacity?: number;
    yOffset?: number;
    renderOrder?: number;
  },
) {
  if (!robotPose || !footprintPolygon || footprintPolygon.length < 6 || footprintPolygon.length % 2 !== 0) {
    return null;
  }

  const fillColor = options?.fillColor ?? "#2b7cff";
  const outlineColor = options?.outlineColor ?? "#134ed0";
  const fillOpacity = options?.fillOpacity ?? 0.14;
  const yOffset = options?.yOffset ?? 0.042;
  const renderOrder = options?.renderOrder ?? 18;

  const shape = new THREE.Shape();
  shape.moveTo(footprintPolygon[0], -footprintPolygon[1]);
  for (let index = 2; index < footprintPolygon.length; index += 2) {
    shape.lineTo(footprintPolygon[index], -footprintPolygon[index + 1]);
  }
  shape.closePath();

  const fill = new THREE.Mesh(
    new THREE.ShapeGeometry(shape),
    new THREE.MeshBasicMaterial({
      color: fillColor,
      transparent: true,
      opacity: fillOpacity,
      side: THREE.DoubleSide,
      depthTest: false,
      depthWrite: false,
    }),
  );
  fill.rotation.x = -Math.PI / 2;
  fill.position.y = yOffset;
  fill.renderOrder = renderOrder;

  const outlinePoints: THREE.Vector3[] = [];
  for (let index = 0; index < footprintPolygon.length; index += 2) {
    outlinePoints.push(new THREE.Vector3(footprintPolygon[index], yOffset + 0.001, -footprintPolygon[index + 1]));
  }
  outlinePoints.push(outlinePoints[0].clone());

  const outline = new THREE.Line(
    new THREE.BufferGeometry().setFromPoints(outlinePoints),
    new THREE.LineBasicMaterial({ color: outlineColor, depthTest: false, depthWrite: false }),
  );
  outline.renderOrder = renderOrder + 1;

  const group = new THREE.Group();
  group.position.set(robotPose.position.x, 0, -robotPose.position.y);
  group.rotation.y = -robotPose.orientation.yaw;
  group.add(fill, outline);
  return group;
}

function buildBlockedLinkOverlay(robotPose: Pose | undefined, blockedPose: Pose | undefined) {
  if (!robotPose || !blockedPose) {
    return null;
  }

  const geometry = new THREE.BufferGeometry().setFromPoints([
    new THREE.Vector3(robotPose.position.x, 0.09, -robotPose.position.y),
    new THREE.Vector3(blockedPose.position.x, 0.09, -blockedPose.position.y),
  ]);
  const line = new THREE.Line(
    geometry,
    new THREE.LineBasicMaterial({
      color: "#4cff63",
      transparent: true,
      opacity: 0.9,
      depthTest: false,
      depthWrite: false,
    }),
  );
  line.renderOrder = 22;
  const group = new THREE.Group();
  group.add(line);
  return group;
}

function createScanSpriteTexture() {
  const canvas = document.createElement("canvas");
  canvas.width = 32;
  canvas.height = 32;
  const context = canvas.getContext("2d");
  if (!context) {
    const fallback = new THREE.CanvasTexture(canvas);
    fallback.needsUpdate = true;
    return fallback;
  }

  context.clearRect(0, 0, canvas.width, canvas.height);
  const gradient = context.createRadialGradient(16, 16, 1, 16, 16, 14);
  gradient.addColorStop(0, "rgba(29,156,44,1)");
  gradient.addColorStop(0.55, "rgba(53,205,74,0.92)");
  gradient.addColorStop(1, "rgba(53,205,74,0)");
  context.fillStyle = gradient;
  context.beginPath();
  context.arc(16, 16, 14, 0, Math.PI * 2);
  context.fill();

  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;
  return texture;
}

function interpolateChannel(start: number, end: number, ratio: number) {
  return Math.round(start + ((end - start) * ratio));
}

function buildOccupancyTexture(
  grid: OccupancyGridMessage,
  palette: "map" | "global_costmap" | "local_costmap",
) {
  const { width, height } = grid.info;
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) {
    const texture = new THREE.Texture();
    texture.needsUpdate = true;
    return texture;
  }

  const imageData = context.createImageData(width, height);
  const rgba = imageData.data;

  for (let row = 0; row < height; row += 1) {
    for (let col = 0; col < width; col += 1) {
      const sourceIndex = ((height - 1 - row) * width) + col;
      const targetIndex = ((row * width) + col) * 4;
      const value = grid.data[sourceIndex] ?? -1;
      let red = 0;
      let green = 0;
      let blue = 0;
      let alpha = 0;

      if (palette === "map") {
        if (value < 0) {
          red = 201;
          green = 201;
          blue = 201;
          alpha = 255;
        } else if (value >= 50) {
          red = 36;
          green = 22;
          blue = 48;
          alpha = 255;
        } else {
          red = 255;
          green = 255;
          blue = 255;
          alpha = 255;
        }
      } else if (value > 0) {
        const normalized = Math.min(Math.max(value / 100, 0), 1);
        if (palette === "global_costmap") {
          if (normalized < 0.45) {
            const ratio = normalized / 0.45;
            red = interpolateChannel(250, 235, ratio);
            green = interpolateChannel(244, 233, ratio);
            blue = interpolateChannel(255, 248, ratio);
          } else {
            const ratio = (normalized - 0.45) / 0.55;
            red = interpolateChannel(232, 138, ratio);
            green = interpolateChannel(112, 30, ratio);
            blue = interpolateChannel(182, 122, ratio);
          }
        } else {
          if (normalized < 0.45) {
            const ratio = normalized / 0.45;
            red = interpolateChannel(255, 232, ratio);
            green = interpolateChannel(214, 112, ratio);
            blue = interpolateChannel(226, 182, ratio);
          } else {
            const ratio = (normalized - 0.45) / 0.55;
            red = interpolateChannel(232, 118, ratio);
            green = interpolateChannel(112, 48, ratio);
            blue = interpolateChannel(182, 135, ratio);
          }
        }
        alpha = Math.round(40 + (normalized * 170));
      }

      rgba[targetIndex] = red;
      rgba[targetIndex + 1] = green;
      rgba[targetIndex + 2] = blue;
      rgba[targetIndex + 3] = alpha;
    }
  }

  context.putImageData(imageData, 0, 0);
  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;
  texture.magFilter = THREE.NearestFilter;
  texture.minFilter = THREE.NearestFilter;
  texture.generateMipmaps = false;
  texture.flipY = true;
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function buildOccupancyMesh(
  grid: OccupancyGridMessage,
  palette: "map" | "global_costmap" | "local_costmap",
  yOffset: number,
) {
  const widthMeters = grid.info.width * grid.info.resolution;
  const heightMeters = grid.info.height * grid.info.resolution;
  const originYaw = grid.info.origin.orientation.yaw;
  const center = rotate2d(widthMeters / 2, heightMeters / 2, originYaw);
  const centerX = grid.info.origin.position.x + center.x;
  const centerY = grid.info.origin.position.y + center.y;

  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(widthMeters, heightMeters),
    new THREE.MeshBasicMaterial({
      map: buildOccupancyTexture(grid, palette),
      transparent: palette !== "map",
      depthWrite: palette === "map",
      side: THREE.DoubleSide,
      toneMapped: false,
    }),
  );
  mesh.rotation.x = -Math.PI / 2;
  mesh.rotation.y = -originYaw;
  mesh.position.set(centerX, yOffset, -centerY);
  mesh.renderOrder = palette === "map" ? 11 : palette === "global_costmap" ? 12 : 13;
  return mesh;
}

function buildFrameLookup(tf?: TfMessage, tfStatic?: TfMessage, robotDescription?: string) {
  const lookup = parseUrdfFrameLookup(robotDescription);
  const collect = (message: TfMessage | undefined) => {
    for (const transform of message?.transforms ?? []) {
      lookup.set(transform.child_frame_id, {
        parent: transform.header.frame_id,
        translation: {
          x: transform.transform.translation.x,
          y: transform.transform.translation.y,
          z: transform.transform.translation.z,
        },
        roll: 0,
        pitch: 0,
        yaw: transform.transform.rotation.yaw,
      });
    }
  };

  collect(tfStatic);
  collect(tf);
  return lookup;
}

function resolveFrame(
  frameId: string,
  lookup: Map<string, FrameEdge>,
  robotPose?: Pose,
  cache = new Map<string, ResolvedFrame | null>(),
  depth = 0,
): ResolvedFrame | null {
  if (cache.has(frameId)) {
    return cache.get(frameId) ?? null;
  }
  if (depth > 24) {
    cache.set(frameId, null);
    return null;
  }

  if (frameId === "map") {
    const identity = { x: 0, y: 0, z: 0, roll: 0, pitch: 0, yaw: 0 };
    cache.set(frameId, identity);
    return identity;
  }

  const edge = lookup.get(frameId);
  if (!edge) {
    if (robotPose && (frameId === "base_footprint" || frameId === "base_link")) {
      const resolved = {
        x: robotPose.position.x,
        y: robotPose.position.y,
        z: robotPose.position.z,
        roll: 0,
        pitch: 0,
        yaw: robotPose.orientation.yaw,
      };
      cache.set(frameId, resolved);
      return resolved;
    }
    cache.set(frameId, null);
    return null;
  }

  const parent = resolveFrame(edge.parent, lookup, robotPose, cache, depth + 1);
  if (!parent) {
    cache.set(frameId, null);
    return null;
  }

  const rotated = rotate2d(edge.translation.x, edge.translation.y, parent.yaw);
  const resolved = {
    x: parent.x + rotated.x,
    y: parent.y + rotated.y,
    z: parent.z + edge.translation.z,
    roll: parent.roll + edge.roll,
    pitch: parent.pitch + edge.pitch,
    yaw: parent.yaw + edge.yaw,
  };
  cache.set(frameId, resolved);
  return resolved;
}

function createPoseFromResolvedFrame(frame: ResolvedFrame): Pose {
  return {
    header: { frame_id: "map" },
    position: {
      x: frame.x,
      y: frame.y,
      z: frame.z,
    },
    orientation: {
      x: 0,
      y: 0,
      z: Math.sin(frame.yaw / 2),
      w: Math.cos(frame.yaw / 2),
      yaw: frame.yaw,
    },
  };
}

function resolveRobotScenePose(
  tf: TfMessage | undefined,
  tfStatic: TfMessage | undefined,
  robotPose: Pose | undefined,
  robotDescription?: string,
) {
  const lookup = buildFrameLookup(tf, tfStatic, robotDescription);
  const cache = new Map<string, ResolvedFrame | null>();
  const resolvedBase =
    resolveFrame("base_footprint", lookup, robotPose, cache)
    ?? resolveFrame("base_link", lookup, robotPose, cache);

  if (!resolvedBase) {
    return robotPose;
  }

  return createPoseFromResolvedFrame(resolvedBase);
}

function buildScanPoints(
  scan: LaserScanMessage | undefined,
  tf: TfMessage | undefined,
  tfStatic: TfMessage | undefined,
  robotPose: Pose | undefined,
) {
  if (!scan) {
    return null;
  }

  const lookup = buildFrameLookup(tf, tfStatic);
  const scanFrame = resolveFrame(scan.header.frame_id, lookup, robotPose);
  const fallbackPose = robotPose
    ? {
      x: robotPose.position.x,
      y: robotPose.position.y,
      z: robotPose.position.z,
      yaw: robotPose.orientation.yaw,
    }
    : { x: 0, y: 0, z: 0, yaw: 0 };
  const pose = scanFrame ?? fallbackPose;
  const points: number[] = [];

  if (scan.points && scan.points.length > 0) {
    for (const point of scan.points) {
      points.push(point.x, 0.08 + (point.z ?? 0), -point.y);
    }
  } else {
    for (let index = 0; index < scan.ranges.length; index += 1) {
      const range = scan.ranges[index];
      if (!Number.isFinite(range) || range < scan.range_min || range > scan.range_max) {
        continue;
      }

      const angle = scan.angle_min + (index * scan.angle_increment);
      const localX = Math.cos(angle) * range;
      const localY = Math.sin(angle) * range;
      const rotated = rotate2d(localX, localY, pose.yaw);
      points.push(pose.x + rotated.x, 0.08, -(pose.y + rotated.y));
    }
  }

  if (points.length === 0) {
    return null;
  }

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(points, 3));
  const material = new THREE.PointsMaterial({
    color: "#25d038",
    map: createScanSpriteTexture(),
    transparent: true,
    opacity: 0.98,
    alphaTest: 0.15,
    depthTest: false,
    depthWrite: false,
    sizeAttenuation: true,
    size: 0.09,
  });
  const pointCloud = new THREE.Points(geometry, material);
  pointCloud.renderOrder = 30;
  return pointCloud;
}

function createTfAxes(color = "#8bff8f") {
  const frameGroup = new THREE.Group();

  const hub = new THREE.Mesh(
    new THREE.SphereGeometry(0.028, 12, 12),
    new THREE.MeshBasicMaterial({ color, depthTest: false, depthWrite: false }),
  );
  hub.renderOrder = 16;
  frameGroup.add(hub);

  const axisRadius = 0.008;
  const xAxis = new THREE.Mesh(
    new THREE.CylinderGeometry(axisRadius, axisRadius, 0.24, 10),
    new THREE.MeshBasicMaterial({ color: "#ff4d4d", depthTest: false, depthWrite: false }),
  );
  xAxis.rotation.z = -Math.PI / 2;
  xAxis.position.x = 0.12;
  xAxis.renderOrder = 17;

  const yAxis = new THREE.Mesh(
    new THREE.CylinderGeometry(axisRadius, axisRadius, 0.24, 10),
    new THREE.MeshBasicMaterial({ color: "#2fd06a", depthTest: false, depthWrite: false }),
  );
  yAxis.rotation.x = Math.PI / 2;
  yAxis.position.z = -0.12;
  yAxis.renderOrder = 17;

  const zAxis = new THREE.Mesh(
    new THREE.CylinderGeometry(axisRadius, axisRadius, 0.18, 10),
    new THREE.MeshBasicMaterial({ color: "#4f8fff", depthTest: false, depthWrite: false }),
  );
  zAxis.position.y = 0.09;
  zAxis.renderOrder = 17;

  frameGroup.add(xAxis, yAxis, zAxis);
  return frameGroup;
}

function createTfLine(color: string) {
  const line = new THREE.Line(
    new THREE.BufferGeometry(),
    new THREE.LineBasicMaterial({
      color,
      transparent: true,
      opacity: 0.95,
    }),
  );
  line.renderOrder = 15;
  return line;
}

function syncTfLine(line: THREE.Line, start: THREE.Vector3, end: THREE.Vector3) {
  const geometry = line.geometry as THREE.BufferGeometry;
  geometry.setFromPoints([start, end]);
  geometry.attributes.position.needsUpdate = true;
  geometry.computeBoundingSphere();
}

function buildTfGroup(
  tf: TfMessage | undefined,
  tfStatic: TfMessage | undefined,
  robotPose: Pose | undefined,
  existingGroup?: THREE.Group | null,
) {
  const lookup = buildFrameLookup(tf, tfStatic);
  const transforms = [
    ...(tfStatic?.transforms.map((transform) => ({ transform, isStatic: true })) ?? []),
    ...(tf?.transforms.map((transform) => ({ transform, isStatic: false })) ?? []),
  ];
  if (transforms.length === 0) {
    return null;
  }

  const group = existingGroup ?? new THREE.Group();
  const cache = new Map<string, ResolvedFrame | null>();
  const tfObjects = (group.userData.tfObjects as Map<string, { axes: THREE.Group; line: THREE.Line | null }> | undefined)
    ?? new Map<string, { axes: THREE.Group; line: THREE.Line | null }>();
  group.userData.tfObjects = tfObjects;

  if (!group.userData.originAxes) {
    const originAxes = createTfAxes("#ffd36b");
    originAxes.position.set(0, 0.1, 0);
    group.userData.originAxes = originAxes;
    group.add(originAxes);
  }

  const activeKeys = new Set<string>();

  for (const entry of transforms) {
    const child = resolveFrame(entry.transform.child_frame_id, lookup, robotPose, cache);
    const parent = resolveFrame(entry.transform.header.frame_id, lookup, robotPose, cache);
    if (!child) {
      continue;
    }

    const key = `${entry.isStatic ? "static" : "dynamic"}:${entry.transform.child_frame_id}`;
    activeKeys.add(key);
    let record = tfObjects.get(key);
    if (!record) {
      record = {
        axes: createTfAxes(entry.isStatic ? "#7aa1ff" : "#8bff8f"),
        line: null,
      };
      tfObjects.set(key, record);
      group.add(record.axes);
    }
    record.axes.position.set(child.x, 0.1, -child.y);
    record.axes.rotation.set(0, -child.yaw, 0);

    if (parent) {
      if (!record.line) {
        record.line = createTfLine(entry.isStatic ? "#5b7dff" : "#56ff86");
        group.add(record.line);
      }
      syncTfLine(
        record.line,
        new THREE.Vector3(parent.x, 0.06, -parent.y),
        new THREE.Vector3(child.x, 0.06, -child.y),
      );
    } else if (record.line) {
      group.remove(record.line);
      disposeObject(record.line);
      record.line = null;
    }
  }

  for (const [key, record] of tfObjects.entries()) {
    if (activeKeys.has(key)) {
      continue;
    }
    group.remove(record.axes);
    disposeObject(record.axes);
    if (record.line) {
      group.remove(record.line);
      disposeObject(record.line);
    }
    tfObjects.delete(key);
  }

  return group.children.length > 0 ? group : null;
}

function buildRobotVisualMesh(visual: UrdfVisual) {
  let object: THREE.Object3D;
  const descriptor =
    visual.geometry.type === "mesh"
      ? `${visual.linkName} ${visual.geometry.filename}`.toLowerCase()
      : visual.linkName.toLowerCase();

  const material = new THREE.MeshBasicMaterial({
    color: visual.color,
    transparent: visual.opacity < 0.999,
    opacity: visual.opacity,
    depthTest: false,
    depthWrite: false,
  });

  switch (visual.geometry.type) {
    case "box":
      object = new THREE.Mesh(
        new THREE.BoxGeometry(
          Math.max(visual.geometry.size.x, 0.01),
          Math.max(visual.geometry.size.z, 0.01),
          Math.max(visual.geometry.size.y, 0.01),
        ),
        material,
      );
      break;
    case "cylinder":
      object = new THREE.Mesh(
        new THREE.CylinderGeometry(
          Math.max(visual.geometry.radius, 0.005),
          Math.max(visual.geometry.radius, 0.005),
          Math.max(visual.geometry.length, 0.01),
          28,
        ),
        material,
      );
      break;
    case "sphere":
      object = new THREE.Mesh(
        new THREE.SphereGeometry(Math.max(visual.geometry.radius, 0.005), 18, 18),
        material,
      );
      break;
    case "mesh":
      if (descriptor.includes("laser") || descriptor.includes("lidar") || descriptor.includes("scan")) {
        object = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.012, 28), material);
      } else if (descriptor.includes("wheel")) {
        object = new THREE.Mesh(new THREE.CylinderGeometry(0.033, 0.033, 0.018, 24), material);
      } else if (descriptor.includes("caster")) {
        object = new THREE.Mesh(new THREE.SphereGeometry(0.018, 20, 20), material);
      } else if (descriptor.includes("base_link")) {
        object = new THREE.Mesh(new THREE.BoxGeometry(0.165, 0.022, 0.145), material);
      } else if (descriptor.includes("plate") || descriptor.includes("burger")) {
        object = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.012, 0.118), material);
      } else if (descriptor.includes("base")) {
        object = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.016, 0.13), material);
      } else {
        object = new THREE.Mesh(
          new THREE.BoxGeometry(
            Math.max(0.14 * visual.geometry.scale.x, 0.05),
            Math.max(0.05 * visual.geometry.scale.z, 0.03),
            Math.max(0.14 * visual.geometry.scale.y, 0.05),
          ),
          material,
        );
      }
      break;
  }

  object.renderOrder = 40;
  addRobotOutline(object);
  return object;
}

function buildRobotModelGroup(
  robotDescription: string | undefined,
  tf: TfMessage | undefined,
  tfStatic: TfMessage | undefined,
  robotPose: Pose | undefined,
) {
  const visuals = parseUrdfVisuals(robotDescription);
  const group = new THREE.Group();
  const lookup = buildFrameLookup(tf, tfStatic, robotDescription);
  const cache = new Map<string, ResolvedFrame | null>();

  if (visuals.length === 0) {
    const fallback = new THREE.Group();

    const body = new THREE.Mesh(
      new THREE.CylinderGeometry(0.082, 0.082, 0.028, 36),
      new THREE.MeshBasicMaterial({ color: "#101010", depthTest: false, depthWrite: false }),
    );
    body.position.y = 0.055;
    body.renderOrder = 40;

    const bodyOutline = new THREE.Mesh(
      new THREE.RingGeometry(0.078, 0.092, 40),
      new THREE.MeshBasicMaterial({ color: "#f2f5f8", side: THREE.DoubleSide, depthTest: false, depthWrite: false }),
    );
    bodyOutline.rotation.x = -Math.PI / 2;
    bodyOutline.position.y = 0.07;
    bodyOutline.renderOrder = 41;

    const lidar = new THREE.Mesh(
      new THREE.CylinderGeometry(0.028, 0.028, 0.03, 24),
      new THREE.MeshBasicMaterial({ color: "#151515", depthTest: false, depthWrite: false }),
    );
    lidar.position.set(0, 0.085, 0);
    lidar.renderOrder = 42;

    const heading = new THREE.Mesh(
      new THREE.ConeGeometry(0.045, 0.13, 3),
      new THREE.MeshBasicMaterial({ color: "#111111", depthTest: false, depthWrite: false }),
    );
    heading.rotation.z = -Math.PI / 2;
    heading.position.set(0.115, 0.07, 0);
    heading.renderOrder = 42;

    fallback.add(body, bodyOutline, lidar, heading);
    group.add(fallback);
    if (robotPose) {
      group.position.set(robotPose.position.x, 0, -robotPose.position.y);
      group.rotation.y = -robotPose.orientation.yaw;
    }
    return group;
  }

  for (const visual of visuals) {
    const frame = resolveFrame(visual.linkName, lookup, robotPose, cache);
    if (!frame) {
      continue;
    }
    const descriptor =
      visual.geometry.type === "mesh"
        ? `${visual.linkName} ${visual.geometry.filename}`.toLowerCase()
        : visual.linkName.toLowerCase();
    const mesh = buildRobotVisualMesh(visual);
    const rotatedOrigin = rotate2d(visual.xyz.x, visual.xyz.y, frame.yaw);
    mesh.position.set(
      frame.x + rotatedOrigin.x,
      frame.z + visual.xyz.z + 0.01,
      -(frame.y + rotatedOrigin.y),
    );
    if (descriptor.includes("wheel")) {
      mesh.rotation.set(visual.rpy.x, -(frame.yaw + visual.rpy.z), visual.rpy.y, "XYZ");
    } else {
      mesh.rotation.set(frame.roll + visual.rpy.x, -(frame.yaw + visual.rpy.z), frame.pitch + visual.rpy.y, "XYZ");
    }
    group.add(mesh);
  }

  return group;
}

export function SceneViewport({
  target,
  state,
  viewMode,
  layerVisibility,
  onResetView,
  resetViewToken,
  goalMarker,
  interactionMode = "idle",
  onPoseSelection,
  onPosePlacement,
  routeWaypoints,
}: SceneViewportProps) {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const controlsRef = useRef<OrbitControls | null>(null);
  const renderRef = useRef<(() => void) | null>(null);
  const robotRef = useRef<THREE.Group | null>(null);
  const robotMarkerRef = useRef<THREE.Group | null>(null);
  const gridRef = useRef<THREE.GridHelper | null>(null);
  const mapMeshRef = useRef<THREE.Mesh | null>(null);
  const globalCostmapMeshRef = useRef<THREE.Mesh | null>(null);
  const localCostmapMeshRef = useRef<THREE.Mesh | null>(null);
  const mapOutlineRef = useRef<THREE.Line | null>(null);
  const globalCostmapOutlineRef = useRef<THREE.Line | null>(null);
  const localCostmapOutlineRef = useRef<THREE.Line | null>(null);
  const footprintRef = useRef<THREE.Group | null>(null);
  const blockedFootprintRef = useRef<THREE.Group | null>(null);
  const blockedLinkRef = useRef<THREE.Group | null>(null);
  const globalPathRef = useRef<THREE.Group | null>(null);
  const localPathRef = useRef<THREE.Group | null>(null);
  const scanRef = useRef<THREE.Points | null>(null);
  const tfGroupRef = useRef<THREE.Group | null>(null);
  const goalMarkerRef = useRef<THREE.Group | null>(null);
  const routeMarkersGroupRef = useRef<THREE.Group | null>(null);
  const previewMarkerRef = useRef<THREE.Group | null>(null);
  const lastCenteredMapSignatureRef = useRef("");
  const previousRobotInputsRef = useRef<{
    robotDescription?: BridgeState["robot_description"];
    tfStatic?: BridgeState["tf_static"];
  }>({});
  const previousPathInputsRef = useRef<{
    globalPath?: BridgeState["global_path"];
    localPath?: BridgeState["local_path"];
  }>({});
  const previousMapInputsRef = useRef<{
    map?: BridgeState["map"];
    globalCostmap?: BridgeState["global_costmap"];
    localCostmap?: BridgeState["local_costmap"];
  }>({});
  const previousFootprintInputsRef = useRef<{
    footprintPolygon?: number[];
    robotPose?: BridgeState["robot_pose"];
    motionStatus?: BridgeState["motion_status"];
  }>({});
  const previousScanInputsRef = useRef<{
    scan?: BridgeState["scan"];
    tf?: BridgeState["tf"];
    tfStatic?: BridgeState["tf_static"];
    robotPose?: BridgeState["robot_pose"];
  }>({});
  const previousTfInputsRef = useRef<{
    tf?: BridgeState["tf"];
    tfStatic?: BridgeState["tf_static"];
    robotPose?: BridgeState["robot_pose"];
  }>({});
  const previousGoalMarkerRef = useRef<SceneViewportProps["goalMarker"]>(null);
  const previousRouteWaypointsRef = useRef<SceneViewportProps["routeWaypoints"]>(undefined);
  const interactionModeRef = useRef<SceneViewportProps["interactionMode"]>("idle");
  const onPoseSelectionRef = useRef<SceneViewportProps["onPoseSelection"]>(undefined);
  const onPosePlacementRef = useRef<SceneViewportProps["onPosePlacement"]>(undefined);
  const interactionStateRef = useRef<{
    mode: "goal" | "initial_pose";
    start: THREE.Vector3;
  } | null>(null);

  useEffect(() => {
    interactionModeRef.current = interactionMode;
  }, [interactionMode]);

  useEffect(() => {
    onPoseSelectionRef.current = onPoseSelection;
  }, [onPoseSelection]);

  useEffect(() => {
    onPosePlacementRef.current = onPosePlacement;
  }, [onPosePlacement]);

  useEffect(() => {
    if (!viewportRef.current) {
      return undefined;
    }

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#dddddd");

    const renderer = new THREE.WebGLRenderer({
      antialias: false,
      alpha: false,
      powerPreference: "low-power",
    });
    renderer.domElement.className = "rcs-scene__canvas";
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.25));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.setSize(viewportRef.current.clientWidth, viewportRef.current.clientHeight);
    viewportRef.current.appendChild(renderer.domElement);

    const camera = new THREE.PerspectiveCamera(
      14,
      viewportRef.current.clientWidth / Math.max(viewportRef.current.clientHeight, 1),
      0.1,
      200,
    );
    camera.zoom = 0.4;
    camera.up.set(0, 0, -1);
    camera.position.set(0, 28, 0.001);
    camera.lookAt(0, 0, 0);
    camera.updateProjectionMatrix();

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.screenSpacePanning = true;
    controls.enablePan = true;
    controls.enableRotate = true;
    controls.enableZoom = true;
    controls.minDistance = 2;
    controls.maxDistance = 80;
    controls.target.set(0, 0, 0);
    controls.addEventListener("change", () => {
      renderer.render(scene, camera);
    });
    controls.update();

    const ambientLight = new THREE.AmbientLight("#ffffff", 1.18);
    const keyLight = new THREE.DirectionalLight("#d8e6ff", 0.84);
    keyLight.position.set(12, 22, 10);
    scene.add(ambientLight, keyLight);

    const grid = new THREE.GridHelper(60, 60, "#9e9e9e", "#c9c9c9");
    grid.position.y = 0.046;
    grid.renderOrder = 14;
    const gridMaterial = Array.isArray(grid.material) ? grid.material : [grid.material];
    for (const material of gridMaterial) {
      material.depthTest = false;
      material.transparent = true;
      material.opacity = 0.58;
    }
    scene.add(grid);

    const floor = new THREE.Mesh(
      new THREE.PlaneGeometry(64, 64),
      new THREE.MeshStandardMaterial({
        color: "#d8d8d8",
        metalness: 0.02,
        roughness: 1,
      }),
    );
    floor.rotation.x = -Math.PI / 2;
    floor.position.y = -0.015;
    floor.renderOrder = -10;
    scene.add(floor);

    const robot = new THREE.Group();
    scene.add(robot);

    const renderScene = () => {
      controls.update();
      renderer.render(scene, camera);
    };
    renderRef.current = renderScene;
    renderScene();

    const resize = () => {
      if (!viewportRef.current) {
        return;
      }
      camera.aspect = viewportRef.current.clientWidth / Math.max(viewportRef.current.clientHeight, 1);
      camera.updateProjectionMatrix();
      renderer.setSize(viewportRef.current.clientWidth, viewportRef.current.clientHeight);
      renderScene();
    };

    const observer = new ResizeObserver(resize);
    observer.observe(viewportRef.current);
    window.addEventListener("resize", resize);

    const groundPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    const intersection = new THREE.Vector3();

    const readGroundPoint = (event: PointerEvent) => {
      const bounds = renderer.domElement.getBoundingClientRect();
      pointer.x = ((event.clientX - bounds.left) / bounds.width) * 2 - 1;
      pointer.y = -(((event.clientY - bounds.top) / bounds.height) * 2 - 1);
      raycaster.setFromCamera(pointer, camera);
      return raycaster.ray.intersectPlane(groundPlane, intersection) ? intersection.clone() : null;
    };

    const clearPreview = () => {
      if (!previewMarkerRef.current) {
        return;
      }
      scene.remove(previewMarkerRef.current);
      disposeObject(previewMarkerRef.current);
      previewMarkerRef.current = null;
    };

    const updatePreview = (mode: "goal" | "initial_pose", start: THREE.Vector3, current: THREE.Vector3) => {
      clearPreview();
      const dx = current.x - start.x;
      const dy = -(current.z - start.z);
      const yaw = Math.atan2(dy, dx || 0.0001);
      previewMarkerRef.current = buildGoalMarker({
        x: start.x,
        y: -start.z,
        yaw,
        kind: mode,
      });
      scene.add(previewMarkerRef.current);
      renderScene();
    };

    const handlePointerDown = (event: PointerEvent) => {
      const currentMode = interactionModeRef.current;
      if ((currentMode !== "goal" && currentMode !== "initial_pose") || event.button !== 0) {
        return;
      }

      const point = readGroundPoint(event);
      if (!point) {
        return;
      }

      controls.enabled = false;
      interactionStateRef.current = {
        mode: currentMode,
        start: point,
      };
      updatePreview(currentMode, point, point);
      event.preventDefault();
    };

    const handlePointerMove = (event: PointerEvent) => {
      if (!interactionStateRef.current) {
        return;
      }

      const point = readGroundPoint(event);
      if (!point) {
        return;
      }

      updatePreview(interactionStateRef.current.mode, interactionStateRef.current.start, point);
      event.preventDefault();
    };

    const handlePointerUp = (event: PointerEvent) => {
      if (!interactionStateRef.current) {
        return;
      }

      const point = readGroundPoint(event) ?? interactionStateRef.current.start;
      const { mode, start } = interactionStateRef.current;
      interactionStateRef.current = null;
      controls.enabled = true;
      clearPreview();

      const dx = point.x - start.x;
      const dy = -(point.z - start.z);
      const yaw = Math.atan2(dy, dx || 0.0001);
      onPoseSelectionRef.current?.(start.x, -start.z, yaw);
      onPosePlacementRef.current?.(mode, start.x, -start.z, yaw);
      event.preventDefault();
    };

    const handleContextMenu = (event: Event) => event.preventDefault();

    renderer.domElement.addEventListener("pointerdown", handlePointerDown);
    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
    renderer.domElement.addEventListener("contextmenu", handleContextMenu);

    sceneRef.current = scene;
    rendererRef.current = renderer;
    cameraRef.current = camera;
    controlsRef.current = controls;
    robotRef.current = robot;
    gridRef.current = grid;

    return () => {
      clearPreview();
      controls.enabled = true;
      observer.disconnect();
      renderer.domElement.removeEventListener("pointerdown", handlePointerDown);
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
      renderer.domElement.removeEventListener("contextmenu", handleContextMenu);
      window.removeEventListener("resize", resize);
      renderRef.current = null;
      controls.dispose();
      disposeObject(globalPathRef.current);
      disposeObject(localPathRef.current);
      disposeObject(mapMeshRef.current);
      disposeObject(globalCostmapMeshRef.current);
      disposeObject(localCostmapMeshRef.current);
      disposeObject(mapOutlineRef.current);
      disposeObject(globalCostmapOutlineRef.current);
      disposeObject(localCostmapOutlineRef.current);
      disposeObject(footprintRef.current);
      disposeObject(blockedFootprintRef.current);
      disposeObject(blockedLinkRef.current);
      disposeObject(scanRef.current);
      disposeObject(tfGroupRef.current);
      disposeObject(goalMarkerRef.current);
      disposeObject(routeMarkersGroupRef.current);
      disposeObject(previewMarkerRef.current);
      disposeObject(robotMarkerRef.current);
      disposeObject(robot);
      renderer.dispose();
      scene.clear();
      viewportRef.current?.removeChild(renderer.domElement);
    };
  }, []);

  useEffect(() => {
    const scene = sceneRef.current;
    const robot = robotRef.current;
    const camera = cameraRef.current;
    const controls = controlsRef.current;
    if (!scene || !robot || !camera) {
      return;
    }

    const robotPose = resolveRobotScenePose(
      state.tf,
      state.tf_static,
      state.robot_pose,
      state.robot_description?.data,
    );
    if (gridRef.current) {
      gridRef.current.visible = layerVisibility.grid;
    }

    robot.visible = layerVisibility.robot;
    const shouldRebuildRobot =
      previousRobotInputsRef.current.robotDescription !== state.robot_description
      || previousRobotInputsRef.current.tfStatic !== state.tf_static;
    if (shouldRebuildRobot) {
      while (robot.children.length > 0) {
        const child = robot.children[0];
        robot.remove(child);
        disposeObject(child);
      }
      robot.add(buildRobotModelGroup(
        state.robot_description?.data,
        undefined,
        state.tf_static,
        ROBOT_LOCAL_ORIGIN_POSE,
      ));
      previousRobotInputsRef.current = {
        robotDescription: state.robot_description,
        tfStatic: state.tf_static,
      };
    }
    robot.position.set(robotPose?.position.x ?? 0, 0, -(robotPose?.position.y ?? 0));
    robot.rotation.set(0, -(robotPose?.orientation.yaw ?? 0), 0);

    if (robotMarkerRef.current) {
      scene.remove(robotMarkerRef.current);
      disposeObject(robotMarkerRef.current);
      robotMarkerRef.current = null;
    }

    const shouldRebuildPaths =
      previousPathInputsRef.current.globalPath !== state.global_path
      || previousPathInputsRef.current.localPath !== state.local_path;
    if (shouldRebuildPaths) {
      disposeObject(globalPathRef.current);
      disposeObject(localPathRef.current);
      if (globalPathRef.current) {
        scene.remove(globalPathRef.current);
        globalPathRef.current = null;
      }
      if (localPathRef.current) {
        scene.remove(localPathRef.current);
        localPathRef.current = null;
      }

      const globalPath = state.global_path?.poses.map((pose) => ({ x: pose.position.x, y: pose.position.y })) ?? [];
      const localPath = state.local_path?.poses.map((pose) => ({ x: pose.position.x, y: pose.position.y })) ?? [];
      globalPathRef.current = buildPathLine(globalPath, "#23d9ff", 0.06);
      localPathRef.current = buildPathLine(localPath, "#95dd00", 0.08);
      if (globalPathRef.current) {
        scene.add(globalPathRef.current);
      }
      if (localPathRef.current) {
        scene.add(localPathRef.current);
      }
      previousPathInputsRef.current = {
        globalPath: state.global_path,
        localPath: state.local_path,
      };
    }
    if (globalPathRef.current) {
      globalPathRef.current.visible = layerVisibility.globalPlan;
    }
    if (localPathRef.current) {
      localPathRef.current.visible = layerVisibility.localPlan;
    }

    if (previousGoalMarkerRef.current !== goalMarker) {
      if (goalMarkerRef.current) {
        scene.remove(goalMarkerRef.current);
        disposeObject(goalMarkerRef.current);
        goalMarkerRef.current = null;
      }
      if (goalMarker) {
        goalMarkerRef.current = buildGoalMarker(goalMarker);
        scene.add(goalMarkerRef.current);
      }
      previousGoalMarkerRef.current = goalMarker;
    }

    if (previousRouteWaypointsRef.current !== routeWaypoints) {
      if (routeMarkersGroupRef.current) {
        scene.remove(routeMarkersGroupRef.current);
        disposeObject(routeMarkersGroupRef.current);
        routeMarkersGroupRef.current = null;
      }
      if (routeWaypoints && routeWaypoints.length > 0) {
        const group = new THREE.Group();

        // polyline connecting waypoints
        if (routeWaypoints.length >= 2) {
          const linePoints = routeWaypoints.map((wp) => new THREE.Vector3(wp.x, 0.07, -wp.y));
          const lineGeom = new THREE.BufferGeometry().setFromPoints(linePoints);
          const line = new THREE.Line(
            lineGeom,
            new THREE.LineBasicMaterial({
              color: "#f57c00",
              transparent: true,
              opacity: 0.72,
              depthTest: false,
              depthWrite: false,
            }),
          );
          line.renderOrder = 22;
          group.add(line);
        }

        for (const wp of routeWaypoints) {
          group.add(buildArrowPoseMarker(wp, { primary: "#f57c00", accent: "#fff3e0" }));
        }
        routeMarkersGroupRef.current = group;
        scene.add(group);
      }
      previousRouteWaypointsRef.current = routeWaypoints;
    }

    for (const [ref, outlineRef, grid, palette, yOffset] of [
      [mapMeshRef, mapOutlineRef, state.map, "map", 0.005],
      [globalCostmapMeshRef, globalCostmapOutlineRef, state.global_costmap, "global_costmap", 0.02],
      [localCostmapMeshRef, localCostmapOutlineRef, state.local_costmap, "local_costmap", 0.03],
    ] as const) {
      const previousGrid =
        palette === "map" ? previousMapInputsRef.current.map :
        palette === "global_costmap" ? previousMapInputsRef.current.globalCostmap :
        previousMapInputsRef.current.localCostmap;
      if (previousGrid !== grid) {
        if (ref.current) {
          scene.remove(ref.current);
          disposeObject(ref.current);
          ref.current = null;
        }
        if (outlineRef.current) {
          scene.remove(outlineRef.current);
          disposeObject(outlineRef.current);
          outlineRef.current = null;
        }
        if (grid) {
          ref.current = buildOccupancyMesh(grid, palette, yOffset);
          scene.add(ref.current);
        }
      }
      if (ref.current) {
        ref.current.visible =
          palette === "map" ? layerVisibility.map :
          palette === "global_costmap" ? layerVisibility.globalCostmap :
          layerVisibility.localCostmap;
      }
    }
    previousMapInputsRef.current = {
      map: state.map,
      globalCostmap: state.global_costmap,
      localCostmap: state.local_costmap,
    };

    const footprintPolygon = state.robot_description?.footprint_polygon;
    const shouldRebuildFootprints =
      previousFootprintInputsRef.current.footprintPolygon !== footprintPolygon
      || previousFootprintInputsRef.current.robotPose !== robotPose
      || previousFootprintInputsRef.current.motionStatus !== state.motion_status;
    if (shouldRebuildFootprints) {
      if (footprintRef.current) {
        scene.remove(footprintRef.current);
        disposeObject(footprintRef.current);
        footprintRef.current = null;
      }
      footprintRef.current = buildFootprintOverlay(
        footprintPolygon,
        robotPose,
        state.motion_status?.costmap_blocked || state.motion_status?.safety_gate_blocked
          ? {
            fillColor: state.motion_status?.safety_gate_blocked ? "#ff4b4b" : "#3f7dff",
            outlineColor: state.motion_status?.safety_gate_blocked ? "#9b1818" : "#1a3d96",
            fillOpacity: 0.16,
            yOffset: 0.044,
            renderOrder: 19,
          }
          : undefined,
      );
      if (footprintRef.current) {
        scene.add(footprintRef.current);
      }

      if (blockedFootprintRef.current) {
        scene.remove(blockedFootprintRef.current);
        disposeObject(blockedFootprintRef.current);
        blockedFootprintRef.current = null;
      }
      if (state.motion_status?.has_blocked_pose) {
        blockedFootprintRef.current = buildFootprintOverlay(
          footprintPolygon,
          state.motion_status.blocked_pose,
          {
            fillColor: "#4cff63",
            outlineColor: "#0e8d22",
            fillOpacity: 0.1,
            yOffset: 0.052,
            renderOrder: 22,
          },
        );
      }
      if (blockedFootprintRef.current) {
        scene.add(blockedFootprintRef.current);
      }

      if (blockedLinkRef.current) {
        scene.remove(blockedLinkRef.current);
        disposeObject(blockedLinkRef.current);
        blockedLinkRef.current = null;
      }
      if (state.motion_status?.has_blocked_pose) {
        blockedLinkRef.current = buildBlockedLinkOverlay(robotPose, state.motion_status.blocked_pose);
      }
      if (blockedLinkRef.current) {
        scene.add(blockedLinkRef.current);
      }
      previousFootprintInputsRef.current = {
        footprintPolygon,
        robotPose,
        motionStatus: state.motion_status,
      };
    }
    if (footprintRef.current) {
      footprintRef.current.visible = layerVisibility.footprint;
    }

    const shouldRebuildScan =
      previousScanInputsRef.current.scan !== state.scan
      || previousScanInputsRef.current.tf !== state.tf
      || previousScanInputsRef.current.tfStatic !== state.tf_static
      || previousScanInputsRef.current.robotPose !== robotPose;
    if (shouldRebuildScan) {
      if (scanRef.current) {
        scene.remove(scanRef.current);
        disposeObject(scanRef.current);
        scanRef.current = null;
      }
      scanRef.current = buildScanPoints(state.scan, state.tf, state.tf_static, robotPose);
      if (scanRef.current) {
        scene.add(scanRef.current);
      }
      previousScanInputsRef.current = {
        scan: state.scan,
        tf: state.tf,
        tfStatic: state.tf_static,
        robotPose,
      };
    }
    if (scanRef.current) {
      scanRef.current.visible = layerVisibility.scan;
    }

    const shouldRebuildTfGroup =
      previousTfInputsRef.current.tf !== state.tf
      || previousTfInputsRef.current.tfStatic !== state.tf_static
      || previousTfInputsRef.current.robotPose !== robotPose;
    if (shouldRebuildTfGroup) {
      const nextTfGroup = buildTfGroup(state.tf, state.tf_static, robotPose, tfGroupRef.current);
      if (!nextTfGroup) {
        if (tfGroupRef.current) {
          scene.remove(tfGroupRef.current);
          disposeObject(tfGroupRef.current);
          tfGroupRef.current = null;
        }
      } else {
        tfGroupRef.current = nextTfGroup;
        if (!scene.children.includes(tfGroupRef.current)) {
          scene.add(tfGroupRef.current);
        }
      }
      previousTfInputsRef.current = {
        tf: state.tf,
        tfStatic: state.tf_static,
        robotPose,
      };
      if (!nextTfGroup) {
        renderRef.current?.();
        return;
      }
    }
    if (tfGroupRef.current) {
      tfGroupRef.current.visible = layerVisibility.tf;
    }

    const activeMap = state.map ?? state.local_costmap ?? state.global_costmap;
    if (activeMap) {
      const mapSignature = [
        activeMap.info.width,
        activeMap.info.height,
        activeMap.info.resolution,
        activeMap.info.origin.position.x,
        activeMap.info.origin.position.y,
        activeMap.info.origin.orientation.yaw,
      ].join(":");

      if (lastCenteredMapSignatureRef.current !== mapSignature) {
        const widthMeters = activeMap.info.width * activeMap.info.resolution;
        const heightMeters = activeMap.info.height * activeMap.info.resolution;
        const center = rotate2d(
          widthMeters / 2,
          heightMeters / 2,
          activeMap.info.origin.orientation.yaw,
        );
        const centerX = activeMap.info.origin.position.x + center.x;
        const centerY = activeMap.info.origin.position.y + center.y;

        camera.position.x = centerX;
        camera.position.z = -(centerY + 0.001);
        if (controls) {
          controls.target.set(centerX, 0, -centerY);
          controls.update();
        } else {
          camera.lookAt(centerX, 0, -centerY);
        }
        lastCenteredMapSignatureRef.current = mapSignature;
      }
    }

    renderRef.current?.();
  }, [goalMarker, layerVisibility, routeWaypoints, state, viewMode]);

  useEffect(() => {
    const camera = cameraRef.current;
    const controls = controlsRef.current;
    const activeMap = state.map ?? state.local_costmap ?? state.global_costmap;
    if (!camera || !activeMap) {
      return;
    }

    const widthMeters = activeMap.info.width * activeMap.info.resolution;
    const heightMeters = activeMap.info.height * activeMap.info.resolution;
    const center = rotate2d(
      widthMeters / 2,
      heightMeters / 2,
      activeMap.info.origin.orientation.yaw,
    );
    const centerX = activeMap.info.origin.position.x + center.x;
    const centerY = activeMap.info.origin.position.y + center.y;

    camera.position.x = centerX;
    camera.position.y = 28;
    camera.position.z = -(centerY + 0.001);
    camera.zoom = 0.4;
    camera.updateProjectionMatrix();
    if (controls) {
      controls.target.set(centerX, 0, -centerY);
      controls.update();
    } else {
      camera.lookAt(centerX, 0, -centerY);
    }
    lastCenteredMapSignatureRef.current = [
      activeMap.info.width,
      activeMap.info.height,
      activeMap.info.resolution,
      activeMap.info.origin.position.x,
      activeMap.info.origin.position.y,
      activeMap.info.origin.orientation.yaw,
    ].join(":");
    renderRef.current?.();
  }, [resetViewToken]);

  return (
    <section className="rcs-scene-panel">
      <div className="rcs-scene-panel__toolbar">
        <div className="rcs-scene-panel__toolbar-main">
          <strong>Scene</strong>
          <span>Background: 228; 228; 228</span>
          <span>Map {state.map ? `${state.map.info.width}x${state.map.info.height}` : "--"}</span>
          <span>Raw --</span>
          <span>Refined --</span>
          <span>Global {state.global_path?.poses.length ?? 0} pts</span>
          <span>Local {state.local_path?.poses.length ?? 0} pts</span>
          <span>Scan {state.scan?.ranges.length ?? state.scan?.points?.length ?? 0} rays</span>
          <span>TF {(state.tf?.transforms.length ?? 0) + (state.tf_static?.transforms.length ?? 0)} frames</span>
        </div>
        <div className="rcs-toolbar-values">
          <button
            type="button"
            className="rcs-scene-refresh-button"
            aria-label="Reset scene view"
            title="Reset scene view"
            onClick={onResetView}
          >
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M20 11a8 8 0 0 0-14.2-4.9" />
              <path d="M4 4v4.8h4.8" />
              <path d="M4 13a8 8 0 0 0 14.2 4.9" />
              <path d="M20 20v-4.8h-4.8" />
            </svg>
          </button>
        </div>
      </div>

      <div className="rcs-scene">
        <div className="rcs-scene__viewport" ref={viewportRef} />
      </div>
    </section>
  );
}
