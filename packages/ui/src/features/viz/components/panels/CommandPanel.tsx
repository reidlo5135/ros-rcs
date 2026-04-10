import { SettingsIconButton } from "../SettingsIconButton";

type CommandPanelProps = {
  goalX: string;
  goalY: string;
  goalYaw: string;
  onGoalXChange: (value: string) => void;
  onGoalYChange: (value: string) => void;
  onGoalYawChange: (value: string) => void;
  onSend: () => void;
  onCancel: () => void;
  onSetInitialPose: () => void;
  onOpenSettings: () => void;
};

export function CommandPanel({
  goalX,
  goalY,
  goalYaw,
  onGoalXChange,
  onGoalYChange,
  onGoalYawChange,
  onSend,
  onCancel,
  onSetInitialPose,
  onOpenSettings,
}: CommandPanelProps) {
  return (
    <section className="rcs-card">
      <div className="rcs-card__header">
        <h2>Command</h2>
        <SettingsIconButton label="Open Command topic settings" onClick={onOpenSettings} />
      </div>

      <div className="rcs-form-grid">
        <label className="rcs-field">
          <span>X</span>
          <input value={goalX} onChange={(event) => onGoalXChange(event.target.value)} />
        </label>
        <label className="rcs-field">
          <span>Y</span>
          <input value={goalY} onChange={(event) => onGoalYChange(event.target.value)} />
        </label>
        <label className="rcs-field">
          <span>Yaw</span>
          <input value={goalYaw} onChange={(event) => onGoalYawChange(event.target.value)} />
        </label>
      </div>

      <div className="rcs-button-row rcs-button-row--split">
        <button className="rcs-button rcs-button--neutral" type="button" onClick={onSend}>Send</button>
        <button className="rcs-button rcs-button--danger" type="button" onClick={onCancel}>Cancel</button>
      </div>

      <button className="rcs-button rcs-button--wide rcs-button--teal-soft" type="button" onClick={onSetInitialPose}>
        Set Initial Pose
      </button>
    </section>
  );
}
