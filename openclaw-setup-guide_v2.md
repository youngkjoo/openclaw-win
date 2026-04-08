# OpenClaw Setup Guide & Troubleshooting

A living document of gotchas, configuration tips, and lessons learned from debugging OpenClaw deployments.

---

## 1. Model & API Key Configuration

### Files involved
| File (host path) | File (container path) | Purpose |
|---|---|---|
| `~/.openclaw/config.json` | `/home/node/.openclaw/config.json` | Bootstrap config: LLM provider, API key, Telegram bot token |
| `~/.openclaw/openclaw.json` | `/home/node/.openclaw/openclaw.json` | Main config: model selection, fallbacks, auth profiles, channels, plugins |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | `/home/node/.openclaw/agents/main/agent/auth-profiles.json` | Runtime auth state: API keys, OAuth tokens, usage stats, cooldown state |

### Gotcha: v2 Docker Image Schema Updates
- The newest v2 Docker image expects strict variable types for `openclaw.json`.
- `channels.telegram.groupPolicy` must be `"open"` (previously `"all"`).
- `channels.telegram.streaming` must be an object (`{ "mode": "partial" }`) rather than a simple string (`"partial"`).
- If OpenClaw refuses to start looping `Config invalid`, simply edit `openclaw.json` or run `oc doctor --fix`.

### Gotcha: API key must be consistent across all three files
- `config.json` stores the API key under `gemini.apiKey`.
- `openclaw.json` declares auth profiles (e.g., `google:default` with `mode: "api_key"`).
- `auth-profiles.json` stores the **actual key the runtime uses** under `profiles.<name>.key`.
- If these diverge (e.g., you rotate a key in `config.json` but not `auth-profiles.json`), the agent will fail with `API_KEY_INVALID` (400) errors.

### Gotcha: Remove stale auth profiles completely
- If you switch from OAuth (`google-gemini-cli`) to API key (`google`), remove the OAuth profile from **both** `openclaw.json` (`auth.profiles`) and `auth-profiles.json` (`profiles`, `lastGood`, `usageStats`).
- Leftover OAuth profiles can cause the agent to attempt authentication via a provider that no longer works, burning through retry attempts and triggering cooldowns.

### Gotcha: Auth profile cooldown / disabled state
- When an API key fails repeatedly (rate limit or invalid key), OpenClaw marks the profile with `window=cooldown` or `window=disabled` and `reason=auth_permanent`.
- This state persists in memory across `docker restart`. A full `docker stop && docker start` is needed to clear in-memory state.
- After fixing the key, also reset the `usageStats` in `auth-profiles.json` — set `lastFailureAt` to `0` and `errorCount` to `0` to avoid residual cooldown behavior.

### Gotcha: Remove fallback models to avoid unnecessary rate limit hits
- If you only want to use one model, remove the `fallbacks` array from `agents.defaults.model` in `openclaw.json`.
- Leftover fallback entries cause the agent to cycle through models on failure, potentially hitting rate limits on multiple providers.

### Adding a fallback model (e.g., Anthropic)
To add a second provider as a fallback, **three files** must be updated consistently:

1. **`openclaw.json`** — Add the fallback model and auth profile:
   - Add the model to `agents.defaults.model.fallbacks`
   - Add a model entry in `agents.defaults.models`
   - Add an auth profile in `auth.profiles`

2. **`auth-profiles.json`** — Add the API key for the new provider:
   - Add a new entry in `profiles` with the API key
   - Add the provider to `lastGood`

3. **Restart the container** with `docker stop && docker start` (not just `restart`) to ensure clean state.

