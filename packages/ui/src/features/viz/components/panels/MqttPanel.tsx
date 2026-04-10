type MqttPanelProps = {
  mqttUrl: string;
  robotId: string;
  onMqttUrlChange: (value: string) => void;
  onRobotIdChange: (value: string) => void;
  onConnect: () => void;
  onDisconnect: () => void;
};

export function MqttPanel({
  mqttUrl,
  robotId,
  onMqttUrlChange,
  onRobotIdChange,
  onConnect,
  onDisconnect,
}: MqttPanelProps) {
  return (
    <section className="rcs-card">
      <div className="rcs-card__header">
        <h2>Global Options</h2>
      </div>

      <label className="rcs-field">
        <span>Broker WS</span>
        <input value={mqttUrl} onChange={(event) => onMqttUrlChange(event.target.value)} />
      </label>

      <label className="rcs-field">
        <span>Robot ID</span>
        <input value={robotId} onChange={(event) => onRobotIdChange(event.target.value)} />
      </label>

      <div className="rcs-button-row rcs-button-row--split">
        <button className="rcs-button rcs-button--neutral" type="button" onClick={onConnect}>Connect</button>
        <button className="rcs-button rcs-button--teal" type="button" onClick={onDisconnect}>Disconnect</button>
      </div>
    </section>
  );
}

