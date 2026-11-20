import { readFileSync } from "node:fs";
function num(name, fallback) {
    const v = Number(process.env[name]);
    return Number.isFinite(v) && v > 0 ? v : fallback;
}
function readApnsKey() {
    if (process.env.APNS_KEY_PATH)
        return readFileSync(process.env.APNS_KEY_PATH, "utf8");
    if (process.env.APNS_KEY)
        return process.env.APNS_KEY.replace(/\\n/g, "\n");
    return undefined;
}
const port = num("PORT", 8787);
const ntfyTopic = process.env.NTFY_TOPIC || undefined;
const apnsKey = readApnsKey();
export const config = {
    port,
    host: process.env.HOST ?? "0.0.0.0",
    dataDir: process.env.DATA_DIR ?? "./data",
    publicUrl: (process.env.PUBLIC_URL ?? `http://localhost:${port}`).replace(/\/+$/, ""),
    adminKey: process.env.ADMIN_KEY || undefined,
    defaultTimeoutSeconds: num("APPROVAL_TIMEOUT_SECONDS", 300),
    anthropicKey: process.env.ANTHROPIC_API_KEY || undefined,
    openaiKey: process.env.OPENAI_API_KEY || undefined,
    openaiBaseUrl: (process.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1").replace(/\/+$/, ""),
    demoCallbackUrl: process.env.DEMO_CALLBACK_URL ?? "http://localhost:8788/callback",
    ntfy: ntfyTopic
        ? {
            server: (process.env.NTFY_SERVER ?? "https://ntfy.sh").replace(/\/+$/, ""),
            topic: ntfyTopic,
            token: process.env.NTFY_TOKEN || undefined,
        }
        : undefined,
    apns: apnsKey && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_TOPIC
        ? {
            key: apnsKey,
            keyId: process.env.APNS_KEY_ID,
            teamId: process.env.APNS_TEAM_ID,
            topic: process.env.APNS_TOPIC,
        }
        : undefined,
};
