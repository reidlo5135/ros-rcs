import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

export type MCPProvider = "claude" | "chatgpt" | "ollama";

type ChatMessageRole = "user" | "assistant" | "event" | "system";

type MCPChatMessage = {
  id: string;
  role: ChatMessageRole;
  content: string;
  timestamp: string;
  category?: string;
};

type WsStatus = "disconnected" | "connecting" | "connected" | "error";

type ChatEventPayload = {
  category: string;
  message: string;
};

type MCPChatPanelProps = {
  mqttUrl: string;
  robotId: string;
  onMqttUrlChange: (url: string) => void;
  onRobotIdChange: (id: string) => void;
  onConnect: () => void;
  onDisconnect: () => void;
};

const providerLabels: Record<MCPProvider, string> = {
  claude: "Claude",
  chatgpt: "ChatGPT",
  ollama: "Ollama",
};

const WS_STATUS_LABEL: Record<WsStatus, string> = {
  disconnected: "Offline",
  connecting: "Connecting...",
  connected: "Connected",
  error: "Error",
};

const starterPrompts = [
  "AMR 전체 함대 상태를 요약해줘.",
  "burger1을 map 기준 x=1.25, y=0.40 위치로 보내줘.",
  "burger1을 충전 스테이션으로 보내는 절차를 설명해줘.",
  "현재 경로 막힘이 있으면 우회 제안을 해줘.",
  "burger1 goal을 map 기준 x=2.00, y=-0.75, yaw=1.57로 보내줘.",
];

