# Agent Onboarding Guide

Welcome your new AI agent to the team! This document walks you through setting up a fully equipped OpenClaw agent with its own identity, cloud services, and communication channels — like onboarding a new hire.

> [!IMPORTANT]
> This guide assumes you have already completed the infrastructure setup from the main [README.md](./README.md) (WSL, Docker, OpenClaw container running).

---

## Step 1: Create the Agent's Google Identity (Optional)

> [!NOTE]
> A Google account is only needed if you want Google Drive backup or Google Calendar integration. If you only need Telegram + email, skip to Step 2.

Give your agent its own Google account so it never touches your personal data.

1. Go to [accounts.google.com/signup](https://accounts.google.com/signup) from any browser.
2. Create a new account with a clear agent identity:
   - **Name:** e.g., `Claw Agent` (or whatever you'd like to call it)
   - **Email:** e.g., `myclaw.agent@gmail.com`
   - **Password:** Use a strong, unique password. Store it in your personal password manager.
3. Complete the account setup (skip phone verification if possible, or use your phone temporarily).
4. Enable **2-Factor Authentication** on the agent's account for security:
   - Go to [myaccount.google.com/security](https://myaccount.google.com/security)
   - Turn on 2-Step Verification

---

## Step 2: Set Up Google Drive (Cloud Backup & File Storage) (Optional)

> [!NOTE]
> Requires the Google account from Step 1. Skip if not needed.

### 2a. Create the Agent's Workspace on Drive
1. Log into Google Drive as the **agent** account.
2. Create a folder structure:
   ```
   My Drive/
   ├── openclaw-backups/     # Automated backup storage
   ├── antigravity-backups/  # Gemini Antigravity conversation backups
   ├── shared-documents/     # Files shared between you and the agent
   └── agent-workspace/      # Agent's working files
   ```

### 2b. Share with Your Personal Account
1. Right-click the `shared-documents/` folder → **Share**.
2. Add your personal Google email with **Editor** access.
3. Now you can see and edit these files from your personal Drive!

### 2c. Install rclone in WSL for Automated Access
1. SSH into your WSL instance and install rclone:
   ```bash
   sudo apt update && sudo apt install -y rclone
   ```

2. Configure rclone with the agent's Google Drive (must be done **on the laptop physically** due to OAuth):
   ```bash
   rclone config
   ```
   - Name: `agent-drive`
   - Storage: `Google Drive`
   - Follow the prompts, sign in as the **agent's** Google account when the browser opens
   - Leave advanced config as defaults

3. Test the connection:
   ```bash
   rclone lsd agent-drive:
   ```
   You should see the folders you created. *(Note: use `lsd` not `ls` — `ls` only lists files, not empty folders!)*

### 2d. Automate Daily Backups
Two backup jobs run on cron: one for OpenClaw config/data, one for Gemini Antigravity conversations. Scripts live in `~/openclaw-win/scripts/`; all logs go to `~/.openclaw/logs/`.

1. Create the log directory and ensure scripts are executable:
   ```bash
   mkdir -p ~/.openclaw/logs
   chmod +x ~/openclaw-win/scripts/openclaw-backup.sh
   chmod +x ~/openclaw-win/scripts/backup-check.sh
   chmod +x ~/openclaw-win/scripts/antigravity-backup.sh
   chmod +x ~/openclaw-win/scripts/antigravity-backup-check.sh
   ```

2. Add cron jobs for both daily scheduled backups and their catch-up checks (catch-up handles missed runs if the laptop was asleep at the scheduled time):
   ```bash
   crontab -e
   ```
   Add:
   ```cron
   # OpenClaw Snapshot Backups
   # Daily backup at 3:00am — excludes config.json for security
   0 3 * * * ~/openclaw-win/scripts/openclaw-backup.sh >> ~/.openclaw/logs/openclaw-backup-cron.log 2>&1
   # Hourly catch-up check (runs backup if laptop was asleep during 3am)
   0 * * * * ~/openclaw-win/scripts/backup-check.sh >> ~/.openclaw/logs/openclaw-backup-check.log 2>&1

   # Antigravity Snapshot Backups (staggered 15 min after OpenClaw to avoid simultaneous uploads)
   # Daily backup at 3:15am
   15 3 * * * ~/openclaw-win/scripts/antigravity-backup.sh >> ~/.openclaw/logs/antigravity-backup-cron.log 2>&1
   # Hourly catch-up check
   15 * * * * ~/openclaw-win/scripts/antigravity-backup-check.sh >> ~/.openclaw/logs/antigravity-backup-check.log 2>&1
   ```

   **Log files** (all under `~/.openclaw/logs/`):
   - `openclaw-backup.log` / `antigravity-backup.log` — per-run detail written by each script
   - `*-backup-cron.log` — daily cron stdout/stderr
   - `*-backup-check.log` — hourly catch-up cron stdout/stderr

   **Success markers** (timestamps, not logs): `~/.openclaw/last_backup_success` and `~/.gemini/antigravity/last_backup_success`

> [!IMPORTANT]
> Since the Docker container writes log files as `root` inside the `~/.openclaw/` directory, you must run `sudo chown -R $USER:$USER ~/.openclaw/` periodically or whenever new agents are created, otherwise the `tar` backup command will fail with a "Permission denied" error.

---

## Step 3: Set Up AgentMail (Agent Email)

[AgentMail](https://agentmail.to) provides disposable email inboxes purpose-built for AI agents — no Google account, App Passwords, or IMAP configuration needed.

### 3a. Create an AgentMail Account and Inbox
1. Sign up at [agentmail.to](https://agentmail.to) and get your API key.
2. Create an inbox via the dashboard or API:
   ```bash
   curl -X POST https://api.agentmail.to/v0/inboxes \
     -H "Authorization: Bearer YOUR_AGENTMAIL_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"username": "myagent"}'
   ```
   This gives your agent an email address like `myagent@agentmail.to`.

### 3b. Install the AgentMail Listener Plugin
The AgentMail WebSocket listener plugin gives your agent **real-time** email notifications — it receives emails instantly as they arrive.

```bash
oc plugins install @openclaw/agentmail-listener
```

Configure the plugin by adding the AgentMail settings to `~/.openclaw/openclaw.json` under the `plugins.entries` section:
```json
{
  "plugins": {
    "entries": {
      "openclaw-agentmail-listener": {
        "enabled": true,
        "config": {
          "apiKey": "YOUR_AGENTMAIL_API_KEY",
          "inboxId": "myagent@agentmail.to",
          "sessionKey": "agent:main:telegram:direct:YOUR_CHAT_ID"
        }
      }
    }
  }
}
```
> [!NOTE]
> Setting `sessionKey` ensures notifications are delivered to your private DM. Your chat ID can be found in `sessions.json`.

Restart the container to activate:
```bash
docker stop openclaw-sandbox && docker start openclaw-sandbox
```

Verify the listener is connected by checking the logs:
```bash
docker logs openclaw-sandbox 2>&1 | grep agentmail
```
You should see:
```
agentmail-listener: connected to wss://ws.agentmail.to/v0, subscribing to myagent@agentmail.to
agentmail-listener: subscribed (org=...)
```

### 3c. Set Up Catch-Up Polling (Resilience)
The WebSocket listener only works while OpenClaw is running. If WSL, Docker, or the container goes down, emails received during the outage would be missed. A catch-up cron job solves this by polling for unread emails on a schedule.

Ask your agent via Telegram to create the cron job:
> "Create an hourly cron job called 'check-agentmail' that uses web_fetch to GET `https://api.agentmail.to/v0/inboxes/myagent@agentmail.to/messages?labels=unread` with Authorization header `Bearer YOUR_AGENTMAIL_API_KEY`. For each unread message, process the email content, then PATCH `https://api.agentmail.to/v0/inboxes/myagent@agentmail.to/messages/{message_id}` with body `{"add_labels":["read"],"remove_labels":["unread"]}` to mark it as read. Deliver results to Telegram."

The agent will create the job with the correct delivery config. Verify:
```bash
docker exec openclaw-sandbox cat /home/node/.openclaw/cron/jobs.json | \
  python3 -c "
import sys,json
jobs=json.load(sys.stdin)['jobs']
for j in jobs:
    if 'agentmail' in j.get('name',''):
        print(f\"name={j['name']}\")
        print(f\"  schedule={j['schedule']}\")
        print(f\"  target={j.get('sessionTarget')}\")
        print(f\"  delivery={j.get('delivery')}\")
        print(f\"  state.lastDeliveryStatus={j.get('state',{}).get('lastDeliveryStatus','N/A')}\")
"
```

> [!TIP]
> **How the two mechanisms work together:**
> - **WebSocket listener** handles real-time delivery when OpenClaw is running (instant, no extra API calls).
> - **Cron polling** catches up on anything missed during downtime (hourly, uses the `unread` label filter so it never reprocesses emails the listener already handled).
> - Both use AgentMail's label system (`unread`/`read`) for deduplication — no email is processed twice.

### 3d. Test Email Delivery
Send a test email to your agent's address from any email client:
```
To: myagent@agentmail.to
Subject: Test
Body: Hello agent!
```

You should receive a Telegram notification within seconds (via the WebSocket listener). If the container was down when the email arrived, the next hourly cron run will pick it up.

---

## Step 4: Set Up Google Calendar (Scheduling) (Optional)

> [!NOTE]
> Requires the Google account from Step 1. Skip if not needed.

### 4a. Share Your Calendar with the Agent
1. Go to [calendar.google.com](https://calendar.google.com) logged into **your personal** account.
2. Click the three dots next to your calendar → **Settings and sharing**.
3. Under "Share with specific people", add the agent's email (`myclaw.agent@gmail.com`).
4. Set permission: **Make changes to events** (so the agent can create/edit events for you).

### 4b. Share the Agent's Calendar with You
1. Log into Google Calendar as the **agent** account.
2. Share the agent's default calendar with your personal email.
3. This gives you visibility into any events the agent creates.

### 4c. Configure Calendar Access in OpenClaw
If OpenClaw supports Google Calendar integration via plugin:
```bash
oc plugins list
# Look for a calendar plugin and install it
oc plugins install @openclaw/google-calendar
```
Follow the plugin's configuration instructions to connect the agent's Google account.

---

## Step 5: Set Up Communication Channels

### 5a. Telegram Bot (Primary)
If you already have a Telegram bot configured, this is done! The bot token lives in your `~/.openclaw/config.json`.

To create a new one:
1. Message [@BotFather](https://t.me/BotFather) on Telegram.
2. Send `/newbot` and follow the prompts.
3. Copy the Bot Token and configure:
   ```bash
   oc configure
   ```
   Add the token under the Telegram channel settings.

### 5b. Slack (Optional)
```bash
oc plugins install @openclaw/slack
oc configure
```
Follow the Slack integration prompts to connect a workspace.

---

## Step 6: Configure the LLM Model & API Keys

OpenClaw uses **three configuration files** that must stay consistent. Mismatches between them are the #1 cause of agent failures.

| File (host path) | Purpose |
|---|---|
| `~/.openclaw/config.json` | Bootstrap: LLM provider, API key, Telegram bot token |
| `~/.openclaw/openclaw.json` | Main config: model selection, fallbacks, auth profiles |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | Runtime auth state: actual API keys the agent uses |

### 6a. Single Model Setup (Recommended to Start)
In `openclaw.json`, configure a single primary model with no fallbacks:
```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "google/gemini-3.1-flash-lite-preview"
      },
      "models": {
        "google/gemini-3.1-flash-lite-preview": {
          "alias": "flash"
        }
      }
    }
  },
  "auth": {
    "profiles": {
      "google:default": {
        "provider": "google",
        "mode": "api_key"
      }
    }
  }
}
```

In `auth-profiles.json`, set the matching API key:
```json
{
  "version": 1,
  "profiles": {
    "google:default": {
      "type": "api_key",
      "provider": "google",
      "key": "YOUR_GEMINI_API_KEY"
    }
  },
  "lastGood": {
    "google": "google:default"
  }
}
```

Verify `config.json` has the same key under `gemini.apiKey`.

### 6b. Adding a Fallback Model (Optional)
To add a second provider (e.g., Anthropic) as a fallback, update **all three files**:

1. **`openclaw.json`** — Add the fallback and auth profile:
   ```json
   {
     "agents": {
       "defaults": {
         "model": {
           "primary": "google/gemini-3.1-flash-lite-preview",
           "fallbacks": ["anthropic/claude-sonnet-4-6"]
         },
         "models": {
           "google/gemini-3.1-flash-lite-preview": { "alias": "flash" },
           "anthropic/claude-sonnet-4-6": { "alias": "sonnet" }
         }
       }
     },
     "auth": {
       "profiles": {
         "google:default": { "provider": "google", "mode": "api_key" },
         "anthropic:default": { "provider": "anthropic", "mode": "api_key" }
       }
     }
   }
   ```

2. **`auth-profiles.json`** — Add the new provider's API key:
   ```json
   {
     "version": 1,
     "profiles": {
       "google:default": {
         "type": "api_key",
         "provider": "google",
         "key": "YOUR_GEMINI_API_KEY"
       },
       "anthropic:default": {
         "type": "api_key",
         "provider": "anthropic",
         "key": "YOUR_ANTHROPIC_API_KEY"
       }
     },
     "lastGood": {
       "google": "google:default",
       "anthropic": "anthropic:default"
     }
   }
   ```

3. **Restart the container** with `docker stop && docker start` (not just `restart`) to ensure clean auth state.

> [!WARNING]
> **Common pitfalls with API keys and models:**
> - If `config.json` and `auth-profiles.json` have different API keys, the agent fails with `API_KEY_INVALID` (400) errors.
> - Leftover OAuth profiles or old API keys in `auth-profiles.json` cause the agent to attempt dead authentication paths.
> - When an API key fails repeatedly, OpenClaw marks the profile as `window=disabled` with `reason=auth_permanent`. This state persists across `docker restart` — you need `docker stop && docker start` to clear it. Also reset `usageStats` in `auth-profiles.json` (set `errorCount` to `0` and `lastFailureAt` to `0`).
> - Leftover fallback model entries cause the agent to cycle through models on failure, potentially hitting rate limits on multiple providers.
> - Plugins require additional packages (grammy, @buape/carbon, @larksuiteoapi/node-sdk, @slack/web-api). If logs show `Cannot find module '<package>'`, run `oc-upgrade` to reinstall all dependencies.
>
> For detailed troubleshooting, see the [Setup Guide](./openclaw-setup-guide.md).

---

## Step 7: Set Up Cron Jobs (Scheduled Tasks)

OpenClaw supports cron jobs for recurring tasks — daily reports, status checks, email polling, reminders, etc.

### 7a. Creating Cron Jobs
The most reliable way to create cron jobs is to **ask the agent via Telegram**. When the agent creates jobs from within a Telegram session, it correctly wires the delivery config.

Example prompt:
> "Create a daily cron job at 8am PT called 'daily-report' that reviews today's chat history and sends me a brief summary."

### 7b. Cron Job Delivery to Telegram
For cron job output to reach you on Telegram, the job must have:
```json
{
  "sessionTarget": "isolated",
  "delivery": {
    "mode": "announce",
    "channel": "telegram",
    "to": "YOUR_TELEGRAM_CHAT_ID"
  }
}
```

> [!WARNING]
> **`sessionTarget: "main"` does NOT deliver to Telegram.** It routes output to the internal `webchat` channel. The job runs successfully (logs show `status: ok`) but you never see the output. Always use `"isolated"` with explicit delivery config.

### 7c. Finding Your Telegram Chat ID
Your chat ID appears in session keys. Check the container logs at startup:
```bash
docker logs openclaw-sandbox 2>&1 | grep "telegram.*direct"
```
Look for a session key like `agent:main:telegram:direct:<chat_id>`.

### 7d. Verify Cron Job Config
After setting up jobs, verify all of them have correct delivery:
```bash
docker exec openclaw-sandbox cat /home/node/.openclaw/cron/jobs.json | \
  python3 -c "
import sys,json
jobs=json.load(sys.stdin)['jobs']
for j in jobs:
    print(f\"{j['name']}: target={j.get('sessionTarget','N/A')}, delivery={j.get('delivery','N/A')}\")
"
```
Every job should show `target=isolated` and `delivery={'mode': 'announce', 'channel': 'telegram', 'to': '<your_chat_id>'}`.

### 7e. Manually Trigger a Cron Job
To test a job immediately:
```bash
docker exec openclaw-sandbox bash -c "export PATH=/home/node/.npm-global/bin:\$PATH && openclaw cron run <job-uuid>"
```
You can find job UUIDs in `~/.openclaw/cron/jobs.json`.

> [!NOTE]
> **Editing `jobs.json` directly may get overwritten.** The OpenClaw gateway manages this file and may overwrite manual edits on reload. Always create or update jobs by asking the agent via Telegram.

---

## Step 8: Security Boundaries

### What the Agent CAN Access
| Service | Access Level | Shared With You? |
|---|---|---|
| AgentMail | Send/receive from agent's inbox | Via Telegram notifications |
| Google Drive | Full access to its own Drive (if configured) | Via shared folders |
| Google Calendar | Read/write its own calendar (if configured) | Via calendar sharing |
| Your Calendar | Read/write (if you shared it) | You control the permission |
| OpenClaw Workspace | Full access to `~/.openclaw/` | Via Docker volume mount |

### What the Agent CANNOT Access
- Your personal Google Drive, Gmail, or contacts
- Your Windows files (automount bridge severed)
- The host WSL system outside Docker (sandboxed)
- Any accounts you haven't explicitly shared

### Security Best Practices
1. **Never share your personal Google password** with the agent account.
2. **Review shared folder permissions** periodically — remove any shares you no longer need.
3. **Set a hard Google Cloud budget** if using any paid APIs on the agent's account.
4. **Rotate API keys** periodically and update all three config files consistently.
5. **Keep the Telegram bot private** — never share the Bot Token, and consider whitelisting only your Telegram User ID.

For a deeper dive on container-level security, Docker sandboxing, and prompt injection risks, see the [Security Reference Guide](./openclaw_security_reference.md).

---

## Step 9: Verify Everything Works

Run through this checklist to confirm your agent is fully operational:

- [ ] **Telegram:** Send a message to your bot and get a response
- [ ] **AgentMail (real-time):** Send an email to the agent's inbox and receive a Telegram notification within seconds
- [ ] **AgentMail (catch-up):** Trigger the `check-agentmail` cron job manually and confirm delivery
- [ ] **Cron jobs:** All jobs show `sessionTarget: "isolated"` with Telegram delivery config
- [ ] **API key consistency:** `config.json` and `auth-profiles.json` have the same API key
- [ ] **Docker health:** `docker ps` shows `openclaw-sandbox` as "Up"
- [ ] **Memory:** Ask the bot "What do you remember about me?" (should pull from memory)
- [ ] **Google Drive:** `rclone lsd agent-drive:` returns your folder list (if configured)
- [ ] **Calendar:** Ask the bot "What's on my calendar today?" (if configured)

---

## Quick Reference

| Action | Command |
|---|---|
| Run any OpenClaw command | `oc <command>` |
| Check bot logs | `docker logs -f openclaw-sandbox` |
| Restart the bot (soft) | `docker restart openclaw-sandbox` |
| Restart the bot (full, clears auth state) | `docker stop openclaw-sandbox && docker start openclaw-sandbox` |
| Upgrade OpenClaw | `oc-upgrade` |
| List agents | `oc agents list --bindings` |
| Add a new agent | `oc agents add <name> --non-interactive --workspace ... --model ... --bind telegram:<name>` |
| Approve Telegram pairing | `oc pairing approve telegram <CODE>` |
| Trigger a cron job | `oc cron run <job-uuid>` |
| Verify cron delivery config | See Step 7d above |
| Manual backup | `rclone sync ~/.openclaw/workspace/ agent-drive:openclaw-backups/workspace/` |
| Check backup cron | `crontab -l` |
| Test Drive connection | `rclone lsd agent-drive:` |
| View bot health | `oc health` |
| Interactive config | `oc configure` |

---

## Troubleshooting

- **Telegram Bot Not Responding in Groups?**
  1. **Disabled Bot Privacy:** Ensure `/setprivacy` is "Disabled" in @BotFather.
  2. **Promote to Admin:** Make the bot an administrator in the group.
  3. **Explicit Chat ID:** If the bot still ignores mentions, add the group's explicit ID to `openclaw.json` (e.g., `-123456789`) as the wildcard `"*"` can sometimes fail.
  4. **Wake Up Connection:** Send `/start@BotUsername` directly in the group.

For more detailed debugging of common issues (API key mismatches, auth cooldowns, cron delivery failures, npm ENOTEMPTY errors, Docker/WSL persistence), see the [OpenClaw Setup Guide](./openclaw-setup-guide.md).
