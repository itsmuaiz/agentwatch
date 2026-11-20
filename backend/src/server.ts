import { randomBytes } from "node:crypto";
import { writeFileSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import { ApprovalService, HttpError } from "./approvals.js";
import { config } from "./config.js";
import { approvalSig, newId, newToken, safeEqual, sha256 } from "./crypto.js";
import { EventHub } from "./hub.js";
import { demoApprovalFor } from "./mock.js";
import { resolveApiKey, streamChat, type ContextMessage } from "./providers.js";
import { sseInit, sseSend } from "./sse.js";
import { Store } from "./store.js";
import {
  ACTION_TYPES,
  PROVIDERS,
  RULE_MODES,
  type ActionType,
  type Agent,
  type AgentStatus,
  type ChatMessage,
  type Device,
  type DeviceKind,
  type ProviderId,
  type RuleMode,
} from "./types.js";

/* ------------------------------------------------------------------ setup */

const store = new Store();
const db = store.db;
const hub = new EventHub();
const approvals = new ApprovalService(store, hub);

const ADMIN_DEVICE: Device = {
  id: "admin",
  name: "Admin key",
  kind: "phone",
  tokenHash: "",
  createdAt: "",
  lastSeenAt: "",
};

/** One-time pairing codes (in memory only, valid 10 minutes). */
const pairCodes = new Map<string, { expires: number; kind: DeviceKind }>();

/** Chats currently generating a reply, keyed by agent id. */
const inflight = new Map<string, AbortController>();
/** Status reported by the agent itself through /v1/webhook/status. */
const external = new Map<string, { status: "working" | "idle"; at: number }>();

const DEFAULT_MODEL: Record<ProviderId, string> = {
  anthropic: "claude-sonnet-5-5",
  openai: "gpt-4o",
  mock: "demo",
};

function agentStatus(id: string): AgentStatus {
  if (approvals.pendingCount(id) > 0) return "waiting";
  const ext = external.get(id);
  if (inflight.has(id) || (ext && ext.status === "working" && Date.now() - ext.at < 10 * 60_000)) return "working";
  return "idle";
}

function agentView(a: Agent, forPhone: boolean) {
  return {
    id: a.id,
    name: a.name,
    provider: a.provider,
    model: a.model,
    status: agentStatus(a.id),
    pending_approvals: approvals.pendingCount(a.id),
    has_api_key: Boolean(a.apiKey),
    created_at: a.createdAt,
    // Only the phone ever sees configuration and the webhook secret. API keys are never sent to any device.
    ...(forPhone ? { system_prompt: a.systemPrompt, endpoint: a.endpoint, webhook_secret: a.webhookSecret } : {}),
  };
}

function newAgent(name: string, provider: ProviderId, model: string): Agent {
  return {
    id: newId(),
    name,
    provider,
    model,
    systemPrompt: "",
    endpoint: provider === "mock" ? config.demoCallbackUrl : "",
    webhookSecret: newToken(),
    apiKey: "",
    createdAt: new Date().toISOString(),
  };
}

/** First start: create a demo agent, plus Claude / ChatGPT agents if their keys are set in the environment. */
function seedAgents(): Agent {
  if (config.anthropicKey && !db.agents.some((a) => a.provider === "anthropic")) {
    db.agents.push(newAgent("Claude", "anthropic", DEFAULT_MODEL.anthropic));
  }
  if (config.openaiKey && !db.agents.some((a) => a.provider === "openai")) {
    db.agents.push(newAgent("ChatGPT", "openai", DEFAULT_MODEL.openai));
  }
  let demo = db.agents.find((a) => a.provider === "mock");
  if (!demo) {
    demo = newAgent("Demo Agent", "mock", "demo");
    db.agents.push(demo);
  }
  store.save();
  return demo;
}

/* ------------------------------------------------------------------ http plumbing */

type Body = Record<string, any>;
interface Ctx {
  req: IncomingMessage;
  res: ServerResponse;
  url: URL;
  params: string[];
  body: Body;
  device?: Device;
  agent?: Agent;
}
type Reply = { status?: number; body: unknown };
type Handler = (c: Ctx) => Promise<Reply | void> | Reply | void;
type Auth = "none" | "device" | "phone" | "agent" | "admin";

const routes: { method: string; re: RegExp; auth: Auth; handler: Handler }[] = [];
function route(method: string, path: string, auth: Auth, handler: Handler): void {
  routes.push({ method, re: new RegExp("^" + path.replace(/:[a-z]+/g, "([^/]+)") + "$"), auth, handler });
}

function bearer(req: IncomingMessage): string | undefined {
  const h = req.headers.authorization;
  return h && h.startsWith("Bearer ") ? h.slice(7).trim() : undefined;
}

function deviceAuth(req: IncomingMessage): Device | undefined {
  const t = bearer(req);
  if (!t) return undefined;
  const h = sha256(t);
  const d = db.devices.find((x) => safeEqual(x.tokenHash, h));
  if (d) d.lastSeenAt = new Date().toISOString();
  return d;
}

function agentAuth(req: IncomingMessage): Agent | undefined {
  const t = bearer(req);
  return t ? db.agents.find((a) => safeEqual(a.webhookSecret, t)) : undefined;
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body);
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(text);
}