### Recommended: Single-model config
```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "google/gemini-3.1-pro-preview"
      },
      "models": {
        "google/gemini-3.1-pro-preview": {
          "alias": "pro"
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

### Recommended: Primary + fallback config
```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "google/gemini-3.1-pro-preview",
        "fallbacks": [
          "anthropic/claude-opus-4-6"
        ]
      },
      "models": {
        "google/gemini-3.1-pro-preview": {
          "alias": "pro"
        },
        "anthropic/claude-opus-4-6": {
          "alias": "opus"
        }
      }
    }
  },
  "auth": {
    "profiles": {
      "google:default": {
        "provider": "google",
        "mode": "api_key"
      },
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key"
      }
    }
  }
}
```
The corresponding `auth-profiles.json` must have API keys for both providers:
```json
{
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

---

## 2. Cron Jobs & Telegram Delivery

### Files involved
| File | Purpose |
|---|---|
| `~/.openclaw/cron/jobs.json` | Cron job definitions, schedules, delivery config |
| `~/.openclaw/agents/main/sessions/sessions.json` | Active session routing and delivery context |

### Gotcha: `sessionTarget: "main"` does NOT deliver to Telegram
- By default, cron jobs may be created with `"sessionTarget": "main"`, which routes to the internal `agent:main:main` session.
- This session delivers to the `webchat` channel (internal/heartbeat), **not** to Telegram.
- The job runs successfully (logs show `status: "ok"`) but the user never sees the output.

### Fix: Use `sessionTarget: "isolated"` with explicit delivery
- Cron jobs that should send results to Telegram need:
```json
{
  "sessionTarget": "isolated",
  "delivery": {
    "mode": "announce",
    "channel": "telegram",
    "to": "<telegram_chat_id>"
  }
}
```
- `isolated` means the job runs in its own session rather than injecting into an existing one.
- `announce` mode pushes the result as a new message to the specified channel.

### Gotcha: Editing `jobs.json` directly may get overwritten
- The OpenClaw gateway process manages `jobs.json` and may overwrite manual edits on reload.
- The reliable way to configure cron jobs is to **ask the agent via Telegram** to create or update them. When the agent creates jobs from within a Telegram session, it correctly wires the delivery config.

### Gotcha: Find your Telegram chat ID
- Your Telegram chat ID appears in session keys: `agent:main:telegram:direct:<chat_id>`
- Check `sessions.json` or container logs at startup for the session key.

### Recommended: Verify cron job delivery config
After setting up cron jobs, verify with:
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

---

## 3. Container Management

### Gotcha: Backups failing with "Permission denied"
- **Symptom:** Your automated backups (e.g., `tar` or `rclone`) fail because they cannot read files inside `~/.openclaw/`.
- **Cause:** The Docker container runs as `root` and creates new configuration files or logs inside the bind-mounted `~/.openclaw/` directory with `root` ownership.
- **Fix:** You must reclaim ownership for your host user. Run:
  ```bash
  sudo chown -R $USER:$USER ~/.openclaw/
  ```
  *(Note: The daily snapshot script in `~/openclaw-win/scripts/openclaw-backup.sh` handles backups and excludes files intelligently, but you must still ensure you own the files if errors arise).*

### Docker setup reference
```bash
# OpenClaw runs using the official pre-packaged image: ghcr.io/openclaw/openclaw:latest
# Host config is bind-mounted into the container:
#   ~/.openclaw -> /home/node/.openclaw

# The CLI inside the container is accessed via the `oc` bash function:
oc <command>

# Manually trigger a cron job (use job UUID, not name):
oc cron run <job-uuid>

# Upgrade OpenClaw to the latest version (pulls new image and recreates container):
oc-upgrade
```

### Official Docker Image (v2 Setup)
- We now securely run the `ghcr.io/openclaw/openclaw:latest` image inside the Docker Sandbox.
- **Auto-Restarts:** Because we no longer use a manual npm installation loop, if the `gateway` process crashes unexpectedly, Docker's native `--restart always` policy cleanly reboots it within a few seconds! This completely resolves overnight gateway stability bugs.
- **Plugins:** All plugin dependencies (like Telegram's `grammy`) are securely built into the image, eliminating `Cannot find module` bugs and `chown` file permission mismatches.
- **Config Storage:** Because OpenClaw naturally compartmentalizes its data onto the `/home/node/.openclaw` volume, upgrading images preserves all your sessions and agents organically.

### Gotcha: `EACCES: permission denied` on v2 Migration
- **Symptom:** When bootstrapping the new official image, Logs show `failed to start: Error: EACCES: permission denied` on `/home/node/.openclaw/cron/jobs.json` or config folders.
- **Cause:** Your previous custom Docker setup ran as `root`, creating config files on your WSL host owned by `root`. The new secure official image runs purely as the unprivileged `node` user (`UID 1000`).
- **Fix:** You must correctly grant file ownership to `UID 1000`. You can safely do this via an Alpine docker mount to bypass any WSL sudo prompts:
  ```bash
  docker run --rm --user root -v ~/.openclaw:/data alpine chown -R 1000:1000 /data
  ```

### Official Chaos Testing Simulator
- To prove your architecture can withstand catastrophic failures, we built an automated chaos-testing bash script.
- **Run the suite:** `~/openclaw-win/scripts/chaos-test.sh`
- **Test 1 ('Unhandled Crash'):** The script naturally assassinates (`kill -9 1`) the core node process, completely bypassing Docker's stop sequence, visually verifying whether the container seamlessly catches the orphaned unhandled-crash state and triggers the automatic `--restart always` reboot loop within seconds.
- **Test 2 ('Nuke & Rebuild'):** The script destructively stops and drops the entire container architecture, natively boots it afresh via your docker-run image command, then continuously polls its logs to physically verify the exact moment the Telegram plugin seamlessly boots from the host.

### Gotcha: `docker restart` vs `docker stop && docker start`
- `docker restart` preserves some in-memory state (including auth profile cooldowns).
- `docker stop && docker start` fully clears process memory — use this after fixing auth issues.

### Gotcha: Config hot reload vs restart
- Some config changes (like model selection) are hot-reloaded automatically.
- Auth profile changes require a full gateway restart (the container handles this via SIGUSR1).
- Plugin changes (adding/removing plugins) require a gateway restart, but a `docker restart` is fast and safe.
- When in doubt, do a full `docker stop && docker start`.

### Gotcha: Docker does not auto-start on WSL2
- WSL2 does not run systemd by default, so Docker won't start automatically after Windows sleeps, hibernates, reboots, or after `wsl --shutdown`.
- **Symptom:** `docker ps` or `oc status` fails with `Cannot connect to the Docker daemon` or `No such file or directory` for `/var/run/docker.sock`.
- **Cause:** The Docker daemon simply isn't running. The WSL instance came up fresh without starting services.
- **Fix:** Run `sudo service docker start`. The container will auto-start if its restart policy is `always`.
- **Prevention:** Add Docker auto-start to `~/.bashrc` and configure passwordless sudo for the docker service (see `wsl_automation_instructions.md` step 6).

### Gotcha: WSL2 shuts down when all terminals are closed
- **Symptom:** OpenClaw stops responding on Telegram after you close all WSL/SSH sessions. It resumes when you open a new terminal.
- **Cause:** WSL2 automatically idles and shuts down when there are no active sessions, killing Docker and the OpenClaw container.
- **Fix:** Create a Windows Scheduled Task that runs a persistent `sleep infinity` process inside WSL. This keeps WSL alive indefinitely. The script also starts Docker on launch. See `wsl_automation_instructions.md` step 7 for full setup.
- **How the chain works:** Task Scheduler runs `keep-alive.sh` at startup and login → script starts Docker and runs `sleep infinity` → Docker auto-starts the OpenClaw container (restart policy: `always`). Two triggers (AtStartup + AtLogOn) ensure the task survives unattended reboots (e.g. Windows Update).
- **Things that do NOT work (save yourself the debugging):**
  - `wsl -e /bin/true` as a periodic ping — exits too fast, `.bashrc` doesn't run for non-interactive shells so Docker never starts
  - Running the task as `SYSTEM` — WSL distributions are per-user, SYSTEM can't access yours
  - Running as your user without `S4U` principal — opens a visible console window that can be accidentally closed

---

## 4. Multi-Agent Setup

OpenClaw supports multiple agents, each with its own workspace, sessions, model, and Telegram bot. This is useful for separating concerns (e.g., a main assistant vs a sysadmin agent).

### Current agents

| Agent | Telegram Bot | Role | Heartbeat | Fallback model |
|-------|-------------|------|-----------|----------------|
| `main` | `@JooJJBot` | General assistant (default) | 1h | `claude-sonnet-4-6` |
| `sysadmin` | `@DF_Sysop_Bot` | System administration, health checks, config validation | disabled | none |

Both agents share a Telegram group ("DF Team") where they respond when mentioned (`@`).

### How it works

- Each agent has its own directory under `~/.openclaw/agents/<id>/` (sessions, auth profiles)
- Each agent has its own workspace under `~/.openclaw/workspace/<id>/` with a `SOUL.md` defining its personality
- Each agent is bound to a separate Telegram bot via `bindings` in `openclaw.json`
- The `channels.telegram.accounts` section maps account IDs to bot tokens
- Group policy is set to `all` with `requireMention: true` — bots only respond when `@`-mentioned in groups

### Adding a new agent

1. Create a new Telegram bot via BotFather (`/newbot`)
2. Add the agent:
   ```bash
   oc agents add <name> \
     --non-interactive \
     --workspace /home/node/.openclaw/workspace/<name> \
     --model google/gemini-3.1-flash-lite-preview \
     --bind telegram:<name>
   ```
3. Add the bot token to `openclaw.json` under `channels.telegram.accounts`:
   ```json5
   accounts: {
     "default": { "botToken": "<existing>" },
     "<name>": { "botToken": "<new token from BotFather>" }
   }
   ```
4. Verify bindings exist in `openclaw.json`:
   ```json5
   bindings: [
     { "agentId": "main", "match": { "channel": "telegram", "accountId": "default" } },
     { "agentId": "<name>", "match": { "channel": "telegram", "accountId": "<name>" } }
   ]
   ```
5. Create `SOUL.md` in the agent's workspace directory
6. Restart gateway: `docker restart openclaw-sandbox`
7. Pair with the new bot: send a message, then approve the pairing code:
   ```bash
   oc pairing approve telegram <CODE>
   ```

### Per-agent overrides

Agents inherit from `agents.defaults`. To override for a specific agent, add keys to its entry in `agents.list`:
- **Disable heartbeat:** `"heartbeat": { "every": "0m" }`
- **Model without fallback:** `"model": { "primary": "google/gemini-3.1-flash-lite-preview" }`
- **Restrict tools:** `"tools": { "allow": ["read", "exec"], "deny": ["write", "edit"] }`

### Plugin ownership

Plugins in `~/.openclaw/extensions/` must be owned by the same user running the gateway. If the container runs as root but plugin files are owned by uid 1000, the gateway blocks them with "suspicious ownership" warnings. Fix with:
```bash
docker exec openclaw-sandbox chown -R root:root /home/node/.openclaw/extensions/<plugin-name>
```

### Telegram group setup

To create a shared group with multiple agents:
1. Create a Telegram group and add all bots
2. Make each bot a group admin (so they can read all messages)
3. Set `groupPolicy: "all"` in `openclaw.json` under `channels.telegram`
4. With `requireMention: true`, bots only respond when `@`-mentioned

### Key constraints
- Never reuse `agentDir` across agents (causes auth/session collisions)
- Each Telegram bot token must be unique — one bot per agent
- Auth credentials are not shared between agents; each gets its own `auth-profiles.json`

---

## 5. Quick Checklist for New OpenClaw Setup

- [ ] Set API key consistently in `config.json` and `auth-profiles.json`
- [ ] Remove any unused auth profiles (OAuth, old API keys) from both `openclaw.json` and `auth-profiles.json`
- [ ] Configure a single primary model without fallbacks (unless you intentionally want failover)
- [ ] If adding a fallback model, update all three files: `openclaw.json`, `auth-profiles.json`, and optionally `config.json`
- [ ] Verify `auth-profiles.json` has no stale `usageStats` with error counts or failure timestamps
- [ ] After creating cron jobs, verify they have `sessionTarget: "isolated"` with Telegram delivery — or create them by asking the agent directly via Telegram
- [ ] Test a cron job manually with `oc cron run <job-uuid>` and confirm delivery arrives on Telegram
- [ ] Use `docker stop && docker start` (not just restart) after any auth-related config changes
- [ ] Verify Telegram plugin loaded (check logs for `[telegram] [default] starting provider` and `[telegram] [sysadmin] starting provider` without `Cannot find module` errors)
- [ ] Set up Docker auto-start on WSL boot (see Section 3 and `wsl_automation_instructions.md` step 6)
- [ ] Set up Windows Task Scheduler to keep WSL alive (see Section 3 and `wsl_automation_instructions.md` step 7)

---

*Last updated: 2026-04-07*
