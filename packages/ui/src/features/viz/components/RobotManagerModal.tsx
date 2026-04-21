import { useEffect, useRef, useState, type KeyboardEvent } from "react";

import { CloseIconButton } from "../../../components/CloseIconButton";

type RobotSummary = {
  robotId: string;
  markerColor: string;
  motion: string;
  batteryLabel: string;
  signalLabel: string;
};

type RobotManagerModalProps = {
  open: boolean;
  robotIds: readonly string[];
  activeRobotId: string;
  robotSummaries: ReadonlyArray<RobotSummary>;
  connected: boolean;
  onClose: () => void;
  onSave: (robotIds: string[], activeRobotId: string) => void;
};

function normalizeRobotId(value: string) {
  return value.trim();
}

function isValidRobotId(value: string) {
  return /^[A-Za-z0-9_-]+$/.test(value);
}

export function RobotManagerModal({
  open,
  robotIds,
  activeRobotId,
  robotSummaries,
  connected,
  onClose,
  onSave,
}: RobotManagerModalProps) {
  const [draftRobotIds, setDraftRobotIds] = useState<string[]>([]);
  const [draftActiveRobotId, setDraftActiveRobotId] = useState(activeRobotId);
  const [newRobotId, setNewRobotId] = useState("");
  const [error, setError] = useState("");
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    const nextIds = robotIds.length > 0 ? [...robotIds] : ["robot1"];
    setDraftRobotIds(nextIds);
    setDraftActiveRobotId(nextIds.includes(activeRobotId) ? activeRobotId : nextIds[0]);
    setNewRobotId("");
    setError("");
  }, [activeRobotId, open, robotIds]);

  useEffect(() => {
    if (!open) {
      return undefined;
    }

    const handleKeyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Escape") {
        return;
      }

      event.preventDefault();
      closeButtonRef.current?.click();
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [open]);

  if (!open) {
    return null;
  }

  const addRobot = () => {
    const nextId = normalizeRobotId(newRobotId);
    if (!nextId) {
      setError("Enter a robot id first.");
      return;
    }
    if (!isValidRobotId(nextId)) {
      setError("Use letters, numbers, underscores, or hyphens only.");
      return;
    }
    if (draftRobotIds.includes(nextId)) {
      setError(`${nextId} is already in the fleet.`);
      return;
    }

    setDraftRobotIds((current) => [...current, nextId]);
    setDraftActiveRobotId((current) => current || nextId);
    setNewRobotId("");
    setError("");
  };

  const handleInputKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key !== "Enter") {
      return;
    }

    event.preventDefault();
    addRobot();
  };

  const removeRobot = (robotId: string) => {
    if (draftRobotIds.length <= 1) {
      setError("Keep at least one robot in the fleet.");
      return;
    }

    setDraftRobotIds((current) => {
      const nextIds = current.filter((id) => id !== robotId);
      if (!nextIds.includes(draftActiveRobotId)) {
        setDraftActiveRobotId(nextIds[0]);
      }
      return nextIds;
    });
    setError("");
  };

  const summaryById = new Map(robotSummaries.map((summary) => [summary.robotId, summary]));

  return (
    <div className="rcs-modal-backdrop" role="presentation" onClick={onClose}>
      <div
        className="rcs-modal rcs-modal--robot-manager"
        role="dialog"
        aria-modal="true"
        aria-label="Robot Manager"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="rcs-modal__header">
          <div>
            <h3>Robot Manager</h3>
            <p>Add robot IDs to subscribe and choose which robot receives commands.</p>
          </div>
          <CloseIconButton ref={closeButtonRef} onClick={onClose} />
        </div>

        <div className="rcs-modal__body">
          <div className="rcs-robot-manager__add-row">
            <label className="rcs-modal__field">
              <span>Robot ID</span>
              <input
                type="text"
                value={newRobotId}
                onChange={(event) => setNewRobotId(event.target.value)}
                onKeyDown={handleInputKeyDown}
              />
            </label>
            <button type="button" className="rcs-button rcs-button--success" onClick={addRobot}>
              Add
            </button>
          </div>

          {error && <div className="rcs-robot-manager__error">{error}</div>}

          <div className="rcs-robot-manager__list">
            {draftRobotIds.map((robotId) => {
              const summary = summaryById.get(robotId);
              const isActive = robotId === draftActiveRobotId;
              return (
                <div key={robotId} className={`rcs-robot-manager__item${isActive ? " is-active" : ""}`}>
                  <span
                    className="rcs-robot-list__dot"
                    style={{ background: summary?.markerColor }}
                    aria-hidden="true"
                  />
                  <div className="rcs-robot-manager__identity">
                    <strong>{robotId}</strong>
                    <span>
                      {summary?.motion ?? "Idle"} · {summary?.batteryLabel ?? "--%"} · {summary?.signalLabel ?? "--"}
                    </span>
                  </div>
                  <button
                    type="button"
                    className="rcs-ghost-button"
                    onClick={() => setDraftActiveRobotId(robotId)}
                  >
                    {isActive ? "Control" : "Select"}
                  </button>
                  <button
                    type="button"
                    className="rcs-button rcs-button--danger rcs-robot-manager__remove"
                    onClick={() => removeRobot(robotId)}
                  >
                    Remove
                  </button>
                </div>
              );
            })}
          </div>
        </div>

        <div className="rcs-modal__footer">
          <span>{connected ? "Saving resubscribes robot topics on the active broker." : "Saved locally and restored on next launch."}</span>
          <div className="rcs-modal__actions">
            <button type="button" className="rcs-button rcs-button--danger rcs-modal__action-button" onClick={onClose}>
              Cancel
            </button>
            <button
              type="button"
              className="rcs-button rcs-button--success rcs-modal__action-button"
              onClick={() => onSave(draftRobotIds, draftActiveRobotId)}
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
