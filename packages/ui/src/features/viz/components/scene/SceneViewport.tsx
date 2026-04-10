import type { ComponentProps } from "react";

import { SceneViewport as BaseSceneViewport } from "@rcs/scene3d";

type SceneViewportProps = ComponentProps<typeof BaseSceneViewport>;

export function SceneViewport(props: SceneViewportProps) {
  return <BaseSceneViewport {...props} />;
}

