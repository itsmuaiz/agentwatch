/**
 * Mock agent. Sends sample approval requests to the relay and prints what you decide on your watch.
 *
 *   npm run build && npm run mock                 # all samples, 8 s apart
 *   npm run mock -- --interval 3 --risk high      # only high-risk ones, 3 s apart
 *   npm run mock -- --loop                        # keep going until Ctrl+C
 *
 * Credentials come from data/demo-agent.json (written by the relay) or from the env vars
 * RELAY_URL, AGENT_ID and AGENT_SECRET (use these to point it at a deployed relay).
 *
 * It demonstrates both ways an agent can learn the decision:
 *   1. polling GET /v1/webhook/approval/:id
 *   2. a signed callback POSTed to http://localhost:8788/callback (the demo agent's endpoint)
 */
import { createHmac, timingSafeEqual } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";

interface Creds {
  relay_url: string;
  agent_id: string;
  agent_secret: string;
}

function loadCreds(): Creds {
  if (process.env.RELAY_URL && process.env.AGENT_ID && process.env.AGENT_SECRET) {
    return { relay_url: process.env.RELAY_URL, agent_id: process.env.AGENT_ID, agent_secret: process.env.AGENT_SECRET };
  }
  const path = join(process.env.DATA_DIR ?? "./data", "demo-agent.json");
  if (!existsSync(path)) {
    console.error(`Could not find ${path}. Start the relay first, or set RELAY_URL, AGENT_ID and AGENT_SECRET.`);
    process.exit(1);
  }
  return JSON.parse(readFileSync(path, "utf8")) as Creds;
}

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(`--${name}`);
const opt = (name: string, fallback: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const creds = loadCreds();
const relay = creds.relay_url.replace(/\/+$/, "");
const interval = Number(opt("interval", "8")) * 1000;
const onlyRisk = opt("risk", "");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const samples = (JSON.parse(readFileSync(new URL("../samples/approvals.json", import.meta.url), "utf8")) as any[]).filter(
  (s) => !onlyRisk || s.risk === onlyRisk,
);

/* Receive signed callbacks from the relay. */
const callbackServer = createServer((req, res) => {
  const chunks: Buffer[] = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    const body = Buffer.concat(chunks).toString("utf8");
    const ts = String(req.headers["x-agentwatch-timestamp"] ?? "");
    const given = String(req.headers["x-agentwatch-signature"] ?? "");
    const expected = "sha256=" + createHmac("sha256", creds.agent_secret).update(`${ts}.${body}`).digest("hex");
    const ok = given.length === expected.length && timingSafeEqual(Buffer.from(given), Buffer.from(expected));
    const fresh = Math.abs(Date.now() - Number(ts)) < 5 * 60_000;
    if (!ok || !fresh) {
      console.log("   callback REJECTED (bad signature or stale timestamp)");
      res.writeHead(401).end();
      return;
    }
    const j = JSON.parse(body);
    console.log(`   callback verified: ${j.id.slice(0, 8)} -> ${j.decision}${j.reason ? ` (${j.reason})` : ""}`);
    res.writeHead(200).end("ok");
  });
});
callbackServer.on("error", (e) => console.warn("callback listener not started:", String(e)));
callbackServer.listen(8788, () => console.log("Listening for signed callbacks on :8788"));

async function api(path: string, init?: RequestInit): Promise<any> {
  const res = await fetch(relay + path, {
    ...init,
    headers: { authorization: `Bearer ${creds.agent_secret}`, "content-type": "application/json" },
  });
  const j: any = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${res.status} ${j.error ?? ""}`);
  return j;
}

async function request(sample: any): Promise<void> {
  const created = await api("/v1/webhook/approval", {
    method: "POST",
    body: JSON.stringify({ ...sample, agent_id: creds.agent_id }),
  });
  console.log(`\n-> requested "${sample.title}" [${sample.risk}]  id ${created.id.slice(0, 8)}`);
  await api("/v1/webhook/status", { method: "POST", body: JSON.stringify({ status: "working" }) }).catch(() => {});
  for (;;) {
    const r = await api(`/v1/webhook/approval/${created.id}`);
    if (r.decision !== "pending") {
      const icon = r.decision === "approved" ? "APPROVED" : r.decision === "declined" ? "DECLINED" : "EXPIRED ";
      console.log(`<- ${icon} "${sample.title}"${r.reason ? `  reason: ${r.reason}` : ""}`);
      return;
    }
    await sleep(1000);
  }
}

async function main() {
  console.log(`Mock agent -> ${relay}  (agent ${creds.agent_id.slice(0, 8)})`);
  const pending: Promise<void>[] = [];
  do {
    for (const s of samples) {
      await sleep(interval);
      pending.push(request(s).catch((e) => console.error("request failed:", String(e))));
    }
    if (flag("loop")) await sleep(30_000);
  } while (flag("loop"));
  await Promise.all(pending);
  await sleep(2000); // let the final callback arrive
  console.log("\nAll sample requests resolved.");
  process.exit(0);
}
main();
