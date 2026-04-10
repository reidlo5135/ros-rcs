import { useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";

import {
  KNOB_RADIUS,
  MAX_ANGULAR_Z,
  MAX_LINEAR_X,
  PAD_RADIUS,
  RESPONSE_EXPONENT,
} from "../../constants";

type JoystickPanelProps = {
  linearX: number;
  angularZ: number;
  onCommandChange: (linearX: number, angularZ: number) => void;
  onCommandStop: () => void;
};

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function shapeNormalized(value: number) {
  const magnitude = Math.abs(value);
  return Math.sign(value) * (magnitude ** RESPONSE_EXPONENT);
}

function JoystickPad({ linearX, angularZ, onCommandChange, onCommandStop }: JoystickPanelProps) {
  const padRef = useRef<HTMLDivElement | null>(null);
  const [dragVector, setDragVector] = useState({ x: 0, y: 0 });

  const knobStyle = useMemo(
    () => ({
      transform: `translate(${dragVector.x}px, ${dragVector.y}px)`,
    }),
    [dragVector.x, dragVector.y],
  );

  const updateFromPointer = (clientX: number, clientY: number) => {
    const pad = padRef.current;
    if (!pad) {
      return;
    }

    const rect = pad.getBoundingClientRect();
    const offsetX = clientX - (rect.left + (rect.width / 2));
    const offsetY = clientY - (rect.top + (rect.height / 2));
    const magnitude = Math.hypot(offsetX, offsetY);
    const limitedScale = magnitude > (PAD_RADIUS - KNOB_RADIUS)
      ? (PAD_RADIUS - KNOB_RADIUS) / magnitude
      : 1;

    const limitedX = offsetX * limitedScale;
    const limitedY = offsetY * limitedScale;
    const normalizedX = clamp(limitedX / (PAD_RADIUS - KNOB_RADIUS), -1, 1);
    const normalizedY = clamp(limitedY / (PAD_RADIUS - KNOB_RADIUS), -1, 1);

    setDragVector({ x: limitedX, y: limitedY });
    onCommandChange(
      -shapeNormalized(normalizedY) * MAX_LINEAR_X,
      shapeNormalized(normalizedX) * MAX_ANGULAR_Z,
    );
  };

  const handlePointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    event.currentTarget.setPointerCapture(event.pointerId);
    updateFromPointer(event.clientX, event.clientY);
  };

  const handlePointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!event.currentTarget.hasPointerCapture(event.pointerId)) {
      return;
    }

    updateFromPointer(event.clientX, event.clientY);
  };

  const stop = () => {
    setDragVector({ x: 0, y: 0 });
    onCommandStop();
  };

  const handlePointerUp = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    stop();
  };

  return (
    <>
      <div className="rcs-joystick">
        <div
          ref={padRef}
          className="rcs-joystick__base"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={handlePointerUp}
        >
          <div className="rcs-joystick__cross rcs-joystick__cross--horizontal" />
          <div className="rcs-joystick__cross rcs-joystick__cross--vertical" />
          <div className="rcs-joystick__knob" style={knobStyle} />
        </div>
      </div>

      <div className="rcs-status-list rcs-status-list--compact">
        <div className="rcs-status-row"><span>Linear X</span><strong>{linearX.toFixed(3)} m/s</strong></div>
        <div className="rcs-status-row"><span>Angular Z</span><strong>{angularZ.toFixed(3)} rad/s</strong></div>
      </div>
    </>
  );
}

export function JoystickPanel(props: JoystickPanelProps) {
  return (
    <section className="rcs-card">
      <div className="rcs-card__header">
        <h2>Joystick</h2>
      </div>

      <JoystickPad {...props} />
    </section>
  );
}

