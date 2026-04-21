type MqttPanelProps = {
  mqttUrl: string;
  activeRobotId: string;
  robotSummaries: ReadonlyArray<{
    robotId: string;
    markerColor: string;
    motion: string;
    batteryLabel: string;
    signalLabel: string;
  }>;
  onMqttUrlChange: (value: string) => void;
  onActiveRobotChange: (value: string) => void;
  onOpenRobotManager: () => void;
  onConnect: () => void;
  onDisconnect: () => void;
};

export function MqttPanel({
  mqttUrl,
  activeRobotId,
  robotSummaries,
  onMqttUrlChange,
  onActiveRobotChange,
  onOpenRobotManager,
  onConnect,
  onDisconnect,
}: MqttPanelProps) {
  return (
    <section className="rcs-card">
      <div className="rcs-card__header">
        <h2>Global Options</h2>
        <button
          type="button"
          className="rcs-icon-button rcs-add-icon-button"
          aria-label="Open robot manager"
          title="Open robot manager"
          onClick={onOpenRobotManager}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M12 5v14" />
            <path d="M5 12h14" />
          </svg>
        </button>
      </div>

      <label className="rcs-field">
        <span>Broker WS</span>
        <input value={mqttUrl} onChange={(event) => onMqttUrlChange(event.target.value)} />
      </label>

      <div className="rcs-robot-list" aria-label="Robot control target">
        {robotSummaries.map((robot) => (
          <button
            key={robot.robotId}
            type="button"
            className={`rcs-robot-list__item${robot.robotId === activeRobotId ? " is-active" : ""}`}
            onClick={() => onActiveRobotChange(robot.robotId)}
          >
            <span className="rcs-robot-list__dot" style={{ background: robot.markerColor }} aria-hidden="true" />
            <strong className="rcs-robot-list__name">{robot.robotId}</strong>
            <span className="rcs-robot-list__meta">
              <span>{robot.motion}</span>
              <span>{robot.batteryLabel}</span>
              <span>{robot.signalLabel}</span>
            </span>
            <span className="rcs-robot-list__arrow" style={{ color: robot.markerColor }} aria-hidden="true">
              <svg viewBox="0 0 28 18">
                <circle cx="14" cy="3.5" r="2.2" />
                <path d="M14 5.8v7" />
                <path d="M9.5 13.5h9" />
                <path d="M14 16.5l-4.2-3.8h8.4z" />
              </svg>
            </span>
          </button>
        ))}
      </div>

      <div className="rcs-button-row rcs-button-row--split">
        <button className="rcs-button rcs-button--neutral" type="button" onClick={onConnect}>Connect</button>
        <button className="rcs-button rcs-button--teal" type="button" onClick={onDisconnect}>Disconnect</button>
      </div>
    </section>
  );
}
