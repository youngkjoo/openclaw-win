# Comprehensive Guide: OpenClaw Setup, Security Hardening & Maintenance on Apple Silicon Mac Mini

This guide serves as a single, comprehensive, step-by-step instruction manual to install, configure, secure, and maintain your exact OpenClaw environment running **"bare metal"** directly on a new Apple Silicon Mac Mini host. It preserves 100% of your histories, configurations, and memories, while introducing strict, host-level security controls, correcting broken automated backup paths, and configuring local LLMs.

---

## Table of Contents
1. [Phase 0: macOS Host Preparation & OS Hardening](#phase-0-macos-host-preparation--os-hardening)
2. [Phase 1: Homebrew & Tooling Dependencies](#phase-1-homebrew--tooling-dependencies)
3. [Phase 2: Bare-Metal Background Daemon (launchd) Setup](#phase-2-bare-metal-background-daemon-launchd-setup)
4. [Phase 3: Ollama Local AI Model Setup](#phase-3-ollama-local-ai-model-setup)
5. [Phase 4: Bare-Metal OpenClaw Configuration Mappings](#phase-4-bare-metal-openclaw-configuration-mappings)
6. [Phase 5: Advanced Security Hardening & Execution Policies](#phase-5-advanced-security-hardening--execution-policies)
7. [Phase 6: Backup Schedules, Crontabs & Private Git Backup](#phase-6-backup-schedules-crontabs--private-git-backup)
8. [Phase 7: Troubleshooting, Gotchas & Lossless Rollback Plan](#phase-7-troubleshooting-gotchas--lossless-rollback-plan)

---

## Phase 0: macOS Host Preparation & OS Hardening

Running OpenClaw bare metal directly on the host machine demands strict security measures to protect your local filesystem and API keys.

### 1. Dual-User Account Workflow
Do **not** run OpenClaw under an Administrator account.
* **Standard User Account (`dfadmin`)**: This is the standard, completely unprivileged user account. OpenClaw runs entirely under this session. Even if an agent or skill is ever compromised, it has zero administrative system access.
* **Administrator User Account (`youngjoo`)**: Use this account solely for system maintenance, package updates (e.g. global npm packages, Homebrew taps), and managing elevated privileges. 

### 2. Enable macOS Application Firewall
OpenClaw uses **outbound polling** (WebSockets) to talk to Telegram and external APIs, requiring **zero inbound network ports** from the LAN.
* Navigate to **System Settings > Network > Firewall** under the `youngjoo` account and toggle it **ON**.
* *Important:* Keep SSH active for headless administration but block all other incoming traffic.

### 3. Restrict SSH & Sharing Services
1. Go to **System Settings > General > Sharing**.
2. Toggle **OFF** all unused sharing options (File Sharing, Screen Sharing, Remote Management).
3. Under **Remote Login (SSH)**, set **"Allow access for:"** to **"Only these users:"** and explicitly whitelist the `youngjoo` admin account. *Do not allow the unprivileged `dfadmin` account to establish remote SSH shell connections directly.*

### 4. Turn on FileVault (Full Disk Encryption)
Plaintext API keys and database records are stored in your home directory. Protect against physical data extraction:
* Go to **System Settings > Privacy & Security > FileVault** and toggle it **ON**.

---

## Phase 1: Homebrew & Tooling Dependencies

On macOS, Homebrew is installed in user-space. Because `dfadmin` is a standard unprivileged user, Homebrew installation and binary writing are managed under the `youngjoo` user.

### 1. Install Homebrew
Log into the **`youngjoo`** admin account and execute:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Required Tools
Run the following Homebrew commands under the Homebrew-owning user account (`youngjoo`) to install essential tools:
```bash
brew install rclone gnu-tar jq gh
```
* **GNU Tar (`gtar`)**: macOS's default `tar` utility is BSD-based. OpenClaw backup scripts rely on **GNU Tar** for advanced path exclusions.
* **GitHub CLI (`gh`)**: Globally accessible under `/opt/homebrew/bin/gh` for managing repository snapshots.

---

## Phase 2: Bare-Metal Background Daemon (launchd) Setup

Rather than running OpenClaw in a Docker container, we run it as a native macOS background LaunchAgent daemon under the `dfadmin` session.

### 1. Register the LaunchAgent Daemon
Log into the **`dfadmin`** account and run the built-in installer to create, register, and bootstrap the `launchd` configuration:
```bash
openclaw gateway install --runtime node
```
This registers a LaunchAgent plist file at `/Users/dfadmin/Library/LaunchAgents/ai.openclaw.gateway.plist` configured to restart OpenClaw automatically if it crashes or the system boots.

### 2. Manage the Service
Use the following commands to control the background daemon under `dfadmin`:
* **Start Gateway**: `openclaw gateway start`
* **Stop Gateway**: `openclaw gateway stop`
* **Check Service State**: `openclaw gateway status`

### 3. Session Persistence & Architecture: LaunchAgent vs. LaunchDaemon
Previously, running OpenClaw in a container required keeping the `dfadmin` account graphically logged in so that the Docker Desktop GUI and virtual machine remained running. Under this native bare-metal setup, a graphical login is no longer required.

#### A. Keep `dfadmin` Logged In via Fast User Switching (Recommended)
Because OpenClaw runs as a native background **LaunchAgent** under `dfadmin`'s session:
* You do **not** need a graphical GUI window open. You can lock the screen, close all windows, or use **Fast User Switching** to log into the `youngjoo` admin account. 
* As long as the `dfadmin` session remains loaded in the background (i.e., you do not explicitly select "Log Out dfadmin" from the Apple menu), OpenClaw will continue running natively 24/7 in the background with near-zero resource usage.

#### B. Why We Do Not Use System-Level LaunchDaemons
To have OpenClaw start up automatically at boot without *ever* logging in, it would need to be registered as a system-level **LaunchDaemon** at `/Library/LaunchDaemons/`. However, this introduces significant risks and downsides:
1. **Privilege Escalation Risk (Root Access)**: LaunchDaemons run as `root` by default. If the configuration to restrict execution to `dfadmin` is ever omitted, modified, or corrupted, the agent will run with full superuser permissions. This violates our standard-user sandbox model.
2. **Operational Overhead**: Plist files in `/Library/LaunchDaemons/` are owned by root. The standard `dfadmin` user would lose the ability to start, stop, or manage the service using user-level commands, requiring `sudo` or switching to `youngjoo` for basic troubleshooting.
3. **Loss of GUI/WindowServer Context**: LaunchDaemons have zero access to the macOS graphical server. If the agent is ever programmed to run skills that automate GUI applications (like opening Apple Notes or Reminders), it will fail silently.
4. **Environment Isolation**: LaunchDaemons do not inherit standard shell environments or `.zshrc` mappings, requiring every tool, environment variable, and path to be rigidly hardcoded.

---

## Phase 3: Ollama Local AI Model Setup & launchd Daemon

Ollama runs locally on the host's Apple Silicon GPU. It is installed and run in user-space as a native background **LaunchAgent** under the **`dfadmin`** account.

### 1. Register the Ollama LaunchAgent Daemon
To ensure Ollama starts automatically at login with strict loopback binding and full hardware acceleration enabled, register it as a native macOS LaunchAgent:

1. Create the plist configuration at `/Users/dfadmin/Library/LaunchAgents/ai.openclaw.ollama.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>ai.openclaw.ollama</string>
    <key>Comment</key>
    <string>OpenClaw Ollama Local LLM Server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
      <string>/opt/homebrew/bin/ollama</string>
      <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
      <key>OLLAMA_HOST</key>
      <string>127.0.0.1</string>
      <key>OLLAMA_FLASH_ATTENTION</key>
      <string>1</string>
      <key>OLLAMA_KV_CACHE_TYPE</key>
      <string>q8_0</string>
      <key>HOME</key>
      <string>/Users/dfadmin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/dfadmin/Library/Logs/openclaw/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/dfadmin/Library/Logs/openclaw/ollama.err.log</string>
    <key>WorkingDirectory</key>
    <string>/Users/dfadmin</string>
  </dict>
</plist>
```

2. Bootstrap and start the Ollama background daemon:
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.openclaw.ollama.plist
```

### 2. GPU Optimizations Explained
* **`OLLAMA_HOST="127.0.0.1"`**: Binds Ollama strictly to loopback, blocking any network exposure.
* **`OLLAMA_FLASH_ATTENTION="1"`**: Accelerates Metal GPU parallel token generation.
* **`OLLAMA_KV_CACHE_TYPE="q8_0"`**: Uses highly optimized 8-bit quantized caching, cutting memory consumption in half without loss in precision.

### 3. Pull Local Models
Download the primary model and local fallback:
```bash
/opt/homebrew/bin/ollama pull qwen3.5:9b
/opt/homebrew/bin/ollama pull gemma4:e4b
```

---

## Phase 4: Bare-Metal OpenClaw Configuration Mappings

The bare-metal setup reads all configuration parameters natively from macOS paths rather than mapped virtual container paths.

### 1. Local Shell Aliases (`~/.zshrc`)
Comment out the old container execution variable inside `/Users/dfadmin/.zshrc` to ensure the host CLI acts natively:
```bash
# Disabled for bare-metal migration. Uncomment to rollback to Docker.
# export OPENCLAW_CONTAINER=openclaw-sandbox

oc() { openclaw "$@"; }
```

### 2. Configuration: `openclaw.json` (`~/.openclaw/openclaw.json`)
Configure your `/Users/dfadmin/.openclaw/openclaw.json` exactly as follows. All paths are resolved to `/Users/dfadmin/` and network bindings are secured.

> [!IMPORTANT]
> **Ollama Network Binding (Bare Metal vs. Docker)**:
> * **Bare Metal (Active)**: In `models.providers.ollama.baseUrl`, you **must** use `"http://127.0.0.1:11434"`. This routes local LLM queries directly via your host's native loopback port.
> * **Docker (Legacy/Rollback)**: The container used `"http://host.docker.internal:11434"`. Using `host.docker.internal` on bare metal will fail immediately with `getaddrinfo ENOTFOUND host.docker.internal` because it is a virtual hostname that only exists inside Docker's network bridge.

> [!WARNING]
> **Legacy Path Pollution (`/home/node`)**:
> Transitioning to bare metal requires a complete sweep of all internal state databases. Stale container paths (`/home/node/.openclaw/...`) inside active session pointer files (`*.trajectory-path.json`), `cron/jobs.json`, and `plugins/installs.json` will cause the gateway to fail during execution with silent `ENOENT` directory creation errors. Follow the path sweep commands in Phase 7 to guarantee a clean state.

```json
{
  "auth": {
    "profiles": {
      "google:default": {
        "provider": "google",
        "mode": "api_key"
      },
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key"
      },
      "ollama:default": {
        "provider": "ollama",
        "mode": "api_key"
      }
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434",
        "apiKey": "ollama-local",
        "auth": "api-key",
        "api": "ollama",
        "params": {
          "num_ctx": 32768
        }
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/qwen3.5:9b",
        "fallbacks": [
          "ollama/gemma4:e4b",
          "google/gemini-3.5-flash",
          "anthropic/claude-sonnet-4-6"
        ]
      },
      "models": {
        "google/gemini-2.5-flash": {
          "alias": "flash"
        },
        "anthropic/claude-sonnet-4-6": {
          "alias": "sonnet",
          "params": {
            "cacheRetention": "short"
          }
        },
        "ollama/qwen3.5:9b": {
          "alias": "qwen"
        },
        "ollama/gemma4:e4b": {
          "alias": "gemma4"
        },
        "google/gemini-3.1-pro-preview": {
          "alias": "pro"
        },
        "google/gemini-3.5-flash": {
          "alias": "flash35"
        }
      },
      "workspace": "/Users/dfadmin/.openclaw/workspace",
      "compaction": {
        "mode": "safeguard",
        "reserveTokensFloor": 20000
      },
      "heartbeat": {
        "every": "1h",
        "target": "telegram"
      },
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "1h"
      },
      "contextTokens": 32000
    },
    "list": [
      {
        "id": "main"
      }
    ]
  },
  "tools": {
    "profile": "coding",
    "web": {
      "search": {
        "provider": "gemini"
      }
    },
    "exec": {
      "host": "gateway",
      "security": "allowlist",
      "ask": "on-miss"
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "session": {
    "dmScope": "per-channel-peer"
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groups": {
        "*": {
          "requireMention": true
        }
      },
      "groupPolicy": "open",
      "streaming": {
        "mode": "partial"
      },
      "accounts": {
        "default": {
          "botToken": "YOUR_MAIN_TELEGRAM_BOT_TOKEN"
        }
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "YOUR_GATEWAY_AUTH_TOKEN"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    },
    "nodes": {
      "denyCommands": [
        "camera.snap",
        "camera.clip",
        "screen.record",
        "contacts.add",
        "calendar.add",
        "reminders.add",
        "sms.send"
      ]
    }
  },
  "bindings": [
    {
      "type": "route",
      "agentId": "main",
      "match": {
        "channel": "telegram",
        "accountId": "default"
      }
    }
  ],
  "plugins": {
    "allow": [
      "google",
      "telegram",
      "anthropic",
      "memory-core",
      "ollama",
      "active-memory"
    ],
    "entries": {
      "google": {
        "enabled": true
      },
      "telegram": {
        "enabled": true
      },
      "anthropic": {
        "enabled": true
      },
      "ollama": {
        "enabled": true
      },
      "memory-core": {
        "enabled": true,
        "config": {
          "dreaming": {
            "enabled": true,
            "model": "flash35"
          }
        }
      },
      "active-memory": {
        "enabled": true,
        "config": {
          "agents": [
            "main"
          ],
          "allowedChatTypes": [
            "direct"
          ],
          "modelFallback": "google/gemini-3-flash",
          "queryMode": "recent",
          "promptStyle": "balanced",
          "timeoutMs": 15000,
          "maxSummaryChars": 220,
          "persistTranscripts": false,
          "logging": true
        }
      }
    },
    "bundledDiscovery": "compat"
  }
}
```

---

## Phase 5: Advanced Security Hardening & Execution Policies

Because Docker is removed, OpenClaw has direct access to the host's standard user space. We lock down access using strict application-level controls:

### 1. Loopback-Only Network Binding
In `openclaw.json`, `"bind"` is set to `"loopback"`. This forces OpenClaw to bind strictly to localhost (`127.0.0.1`), physical blocking any other computer on your LAN or WiFi from hitting the local WebSocket Gateway port `18789`.

### 2. Directory Permissions Lockdown
Protect configurations, API keys, and memory DBs on the host:
```bash
chmod 700 /Users/dfadmin/.openclaw
```
This restricts read/write permissions exclusively to the `dfadmin` user.

### 3. Cautious Shell Execution Policy
OpenClaw enforces a human-in-the-loop validation process before executing *any* shell command or script:
```bash
openclaw exec-policy preset cautious
```
This configures `defaults.security` to `"allowlist"` and `defaults.ask` to `"on-miss"`. The agent **cannot** run shell tools directly. For every command execution, OpenClaw stops and sends an interactive verification request to your Telegram chat (`@JooJJBot`). It will only execute if you tap **Approve**.

* **Socket Fix**: Ensure `/Users/dfadmin/.openclaw/exec-approvals.json` maps `"socket.path"` to `/Users/dfadmin/.openclaw/exec-approvals.sock` rather than container legacy paths.

---

## Phase 6: Backup Schedules, Crontabs & Private Git Backup

Legacy automated snapshot backups were failing due to WSL2 path discrepancies (`/home/young/`). Both cron check scripts and active user crontabs have been fully repaired and corrected to macOS host paths.

### 1. Repaired Backup Verification Scripts
All path variables have been corrected to `/Users/dfadmin/` in the script directory:
* `/Users/dfadmin/openclaw-win/scripts/backup-check.sh`
* `/Users/dfadmin/openclaw-win/scripts/antigravity-backup-check.sh`

### 2. Active macOS Crontab Schedule
Open the `dfadmin` crontab using `crontab -e` and confirm that it matches the corrected host-level schedules:
```cron
# OpenClaw Snapshot Backups
0 3 * * * /Users/dfadmin/openclaw-win/scripts/openclaw-backup.sh >> /Users/dfadmin/.openclaw/logs/openclaw-backup-cron.log 2>&1
0 * * * * /Users/dfadmin/openclaw-win/scripts/backup-check.sh >> /Users/dfadmin/.openclaw/logs/openclaw-backup-check.log 2>&1

# Antigravity Snapshot Backups
15 3 * * * /Users/dfadmin/openclaw-win/scripts/antigravity-backup.sh >> /Users/dfadmin/.openclaw/logs/antigravity-backup-cron.log 2>&1
15 * * * * /Users/dfadmin/openclaw-win/scripts/antigravity-backup-check.sh >> /Users/dfadmin/.openclaw/logs/antigravity-backup-check.log 2>&1
```

### 3. Private Git Workspace Backup
Keep a persistent, encrypted Git history of your agent memories and custom skills:
1. Navigate to the local workspace:
   ```bash
   cd /Users/dfadmin/.openclaw/workspace
   ```
2. Check Git status and stage files:
   ```bash
   git status
   git add .
   git commit -m "Snapshot backup: bare-metal transition"
   ```
3. Push to your private remote repository:
   ```bash
   git push origin main
   ```

---

## Phase 7: Troubleshooting, Gotchas & Lossless Rollback Plan

### 1. Troubleshooting Tools
Use native OpenClaw tools to inspect the active bare-metal daemon:
* **Gateway Logs**: `tail -f ~/Library/Logs/openclaw/gateway.log`
* **CLI Status**: `openclaw status` (runs natively on loopback)
* **Model Test**: `openclaw model test ollama/qwen3.5:9b`

### 2. Loss-Free Rollback Procedure (Revert to Docker)
If you ever need to return to running OpenClaw in a Docker container, we have preserved the original Docker-mapped configuration backup: `/Users/dfadmin/.openclaw/openclaw.json.bak.docker`.

Follow these simple steps:
1. **Stop & Uninstall the Bare-Metal Service**:
   ```bash
   openclaw gateway stop
   openclaw gateway uninstall
   ```
2. **Re-Enable old Container Shell Shortcuts**:
   Open `/Users/dfadmin/.zshrc` and uncomment the container environment variable:
   ```bash
   export OPENCLAW_CONTAINER=openclaw-sandbox
   ```
3. **Revert Path Config Mapping**:
   ```bash
   cp /Users/dfadmin/.openclaw/openclaw.json.bak.docker /Users/dfadmin/.openclaw/openclaw.json
   ```
4. **Relaunch the Docker Sandbox Container**:
   ```bash
   docker start openclaw-sandbox
   ```
   All of your historical files, memories, and databases are preserved intact inside the `~/.openclaw` directory, and OpenClaw will resume containerized execution immediately.

### 3. Stale Container Paths Gotcha (`/home/node`)
If the Telegram bot stays stuck in a `...typing` state or hangs indefinitely, the gateway is likely encountering a silent directory creation exception:
```
ENOENT: no such file or directory, mkdir '/home/node'
```
Even after updating `openclaw.json`, legacy Docker path references (`/home/node`) can remain hardcoded inside active runtime database records. 

To completely sweep the filesystem and align all state files with your standard macOS user directory (`/Users/dfadmin`):

1. **Re-align Session Trajectory Pointers**:
   ```bash
   find /Users/dfadmin/.openclaw/agents/main/sessions/ -name "*.trajectory-path.json" -exec sed -i '' 's|/home/node|/Users/dfadmin|g' {} +
   ```
2. **Re-align Scheduled Cron Tasks**:
   ```bash
   sed -i '' 's|/home/node|/Users/dfadmin|g' /Users/dfadmin/.openclaw/cron/jobs.json
   ```
3. **Re-align Plugin Registries**:
   ```bash
   sed -i '' 's|/home/node|/Users/dfadmin|g' /Users/dfadmin/.openclaw/plugins/installs.json
   ```
4. **Clean Session Locks & Refresh Integrities**:
   Run the CLI doctor utility to purge hung locks and refresh state parameters:
   ```bash
   openclaw doctor --fix
   ```
5. **Recycle the Gateway Service**:
   ```bash
   openclaw gateway stop
   openclaw gateway start
   ```