async function readJson(req: IncomingMessage): Promise<Body> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const c of req) {
    size += (c as Buffer).length;
    if (size > 1_000_000) throw new HttpError(413, "Body too large");
    chunks.push(c as Buffer);
  }
  if (!chunks.length) return {};
  try {
    const v = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (v && typeof v === "object" && !Array.isArray(v)) return v as Body;
  } catch {
    /* fall through */
  }
  throw new HttpError(400, "Body must be a JSON object");
}

/** Simple brake on guessing tokens: 20 failed auth attempts per minute per address. */
const failures = new Map<string, { n: number; reset: number }>();
function failed(ip: string): void {
  const now = Date.now();
  const f = failures.get(ip);
  if (!f || f.reset < now) failures.set(ip, { n: 1, reset: now + 60_000 });
  else f.n++;
}
function blocked(ip: string): boolean {
  const f = failures.get(ip);
  return Boolean(f && f.reset > Date.now() && f.n >= 20);
}

const server = createServer(async (req, res) => {
  const started = Date.now();
  const ip = req.socket.remoteAddress ?? "?";
  const url = new URL(req.url ?? "/", "http://localhost");
  const method = req.method ?? "GET";
  try {
    if (blocked(ip)) throw new HttpError(429, "Too many failed attempts. Try again in a minute.");
    let params: string[] = [];
    const r = routes.find((x) => {
      if (x.method !== method) return false;
      const m = x.re.exec(url.pathname);
      if (m) params = m.slice(1).map(decodeURIComponent);
      return Boolean(m);
    });
    if (!r) throw new HttpError(404, "Not found");

    let device: Device | undefined;
    let agent: Agent | undefined;
    if (r.auth === "device" || r.auth === "phone") {
      const adminKey = req.headers["x-admin-key"];
      if (adminKey !== undefined) {
        // The admin key can do everything the phone can (used by curl and scripts when no iPhone app is installed).
        if (!safeEqual(String(adminKey), db.adminKey)) throw new HttpError(401, "Unauthorized");
        device = ADMIN_DEVICE;
      } else {
        device = deviceAuth(req);
      }
      if (!device) throw new HttpError(401, "Unauthorized");
      if (r.auth === "phone" && device.kind !== "phone") throw new HttpError(403, "Only the iPhone app can do this");
    } else if (r.auth === "agent") {
      agent = agentAuth(req);
      if (!agent) throw new HttpError(401, "Unauthorized");
    } else if (r.auth === "admin") {
      const k = String(req.headers["x-admin-key"] ?? "");
      if (!k || !safeEqual(k, db.adminKey)) throw new HttpError(401, "Unauthorized");
    }

    const body = method === "POST" || method === "PUT" ? await readJson(req) : {};
    const reply = await r.handler({ req, res, url, params, body, device, agent });
    if (reply) sendJson(res, reply.status ?? 200, reply.body);
  } catch (e) {
    const err = e instanceof HttpError ? e : new HttpError(500, "Internal error");
    if (!(e instanceof HttpError)) console.error(e);
    if (err.status === 401 || err.status === 403) failed(ip);
    if (!res.headersSent) sendJson(res, err.status, { error: err.message });
    else res.end();
  } finally {
    // Path only. Query strings can contain single-use signatures, so they are never logged.
    console.log(`${new Date().toISOString()} ${method} ${url.pathname} ${res.statusCode} ${Date.now() - started}ms`);
  }
});

