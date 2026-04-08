# OpenClaw AI Assistant Handoff Document

**Generated:** 2026-04-08
**Purpose:** Complete context transfer for any AI model to continue managing Young's OpenClaw deployment without starting from scratch.

---

## 1. Who Is Young?

- **Name:** Young Joo (young.k.joo@gmail.com)
- **Setup:** Runs OpenClaw (AI agent platform) on WSL2 Ubuntu inside a Docker container on a Windows laptop (16GB RAM)
- **Channels:** Telegram (primary), AgentMail (email)
- **LLM:** Google Gemini (gemini-3.1-flash-lite-preview primary, claude-sonnet-4-6 fallback)
- **Experience level:** Technical but not a sysadmin; prefers guided step-by-step instructions
- **Communication style:** Direct, wants concise answers. Gets frustrated with repeated instability.

---

## 2. Architecture Overview

```
Windows Laptop
  └── WSL2 (Ubuntu)
       ├── Docker Engine (auto-starts via .bashrc + sudoers)
       │    └── Container: openclaw-sandbox
       │         ├── Image: node:22-slim
       │         ├── Restart policy: always
       │         ├── User: runs as root (container default)
       │         ├── Volume: ~/.openclaw -> /home/node/.openclaw
       │         ├── OpenClaw installed at /home/node/.npm-global/
       │         ├── Agent: main (@JooJJBot on Telegram)
       │         ├── Agent: sysadmin (@DF_Sysop_Bot on Telegram)
       │         └── Plugin: openclaw-agentmail-listener
       │
       ├── keep-alive.sh (sleep infinity — keeps WSL alive)
       └── Windows Task Scheduler: "KeepWSLAlive" (runs keep-alive.sh at startup + logon)
```

### Key design decisions
- **Windows drive automount disabled** (`/etc/wsl.conf`) — air-gap isolation from Windows filesystem
- **No Docker Desktop** — raw Linux Docker Engine to maintain isolation
- **Install-once boot pattern** — container only installs OpenClaw on first boot; upgrades are manual via `oc-upgrade`
- **Container runs as root** but the npm prefix is at `/home/node/.npm-global` (historical artifact from earlier uid 1000 setup)

---

## 3. Current Configuration Files

### 3a. Container CMD (boot command)
```bash
bash -c 'mkdir -p /home/node/.npm-global && npm config set prefix "/home/node/.npm-global" && export PATH=/home/node/.npm-global/bin:$PATH && if ! command -v openclaw >/dev/null 2>&1; then npm install -g openclaw && cd /home/node/.npm-global/lib/node_modules/openclaw && npm install grammy @grammyjs/runner @grammyjs/transformer-throttler @grammyjs/types @buape/carbon @larksuiteoapi/node-sdk @slack/web-api; fi && (openclaw gateway --allow-unconfigured || sleep infinity)'
```

**Critical flaw (unsolved):** If the gateway crashes mid-operation, bash falls through to `sleep infinity`. Docker shows the container as "Up" but the gateway is dead. There is no auto-restart for the gateway process. This is the primary source of overnight outages.

**Proposed fix (not yet applied):** Replace `openclaw gateway || sleep infinity` with a restart loop:
```bash
while true; do openclaw gateway --allow-unconfigured; echo "[$(date)] Gateway exited, restarting in 10s..."; sleep 10; done
```
This requires recreating the container (`docker stop && docker rm && docker run ...`).

### 3b. Host path: ~/.openclaw/config.json
```json
{
  "llmProvider": "gemini",
  "gemini": {
    "apiKey": "<REDACTED — Gemini API key>"
  },
  "channels": {
    "telegram": {
      "token": "<REDACTED — main bot token>",
      "groupPolicy": "all"
    }
  }
}
```

