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

### Docker setup reference
```bash
# OpenClaw runs in a node:22-slim container named "openclaw-sandbox"
# Host config is bind-mounted into the container:
#   ~/.openclaw -> /home/node/.openclaw

# The CLI inside the container is accessed via the `oc` bash function:
oc <command>

# Manually trigger a cron job (use job UUID, not name):
oc cron run <job-uuid>

# Upgrade OpenClaw to the latest version:
oc-upgrade
```

### Container boot behavior: install-once
- The container CMD uses `command -v openclaw` to check if OpenClaw is already installed.
- **First boot:** Installs OpenClaw and plugin dependencies via `npm install -g` + manual dep install (needed because `npm install -g openclaw` doesn't include plugin deps — see [#52719](https://github.com/openclaw/openclaw/issues/52719)), then starts the gateway with `--allow-unconfigured`.
- **Subsequent boots:** Skips installation and starts the gateway immediately.
- **Upgrading:** Run `oc-upgrade` which calls `openclaw update` — this upgrades the core, syncs plugin dependencies, runs doctor checks, and restarts the gateway automatically.

### Why not reinstall on every boot?
The original container CMD ran `npm install -g openclaw` on every boot to auto-update. This caused recurring problems:
- **ENOTEMPTY restart loop:** If a boot was interrupted mid-install, npm left stale temp directories (`.openclaw-*`) that blocked all future installs, putting the container in an infinite restart loop.
- **Slow boot times:** Every restart downloaded and installed 500+ packages.
- **Dependency loss:** Extra packages installed inside the container (like `grammy` for Telegram) were wiped on every boot by the fresh `npm install -g`.
- **Network dependency:** If the npm registry was slow or down, the container couldn't start.

### Gotcha: Plugin missing dependencies
- `npm install -g openclaw` does not install all plugin dependencies ([#52719](https://github.com/openclaw/openclaw/issues/52719)). This only affects first boot (the container CMD handles it manually).
- **Symptom:** Logs show `Cannot find module '<package>'` and the gateway fails to start.
- **Fix:** Run `oc-upgrade` (which calls `openclaw update` and syncs all plugin deps). If the CLI itself is broken, fall back to manual install:
  ```bash
  docker exec openclaw-sandbox bash -c "export PATH=/home/node/.npm-global/bin:\$PATH && cd /home/node/.npm-global/lib/node_modules/openclaw && npm install grammy @grammyjs/runner @grammyjs/transformer-throttler @grammyjs/types @buape/carbon @larksuiteoapi/node-sdk @slack/web-api"
  docker restart openclaw-sandbox
  ```

### Gotcha: `docker restart` vs `docker stop && docker start`
- `docker restart` preserves some in-memory state (including auth profile cooldowns).
- `docker stop && docker start` fully clears process memory — use this after fixing auth issues.

### Gotcha: Config hot reload vs restart
- Some config changes (like model selection) are hot-reloaded automatically.
- Auth profile changes require a full gateway restart (the container handles this via SIGUSR1).
- Plugin changes (adding/removing plugins) require a gateway restart, but since the container uses install-once, a `docker restart` is fast and safe.
- When in doubt, do a full `docker stop && docker start`.

### Legacy gotcha: npm ENOTEMPTY error (resolved)
> This issue has been resolved by switching to install-once boot. It is documented here for reference in case you encounter it with an older container configuration.
- **Symptom:** Container enters a restart loop with `ENOTEMPTY: directory not empty, rename '.../openclaw' -> '.../openclaw-*'`.
- **Cause:** The old container CMD ran `npm install -g openclaw` on every boot. Interrupted installs left stale temp directories.
- **Fix:** Remove stale dirs and both the existing and backup openclaw directories, then restart:
  ```bash
  docker update --restart=no openclaw-sandbox && docker stop openclaw-sandbox
  docker start openclaw-sandbox && docker exec -u root openclaw-sandbox sh -c \
    "rm -rf /home/node/.npm-global/lib/node_modules/.openclaw-* /home/node/.npm-global/lib/node_modules/openclaw"
  docker stop openclaw-sandbox
  docker update --restart=always openclaw-sandbox && docker start openclaw-sandbox
  ```
- **Permanent fix:** Recreate the container with the install-once CMD (see `wsl_automation_instructions.md` step 3).

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

## 4. Quick Checklist for New OpenClaw Setup

- [ ] Set API key consistently in `config.json` and `auth-profiles.json`
- [ ] Remove any unused auth profiles (OAuth, old API keys) from both `openclaw.json` and `auth-profiles.json`
- [ ] Configure a single primary model without fallbacks (unless you intentionally want failover)
- [ ] If adding a fallback model, update all three files: `openclaw.json`, `auth-profiles.json`, and optionally `config.json`
- [ ] Verify `auth-profiles.json` has no stale `usageStats` with error counts or failure timestamps
- [ ] After creating cron jobs, verify they have `sessionTarget: "isolated"` with Telegram delivery — or create them by asking the agent directly via Telegram
- [ ] Test a cron job manually with `oc cron run <job-uuid>` and confirm delivery arrives on Telegram
- [ ] Use `docker stop && docker start` (not just restart) after any auth-related config changes
- [ ] Verify Telegram plugin loaded (check logs for `[telegram] [default] starting provider` without `Cannot find module` errors)
- [ ] Set up Docker auto-start on WSL boot (see Section 3 and `wsl_automation_instructions.md` step 6)
- [ ] Set up Windows Task Scheduler to keep WSL alive (see Section 3 and `wsl_automation_instructions.md` step 7)

---

*Last updated: 2026-04-04*
