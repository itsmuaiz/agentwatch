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

The **relay** is a small server you run on your computer or a VPS. Your AI agents call the relay when they need approval. The relay forwards the request to your watch over a live connection. When you approve or decline, the relay tells the agent what you decided.

Your API keys (Anthropic, OpenAI) stay on the relay — the watch and iPhone only hold a small token to authenticate with the relay.

---

## Requirements

- A GitHub account (free)
- A free Apple ID — no paid developer account needed
- [WatchBridge](https://watchbridge.app/) or [AltStore](https://altstore.io/) installed on your iPhone and Mac
- A Mac or PC to run the relay (or any cheap VPS / cloud server)
- Node.js 20 or newer — download at [nodejs.org](https://nodejs.org/)

---

## Step 1 — Build the IPA

The app is built automatically by GitHub. You don't need Xcode.

1. Click **Fork** at the top right of this page to copy the repo to your own GitHub account
2. In your fork, go to the **Actions** tab
3. Click **Build unsigned IPA** in the left sidebar, then click **Run workflow → Run workflow**
4. Wait about 10 minutes for it to finish (the dot turns green)
5. Click the finished run, scroll to the bottom, and download the **AgentWatch-1** zip
6. Unzip it — inside is `AgentWatch.ipa`

> If the build fails, click the red run, open the **build-log** artifact, and look for the first line that says `error:`. Open an issue or ask for help.

---

## Step 2 — Start the relay

The relay is the bridge between your AI agent and your watch. Run it on any machine that stays on — your home PC, a Raspberry Pi, or a cheap VPS.

**Install Node.js** if you haven't already: [nodejs.org](https://nodejs.org/) → download the LTS version and run the installer.

**Clone and start the relay:**

```bash
# Download the project (skip if you already have it)
git clone https://github.com/itsmuaiz/agentwatch
cd agentwatch/backend

# Copy the example config
cp .env.example .env
```

Open `.env` in any text editor (Notepad, TextEdit, VS Code) and fill in:

```
PORT=3000
PUBLIC_URL=http://localhost:3000   # change this once you expose it publicly
ANTHROPIC_API_KEY=sk-ant-...       # optional — only needed for the Claude agent
OPENAI_API_KEY=sk-...              # optional — only needed for the ChatGPT agent
```

Then start it:

```bash
npm install       # downloads dependencies (one-time)
npm run build     # compiles TypeScript (one-time)
npm start
```

You should see something like:

```
AgentWatch relay listening on :3000
Admin key: aw-admin-XXXXXXXXXXXXXXXX   ← copy this, you need it in the app
```

**Copy the admin key** — you'll need it in the next step. It's only shown once (but you can find it again in `data/keys.json`).

### Make the relay reachable from outside your home network

The watch needs to reach the relay when you're away from home Wi-Fi. The easiest free option is **Cloudflare Tunnel**:

1. Install it: [developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
2. Run:
   ```bash
   cloudflared tunnel --url http://localhost:3000
   ```
3. Cloudflare prints a URL like `https://random-words.trycloudflare.com` — copy it
4. Paste that URL into `PUBLIC_URL=` in your `.env` and restart the relay

For home-only use (same Wi-Fi as your phone), `http://192.168.x.x:3000` works fine.

---

## Step 3 — Sideload the IPA

You need **WatchBridge** (easiest) or **AltStore** to install unsigned apps.

### Option A — WatchBridge (recommended)
1. Install [WatchBridge](https://watchbridge.app/) on your iPhone
2. Open WatchBridge → tap **+** → select `AgentWatch.ipa`
3. It installs the iPhone app and the watch app automatically

### Option B — AltStore
1. Install [AltStore](https://altstore.io/) on your Mac and iPhone following their guide
2. Open AltStore on your iPhone → **My Apps** → **+** → pick `AgentWatch.ipa`
3. The watch app installs via the iPhone companion app

> **Important:** Apps sideloaded with a free Apple ID expire after **7 days**. Just re-open WatchBridge or AltStore and reinstall — your data stays intact.

---

## Step 4 — Connect the app

1. Open **AgentWatch** on your iPhone
2. Enter your relay URL (e.g. `https://random-words.trycloudflare.com`) and the admin key you copied earlier
3. Tap **Connect**

The iPhone app automatically sends the connection details to your watch over Bluetooth. After a few seconds the watch app should show your agents list.

If the watch doesn't update automatically:
- Make sure both devices have Bluetooth on
- Open the Watch app on your iPhone → scroll down → tap AgentWatch → toggle it off and on
- Or open the watch app manually and tap **Enter code** to pair with a code instead (`npm run pair` on the relay prints one)

---

## Step 5 — Try it out

The relay creates a **Demo agent** automatically. Test the whole flow:

```bash
# In the backend folder:
npm run mock
```

This sends a series of fake approval requests to your watch — a fake email, command, purchase, and code push. Approve or decline them on your wrist and watch the terminal respond.

---

## Connect your own AI agent

Your agent sends a single HTTP request to the relay when it needs approval, then waits for the decision.

### The request

```bash
curl -X POST https://your-relay-url/v1/webhook/approval \
  -H "Authorization: Bearer YOUR_AGENT_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "YOUR_AGENT_ID",
    "action_type": "run_command",
    "title": "Deploy to production",
    "risk": "high",
    "details": {
      "Command": "npm run deploy",
      "Server": "prod-01"
    },
    "reasoning": "All tests passed. This is the final step to ship the fix."
  }'
```

The relay responds instantly with:
```json
{ "id": "appr_abc123", "status": "pending" }
```

### Wait for the decision

Poll every second until `decision` is no longer `"pending"`:

```bash
curl https://your-relay-url/v1/webhook/approval/appr_abc123 \
  -H "Authorization: Bearer YOUR_AGENT_SECRET"
```

```json
{ "id": "appr_abc123", "decision": "approved" }
```

Then continue (or stop) based on the decision.

### In Python

```python
import httpx, time

RELAY = "https://your-relay-url"
SECRET = "your-agent-secret"

def request_approval(title, action_type, details, reasoning, risk="medium"):
    r = httpx.post(f"{RELAY}/v1/webhook/approval",
        headers={"Authorization": f"Bearer {SECRET}"},
        json={
            "agent_id": "your-agent-id",
            "action_type": action_type,
            "title": title,
            "risk": risk,
            "details": details,
            "reasoning": reasoning,
        }
    )
    approval_id = r.json()["id"]

    # Poll until decided (default timeout: 5 minutes)
    while True:
        result = httpx.get(f"{RELAY}/v1/webhook/approval/{approval_id}",
            headers={"Authorization": f"Bearer {SECRET}"}
        ).json()
        if result["decision"] != "pending":
            return result["decision"]  # "approved" or "declined"
        time.sleep(1)

# Example usage
decision = request_approval(
    title="Send weekly report email",
    action_type="send_email",
    details={"To": "boss@example.com", "Subject": "Weekly report"},
    reasoning="You asked me to send the report every Friday.",
    risk="low",
)

if decision == "approved":
    send_the_email()
else:
    print("User declined — skipping.")
```

### Where to find your agent ID and secret

After starting the relay, they're in `backend/data/demo-agent.json`. For agents you create through the iPhone app, tap the agent → copy the webhook URL and secret shown there.

### action_type values

| value | shown as |
|---|---|
| `send_email` | Send Email |
| `run_command` | Run Command |
| `purchase` | Purchase |
| `code_push` | Code Push |
| `file_delete` | Delete Files |
| `other` | Action |

### risk levels

| value | effect |
|---|---|
| `low` | Normal approval notification |
| `medium` | Normal approval notification |
| `high` | Approve requires a second confirmation tap on the watch |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Watch shows "Offline" | Tap Settings → Reconnect in the watch app. If the relay URL changed, re-enter it on the iPhone. |
| "Invalid or expired code" | Pairing codes expire in 10 min. Run `npm run pair` again. |
| Build failed in Actions | Download `build-log-*.txt` from the failed run's Artifacts. Find the first `error:` line. |
| App expired after 7 days | Re-install via WatchBridge or AltStore — this is normal with a free Apple ID. |
| Can't reach relay away from home | Set up Cloudflare Tunnel (see Step 2) and update `PUBLIC_URL` in `.env`. |
| Complication shows "–" | App Groups aren't available without a paid developer account. Everything else works fine. |

---

## Notes

- **No push notifications** on a free Apple ID — the app uses a live connection while open and polls in the background as a fallback. Optional free push via [ntfy](https://ntfy.sh/) is documented in [`docs/SETUP.md`](docs/SETUP.md).
- **API keys stay on the relay.** The watch and phone only hold a small auth token.
- Requires watchOS 10 and iOS 17 or newer.