function createMessage(
  role: MCPChatMessage["role"],
  content: string,
  category?: string,
): MCPChatMessage {
  return {
    id: `${role}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    role,
    content,
    category,
    timestamp: new Date().toLocaleTimeString("ko-KR", { hour12: false }),
  };
}

const initialMessages: MCPChatMessage[] = [
  createMessage(
    "assistant",
    "RCS는 RMS /chat 채널을 통해 자연어 명령과 navigation lifecycle 이벤트를 같은 타임라인으로 표시합니다.",
    "assistant",
  ),
];

function GearIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
      <path
        fillRule="evenodd"
        clipRule="evenodd"
        d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z"
      />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg viewBox="0 0 20 20" fill="none" aria-hidden="true">
      <path d="M5 5l10 10M15 5L5 15" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

function toCategoryClass(category?: string) {
  if (!category) {
    return "";
  }

  return category
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function extractChatEvent(payload: unknown): ChatEventPayload | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  const record = payload as Record<string, unknown>;
  const params = record.params && typeof record.params === "object" ? (record.params as Record<string, unknown>) : null;
  const sources = [record, params].filter((item): item is Record<string, unknown> => Boolean(item));

  for (const source of sources) {
    const eventType =
      typeof source.type === "string"
        ? source.type
        : typeof source.event === "string"
          ? source.event
          : typeof source.method === "string"
            ? source.method
            : null;

    const category = typeof source.category === "string" ? source.category : null;
    const message = typeof source.message === "string" ? source.message.trim() : null;

    if ((eventType === "chat.event" || category) && message) {
      return {
        category: category ?? "assistant",
        message,
      };
    }
  }

  return null;
}

function eventRoleFromCategory(category: string): ChatMessageRole {
  return category === "assistant" ? "assistant" : "event";
}

function eventAvatarClass(category: string) {
  if (category === "error" || category.endsWith(".failed")) {
    return "rcs-mcp-avatar--error";
  }

  if (category.endsWith(".completed")) {
    return "rcs-mcp-avatar--success";
  }

  if (category.startsWith("navigation.")) {
    return "rcs-mcp-avatar--lifecycle";
  }

  return "rcs-mcp-avatar--event";
}

function eventAvatarLabel(category: string) {
  if (category === "error" || category.endsWith(".failed")) {
    return "ERR";
  }

  if (category.endsWith(".completed")) {
    return "OK";
  }

  if (category.startsWith("navigation.")) {
    return "NAV";
  }

  return "EV";
}

function MessageAvatar({
  role,
  provider,
  category,
}: {
  role: MCPChatMessage["role"];
  provider: MCPProvider;
  category?: string;
}) {
  if (role === "assistant") {
    const label = provider === "claude" ? "C" : provider === "chatgpt" ? "G" : "O";
    return <div className={`rcs-mcp-avatar rcs-mcp-avatar--${provider}`}>{label}</div>;
  }

  if (role === "event") {
    return <div className={`rcs-mcp-avatar ${eventAvatarClass(category ?? "")}`}>{eventAvatarLabel(category ?? "")}</div>;
  }

  return <div className="rcs-mcp-avatar rcs-mcp-avatar--operator">OP</div>;
}

export function MCPChatPanel({
  mqttUrl,
  robotId,
  onMqttUrlChange,
  onRobotIdChange,
  onConnect,
  onDisconnect,
}: MCPChatPanelProps) {
  const [provider, setProvider] = useState<MCPProvider>("chatgpt");
  const [endpoint, setEndpoint] = useState("ws://127.0.0.1:3001/chat");
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<MCPChatMessage[]>(initialMessages);
  const [configOpen, setConfigOpen] = useState(false);
  const [wsStatus, setWsStatus] = useState<WsStatus>("disconnected");
  const [isWaiting, setIsWaiting] = useState(false);

  const chatlogRef = useRef<HTMLDivElement>(null);
  const configModalRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const hasUserMessage = messages.some((message) => message.role === "user");

  useEffect(() => {
    const el = chatlogRef.current;
    if (el) {
      el.scrollTop = el.scrollHeight;
    }
  }, [messages, isWaiting]);

  useEffect(() => {
    if (configOpen) {
      configModalRef.current?.focus();
    }
  }, [configOpen]);

  useEffect(() => {
    if (!configOpen) {
      return;
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setConfigOpen(false);
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [configOpen]);

  useEffect(() => {
    return () => {
      wsRef.current?.close();
    };
  }, []);

  const pushMessage = (
    role: MCPChatMessage["role"],
    content: string,
    category?: string,
  ) => {
    setMessages((prev) => [...prev, createMessage(role, content, category)]);
  };

  const handleIncomingPayload = (raw: string) => {
    let parsed: unknown;

    try {
      parsed = JSON.parse(raw);
    } catch {
      const text = raw.trim();
      if (text) {
        pushMessage("system", text);
      }
      return;
    }

    const chatEvent = extractChatEvent(parsed);
    if (chatEvent) {
      pushMessage(eventRoleFromCategory(chatEvent.category), chatEvent.message, chatEvent.category);
      setIsWaiting(false);
      return;
    }

    const record = parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>) : null;
    const fallback =
      (typeof record?.message === "string" && record.message.trim()) ||
      (typeof record?.detail === "string" && record.detail.trim()) ||
      "";

    if (fallback) {
      setIsWaiting(false);
      pushMessage("system", fallback);
    }
  };

  const connectChat = () => {
    wsRef.current?.close();
    wsRef.current = null;
    setWsStatus("connecting");
    pushMessage("system", `RMS /chat 연결 시도: ${endpoint}`);

    let ws: WebSocket;
    try {
      ws = new WebSocket(endpoint);
    } catch {
      setWsStatus("error");
      pushMessage("system", `연결 실패: 유효하지 않은 엔드포인트 "${endpoint}"`);
      return;
    }

    wsRef.current = ws;

    ws.onopen = () => {
      setWsStatus("connected");
      pushMessage("system", `RMS /chat 연결 완료: ${endpoint}`);
    };

    ws.onmessage = async (event) => {
      if (typeof event.data === "string") {
        handleIncomingPayload(event.data);
        return;
      }

      if (event.data instanceof Blob) {
        handleIncomingPayload(await event.data.text());
        return;
      }

      handleIncomingPayload(String(event.data));
    };

    ws.onerror = () => {
      setWsStatus("error");
      setIsWaiting(false);
      pushMessage("system", `WebSocket 오류: ${endpoint} 에 연결할 수 없습니다.`);
    };

    ws.onclose = (event) => {
      if (wsRef.current === ws) {
        wsRef.current = null;
      }
      setIsWaiting(false);
      setWsStatus(event.wasClean ? "disconnected" : "error");
      const reason = event.reason ? ` (${event.reason})` : "";
      pushMessage("system", `RMS /chat 연결 종료 [${event.code}]${reason}`);
    };
  };

  const disconnectChat = () => {
    setIsWaiting(false);
    wsRef.current?.close();
    wsRef.current = null;
    setWsStatus("disconnected");
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      void handleSubmit();
    }
  };

  const handleSubmit = async () => {
    const trimmed = draft.trim();
    if (!trimmed || isWaiting) {
      return;
    }

    pushMessage("user", trimmed);
    setDraft("");

    const ws = wsRef.current;
    if (!ws || ws.readyState !== WebSocket.OPEN || wsStatus !== "connected") {
      pushMessage("system", "RMS /chat 서버에 연결되어 있지 않습니다. 설정에서 Connect Chat을 누르세요.");
      return;
    }

    setIsWaiting(true);
    ws.send(
      JSON.stringify({
        message: trimmed,
        provider,
        robot_id: robotId,
      }),
    );
  };

  return (
    <section className={`rcs-mcp-panel rcs-mcp-panel--${provider}`}>
      <div className="rcs-mcp-panel__header">
        <div className="rcs-mcp-panel__title-area">
          <span className="rcs-mcp-panel__eyebrow">AI Mission Control</span>
          <div className="rcs-mcp-panel__provider-tabs" role="tablist" aria-label="AI provider">
            {(["claude", "chatgpt", "ollama"] as MCPProvider[]).map((item) => (
              <button
                key={item}
                type="button"
                role="tab"
                aria-selected={provider === item}
                className={`rcs-mcp-tab${provider === item ? " rcs-mcp-tab--active" : ""}`}
                onClick={() => setProvider(item)}
              >
                {providerLabels[item]}
              </button>
            ))}
          </div>
        </div>

        <div className="rcs-mcp-panel__header-right">
          <span className={`rcs-mcp-status rcs-mcp-status--${wsStatus}`}>
            {WS_STATUS_LABEL[wsStatus]}
          </span>
          <button
            type="button"
            className={`rcs-mcp-config-toggle${configOpen ? " is-open" : ""}`}
            aria-label="Toggle configuration"
            onClick={() => setConfigOpen((value) => !value)}
          >
            <GearIcon />
          </button>
        </div>
      </div>

      {configOpen && typeof document !== "undefined"
        ? createPortal(
            <div
              className="rcs-mcp-config-modal-backdrop"
              role="dialog"
              aria-modal="true"
              aria-label="Connection settings"
              onClick={() => setConfigOpen(false)}
            >
              <div
                ref={configModalRef}
                className="rcs-mcp-config-modal"
                tabIndex={-1}
                onClick={(event) => event.stopPropagation()}
              >
                <div className="rcs-mcp-config-modal__header">
                  <div>
                    <strong>Connection Settings</strong>
                    <p>RMS /chat 소켓과 MQTT 연결 설정을 같은 방식으로 관리합니다.</p>
                  </div>
                  <button
                    type="button"
                    className="rcs-close-button"
                    aria-label="Close connection settings"
                    onClick={() => setConfigOpen(false)}
                  >
                    <CloseIcon />
                  </button>
                </div>

                <div className="rcs-mcp-config-modal__body">
                  <section className="rcs-mcp-config-card">
                    <div className="rcs-mcp-config-card__header">
                      <div>
                        <span className="rcs-mcp-config-card__eyebrow">CHAT</span>
                        <h3>RMS Chat Socket</h3>
                      </div>
                      <span className={`rcs-mcp-status rcs-mcp-status--${wsStatus}`}>
                        {WS_STATUS_LABEL[wsStatus]}
                      </span>
                    </div>

                    <label className="rcs-field">
                      <span>Endpoint</span>
                      <input
                        value={endpoint}
                        onChange={(event) => setEndpoint(event.target.value)}
                        placeholder="ws://host:port/chat"
                      />
                    </label>

                    <div className="rcs-mcp-config-actions rcs-mcp-config-actions--single">
                      {wsStatus === "connected" ? (
                        <button type="button" className="rcs-button rcs-button--danger" onClick={disconnectChat}>
                          Disconnect Chat
                        </button>
                      ) : (
                        <button
                          type="button"
                          className={`rcs-button rcs-button--teal${wsStatus === "connecting" ? " rcs-button--armed-goal" : ""}`}
                          onClick={connectChat}
                          disabled={wsStatus === "connecting"}
                        >
                          {wsStatus === "connecting" ? "Connecting..." : "Connect Chat"}
                        </button>
                      )}
                    </div>
                  </section>

                  <section className="rcs-mcp-config-card">
                    <div className="rcs-mcp-config-card__header">
                      <div>
                        <span className="rcs-mcp-config-card__eyebrow">MQTT</span>
                        <h3>Broker Session</h3>
                      </div>
                    </div>

                    <div className="rcs-mcp-config-grid">
                      <label className="rcs-field">
                        <span>Broker URL</span>
                        <input
                          value={mqttUrl}
                          onChange={(event) => onMqttUrlChange(event.target.value)}
                          placeholder="ws://host:9001/mqtt"
                        />
                      </label>
                      <label className="rcs-field">
                        <span>Robot ID</span>
                        <input
                          value={robotId}
                          onChange={(event) => onRobotIdChange(event.target.value)}
                          placeholder="burger1"
                        />
                      </label>
                    </div>

                    <div className="rcs-mcp-config-actions">
                      <button type="button" className="rcs-button rcs-button--teal" onClick={onConnect}>
                        Connect MQTT
                      </button>
                      <button type="button" className="rcs-button rcs-button--danger" onClick={onDisconnect}>
                        Disconnect MQTT
                      </button>
                    </div>
                  </section>
                </div>
              </div>
            </div>,
            document.body,
          )
        : null}

      <div ref={chatlogRef} className="rcs-mcp-chatlog" aria-live="polite">
        {!hasUserMessage && (
          <div className="rcs-mcp-starters">
            <p className="rcs-mcp-starters__label">Quick prompts</p>
            {starterPrompts.map((prompt) => (
              <button key={prompt} type="button" className="rcs-mcp-prompt" onClick={() => setDraft(prompt)}>
                {prompt}
              </button>
            ))}
          </div>
        )}

        {messages.map((message) => {
          if (message.role === "system") {
            return (
              <div key={message.id} className="rcs-mcp-system-note">
                {message.content}
              </div>
            );
          }

          const categoryClass = toCategoryClass(message.category);

          return (
            <article
              key={message.id}
              className={`rcs-mcp-message rcs-mcp-message--${message.role}${categoryClass ? ` rcs-mcp-message--category-${categoryClass}` : ""}`}
            >
              <MessageAvatar role={message.role} provider={provider} category={message.category} />
              <div className="rcs-mcp-bubble">
                <p>{message.content}</p>
                <time className="rcs-mcp-message__time">{message.timestamp}</time>
              </div>
            </article>
          );
        })}

        {isWaiting && (
          <div className="rcs-mcp-message rcs-mcp-message--assistant">
            <MessageAvatar role="assistant" provider={provider} category="assistant" />
            <div className="rcs-mcp-bubble">
              <div className="rcs-mcp-typing">
                <span />
                <span />
                <span />
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="rcs-mcp-composer">
        <textarea
          className="rcs-mcp-composer__input"
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={`Message ${providerLabels[provider]}...`}
          disabled={isWaiting}
        />
        <div className="rcs-mcp-composer__actions">
          <span className="rcs-mcp-composer__hint">Ctrl+Enter로 전송</span>
          <button
            type="button"
            className={`rcs-button rcs-button--${provider}`}
            onClick={() => void handleSubmit()}
            disabled={wsStatus !== "connected"}
          >
            {isWaiting ? "Waiting..." : `Send to ${providerLabels[provider]}`}
          </button>
        </div>
      </div>
    </section>
  );
}
