import { forwardRef } from "react";

type CloseIconButtonProps = {
  label?: string;
  onClick: () => void;
};

export const CloseIconButton = forwardRef<HTMLButtonElement, CloseIconButtonProps>(
  function CloseIconButton({ label = "Close", onClick }, ref) {
    return (
      <button ref={ref} type="button" className="rcs-close-button" aria-label={label} title={label} onClick={onClick}>
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <path d="M3.5 3.5 12.5 12.5" />
          <path d="M12.5 3.5 3.5 12.5" />
        </svg>
      </button>
    );
  },
);