### 3c. Container path: /home/node/.openclaw/openclaw.json (full current config)
```json
{
  "meta": {
    "lastTouchedVersion": "2026.4.5",
    "lastTouchedAt": "2026-04-07T02:42:55.841Z"
  },
  "auth": {
    "profiles": {
      "google:default": { "provider": "google", "mode": "api_key" },
      "anthropic:default": { "provider": "anthropic", "mode": "api_key" }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "google/gemini-3.1-flash-lite-preview",
        "fallbacks": ["anthropic/claude-sonnet-4-6"]
      },
      "workspace": "/home/node/.openclaw/workspace",
      "heartbeat": { "every": "1h", "target": "telegram" }
    },
    "list": [
      { "id": "main" },
      {
        "id": "sysadmin",
        "workspace": "/home/node/.openclaw/workspace/sysadmin",
        "agentDir": "/home/node/.openclaw/agents/sysadmin/agent",
        "model": { "primary": "google/gemini-3.1-flash-lite-preview" },
        "heartbeat": { "every": "0m" }
      }
    ]
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "all",
      "groups": { "*": { "requireMention": true } },
      "streaming": "partial",
      "accounts": {
        "default": { "botToken": "<REDACTED — main bot token>" },
        "sysadmin": { "botToken": "<REDACTED — sysadmin bot token>" }
      }
    }
  },
  "plugins": {
    "allow": ["google", "telegram", "anthropic", "openclaw-agentmail-listener"],
    "load": {
      "paths": [
        "/home/node/.openclaw/extensions/openclaw-agentmail-listener",
        "/home/node/.npm-global/lib/node_modules/openclaw/dist/extensions/telegram"
      ]
    },
    "entries": {
      "google": { "enabled": true },
      "telegram": { "enabled": true },
      "anthropic": { "enabled": true },
      "openclaw-agentmail-listener": {
        "enabled": true,
        "config": {
          "apiKey": "<REDACTED — AgentMail API key>",
          "inboxId": "excitedmagazine226@agentmail.to"
        }
      }
    }
  },
  "bindings": [
    { "type": "route", "agentId": "main", "match": { "channel": "telegram", "accountId": "default" } },
    { "type": "route", "agentId": "sysadmin", "match": { "channel": "telegram", "accountId": "sysadmin" } }
  ],
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback"
  }
}
```
*(Auth tokens and gateway auth token omitted for brevity but are present in the live file)*

### 3d. Bash shortcuts (~/.bashrc)
```bash
# OpenClaw shortcuts
oc() { docker exec -it openclaw-sandbox bash -c "export PATH=/home/node/.npm-global/bin:\$PATH && openclaw $*"; }
alias oc-upgrade="docker exec openclaw-sandbox bash -c 'export PATH=/home/node/.npm-global/bin:\$PATH && npm install -g openclaw && cd /home/node/.npm-global/lib/node_modules/openclaw && npm install grammy @grammyjs/runner @grammyjs/transformer-throttler @grammyjs/types @buape/carbon @larksuiteoapi/node-sdk @slack/web-api && openclaw doctor && openclaw gateway restart'"

# Auto-start Docker daemon if not running
if ! pgrep -x dockerd > /dev/null 2>&1; then
  sudo service docker start > /dev/null 2>&1
fi
```

### 3e. WSL config (/etc/wsl.conf)
```ini
[automount]
enabled = false
[interop]
appendWindowsPath = false
[boot]
command = service cron start
```

### 3f. Sysadmin agent personality (/home/node/.openclaw/workspace/sysadmin/SOUL.md)
Defines the sysadmin agent as a concise, factual system administration assistant. It can check container health, read logs, validate configs, monitor cron jobs, and troubleshoot. It does NOT modify configs directly or restart services without permission.

---

## 4. Known Issues & Recurring Problems

### 4a. Gateway crashes overnight (CRITICAL — unsolved)
- **Symptom:** Agents stop responding on Telegram. `docker ps` shows container "Up" but gateway is dead inside.
- **Root cause:** OpenClaw has unhandled promise rejections (e.g., `Agent listener invoked outside active run`) that crash the gateway process. The container CMD falls through to `sleep infinity`.
- **Current workaround:** Manual `docker restart openclaw-sandbox` each time.
- **Proper fix:** Add a restart loop to the container CMD (see Section 3a above). Requires recreating the container.

### 4b. Missing plugin dependencies (upstream bug)
- **Issue:** `npm install -g openclaw` does not include channel extension dependencies (grammy, @buape/carbon, @larksuiteoapi/node-sdk, @slack/web-api).
- **Tracking:** openclaw/openclaw#52719 (closed as fixed but NOT actually fixed in npm distribution)
- **Workaround:** Container CMD and `oc-upgrade` alias manually install these deps.
- **Risk:** Any OpenClaw update could add new undeclared dependencies that break the install.

### 4c. Plugin ownership mismatch
- **Symptom:** Logs show `blocked plugin candidate: suspicious ownership` for agentmail plugin.
- **Root cause:** Plugin files sometimes end up owned by uid 1000 while the container runs as root.
- **Fix:** `docker exec openclaw-sandbox chown -R root:root /home/node/.openclaw/extensions/openclaw-agentmail-listener`
- **Recurrence:** Can happen after plugin updates or container recreation.

### 4d. `openclaw update` is destructive — DO NOT USE
- **What it does:** Runs `npm install -g openclaw` (wipes manually-installed plugin deps), then runs `openclaw doctor` which crashes because deps are gone.
- **Use instead:** `oc-upgrade` alias (reinstalls openclaw + plugin deps + doctor + gateway restart).

