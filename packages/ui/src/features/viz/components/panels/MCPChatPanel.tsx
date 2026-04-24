import { useEffect, useRef, useState } from "react";

export type MCPProvider = "claude" | "chatgpt";

type MCPChatMessage = {
  id: string;
  role: "system" | "user" | "assistant";
  content: string;
  timestamp: string;
};

const providerLabels: Record<MCPProvider, string> = {
  claude: "Claude",
  chatgpt: "ChatGPT",
};

const starterPrompts = [
  "AMR 전체 함대 상태를 요약해줘.",
  "burger1을 충전 스테이션으로 보내는 절차를 설명해줘.",
  "현재 경로 막힘 이벤트가 있으면 우회 제안을 해줘.",
  "맵 상에서 작업 구역별 대기 중 로봇을 분류해줘.",
];

function createMessage(role: MCPChatMessage["role"], content: string): MCPChatMessage {
  return {
    id: `${role}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    role,
    content,
    timestamp: new Date().toLocaleTimeString("ko-KR", { hour12: false }),
  };
}

const initialMessages: MCPChatMessage[] = [
  createMessage("system", "MCP 세션 대기 중."),
  createMessage(
    "assistant",
    "Claude 또는 ChatGPT를 선택한 뒤, 관제 프롬프트를 입력하면 MCP 요청 흐름을 시작할 수 있습니다.",
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

function MessageAvatar({ role, provider }: { role: MCPChatMessage["role"]; provider: MCPProvider }) {
  const cls = role === "assistant" ? `rcs-mcp-avatar--${provider}` : "rcs-mcp-avatar--operator";
  const label = role === "assistant" ? (provider === "claude" ? "C" : "G") : "OP";
  return <div className={`rcs-mcp-avatar ${cls}`}>{label}</div>;
}

type MCPChatPanelProps = {
  mqttUrl: string;
  robotId: string;
  onMqttUrlChange: (url: string) => void;
  onRobotIdChange: (id: string) => void;
  onConnect: () => void;
  onDisconnect: () => void;
};

export function MCPChatPanel({
  mqttUrl,
  robotId,
  onMqttUrlChange,
  onRobotIdChange,
  onConnect,
  onDisconnect,
}: MCPChatPanelProps) {
  const [provider, setProvider] = useState<MCPProvider>("claude");
  const [endpoint, setEndpoint] = useState("ws://127.0.0.1:3001/mcp");
  const [sessionLabel, setSessionLabel] = useState("Follow Robot");
  const [draft, setDraft] = useState("");
  const [messages, setMessages] = useState<MCPChatMessage[]>(initialMessages);
  const [configOpen, setConfigOpen] = useState(false);
  const chatlogRef = useRef<HTMLDivElement>(null);

  const hasUserMessage = messages.some((m) => m.role === "user");

  useEffect(() => {
    const el = chatlogRef.current;
    if (el) {
      el.scrollTop = el.scrollHeight;
    }
  }, [messages]);

  const handleKeyDown = (event: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
      event.preventDefault();
      handleSubmit();
    }
  };

  const handleSubmit = () => {
    const trimmed = draft.trim();
    if (!trimmed) {
      return;
    }

    const providerLabel = providerLabels[provider];
    setMessages((current) => [
      ...current,
      createMessage("user", trimmed),
      createMessage(
        "assistant",
        `${providerLabel} MCP 브리지 준비 완료. 현재 ros2_mcp_server 연결 전 단계입니다.\n\n예상 실행: robot.lookup_status → navigation.review_queue → operator.confirm_dispatch`,
      ),
    ]);
    setDraft("");
  };

  return (
    <section className={`rcs-mcp-panel rcs-mcp-panel--${provider}`}>
      <div className="rcs-mcp-panel__header">
        <div className="rcs-mcp-panel__title-area">
          <span className="rcs-mcp-panel__eyebrow">AI Mission Control</span>
          <div className="rcs-mcp-panel__provider-tabs" role="tablist" aria-label="AI provider">
            {(["claude", "chatgpt"] as MCPProvider[]).map((item) => (
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
          <button
            type="button"
            className={`rcs-mcp-config-toggle${configOpen ? " is-open" : ""}`}
            aria-label="Toggle configuration"
            onClick={() => setConfigOpen((v) => !v)}
          >
            <GearIcon />
          </button>
        </div>
      </div>

      {configOpen && (
        <div className="rcs-mcp-panel__config">
          <label className="rcs-field">
            <span>MCP Endpoint</span>
            <input
              value={endpoint}
              onChange={(e) => setEndpoint(e.target.value)}
              placeholder="ws://host:port/mcp"
            />
          </label>
          <label className="rcs-field">
            <span>Session Scope</span>
            <input
              value={sessionLabel}
              onChange={(e) => setSessionLabel(e.target.value)}
              placeholder="robot-id / operator-room"
            />
          </label>

          <div className="rcs-mcp-config-divider">MQTT</div>

          <label className="rcs-field">
            <span>Broker URL</span>
            <input
              value={mqttUrl}
              onChange={(e) => onMqttUrlChange(e.target.value)}
              placeholder="ws://host:9001/mqtt"
            />
          </label>
          <label className="rcs-field">
            <span>Robot ID</span>
            <input
              value={robotId}
              onChange={(e) => onRobotIdChange(e.target.value)}
              placeholder="burger1"
            />
          </label>

          <div className="rcs-mcp-config-actions">
            <button type="button" className="rcs-button rcs-button--teal" onClick={onConnect}>
              Connect
            </button>
            <button type="button" className="rcs-button rcs-button--danger" onClick={onDisconnect}>
              Disconnect
            </button>
          </div>
        </div>
      )}

      <div ref={chatlogRef} className="rcs-mcp-chatlog" aria-live="polite">
        {!hasUserMessage && (
          <div className="rcs-mcp-starters">
            <p className="rcs-mcp-starters__label">Quick prompts</p>
            {starterPrompts.map((prompt) => (
              <button
                key={prompt}
                type="button"
                className="rcs-mcp-prompt"
                onClick={() => setDraft(prompt)}
              >
                {prompt}
              </button>
            ))}
          </div>
        )}

        {messages
          .filter((m) => m.role !== "system")
          .map((message) => (
            <article key={message.id} className={`rcs-mcp-message rcs-mcp-message--${message.role}`}>
              <MessageAvatar role={message.role} provider={provider} />
              <div className="rcs-mcp-bubble">
                <p>{message.content}</p>
                <time className="rcs-mcp-message__time">{message.timestamp}</time>
              </div>
            </article>
          ))}
      </div>

      <div className="rcs-mcp-composer">
        <textarea
          className="rcs-mcp-composer__input"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={`Message ${providerLabels[provider]}…`}
        />
        <div className="rcs-mcp-composer__actions">
          <span className="rcs-mcp-composer__hint">Ctrl+Enter로 전송</span>
          <button
            type="button"
            className={`rcs-button rcs-button--${provider}`}
            onClick={handleSubmit}
          >
            Send to {providerLabels[provider]}
          </button>
        </div>
      </div>
    </section>
  );
}
