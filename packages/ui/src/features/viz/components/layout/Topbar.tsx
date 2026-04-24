type TopbarProps = {
  productName: string;
  connectionLabel: string;
  poseLabel: string;
  viewMode: "nav" | "mcp";
  onViewModeChange: (mode: "nav" | "mcp") => void;
  signalBars: number;
  signalLabel: string;
  batteryPercentage: number | null;
  batteryLabel: string;
};

export function Topbar({
  productName,
  connectionLabel,
  poseLabel,
  viewMode,
  onViewModeChange,
  signalBars,
  signalLabel,
  batteryPercentage,
  batteryLabel,
}: TopbarProps) {
  return (
    <header className="rcs-topbar">
      <div className="rcs-topbar__title-wrap rcs-topbar__title-wrap--tight">
        <strong className="rcs-brand">{productName}</strong>
      </div>

      <div className="rcs-topbar__meta rcs-topbar__meta--right">
        <span className="rcs-topbar-chip">Fixed Frame: map</span>
        <span className="rcs-topbar-chip">{connectionLabel}</span>
        <span className="rcs-topbar-chip">{poseLabel}</span>
        <div className="rcs-tabset" role="tablist" aria-label="Mode tabs">
          <button
            className={`rcs-tab${viewMode === "nav" ? " rcs-tab--active" : ""}`}
            type="button"
            onClick={() => onViewModeChange("nav")}
          >
            Navigation
          </button>
          <button
            className={`rcs-tab${viewMode === "mcp" ? " rcs-tab--active-mcp" : ""}`}
            type="button"
            onClick={() => onViewModeChange("mcp")}
          >
            MCP
          </button>
        </div>
        <div className="rcs-signal" aria-label="MQTT signal status">
          <div className="rcs-signal__bars" aria-hidden="true">
            {[0, 1, 2, 3].map((index) => (
              <span key={index} className={signalBars > index ? "is-active" : ""} />
            ))}
          </div>
          <span className="rcs-signal__label">{signalLabel}</span>
        </div>
        <div className="rcs-battery" aria-label="Battery status">
          <span className="rcs-battery__shell">
            <span
              className={`rcs-battery__fill${batteryPercentage == null ? "" : batteryPercentage > 80 ? " is-high" : batteryPercentage >= 40 ? " is-medium" : " is-low"}`}
              style={{ width: `${batteryPercentage ?? 0}%` }}
            />
            <span className="rcs-battery__tip" />
          </span>
          <span className="rcs-battery__label">{batteryLabel}</span>
        </div>
      </div>
    </header>
  );
}

