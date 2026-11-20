import { createPrivateKey, sign } from "node:crypto";
import http2 from "node:http2";
import { config } from "./config.js";
import { approvalSig, scrubText } from "./crypto.js";
/**
 * Notification text never includes the approval details, only the agent name, a short scrubbed title and the risk level.
 * Details are shown inside the app, after the device authenticates.
 */
function notificationText(agent, a) {
    return {
        title: scrubText(agent.name).slice(0, 60),
        body: `${scrubText(a.title).slice(0, 100)} · ${a.risk} risk`,
    };
}
export async function notifyNewApproval(db, agent, a) {
    const sig = approvalSig(db.serverSecret, a);
    const jobs = [];
    if (config.ntfy)
        jobs.push(sendNtfy(agent, a, sig).catch((e) => console.warn("[ntfy]", String(e))));
    if (config.apns) {
        for (const d of db.devices) {
            if (d.pushToken) {
                jobs.push(sendApns(db, d, agent, a, sig).catch((e) => console.warn("[apns]", d.name, String(e))));
            }
        }
    }
    await Promise.all(jobs);
}
/* ------------------------------------------------------------------ ntfy (free) */
async function sendNtfy(agent, a, sig) {
    const cfg = config.ntfy;
    if (!cfg)
        return;
    const { title, body } = notificationText(agent, a);
    const decisionUrl = (d) => `${config.publicUrl}/v1/approvals/${a.id}/decision?decision=${d}&sig=${encodeURIComponent(sig)}`;
    // High-risk actions are never approvable from a notification button: they need the extra confirmation inside the app.
    const actions = a.risk === "high"
        ? [
            { action: "http", label: "Decline", url: decisionUrl("declined"), method: "POST", clear: true },
            { action: "view", label: "Review", url: `agentwatch://approval/${a.id}` },
        ]
        : [
            { action: "http", label: "Approve", url: decisionUrl("approved"), method: "POST", clear: true },
            { action: "http", label: "Decline", url: decisionUrl("declined"), method: "POST", clear: true },
        ];
    const headers = { "content-type": "application/json" };
    if (cfg.token)
        headers.authorization = `Bearer ${cfg.token}`;
    const res = await fetch(cfg.server, {
        method: "POST",
        headers,
        body: JSON.stringify({
            topic: cfg.topic,
            title,
            message: body,
            priority: a.risk === "high" ? 5 : 4,
            tags: [a.risk === "high" ? "warning" : "bell"],
            actions,
        }),
        signal: AbortSignal.timeout(8000),
    });
    if (!res.ok)
        throw new Error(`ntfy responded ${res.status}`);
}
/* ------------------------------------------------------------------ APNs (needs paid developer account) */
let cachedJwt;
function b64url(buf) {
    return Buffer.from(buf).toString("base64url");
}
function apnsJwt() {
    const cfg = config.apns;
    if (!cfg)
        throw new Error("APNs not configured");
    const now = Math.floor(Date.now() / 1000);
    if (cachedJwt && now - cachedJwt.at < 50 * 60)
        return cachedJwt.token;
    const header = b64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId }));
    const claims = b64url(JSON.stringify({ iss: cfg.teamId, iat: now }));
    const data = `${header}.${claims}`;
    const signature = sign("sha256", Buffer.from(data), {
        key: createPrivateKey(cfg.key),
        dsaEncoding: "ieee-p1363",
    });
    const token = `${data}.${b64url(signature)}`;
    cachedJwt = { token, at: now };
    return token;
}
async function sendApns(db, device, agent, a, sig) {
    const cfg = config.apns;
    if (!cfg || !device.pushToken)
        return;
    const { title, body } = notificationText(agent, a);
    const payload = JSON.stringify({
        aps: {
            alert: { title, body },
            sound: "default",
            // Two categories: high-risk has no Approve button on the notification, only Decline and Review.
            category: a.risk === "high" ? "APPROVAL_HIGH" : "APPROVAL",
            "thread-id": agent.id,
        },
        approval_id: a.id,
        sig,
    });
    const host = device.pushEnv === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
    const client = http2.connect(host);
    try {
        const status = await new Promise((resolve, reject) => {
            client.on("error", reject);
            const req = client.request({
                ":method": "POST",
                ":path": `/3/device/${device.pushToken}`,
                authorization: `bearer ${apnsJwt()}`,
                "apns-topic": device.pushTopic ?? cfg.topic,
                "apns-push-type": "alert",
                "apns-priority": "10",
                "apns-expiration": String(Math.floor(Date.parse(a.expiresAt) / 1000)),
            });
            let code = 0;
            let text = "";
            req.setEncoding("utf8");
            req.on("response", (h) => {
                code = Number(h[":status"] ?? 0);
            });
            req.on("data", (c) => (text += c));
            req.on("end", () => resolve({ code, text }));
            req.on("error", reject);
            req.end(payload);
        });
        if (status.code === 410 || /BadDeviceToken|Unregistered/.test(status.text)) {
            device.pushToken = undefined; // stale token, drop it
        }
        else if (status.code !== 200) {
            throw new Error(`APNs ${status.code} ${status.text}`);
        }
    }
    finally {
        client.close();
    }
    void db;
}
