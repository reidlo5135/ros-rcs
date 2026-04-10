import { useEffect, useRef, useState, type FC } from "react";

import { CloseIconButton } from "./components/CloseIconButton";

export type TopicSettingDefinition = {
  key: string;
  label: string;
};

type TopicSettingsModalProps = {
  open: boolean;
  title: string;
  description: string;
  topics: TopicSettingDefinition[];
  values: Record<string, string>;
  onClose: () => void;
  onSave: (nextValues: Record<string, string>) => void;
};

export const TopicSettingsModal: FC<TopicSettingsModalProps> = ({
  open,
  title,
  description,
  topics,
  values,
  onClose,
  onSave,
}) => {
  const [draftValues, setDraftValues] = useState<Record<string, string>>(values);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    if (open) {
      setDraftValues(values);
    }
  }, [open, values]);

  useEffect(() => {
    if (!open) {
      return undefined;
    }

    const handleKeyDown = (event: KeyboardEvent) => {
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

  return (
    <div className="rcs-modal-backdrop" role="presentation" onClick={onClose}>
      <div className="rcs-modal" role="dialog" aria-modal="true" aria-label={title} onClick={(event) => event.stopPropagation()}>
        <div className="rcs-modal__header">
          <div>
            <h3>{title}</h3>
            <p>{description}</p>
          </div>
          <CloseIconButton ref={closeButtonRef} onClick={onClose} />
        </div>

        <div className="rcs-modal__body">
          {topics.map((topic) => (
            <label key={topic.key} className="rcs-modal__field">
              <span>{topic.label}</span>
              <input
                type="text"
                value={draftValues[topic.key] ?? ""}
                onChange={(event) => {
                  const nextTopic = event.target.value;
                  setDraftValues((current) => ({
                    ...current,
                    [topic.key]: nextTopic,
                  }));
                }}
              />
            </label>
          ))}
        </div>

        <div className="rcs-modal__footer">
          <span>Saved locally and restored on next launch.</span>
          <div className="rcs-modal__actions">
            <button type="button" className="rcs-button rcs-button--danger rcs-modal__action-button" onClick={onClose}>
              Cancel
            </button>
            <button type="button" className="rcs-button rcs-button--success rcs-modal__action-button" onClick={() => onSave(draftValues)}>
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