/* ------------------------------------------------------------------ helpers for validation */

function parseAgentInput(b: Body, partial: boolean): Partial<Agent> {
  const out: Partial<Agent> = {};
  if (!partial || b.name !== undefined) {
    const name = typeof b.name === "string" ? b.name.trim().slice(0, 60) : "";
    if (!name) throw new HttpError(400, "name is required");
    out.name = name;
  }
  if (!partial || b.provider !== undefined) {
    if (!PROVIDERS.includes(b.provider)) throw new HttpError(400, "provider must be anthropic, openai or mock");
    out.provider = b.provider;
  }
  if (b.model !== undefined) {
    if (typeof b.model !== "string" || b.model.length > 100) throw new HttpError(400, "model is invalid");
    out.model = b.model.trim();
  }
  if (b.system_prompt !== undefined) {
    if (typeof b.system_prompt !== "string" || b.system_prompt.length > 8000) throw new HttpError(400, "system_prompt is too long");
    out.systemPrompt = b.system_prompt;
  }
  if (b.endpoint !== undefined) {
    if (typeof b.endpoint !== "string") throw new HttpError(400, "endpoint must be a string");
    const e = b.endpoint.trim();
    if (e) {
      try {
        const u = new URL(e);
        if (u.protocol !== "http:" && u.protocol !== "https:") throw new Error();
      } catch {
        throw new HttpError(400, "endpoint must be an http(s) URL");
      }
    }
    out.endpoint = e;
  }
  if (typeof b.api_key === "string" && b.api_key.trim()) out.apiKey = b.api_key.trim().slice(0, 500);
  if (b.clear_api_key === true) out.apiKey = "";
  return out;
}

function findAgent(id: string): Agent {
  const a = db.agents.find((x) => x.id === id);
  if (!a) throw new HttpError(404, "Agent not found");
  return a;
}

/* ------------------------------------------------------------------ routes: health, pairing, devices */

route("GET", "/health", "none", () => ({ body: { ok: true, name: "agentwatch-relay" } }));

/** First pairing: the iPhone app exchanges the admin key for a per-device token. */
route("POST", "/v1/pair", "admin", ({ body }) => {
  const kind: DeviceKind = body.kind === "watch" ? "watch" : "phone";
  const token = newToken();
  const device: Device = {
    id: newId(),
    name: (typeof body.name === "string" && body.name.trim().slice(0, 60)) || (kind === "phone" ? "iPhone" : "Apple Watch"),
    kind,
    tokenHash: sha256(token),
    createdAt: new Date().toISOString(),
    lastSeenAt: new Date().toISOString(),
  };
  db.devices.push(device);
  approvals.audit("device_paired", { actor: device.id, detail: `${kind}: ${device.name}` });
  return { status: 201, body: { device_id: device.id, token, kind } };
});

