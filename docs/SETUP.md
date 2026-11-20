# AgentWatch – Setup Guide

AgentWatch is an Apple Watch remote control for Claude and ChatGPT agents.
It has three parts: a **relay** (Node.js backend), an **iPhone companion app**, and the **watch app**.

---

## What you need

| Thing | Free? | Notes |
|---|---|---|
| GitHub account | ✅ | For the CI build |
| Apple ID (free) | ✅ | For WatchBridge / AltStore sideloading |
| VPS or home server with public IP | Varies | For the relay; a free Cloudflare Tunnel works too |
| Node.js 20+ on that server | ✅ | |

**No paid Apple Developer account required.**  
Push notifications will not work (Apple restricts APNs to paid accounts). The app uses live SSE while open and background polling as a fallback. You can optionally enable [ntfy](https://ntfy.sh/) push (free) for background notifications.

---

## 1 · Build the IPA

1. **Fork** this repository to your GitHub account.
2. Push to `main` (or run the workflow manually from the **Actions** tab).
3. Wait ~10 minutes for the build to finish.
4. Download `AgentWatch-<n>.ipa` from the **Artifacts** section of the run.

> **If the build fails:** download `build-log-<n>.txt`, find the first `error:` line, fix it, and push again. Swift compiler errors are the most likely cause.

---

## 2 · Start the relay

```bash
git clone https://github.com/YOUR_USERNAME/AgentWatch
cd AgentWatch/backend
cp .env.example .env
# Edit .env:
#   PUBLIC_URL=https://your-relay-url.example.com
#   PORT=3000
#   ANTHROPIC_API_KEY=sk-ant-...   (optional)
#   OPENAI_API_KEY=sk-...          (optional)
npm install
npm run build
npm start
```

The relay prints your **admin key** once on first run. Copy it – you need it in the app.

### Expose the relay publicly

The watch needs HTTPS to reach the relay away from home.

**Option A – Cloudflare Tunnel (free)**
```bash
cloudflared tunnel --url http://localhost:3000
# Cloudflare prints a *.trycloudflare.com URL. Use that as PUBLIC_URL.
```

**Option B – ngrok (free tier)**
```bash
ngrok http 3000
```

**Option C – VPS reverse proxy** (nginx/Caddy with a real domain + TLS cert).

For LAN-only use (home Wi-Fi, same network) you can use `http://` – the app allows local networking.

---

## 3 · Install the IPA

### WatchBridge (recommended)
1. Open WatchBridge on your iPhone.
2. Import `AgentWatch.ipa`.
3. Install to watch.

### AltStore
1. Install [AltStore](https://altstore.io/) on your iPhone and Mac.
2. Open AltStore on iPhone → **My Apps** → **+** → select the IPA.
3. The watch app installs automatically via the companion app.

> **Free Apple ID limit:** apps signed with a free account expire after **7 days**. Re-install through WatchBridge/AltStore each week.

---

## 4 · Connect the iPhone app

1. Open **AgentWatch** on your iPhone.
2. It prompts for the relay URL and admin key.
3. Tap **Connect**. The app pairs itself and sends credentials to your watch via WatchConnectivity.

The watch app shows the relay URL input screen until creds arrive. If WatchConnectivity is slow:
- On your iPhone: Settings → Apple Watch → tick "AgentWatch".
- Or enter a pairing code manually on the watch (see below).

---

## 5 · Manual pairing (alternative)

If the automatic transfer does not work:

```bash
# On the relay server:
npm run pair
# Prints: XXXX-XXXX  (valid 10 minutes)
```

On the watch: tap **Enter code** on the pairing screen, fill in the relay URL and the code.

---

## 6 · Connect your AI agent

The relay exposes a webhook your agent calls to request approval:

```
POST https://your-relay-url/v1/webhook/approval
Authorization: Bearer <agent_secret>
Content-Type: application/json

{
  "action_type": "run_command",
  "title": "Deploy to production",
  "risk": "high",
  "details": { "Command": "npm run deploy", "Host": "prod-01" },
  "reasoning": "Tests pass. This is the last step.",
  "agent_id": "<your agent id>"
}
```

The relay responds immediately with `{ "id": "...", "status": "pending" }`.
Poll `GET /v1/webhook/approval/:id` or receive a signed callback at your `endpoint`.

The relay seeds three agents automatically:
- **Demo** – no API key needed; type anything
- **Claude** – add your Anthropic key in `.env`
- **ChatGPT** – add your OpenAI key in `.env`

Webhook secrets and agent IDs are in `data/demo-agent.json` after first start.

Try the mock agent to see approvals on your wrist:
```bash
npm run build && npm run mock
# Type: email Sam, run a command, buy something, push code
```

---

## 7 · Optional ntfy push notifications

For background approvals without APNs:

```bash
# In .env:
NTFY_URL=https://ntfy.sh/YOUR-UNIQUE-TOPIC
NTFY_TOKEN=                      # leave blank for public topics
```

Install the [ntfy app](https://ntfy.sh/) on your iPhone, subscribe to `YOUR-UNIQUE-TOPIC`.  
Approval notifications arrive with **Approve** and **Decline** action buttons.  
> The button URLs contain a single-use signed token. Each approval can only be acted on once.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Watch shows "Offline" | The SSE connection dropped. Tap Settings → Reconnect, or force-close and reopen the app. |
| "Invalid or expired code" | Pairing codes expire in 10 minutes. Run `npm run pair` again. |
| Complication shows "–" | App Groups entitlement not applied (free sideloading limitation). The rest of the app works fine. |
| Build error in Actions | Download `build-log-*.txt`. Find the first `error:` line and fix the Swift source. |
| Watch app expires after 7 days | Re-sign and re-install via WatchBridge/AltStore. |
| `npm start` fails with EADDRINUSE | Another process is using port 3000. Set `PORT=3001` in `.env`. |

---

## Security notes

- **API keys live on the relay only.** The watch and phone hold only a device token.  
- Each approval carries a single-use HMAC signature. Replaying an approved decision returns 409.  
- The audit log is append-only and stored in `data/audit.json`.  
- Tokens are stored in the iPhone Keychain behind Face ID / passcode (iOS) and in UserDefaults (watchOS – protected by the watch passcode).  
- The relay signs callbacks with `x-agentwatch-signature: sha256=HMAC(secret, timestamp.body)`. Verify this in your agent before trusting a decision.

---

## Directory layout

```
AgentWatch/
├── backend/          Node.js relay (TypeScript)
│   ├── src/
│   ├── samples/      Sample approval requests for the mock agent
│   └── .env.example
├── Shared/           Swift code shared by iOS + watchOS
├── WatchApp/         watchOS app
├── iOSApp/           iPhone companion app
├── Complication/     WidgetKit complication for Apple Watch
├── docs/             This guide
├── project.yml       XcodeGen spec
└── .github/workflows/build.yml   CI build
```
