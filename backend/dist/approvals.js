import { approvalSig, hmacHex, newId, newToken, redactDetail } from "./crypto.js";
import { notifyNewApproval } from "./notify.js";
import { ACTION_TYPES, RISKS, } from "./types.js";
export class HttpError extends Error {
    status;
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}
function str(v, max) {
    return typeof v === "string" ? v.slice(0, max) : "";
}
export class ApprovalService {
    store;
    hub;
    constructor(store, hub) {
        this.store = store;
        this.hub = hub;
    }
    get db() {
        return this.store.db;
    }
    audit(event, extra = {}) {
        this.db.audit.push({ ts: new Date().toISOString(), event, ...extra });
        this.store.save();
    }
    get(id) {
        return this.db.approvals.find((a) => a.id === id);
    }
    pendingCount(agentId) {
        return this.db.approvals.filter((a) => a.status === "pending" && (!agentId || a.agentId === agentId)).length;
    }
    /** Public JSON shape (snake_case). The signature is only included for pending approvals. */
    view(a, withSig = false) {
        const agent = this.db.agents.find((x) => x.id === a.agentId);
        return {
            id: a.id,
            agent_id: a.agentId,
            agent_name: agent?.name ?? "Unknown agent",
            action_type: a.actionType,
            title: a.title,
            details: a.details.map(([label, value]) => ({ label, value: redactDetail(label, value) })),
            reasoning: a.reasoning,
            risk: a.risk,
            status: a.status,
            created_at: a.createdAt,
            expires_at: a.expiresAt,
            decided_at: a.decidedAt,
            decided_by: a.decidedBy,
            reason: a.reason,
            sig: withSig && a.status === "pending" ? approvalSig(this.db.serverSecret, a) : undefined,
        };
    }
    list(kind, limit = 50) {
        let items = this.db.approvals;
        if (kind === "pending") {
            items = items.filter((a) => a.status === "pending").sort((a, b) => a.expiresAt.localeCompare(b.expiresAt));
        }
        else {
            if (kind === "history")
                items = items.filter((a) => a.status !== "pending");
            items = [...items].sort((a, b) => (b.decidedAt ?? b.createdAt).localeCompare(a.decidedAt ?? a.createdAt));
        }
        return items.slice(0, limit);
    }
    /** Handle an approval request coming from an agent. */
    async create(agent, body) {
        const now = Date.now();
        let id;
        if (body.id === undefined)
            id = newId();
        else if (typeof body.id === "string" && /^[A-Za-z0-9-]{8,64}$/.test(body.id))
            id = body.id;
        else
            throw new HttpError(400, "id must be a UUID-like string");
        const existing = this.get(id);
        if (existing) {
            if (existing.agentId !== agent.id)
                throw new HttpError(409, "id already in use");
            return existing; // idempotent retry
        }
        const title = str(body.title, 200).trim();
        if (!title)
            throw new HttpError(400, "title is required");
        const actionType = ACTION_TYPES.includes(body.action_type)
            ? body.action_type
            : "other";
        const risk = RISKS.includes(body.risk) ? body.risk : "medium";
        const details = [];
        if (body.details && typeof body.details === "object" && !Array.isArray(body.details)) {
            for (const [k, v] of Object.entries(body.details).slice(0, 40)) {
                const value = typeof v === "string" ? v : JSON.stringify(v);
                details.push([k.slice(0, 60), String(value ?? "").slice(0, 500)]);
            }
        }
        else if (body.details !== undefined) {
            throw new HttpError(400, "details must be an object of key/value pairs");
        }
        // The user's configured timeout is the ceiling; an agent may ask for a shorter one.
        let expires = now + this.db.settings.timeoutSeconds * 1000;
        if (body.expires_at !== undefined) {
            const t = Date.parse(String(body.expires_at));
            if (!Number.isFinite(t))
                throw new HttpError(400, "expires_at must be an ISO 8601 date");
            if (t <= now)
                throw new HttpError(400, "expires_at is in the past");
            expires = Math.min(expires, t);
        }
        const a = {
            id,
            agentId: agent.id,
            actionType,
            title,
            details,
            reasoning: str(body.reasoning, 2000),
            risk,
            createdAt: new Date(now).toISOString(),
            expiresAt: new Date(expires).toISOString(),
            status: "pending",
            nonce: newToken(),
        };
        this.db.approvals.push(a);
        this.audit("created", { approvalId: id, agentId: agent.id, actor: "agent", detail: `${actionType} · ${risk} · ${title}` });
        // Approval rules from the iPhone app. High-risk actions can never be auto-approved.
        const mode = this.db.rules[actionType];
        if (mode === "block") {
            this.finalize(a, "declined", "rule:block", "Blocked by your approval rules", "blocked");
        }
        else if (mode === "auto" && risk !== "high") {
            this.finalize(a, "approved", "rule:auto", "Auto-approved by your approval rules", "auto_approved");
        }
        else {
            this.hub.emit("approval_created", this.view(a, true));
            this.hub.emit("agent_status", { agent_id: agent.id, status: "waiting" });
            void notifyNewApproval(this.db, agent, a);
        }
        this.store.save();
        return a;
    }
    /**
     * Record a decision from a device. Single use: only a pending, unexpired approval can be decided,
     * so replaying the same request fails with 409.
     */
    decide(id, decision, reason, actor) {
        const a = this.get(id);
        if (!a)
            throw new HttpError(404, "Approval not found");
        if (a.status !== "pending")
            throw new HttpError(409, `Already ${a.status}`);
        if (Date.parse(a.expiresAt) <= Date.now()) {
            this.finalize(a, "expired", "timeout", undefined, "expired");
            throw new HttpError(409, "Approval has expired");
        }
        this.finalize(a, decision, actor, reason?.slice(0, 500), decision);
        return a;
    }
    /** Auto-decline everything that has passed its expiry time. */
    sweep() {
        const now = Date.now();
        for (const a of this.db.approvals) {
            if (a.status === "pending" && Date.parse(a.expiresAt) <= now) {
                this.finalize(a, "expired", "timeout", undefined, "expired");
            }
        }
    }
    finalize(a, status, decidedBy, reason, auditEvent) {
        a.status = status;
        a.decidedAt = new Date().toISOString();
        a.decidedBy = decidedBy;
        if (reason)
            a.reason = reason;
        this.audit(auditEvent, { approvalId: a.id, agentId: a.agentId, actor: decidedBy, detail: reason });
        this.hub.emit("approval_resolved", this.view(a));
        this.hub.emit("agent_status", {
            agent_id: a.agentId,
            status: this.pendingCount(a.agentId) > 0 ? "waiting" : "idle",
        });
        this.store.save();
        void this.callback(a);
    }
    /** Tell the agent what happened. Signed with the agent's webhook secret; retried a few times. */
    async callback(a) {
        const agent = this.db.agents.find((x) => x.id === a.agentId);
        if (!agent || !agent.endpoint) {
            a.callbackState = "none";
            return;
        }
        a.callbackState = "pending";
        const body = JSON.stringify({
            id: a.id,
            decision: a.status,
            reason: a.reason ?? null,
            decided_at: a.decidedAt,
            decided_by: a.decidedBy,
        });
        const delays = [0, 1000, 3000];
        for (let i = 0; i < delays.length; i++) {
            if (delays[i])
                await new Promise((r) => setTimeout(r, delays[i]));
            try {
                const ts = String(Date.now());
                const res = await fetch(agent.endpoint, {
                    method: "POST",
                    headers: {
                        "content-type": "application/json",
                        "x-agentwatch-timestamp": ts,
                        "x-agentwatch-signature": "sha256=" + hmacHex(agent.webhookSecret, `${ts}.${body}`),
                    },
                    body,
                    signal: AbortSignal.timeout(8000),
                });
                if (res.ok) {
                    a.callbackState = "ok";
                    this.audit("callback_ok", { approvalId: a.id, agentId: a.agentId });
                    return;
                }
                throw new Error(`HTTP ${res.status}`);
            }
            catch (e) {
                if (i === delays.length - 1) {
                    a.callbackState = "failed";
                    this.audit("callback_failed", { approvalId: a.id, agentId: a.agentId, detail: String(e).slice(0, 200) });
                }
            }
        }
    }
}