/** Admin: mint a one-time code to type on the watch (works without the iPhone app). */
route("POST", "/v1/pair/code", "admin", ({ body }) => {
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let code = "";
  for (const b of randomBytes(8)) code += alphabet[b % alphabet.length];
  pairCodes.set(code, { expires: Date.now() + 10 * 60_000, kind: body.kind === "phone" ? "phone" : "watch" });
  return { status: 201, body: { code: `${code.slice(0, 4)}-${code.slice(4)}`, expires_in_seconds: 600 } };
});

/** The watch (or phone) exchanges a pairing code for its own device token. */
route("POST", "/v1/pair/redeem", "none", ({ body }) => {
  const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const entry = pairCodes.get(code);
  if (!entry || entry.expires < Date.now()) throw new HttpError(403, "Invalid or expired code");
  pairCodes.delete(code); // single use
  const token = newToken();
  const device: Device = {
    id: newId(),
    name: (typeof body.name === "string" && body.name.trim().slice(0, 60)) || (entry.kind === "watch" ? "Apple Watch" : "iPhone"),
    kind: entry.kind,
    tokenHash: sha256(token),
    createdAt: new Date().toISOString(),
    lastSeenAt: new Date().toISOString(),
  };
  db.devices.push(device);
  approvals.audit("device_paired", { actor: device.id, detail: `${entry.kind}: ${device.name} (code)` });
  return { status: 201, body: { device_id: device.id, token, kind: entry.kind } };
});

/** The phone creates a token for the watch (delivered over WatchConnectivity). */
route("POST", "/v1/devices", "phone", ({ body }) => {
  const token = newToken();
  const device: Device = {
    id: newId(),
    name: (typeof body.name === "string" && body.name.trim().slice(0, 60)) || "Apple Watch",
    kind: "watch",
    tokenHash: sha256(token),
    createdAt: new Date().toISOString(),
    lastSeenAt: new Date().toISOString(),
  };
  db.devices.push(device);
  approvals.audit("device_paired", { actor: device.id, detail: `watch: ${device.name}` });
  return { status: 201, body: { device_id: device.id, token, kind: "watch" } };
});

route("GET", "/v1/devices", "phone", () => ({
  body: {
    devices: db.devices.map((d) => ({
      id: d.id,
      name: d.name,
      kind: d.kind,
      created_at: d.createdAt,
      last_seen_at: d.lastSeenAt,
      has_push_token: Boolean(d.pushToken),
    })),
  },
}));

route("DELETE", "/v1/devices/:id", "phone", ({ params }) => {
  const i = db.devices.findIndex((d) => d.id === params[0]);
  if (i < 0) throw new HttpError(404, "Device not found");
  const [d] = db.devices.splice(i, 1);
  approvals.audit("device_revoked", { detail: `${d.kind}: ${d.name}` });
  return { body: { ok: true } };
});

route("POST", "/v1/devices/me/push-token", "device", ({ device, body }) => {
  if (typeof body.token !== "string" || !/^[0-9a-fA-F]{32,200}$/.test(body.token)) throw new HttpError(400, "token is invalid");
  device!.pushToken = body.token;
  device!.pushEnv = body.environment === "production" ? "production" : "sandbox";
  device!.pushTopic = typeof body.topic === "string" ? body.topic.slice(0, 200) : undefined;
  store.save();
  return { body: { ok: true } };
});

/* ------------------------------------------------------------------ routes: agents and chat */

route("GET", "/v1/agents", "device", ({ device }) => ({
  body: { agents: db.agents.map((a) => agentView(a, device!.kind === "phone")) },
}));

route("POST", "/v1/agents", "phone", ({ body }) => {
  const input = parseAgentInput(body, false);
  const provider = input.provider as ProviderId;
  const agent: Agent = {
    id: newId(),
    name: input.name!,
    provider,
    model: input.model || DEFAULT_MODEL[provider],
    systemPrompt: input.systemPrompt ?? "",
    endpoint: input.endpoint ?? "",
    webhookSecret: newToken(),
    apiKey: input.apiKey ?? "",
    createdAt: new Date().toISOString(),
  };
  db.agents.push(agent);
  approvals.audit("agent_created", { agentId: agent.id, detail: `${agent.name} (${provider})` });
  return { status: 201, body: agentView(agent, true) };
});

