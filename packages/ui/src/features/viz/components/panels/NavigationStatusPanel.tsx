type NavigationStatusPanelProps = {
  targetRobotId: string;
  motion: string;
  remainingLabel: string;
  headingLabel: string;
  goalLabel: string;
  blockedSourceLabel: string;
};

export function NavigationStatusPanel({
  targetRobotId,
  motion,
  remainingLabel,
  headingLabel,
  goalLabel,
  blockedSourceLabel,
}: NavigationStatusPanelProps) {
  return (
    <section className="rcs-card">
      <div className="rcs-card__header">
        <h2>Navigation Status</h2>
      </div>

      <div className="rcs-status-list">
        <div className="rcs-status-row"><span>Target</span><strong>{targetRobotId}</strong></div>
        <div className="rcs-status-row"><span>Motion</span><strong>{motion}</strong></div>
        <div className="rcs-status-row"><span>Remaining</span><strong>{remainingLabel}</strong></div>
        <div className="rcs-status-row"><span>Heading</span><strong>{headingLabel}</strong></div>
        <div className="rcs-status-row"><span>Goal</span><strong>{goalLabel}</strong></div>
        <div className="rcs-status-row"><span>Blocked Source</span><strong>{blockedSourceLabel}</strong></div>
      </div>
    </section>
  );
}
