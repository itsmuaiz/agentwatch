# AgentWatch

Control your AI agents from your wrist. AgentWatch puts Claude and ChatGPT on your Apple Watch — approve or decline agent actions in under 3 seconds, chat by voice, and get notified the moment your agent needs you.

---

## What it does

**Approvals** — When an AI agent wants to send an email, run a command, make a purchase, or push code, it pauses and asks your watch. You see what it wants to do and why, then tap Approve or Decline. High-risk actions need a second confirmation tap.

**Chat** — Talk to any agent by voice or Scribble. Replies stream in live. Long answers show a summary with a "Show more" tap.

**Complication** — A watch face complication shows how many approvals are waiting. Tap it to open the inbox.

**iPhone app** — Manage agents, set rules (auto-approve / always block per action type), browse the audit log, and configure the relay connection.

---

## How it works

```
Your AI agent  →  Relay (Node.js)  →  Apple Watch
               ←  Decision        ←
```

The relay is a small Node.js server you run yourself. Your agents call its webhook to request approval; the watch connects via SSE and shows the request. API keys stay on the relay — the watch holds no secrets.

---

## Install

### 1 · Build the IPA

The GitHub Actions workflow builds an unsigned IPA automatically on every push.

1. Fork this repo
2. Push to `main` (or run the workflow manually from the **Actions** tab)
3. Wait ~10 minutes, then download `AgentWatch-*.ipa` from the run's **Artifacts**

### 2 · Start the relay

```bash
cd backend
cp .env.example .env        # add your relay URL and API keys
npm install
npm run build
npm start
```

The relay prints your **admin key** once on first run — copy it.

To reach the relay away from home, expose it with [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (free):
```bash
cloudflared tunnel --url http://localhost:3000
```

### 3 · Sideload the IPA

Use **[WatchBridge](https://watchbridge.app/)** or **[AltStore](https://altstore.io/)** — no paid Apple Developer account needed.

> Free Apple ID apps expire every 7 days. Re-sign weekly via WatchBridge or AltStore.

### 4 · Connect

Open **AgentWatch** on your iPhone, enter the relay URL and admin key, tap **Connect**. Credentials are pushed to the watch automatically over WatchConnectivity.

---

## Connect your agent

```http
POST /v1/webhook/approval
Authorization: Bearer <agent_secret>

{
  "action_type": "run_command",
  "title": "Deploy to production",
  "risk": "high",
  "details": { "Command": "npm run deploy", "Host": "prod-01" },
  "reasoning": "Tests pass. This is the last step.",
  "agent_id": "<your agent id>"
}
```

Poll `GET /v1/webhook/approval/:id` or receive a signed callback at your endpoint. Try the built-in mock agent to see it end-to-end:

```bash
npm run mock
# say: email Sam, run a command, buy something, push code
```

Full docs in [`docs/SETUP.md`](docs/SETUP.md).

---

## Notes

- **No push notifications** on a free Apple ID — the app uses live SSE while open and background polling as a fallback. Optional free push via [ntfy](https://ntfy.sh/) is documented in SETUP.md.
- **API keys live on the relay only.** The watch and phone hold only a device token.
- Tested on watchOS 10 / iOS 17.