route("PUT", "/v1/agents/:id", "phone", ({ params, body }) => {
  const agent = findAgent(params[0]);
  Object.assign(agent, parseAgentInput(body, true));
  approvals.audit("agent_updated", { agentId: agent.id, detail: agent.name });
  return { body: agentView(agent, true) };
});

route("DELETE", "/v1/agents/:id", "phone", ({ params }) => {
  const agent = findAgent(params[0]);
  inflight.get(agent.id)?.abort();
  db.agents = db.agents.filter((a) => a.id !== agent.id);
  delete db.messages[agent.id];
  approvals.audit("agent_deleted", { detail: agent.name });
  return { body: { ok: true } };
});

route("GET", "/v1/agents/:id/messages", "device", ({ params, url }) => {
  const agent = findAgent(params[0]);
  const limit = Math.min(Number(url.searchParams.get("limit")) || 100, 200);
  const msgs = (db.messages[agent.id] ?? []).slice(-limit);
  return { body: { messages: msgs, busy: inflight.has(agent.id) } };
});

route("DELETE", "/v1/agents/:id/messages", "phone", ({ params }) => {
  const agent = findAgent(params[0]);
  inflight.get(agent.id)?.abort();
  db.messages[agent.id] = [];
  approvals.audit("history_cleared", { agentId: agent.id });
  return { body: { ok: true } };
});

route("POST", "/v1/agents/:id/stop", "device", ({ params }) => {
  const agent = findAgent(params[0]);
  inflight.get(agent.id)?.abort();
  return { body: { ok: true } };
});

route("POST", "/v1/agents/:id/chat", "device", async ({ res, params, body }) => {
  const agent = findAgent(params[0]);
  const text = typeof body.text === "string" ? body.text.trim() : "";
  if (!text || text.length > 4000) throw new HttpError(400, "text must be 1 to 4000 characters");
  if (inflight.has(agent.id)) throw new HttpError(409, "Agent is still replying");
  const apiKey = resolveApiKey(agent);
  if (!apiKey) {
    throw new HttpError(400, `No API key for ${agent.provider}. Add one in the iPhone app or set it on the relay.`);
  }

  const msgs = (db.messages[agent.id] ??= []);
  const context: ContextMessage[] = msgs
    .filter((m) => !m.streaming && m.content)
    .slice(-30)
    .map((m) => ({ role: m.role, content: m.content }));
  context.push({ role: "user", content: text });

  const now = new Date().toISOString();
  const userMsg: ChatMessage = { id: newId(), role: "user", content: text, createdAt: now };
  const botMsg: ChatMessage = { id: newId(), role: "assistant", content: "", createdAt: now, streaming: true };
  msgs.push(userMsg, botMsg);
  store.save();

  const ac = new AbortController();
  inflight.set(agent.id, ac);
  hub.emit("agent_status", { agent_id: agent.id, status: agentStatus(agent.id) });

  sseInit(res);
  let open = true;
  res.on("close", () => (open = false));
  const send = (event: string, data: unknown) => {
    if (!open) return;
    try {
      sseSend(res, event, data);
    } catch {
      open = false;
    }
  };
  send("start", { user_message_id: userMsg.id, assistant_message_id: botMsg.id });

  const system =
    agent.systemPrompt +
    (body.style === "watch"
      ? "\n\nThe person is reading on a smartwatch. Start with a one or two sentence answer, then add detail only if needed."
      : "");

  // Generation keeps going even if the watch screen turns off, so the full reply is waiting when you look again.
  try {
    for await (const delta of streamChat(agent, { apiKey, model: agent.model, system, messages: context, signal: ac.signal })) {
      botMsg.content += delta;
      send("delta", { text: delta });
      store.save();
    }
  } catch (e) {
    if (!ac.signal.aborted) {
      const message = e instanceof Error ? e.message.slice(0, 300) : "Provider error";
      approvals.audit("chat_error", { agentId: agent.id, detail: message });
      if (!botMsg.content) msgs.splice(msgs.indexOf(botMsg), 1);
      send("error", { message });
    }
  } finally {
    botMsg.streaming = false;
    if (!botMsg.content && msgs.includes(botMsg)) msgs.splice(msgs.indexOf(botMsg), 1);
    inflight.delete(agent.id);
    store.save();
    send("done", { message: botMsg.content ? botMsg : null });
    if (open) res.end();
    hub.emit("agent_status", { agent_id: agent.id, status: agentStatus(agent.id) });
  }

  if (agent.provider === "mock" && !ac.signal.aborted) {
    const demo = demoApprovalFor(text);
    if (demo) await approvals.create(agent, demo).catch((e) => console.warn("demo approval failed", e));
  }
});

