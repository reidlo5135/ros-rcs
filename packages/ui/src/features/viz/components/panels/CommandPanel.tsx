import { SettingsIconButton } from "../SettingsIconButton";

type GoalWaypoint = {
  x: number;
  y: number;
  yaw: number;
};

type CommandPanelProps = {
  poseInteractionMode: "idle" | "goal" | "initial_pose";
  onOpenSettings: () => void;
  onSetInitialPose: () => void;
  routeWaypoints: ReadonlyArray<GoalWaypoint>;
  /** 0-based index of the goal currently being executed. -1 = not started. */
  activeGoalIndex: number;
  onAddWaypoint: () => void;
  onRemoveWaypoint: (index: number) => void;
  onClearWaypoints: () => void;
  onSendRoute: () => void;
  onCancelRoute: () => void;
};

export function CommandPanel({
  poseInteractionMode,
  onOpenSettings,
  onSetInitialPose,
  routeWaypoints,
  activeGoalIndex,
  onAddWaypoint,
  onRemoveWaypoint,
  onClearWaypoints,
  onSendRoute,
  onCancelRoute,
}: CommandPanelProps) {
  const isAddingWaypoint = poseInteractionMode === "goal";

  return (
    <section className="rcs-card">
      <div className="rcs-card__header">
        <h2>Command</h2>
        <SettingsIconButton label="Open Command topic settings" onClick={onOpenSettings} />
      </div>

      {routeWaypoints.length > 0 && (
        <ol className="rcs-waypoint-list">
          {routeWaypoints.map((wp, index) => (
            <li
              key={index}
              className={`rcs-waypoint-item${
                index < activeGoalIndex
                  ? " rcs-waypoint-item--completed"
                  : index === activeGoalIndex
                  ? " rcs-waypoint-item--active"
                  : ""
              }`}
            >
              <span className="rcs-waypoint-index">
                {index < activeGoalIndex ? "Done" : index === activeGoalIndex ? "Now" : index + 1}
              </span>
              <span className="rcs-waypoint-coords">
                <span className="rcs-waypoint-label">x</span>{wp.x.toFixed(2)}
                <span className="rcs-waypoint-label">y</span>{wp.y.toFixed(2)}
                <span className="rcs-waypoint-label">yaw</span>{wp.yaw.toFixed(2)}
              </span>
              <button
                className="rcs-waypoint-remove"
                type="button"
                onClick={() => onRemoveWaypoint(index)}
                aria-label={`Remove waypoint ${index + 1}`}
              >
                X
              </button>
            </li>
          ))}
        </ol>
      )}

      <button
        className={`rcs-button rcs-button--wide rcs-button--add${isAddingWaypoint ? " rcs-button--armed-goal" : ""}`}
        type="button"
        onClick={onAddWaypoint}
      >
        {isAddingWaypoint ? (
          <>
            <span className="rcs-pulse-dot" aria-hidden="true" /> Placing...
          </>
        ) : (
          "+ Add Waypoint"
        )}
      </button>

      <div className="rcs-button-row rcs-button-row--split">
        <button
          className="rcs-button rcs-button--success"
          type="button"
          disabled={routeWaypoints.length === 0}
          onClick={onSendRoute}
        >
          Send
        </button>
        <button className="rcs-button rcs-button--danger" type="button" onClick={onCancelRoute}>
          Cancel
        </button>
      </div>

      <div className="rcs-button-row rcs-button-row--split">
        <button
          className="rcs-button rcs-button--neutral"
          type="button"
          disabled={routeWaypoints.length === 0}
          onClick={onClearWaypoints}
        >
          Clear
        </button>
        <button
          className={`rcs-button rcs-button--teal-soft ${poseInteractionMode === "initial_pose" ? "rcs-button--armed-initial" : ""}`}
          type="button"
          onClick={onSetInitialPose}
        >
          Init Pose
        </button>
      </div>
    </section>
  );
}
