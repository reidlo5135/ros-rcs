import type { EventEntry } from "../../types";

type EventsPanelProps = {
  events: EventEntry[];
};

export function EventsPanel({ events }: EventsPanelProps) {
  return (
    <section className="rcs-card rcs-card--fill">
      <div className="rcs-card__header">
        <h2>Events / Feedback</h2>
      </div>

      <div className="rcs-event-list">
        {events.map((event) => (
          <article className="rcs-event" key={`${event.time}-${event.text}`}>
            <time>{event.time}</time>
            <strong>{event.text}</strong>
          </article>
        ))}
      </div>
    </section>
  );
}