/* ------------------------------------------------------------------ routes: approvals (devices) */

route("GET", "/v1/approvals", "device", ({ url }) => {
  const kind = url.searchParams.get("status");
  const k = kind === "history" ? "history" : kind === "all" ? "all" : "pending";
  const limit = Math.min(Number(url.searchParams.get("limit")) || 50, 200);
  return { body: { approvals: approvals.list(k, limit).map((a) => approvals.view(a, true)) } };
});

route("GET", "/v1/approvals/:id", "device", ({ params }) => {
  const a = approvals.get(params[0]);
  if (!a) throw new HttpError(404, "Approval not found");
  return { body: approvals.view(a, true) };
});

/**
 * Decide an approval. Body: { id?, decision: "approved" | "declined", reason?, sig, confirmed? }.
 * The device must authenticate with its token AND present the approval's signature.
 * Exception: when ntfy is configured, the signature alone is accepted (that is what the notification buttons carry),
 * but never for approving a high-risk action.
 */
route("POST", "/v1/approvals/:id/decision", "none", ({ req, url, params, body }) => {
  const a = approvals.get(params[0]);
  if (!a) throw new HttpError(404, "Approval not found");
  if (body.id !== undefined && body.id !== a.id) throw new HttpError(400, "id does not match");

  const decision = String(body.decision ?? url.searchParams.get("decision") ?? "");
  if (decision !== "approved" && decision !== "declined") throw new HttpError(400, "decision must be approved or declined");

  const sig = String(body.sig ?? url.searchParams.get("sig") ?? "");
  if (!sig || !safeEqual(sig, approvalSig(db.serverSecret, a))) throw new HttpError(403, "Bad signature");

  const device = deviceAuth(req);
  if (!device) {
    if (!config.ntfy) throw new HttpError(401, "Unauthorized");
    if (a.risk === "high" && decision === "approved") {
      throw new HttpError(403, "High-risk actions must be approved inside the app");
    }
  } else if (a.risk === "high" && decision === "approved" && body.confirmed !== true) {
    throw new HttpError(403, "High-risk actions need the extra confirmation step");
  }

  const reason = typeof body.reason === "string" ? body.reason : undefined;
  const done = approvals.decide(a.id, decision, reason, device ? device.id : "notification-button");
  return { body: approvals.view(done) };
});

/* ------------------------------------------------------------------ routes: rules, settings, audit, events */

route("GET", "/v1/rules", "device", () => ({ body: { rules: db.rules } }));

route("PUT", "/v1/rules", "phone", ({ body }) => {
  const incoming = (body.rules ?? {}) as Record<string, unknown>;
  for (const [k, v] of Object.entries(incoming)) {
    if (!ACTION_TYPES.includes(k as ActionType) || !RULE_MODES.includes(v as RuleMode)) {
      throw new HttpError(400, `Invalid rule ${k}`);
    }
    db.rules[k as ActionType] = v as RuleMode;
  }
  approvals.audit("rules_updated", { detail: JSON.stringify(db.rules) });
  return { body: { rules: db.rules } };
});

