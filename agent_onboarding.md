# Agent Onboarding Guide

Welcome your new AI agent to the team! This document walks you through setting up a fully equipped OpenClaw agent with its own identity, cloud services, and communication channels — like onboarding a new hire.

> [!IMPORTANT]
> This guide assumes you have already completed the infrastructure setup from the main [README.md](./README.md) (WSL, Docker, OpenClaw container running).

---

## Step 1: Create the Agent's Google Identity

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

## Step 2: Set Up Google Drive (Cloud Backup & File Storage)

### 2a. Create the Agent's Workspace on Drive
1. Log into Google Drive as the **agent** account.
2. Create a folder structure:
   ```
   My Drive/
   ├── openclaw-backups/     # Automated backup storage
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
Add a cron job to back up OpenClaw data to Drive daily:
```bash
crontab -e
```
Add:
```cron
# Daily backup at 3am — excludes config.json for security
0 3 * * * rclone sync ~/.openclaw/workspace/ agent-drive:openclaw-backups/workspace/ --exclude config.json 2>&1 | logger -t openclaw-backup

# Weekly full backup archive (Sundays at 4am)
0 4 * * 0 tar -czf /tmp/openclaw-full-$(date +\%Y\%m\%d).tar.gz --exclude='config.json' ~/.openclaw/ && rclone copy /tmp/openclaw-full-*.tar.gz agent-drive:openclaw-backups/archives/ && rm /tmp/openclaw-full-*.tar.gz
```

---

## Step 3: Set Up Gmail (Agent Email)

### 3a. Generate an App Password
Since the agent account has 2FA enabled, you need an App Password for programmatic access:
1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) (logged in as the agent).
2. Create a new App Password:
   - App: `Mail`
   - Device: `Linux`
3. Copy the generated 16-character password — you'll need it below.

### 3b. Configure Email in OpenClaw
```bash
oc configure
```
Navigate to the email/SMTP settings and enter:
- **SMTP Host:** `smtp.gmail.com`
- **SMTP Port:** `587`
- **Username:** `myclaw.agent@gmail.com`
- **Password:** *(the App Password from Step 3a)*

### 3c. Set Up Email Forwarding (Optional)
If you want the agent to monitor incoming emails:
1. In the **agent's** Gmail settings → **Forwarding and POP/IMAP**
2. Enable IMAP access
3. Optionally set up a forwarding rule to your personal email for visibility

---

## Step 4: Set Up Google Calendar (Scheduling)

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

## Step 6: Security Boundaries

### What the Agent CAN Access
| Service | Access Level | Shared With You? |
|---|---|---|
| Google Drive | Full access to its own Drive | Via shared folders |
| Gmail | Send/receive from agent's email | Via forwarding (optional) |
| Google Calendar | Read/write its own calendar | Via calendar sharing |
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
3. **Monitor the agent's Gmail** by setting up forwarding to your personal email.
4. **Set a hard Google Cloud budget** if using any paid APIs on the agent's account.
5. **Rotate the App Password** periodically (delete and recreate in Google settings).

For a deeper dive on container-level security, Docker sandboxing, and prompt injection risks, see the [Security Reference Guide](./openclaw_security_reference.md).

---

## Step 7: Verify Everything Works

Run through this checklist to confirm your agent is fully operational:

- [ ] **Google Drive:** `rclone lsd agent-drive:` returns your folder list
- [ ] **Backup cron:** `crontab -l` shows the backup schedule
- [ ] **Telegram:** Send a message to your bot and get a response
- [ ] **Calendar:** Ask the bot "What's on my calendar today?"
- [ ] **Email:** Ask the bot to "Send a test email to my personal address"
- [ ] **Memory:** Ask the bot "What do you remember about me?" (should pull from MEMORY.md)
- [ ] **Docker health:** `docker ps` shows `openclaw-sandbox` as "Up"

---

## Quick Reference

| Action | Command |
|---|---|
| Run any OpenClaw command | `oc <command>` |
| Check bot logs | `docker logs -f openclaw-sandbox` |
| Restart the bot | `docker restart openclaw-sandbox` |
| Manual backup | `rclone sync ~/.openclaw/workspace/ agent-drive:openclaw-backups/workspace/` |
| Check backup cron | `crontab -l` |
| Test Drive connection | `rclone lsd agent-drive:` |
| View bot health | `oc health` |
| Interactive config | `oc configure` |
