import { layerEntries } from "../../constants";
import type { SceneLayerVisibility } from "../../types";
import { LayerIcon } from "../LayerIcon";
import { SettingsIconButton } from "../SettingsIconButton";

type VisualizationPanelProps = {
  layerVisibility: SceneLayerVisibility;
  onLayerVisibilityChange: (key: keyof SceneLayerVisibility, checked: boolean) => void;
  onOpenSettings: () => void;
};

export function VisualizationPanel({ layerVisibility, onLayerVisibilityChange, onOpenSettings }: VisualizationPanelProps) {
  return (
    <section className="rcs-card rcs-card--layers">
      <div className="rcs-card__header">
        <h2>Visualization</h2>
        <SettingsIconButton label="Open Visualization topic settings" onClick={onOpenSettings} />
      </div>

      <div className="rcs-layer-list" role="group" aria-label="Display layers">
        {layerEntries.map((layer) => (
          <label className="rcs-layer-item" key={layer.key}>
            <input
              checked={layerVisibility[layer.key]}
              type="checkbox"
              onChange={(event) => onLayerVisibilityChange(layer.key, event.target.checked)}
            />
            <LayerIcon kind={layer.icon} />
            <span>{layer.label}</span>
          </label>
        ))}
      </div>
    </section>
  );
}