route("GET", "/v1/settings", "device", () => ({ body: { timeout_seconds: db.settings.timeoutSeconds } }));

route("PUT", "/v1/settings", "phone", ({ body }) => {
  const t = Number(body.timeout_seconds);
  if (!Number.isFinite(t) || t < 30 || t > 3600) throw new HttpError(400, "timeout_seconds must be between 30 and 3600");
  db.settings.timeoutSeconds = Math.round(t);
  approvals.audit("settings_updated", { detail: `timeout ${db.settings.timeoutSeconds}s` });
  return { body: { timeout_seconds: db.settings.timeoutSeconds } };
});

route("GET", "/v1/audit", "phone", ({ url }) => {
  const limit = Math.min(Number(url.searchParams.get("limit")) || 200, 1000);
  return { body: { entries: db.audit.slice(-limit).reverse() } };
});

/** Live event stream for the watch and phone (new approvals, decisions, agent status). */
route("GET", "/v1/events", "device", ({ res, device }) => {
  sseInit(res);
  hub.add(res, device!.id);
  sseSend(res, "hello", {
    pending_count: approvals.pendingCount(),
    approvals: approvals.list("pending", 50).map((a) => approvals.view(a, true)),
  });
});

/* ------------------------------------------------------------------ routes: webhook for agents */

/** An agent asks for permission. Authenticate with `Authorization: Bearer <agent webhook secret>`. */
route("POST", "/v1/webhook/approval", "agent", async ({ agent, body }) => {
  if (body.agent_id !== undefined && body.agent_id !== agent!.id) throw new HttpError(403, "agent_id does not match this secret");
  const a = await approvals.create(agent!, body);
  return {
    status: 201,
    body: { id: a.id, status: a.status, expires_at: a.expiresAt, decision: a.status === "pending" ? undefined : a.status },
  };
});

/** Agents that cannot receive callbacks can poll for the decision. */
route("GET", "/v1/webhook/approval/:id", "agent", ({ agent, params }) => {
  const a = approvals.get(params[0]);
  if (!a || a.agentId !== agent!.id) throw new HttpError(404, "Approval not found");
  return { body: { id: a.id, decision: a.status, reason: a.reason ?? null, decided_at: a.decidedAt ?? null } };
});

/** Optional: let the agent report that it is working, so the watch can show it. */
route("POST", "/v1/webhook/status", "agent", ({ agent, body }) => {
  const status = body.status === "working" ? "working" : "idle";
  external.set(agent!.id, { status, at: Date.now() });
  hub.emit("agent_status", { agent_id: agent!.id, status: agentStatus(agent!.id) });
  return { body: { ok: true } };
});

/* ------------------------------------------------------------------ start */

const demo = seedAgents();
writeFileSync(
  join(config.dataDir, "demo-agent.json"),
  JSON.stringify({ relay_url: `http://localhost:${config.port}`, agent_id: demo.id, agent_secret: demo.webhookSecret }, null, 2),
  { mode: 0o600 },
);

setInterval(() => approvals.sweep(), 1000);
setInterval(() => hub.heartbeat(), 15_000);

function shutdown(): void {
  store.flush();
  process.exit(0);
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

server.listen(config.port, config.host, () => {
  console.log(`\nAgentWatch relay listening on ${config.host}:${config.port}`);
  console.log(`Public URL (what phone/watch use): ${config.publicUrl}`);
  if (store.created && !config.adminKey) {
    console.log(`\nAdmin key (shown once, also stored in ${join(config.dataDir, "db.json")}):\n  ${db.adminKey}\n`);
  }
  console.log(`Demo agent: ${demo.name}  (credentials in ${join(config.dataDir, "demo-agent.json")})`);
  console.log(`Push: ${config.apns ? "APNs on" : "APNs off"}, ${config.ntfy ? "ntfy on" : "ntfy off"}\n`);
});
