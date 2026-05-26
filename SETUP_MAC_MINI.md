# Comprehensive Guide: OpenClaw Setup, Security Hardening & Maintenance on Apple Silicon Mac Mini

This guide serves as a single, comprehensive, step-by-step instruction manual to install, configure, secure, and maintain your exact OpenClaw environment on a new Apple Silicon Mac Mini host. It consolidates all system architecture, dependencies, local AI model setups, multi-agent configurations, troubleshooting gotchas, and advanced security practices into a single workflow.

---

## Table of Contents
1. [Phase 0: macOS Host Preparation & OS Hardening](#phase-0-macos-host-preparation--os-hardening)
2. [Phase 1: Homebrew & Tooling Dependencies](#phase-1-homebrew--tooling-dependencies)
3. [Phase 2: Docker Desktop & Isolated Sandboxing](#phase-2-docker-desktop--isolated-sandboxing)
4. [Phase 3: Ollama Local AI Model Setup](#phase-3-ollama-local-ai-model-setup)
5. [Phase 4: OpenClaw Configurations & Mappings](#phase-4-openclaw-configurations--mappings)
6. [Phase 5: VFS Mount EPERM Patch for Command Runner](#phase-5-vfs-mount-eperm-patch-for-command-runner)
7. [Phase 6: Backup Schedules & Host Cron Permissions](#phase-6-backup-schedules--host-cron-permissions)
8. [Phase 7: Gotchas, Troubleshooting & Chaos Testing](#phase-7-gotchas-troubleshooting--chaos-testing)

---

## Phase 0: macOS Host Preparation & OS Hardening

OpenClaw runs autonomously and holds the keys to cloud LLM billing accounts and local command execution. Keeping the host operating system strictly secured is critical.

### 1. Dual-User Account Workflow
Do **not** run OpenClaw under an Administrator account. 
- Create a dedicated **Standard User** (e.g., `youngjoo` or `openclaw`) for running the OpenClaw service and local Ollama runtime.
- Use your separate **Administrator User** (e.g., `dfadmin`) solely for managing system-wide apps, privileges, and the Docker daemon.

### 2. Enable macOS Application Firewall
OpenClaw uses **outbound polling** (WebSockets) to talk to Telegram and external APIs, meaning it requires **zero open inbound network ports**.
- Log in as your Admin user, navigate to **System Settings > Network > Firewall**, and toggle it **ON**.
- *Important:* Do **NOT** click "Block all incoming connections" in the Options menu if you are managing the Mac Mini headlessly via SSH, as this will lock out your SSH session. Turning the Firewall ON keeps your explicitly allowed Sharing services (SSH) active while blocking unauthorized inbound ports.

### 3. Restrict SSH & Sharing Services
1. Go to **System Settings > General > Sharing**.
2. Toggle **OFF** all unused sharing options (File Sharing, Screen Sharing, Remote Management).
3. If you use **Remote Login (SSH)**, click the info `(i)` button next to it. Set **"Allow access for:"** to **"Only these users:"** and explicitly whitelist only your **Admin account**. *Do not allow the restricted OpenClaw Standard user to SSH into the machine.*

### 4. Turn on FileVault (Full Disk Encryption)
Your config files store plaintext API keys. To prevent physical data extraction if the Mac Mini is stolen:
- Go to **System Settings > Privacy & Security > FileVault** and toggle it **ON**.

### 5. Disable System Sleep
Ensure the Mac Mini remains awake to process background cron jobs and Telegram queries:
- Go to **System Settings > Displays > Advanced...** (or **Energy Saver**) and toggle on **"Prevent automatic sleeping when the display is off"**.

---

## Phase 1: Homebrew & Tooling Dependencies

On macOS, Homebrew is installed in user-space. Because your OpenClaw account is a standard user, Homebrew installation and privileged commands should be bridged via the Admin account.

### 1. Install Homebrew
- Log into your **Admin Account** and execute:
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

### 2. Install Required Tools
Run the following system-wide Homebrew commands as Admin to install essential OpenClaw dependency tools:
```bash
brew install rclone gnu-tar jq
```
*Note:*
* macOS's default `tar` utility is BSD-based. OpenClaw backup scripts rely on **GNU Tar** (`gtar`) for advanced path exclusions.
* The standard user will access these tools at `/opt/homebrew/bin/rclone` and `/opt/homebrew/bin/gtar`.

---

## Phase 2: Docker Desktop & Isolated Sandboxing

On Apple Silicon Macs, Docker Desktop uses the highly optimized Apple Virtualization Framework which manages host memory dynamically. Since OpenClaw is extremely lightweight (< 300MB RAM), you can safely leave Docker resources at their defaults.

### 1. Install & Share Privileges
1. Log into your **Admin Account**.
2. Download and install [Docker Desktop for Mac (Apple Silicon)](https://www.docker.com/products/docker-desktop/).
3. Launch it once as Admin to install its privileged helper (input admin password when prompted).
4. In Docker Desktop Settings under **General**, ensure **"Allow the default Docker socket to be used"** is enabled. This allows standard users to run docker commands.

### 2. Configure Restricted File Sharing (The Air-Gap)
By default, Docker Desktop shares the entire `/Users` and `/tmp` directories, which leaves the host vulnerable if the container is compromised.
1. Open Docker Desktop -> **Settings > Resources > File sharing**.
2. Delete the default paths (`/Users`, `/Volumes`, `/tmp`).
3. Add **only** the absolute path to your standard user's OpenClaw data directory: `/Users/<standard-username>/.openclaw`.

### 3. Launch Docker at Login
1. Log into your restricted **Standard Account**.
2. Open Docker Desktop.
3. Open **System Settings > General > Login Items** on your Mac and add **Docker** to the list to ensure the daemon automatically spins up on user login.

---

## Phase 3: Ollama Local AI Model Setup

Ollama runs locally on the host's Apple Silicon GPU. We install and run it in user-space under the **Standard Account**, bypassing root requirements.

### 1. Start Ollama with Container Accessibility
Ollama must bind to `0.0.0.0` (all interfaces) rather than the default `127.0.0.1` so that the Docker container can communicate with the host's Ollama instance.

Log into your **Standard Account** and run:
```bash
mkdir -p ~/.ollama
OLLAMA_HOST=0.0.0.0 OLLAMA_FLASH_ATTENTION="1" OLLAMA_KV_CACHE_TYPE="q8_0" nohup /opt/homebrew/bin/ollama serve > ~/.ollama/ollama.log 2>&1 &
```
*Optimizations:*
* `OLLAMA_FLASH_ATTENTION="1"`: Dramatically speeds up token processing.
* `OLLAMA_KV_CACHE_TYPE="q8_0"`: Uses 8-bit quantized caching, cutting host memory consumption in half while retaining model accuracy.

### 2. Pull Local Models
Download your primary model and optimized local fallback:
```bash
/opt/homebrew/bin/ollama pull qwen3.5:9b
/opt/homebrew/bin/ollama pull gemma4:e4b
```

### 3. Verify Connection
Check if Ollama is running and has loaded the models:
```bash
curl -s http://127.0.0.1:11434/api/tags
```

---

## Phase 4: OpenClaw Configurations & Mappings

OpenClaw mounts its configuration files from `~/.openclaw/` on the Mac host into `/home/node/.openclaw/` inside the container. 

### 1. Local Shell Aliases (`~/.zshrc`)
macOS uses `zsh` as its default shell. Log into your **Standard Account** and add these helper shortcuts to your `~/.zshrc`:
```bash
cat >> ~/.zshrc << 'EOF'

# OpenClaw shortcuts
oc() { docker exec -it openclaw-sandbox openclaw "$@"; }
alias oc-upgrade="docker pull ghcr.io/openclaw/openclaw:latest && docker stop openclaw-sandbox && docker rm openclaw-sandbox && docker run -d --name openclaw-sandbox --restart always --security-opt no-new-privileges:true -v ~/.openclaw:/home/node/.openclaw -e HOME=/home/node ghcr.io/openclaw/openclaw:latest"
EOF
source ~/.zshrc
```

### 2. Configuration: `openclaw.json` (`~/.openclaw/openclaw.json`)
Configure your `openclaw.json` exactly as follows. This registers your local Ollama models, overrides context truncation, defines cloud fallbacks, and locks down bot settings.

> [!IMPORTANT]
> You **must** define `params.num_ctx` as `65536` (64k tokens) under Ollama. By default, Ollama cuts off API request context at `2048` tokens, which causes OpenClaw's memory context to truncate and leads to immediate agent failures on complex turns.

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
        "baseUrl": "http://host.docker.internal:11434",
        "apiKey": "ollama-local",
        "auth": "api-key",
        "api": "ollama",
        "params": {
          "num_ctx": 65536
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
        "google/gemini-3.1-pro": {
          "alias": "pro"
        },
        "google/gemini-3.5-flash": {
          "alias": "flash35"
        }
      },
      "workspace": "/home/node/.openclaw/workspace",
      "compaction": {
        "mode": "safeguard"
      },
      "heartbeat": {
        "every": "1h",
        "target": "telegram"
      }
    },
    "list": [
      { "id": "main" }
    ]
  },
  "tools": {
    "profile": "coding"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "pairing",
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
    "bind": "all",
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
      "ollama"
    ],
    "entries": {
      "google": { "enabled": true },
      "telegram": { "enabled": true },
      "anthropic": { "enabled": true },
      "ollama": { "enabled": true },
      "memory-core": {
        "enabled": true,
        "config": {
          "dreaming": {
            "enabled": true,
            "model": "flash35"
          }
        }
      }
    }
  }
}
```

### 3. Config Runtime: `auth-profiles.json` (`~/.openclaw/agents/main/agent/auth-profiles.json`)
Configure your keys under the `profiles` array. Make sure you map the `ollama:default` configuration with a dummy API key to authenticate local routing:
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
    },
    "ollama:default": {
      "type": "api_key",
      "provider": "ollama",
      "key": "ollama-local"
    }
  },
  "lastGood": {
    "google": "google:default",
    "anthropic": "anthropic:default",
    "ollama": "ollama:default"
  }
}
```

### 4. Boot Up the OpenClaw Container
Spin up the main runtime container using the secure `latest` official image:
```bash
docker run -d \
  --name openclaw-sandbox \
  --restart always \
  --security-opt no-new-privileges:true \
  -v ~/.openclaw:/home/node/.openclaw \
  -e HOME=/home/node \
  ghcr.io/openclaw/openclaw:latest
```

### 5. Reconcile Configuration Schema
Run the doctor fix utility inside the container to ensure all plugins align with the latest image schema changes:
```bash
docker exec -it openclaw-sandbox openclaw doctor --fix
docker restart openclaw-sandbox
```

---

## Phase 5: VFS Mount EPERM Patch for Command Runner

### The EPERM Blockage
Because OpenClaw mounts `/Users/<standard-user>/.openclaw` from the macOS host directly to `/home/node/.openclaw` in the container, any internal Node call to `fs.chmodSync('/home/node/.openclaw', 448)` triggers a macOS Virtual File System (VFS) permissions block, returning an `EPERM (Operation not permitted)` error. Since OpenClaw performs this directory check every time the agent executes a shell command, **all agent command runs will fail by default.**

### The Hot-Patch
To resolve this, we intercept the throwing `chmodSync` line in `/app/dist/exec-approvals-*.js` inside the container to gracefully bypass container-level mount permission blocks:

1. Create a script `/Users/<standard-user>/.openclaw/patch-docker-eperm.sh` on the host:
   ```bash
   cat << 'EOF' > ~/.openclaw/patch-docker-eperm.sh
   #!/bin/bash
   # A script to patch OpenClaw's EPERM chmod bug inside the docker container on macOS host.
   
   CONTAINER_NAME="openclaw-sandbox"
   
   echo "=== Checking if container \$CONTAINER_NAME is running... ==="
   if ! /usr/local/bin/docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}$"; then
     echo "Error: Container \$CONTAINER_NAME is not running. Please start it first."
     exit 1
   fi
   
   echo "=== Searching for the exec approvals javascript file... ==="
   FILE=\$(/usr/local/bin/docker exec \$CONTAINER_NAME sh -c "grep -l 'Refusing to use unsafe exec approvals directory' /app/dist/*.js 2>/dev/null | head -n 1")
   
   if [ -z "\$FILE" ]; then
     echo "Error: Could not locate the target javascript file inside the container."
     exit 1
   fi
   
   echo "Found file inside container: \$FILE"
   
   echo "=== Applying patch inside the container... ==="
   /usr/local/bin/docker exec \$CONTAINER_NAME node -e "
   const fs = require('fs');
   const filePath = '\$FILE';
   let content = fs.readFileSync(filePath, 'utf8');
   const target = 'if (process.platform !== \\\"win32\\\") throw err;';
   const replacement = 'if (process.platform !== \\\"win32\\\" && err.code !== \\\"EPERM\\\" && err.code !== \\\"EACCES\\\") throw err;';
   if (content.includes(target)) {
     content = content.replace(target, replacement);
     fs.writeFileSync(filePath, content, 'utf8');
     console.log('Successfully patched ' + filePath);
   } else if (content.includes(replacement)) {
     console.log('File is already patched.');
   } else {
     console.log('Error: Could not find target pattern in ' + filePath);
     process.exit(1);
   }
   "
   
   if [ \$? -eq 0 ]; then
     echo "=== Restarting the container to apply changes... ==="
     /usr/local/bin/docker restart \$CONTAINER_NAME
     echo "=== Done! OpenClaw successfully patched and restarted. ==="
   else
     echo "Error: Patch application failed."
     exit 1
   fi
   EOF
   chmod +x ~/.openclaw/patch-docker-eperm.sh
   ```
2. Execute the patch:
   ```bash
   ~/.openclaw/patch-docker-eperm.sh
   ```
*Note:* If you ever rebuild, upgrade, or recreate the container (e.g., pulling a new image), simply re-run this script on your host.

---

## Phase 6: Backup Schedules & Host Cron Permissions

### 1. Grant macOS Full Disk Access to `cron`
macOS blocks the host `cron` daemon from reading directories like `Documents` or standard user Home directories. To prevent backups from failing with `Permission Denied` errors:
1. Open **System Settings > Privacy & Security > Full Disk Access**.
2. Click the `+` button and authenticate with your Admin credentials.
3. Press `Cmd + Shift + G`, type `/usr/sbin/cron`, and select the `cron` binary.
4. Ensure the toggle next to `cron` is turned **ON**.

### 2. Configure Backup Script (`~/.openclaw/openclaw-backup.sh`)
Create the backup script on the host to compress your configuration volume using GNU Tar (`gtar`) and back it up directly to Google Drive via `rclone`:

```bash
cat << 'EOF' > ~/.openclaw/openclaw-backup.sh
#!/bin/bash
# Backup OpenClaw settings and workspaces

USER_HOME="/Users/youngjoo" # Update to standard user home directory
BACKUP_DIR="${USER_HOME}/.openclaw"
ARCHIVE="${USER_HOME}/openclaw-backup.tar.gz"

# Compress configuration folders, excluding unnecessary log files
/opt/homebrew/bin/gtar --exclude='*.log' --exclude='logs' --exclude='tmp' -czf "$ARCHIVE" -C "${USER_HOME}" .openclaw

# Upload backup to Google Drive
/opt/homebrew/bin/rclone copy "$ARCHIVE" agent-drive:openclaw-backups/snapshots/

# Clean up local archive
rm "$ARCHIVE"
EOF
chmod +x ~/.openclaw/openclaw-backup.sh
```

### 3. Load Backup Cron Job
Open the user's crontab:
```bash
crontab -e
```
Add the daily execution line (e.g. daily at 3:00 AM):
```cron
0 3 * * * /Users/youngjoo/.openclaw/openclaw-backup.sh > /dev/null 2>&1
```

### 4. Cron jobs.json Telegram Delivery Configuration
When setting up automated in-agent tasks (like morning briefings or repository audits) in `~/.openclaw/cron/jobs.json`, **never** leave `"sessionTarget": "main"`. It will silently dump outputs to your internal webchat without delivering them to your devices.

Ensure every cron job utilizes **isolated sessions** routed explicitly to your Telegram ID:
```json
{
  "name": "daily-briefing",
  "schedule": "0 8 * * *",
  "sessionTarget": "isolated",
  "delivery": {
    "mode": "announce",
    "channel": "telegram",
    "to": "YOUR_TELEGRAM_CHAT_ID"
  }
}
```

### 5. Private Git Workspace Backup
Because your agent workspace contains sensitive memories, custom skills, daily logs, and configuration maps, it should be backed up regularly to a **private** Git repository to prevent data loss.

1. **Staging & Storing Workspace**: The workspace files are stored under `/Users/dfadmin/.openclaw/workspace`. We have initialized this as a Git repository, staged the active agent files (ignoring `.DS_Store` and other OS-level files), and committed the first revision.
2. **Wiring a Remote**: Create a **private** repository on your preferred provider (GitHub/GitLab) without initializing it with a README.
3. **Register and Push (Run on Mac Mini host)**:
   ```bash
   cd ~/.openclaw/workspace
   git remote add origin <your-private-git-repo-url>
   git push -u origin main
   ```
4. **Subsequent Backups**: To back up memory files as your agent operates:
   ```bash
   cd ~/.openclaw/workspace
   git add .
   git commit -m "Update memory logs"
   git push
   ```

---

## Phase 7: Gotchas, Troubleshooting & Chaos Testing

### 1. Resetting Auth Cooldowns
If your API key fails or rate-limits repeatedly, OpenClaw places the profile into a hard `cooldown` state. This state **persists in process memory** across container restarts.

To clear a locked auth profile:
1. Stop the container fully: `docker stop openclaw-sandbox`.
2. Open `~/.openclaw/agents/main/agent/auth-profiles.json`.
3. Locate your failing provider under the `profiles` array. Find `usageStats` and reset the values:
   ```json
   "usageStats": {
     "errorCount": 0,
     "lastFailureAt": 0
   }
   ```
4. Start the container again: `docker start openclaw-sandbox`.

### 2. Standard Restart Rules
* `docker restart openclaw-sandbox` is fast and safely applies basic settings changes.
* `docker stop openclaw-sandbox && docker start openclaw-sandbox` is **required** to clear in-memory auth cooldowns, rate limits, and provider state caches.

### 3. File Ownership Mismatches
Because Docker's daemon runs under root-level contexts, new directories created inside mounts can sometimes be clobbered with `root` ownership, resulting in `EACCES` errors. If files become unreadable by the standard host user, regain ownership:
```bash
sudo chown -R $(id -u):$(id -g) ~/.openclaw/
```

### 4. Host Verification & Testing Commands
Always verify configurations using these commands:
* Check all registered models and see which is default:
  ```bash
  oc models list
  ```
* Test if the local model responds properly:
  ```bash
  oc model test ollama/qwen3.5:9b
  ```
* Trigger a cron job manually (using its UUID) to test delivery configurations:
  ```bash
  oc cron run <job-uuid>
  ```