### 4e. API key consistency across three files
- `config.json`, `openclaw.json` (auth profiles), and `agents/main/agent/auth-profiles.json` must all have matching API keys.
- If they diverge, the agent fails with `API_KEY_INVALID` (400) errors.
- After fixing keys, also reset `usageStats` in `auth-profiles.json` and use `docker stop && docker start` (not just restart) to clear in-memory cooldown state.

### 4f. Cron job delivery to Telegram
- Jobs with `sessionTarget: "main"` deliver to internal webchat, NOT Telegram.
- Must use `sessionTarget: "isolated"` with explicit `delivery: { mode: "announce", channel: "telegram", to: "<chat_id>" }`.
- Best practice: Create cron jobs by asking the agent via Telegram (auto-wires delivery).

### 4g. WSL2 idle shutdown
- WSL shuts down when all terminals close, killing Docker and OpenClaw.
- Fixed via Windows Task Scheduler task "KeepWSLAlive" that runs `sleep infinity` inside WSL.
- Task uses dual triggers (AtStartup + AtLogOn) to survive Windows Update reboots.
- If task state shows `267014` (terminated), run `Start-ScheduledTask -TaskName "KeepWSLAlive"` in PowerShell.

---

## 5. Common Operations

| Task | Command |
|------|---------|
| Check if gateway is alive | `docker logs --tail 5 openclaw-sandbox` |
| Restart gateway | `docker restart openclaw-sandbox` |
| Full restart (clears auth state) | `docker stop openclaw-sandbox && docker start openclaw-sandbox` |
| Upgrade OpenClaw | `oc-upgrade` |
| Run any openclaw command | `oc <command>` |
| Fix agentmail ownership | `docker exec openclaw-sandbox chown -R root:root /home/node/.openclaw/extensions/openclaw-agentmail-listener` |
| Check plugin status | `oc plugins list` |
| List agents | `oc agents list --bindings` |
| Trigger cron job | `oc cron run <job-uuid>` |
| View full config | `docker exec openclaw-sandbox cat /home/node/.openclaw/openclaw.json` |
| Check Telegram connection | `docker logs openclaw-sandbox 2>&1 \| grep telegram` |
| Check agentmail connection | `docker logs openclaw-sandbox 2>&1 \| grep agentmail` |

---

## 6. File Map

| Path (host) | Path (container) | Purpose |
|-------------|------------------|---------|
| `~/.openclaw/config.json` | `/home/node/.openclaw/config.json` | Bootstrap config |
| `~/.openclaw/openclaw.json` | `/home/node/.openclaw/openclaw.json` | Main config |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | same | Runtime auth (API keys) |
| `~/.openclaw/agents/sysadmin/agent/` | same | Sysadmin agent auth |
| `~/.openclaw/workspace/` | same | Main agent workspace |
| `~/.openclaw/workspace/sysadmin/SOUL.md` | same | Sysadmin personality |
| `~/.openclaw/extensions/openclaw-agentmail-listener/` | same | AgentMail plugin |
| `~/.openclaw/cron/jobs.json` | same | Cron job definitions |
| `~/openclaw-win/openclaw-setup-guide.md` | N/A | Detailed troubleshooting guide |
| `~/openclaw-win/wsl_automation_instructions.md` | N/A | Step-by-step setup instructions |
| `~/openclaw-win/agent_onboarding.md` | N/A | Agent onboarding guide |
| `~/keep-alive.sh` | N/A | WSL keep-alive script |
| `/etc/wsl.conf` | N/A | WSL config (automount disabled) |
| `/etc/sudoers.d/docker-service` | N/A | Passwordless sudo for Docker |

---

## 7. What Needs Fixing Next

1. **Gateway auto-restart** — The single most impactful fix. Recreate the container with a restart loop so overnight gateway crashes self-heal.

2. **Consider official OpenClaw Docker image** — If one exists, it would eliminate the plugin dependency, ownership, and boot pattern issues entirely.

3. **Agentmail plugin config validation race** — On startup, the plugin logs "invalid config" errors before config is fully resolved. These stop after a few seconds but are noisy. This is an OpenClaw framework bug.

---

## 8. Detailed Reference Documents

For deeper troubleshooting and setup procedures, read:
- `~/openclaw-win/openclaw-setup-guide.md` — Comprehensive troubleshooting (model config, cron, container management, multi-agent)
- `~/openclaw-win/wsl_automation_instructions.md` — Step-by-step initial setup (Docker, container creation, WSL persistence)
- `~/openclaw-win/agent_onboarding.md` — Adding new agents, Google Drive, AgentMail, Calendar, cron jobs

---

*Sensitive values (API keys, bot tokens) have been replaced with `<REDACTED>` placeholders. The new model should prompt you for these when needed, or read them from the live config files.*
