export type ProviderId = "anthropic" | "openai" | "mock";
export const PROVIDERS: ProviderId[] = ["anthropic", "openai", "mock"];

export type ActionType = "send_email" | "run_command" | "purchase" | "code_push" | "other";
export const ACTION_TYPES: ActionType[] = ["send_email", "run_command", "purchase", "code_push", "other"];

export type Risk = "low" | "medium" | "high";
export const RISKS: Risk[] = ["low", "medium", "high"];

export type ApprovalStatus = "pending" | "approved" | "declined" | "expired";
export type RuleMode = "ask" | "auto" | "block";
export const RULE_MODES: RuleMode[] = ["ask", "auto", "block"];
export type Rules = Record<ActionType, RuleMode>;

export type DeviceKind = "phone" | "watch";
export type AgentStatus = "idle" | "working" | "waiting";

export interface Agent {
  id: string;
  name: string;
  provider: ProviderId;
  model: string;
  systemPrompt: string;
  /** Where decisions are POSTed back to the agent. Empty = agent polls instead. */
  endpoint: string;
  /** Authenticates the agent to the webhook and signs callbacks to the agent. */
  webhookSecret: string;
  /** Provider API key. Empty = fall back to the relay's environment variable. Never sent to devices. */
  apiKey: string;
  createdAt: string;
}

export interface Device {
  id: string;
  name: string;
  kind: DeviceKind;
  tokenHash: string;
  pushToken?: string;
  pushEnv?: "sandbox" | "production";
  pushTopic?: string;
  createdAt: string;
  lastSeenAt: string;
}

export interface Approval {
  id: string;
  agentId: string;
  actionType: ActionType;
  title: string;
  details: [string, string][];
  reasoning: string;
  risk: Risk;
  createdAt: string;
  expiresAt: string;
  status: ApprovalStatus;
  decidedAt?: string;
  decidedBy?: string;
  reason?: string;
  nonce: string;
  callbackState?: "none" | "pending" | "ok" | "failed";
}

export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  createdAt: string;
  streaming?: boolean;
}

export interface AuditEntry {
  ts: string;
  event: string;
  approvalId?: string;
  agentId?: string;
  actor?: string;
  detail?: string;
}

export interface DB {
  serverSecret: string;
  adminKey: string;
  devices: Device[];
  agents: Agent[];
  approvals: Approval[];
  audit: AuditEntry[];
  messages: Record<string, ChatMessage[]>;
  rules: Rules;
  settings: { timeoutSeconds: number };
}
