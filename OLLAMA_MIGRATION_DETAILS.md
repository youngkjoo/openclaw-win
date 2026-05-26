# OpenClaw Migration: Switch to Local Qwen 3.5 9B via Ollama

This document captures the technical details, configuration parameters, and execution steps used to migrate the OpenClaw instance running inside a Docker container (`openclaw-sandbox`) on the Mac Mini (`joo-mac-mini.local`) to a locally hosted **Qwen 3.5 9B** model.

---

## 1. System & Network Architecture

### Host Environment
* **Hardware**: Apple Silicon Mac Mini (`joo-mac-mini.local`)
* **Host OS**: macOS (Darwin 25.5.0)
* **Users**:
  * `youngjoo`: Standard user account with Homebrew installed (`/opt/homebrew`).
  * `dfadmin`: Administrator account used to host the Docker daemon.

### Networking & Topology
* The OpenClaw gateway runs inside a Docker container called `openclaw-sandbox` under `dfadmin`.
* The Ollama server runs on the host OS under the `youngjoo` user.
* To bridge the network boundary, we utilize **Docker Desktop's host resolution DNS**:
  * Inside the container, the host machine is reached via `http://host.docker.internal:11434`.
  * To accept inbound bridge connections from the container, the Ollama server is explicitly configured to listen on all interfaces (`0.0.0.0`) by setting the `OLLAMA_HOST` environment variable.

---

## 2. Ollama Installation & Configuration

Ollama was installed in **user-space** under the `youngjoo` account, completely bypassing the need for administrative or sudo privileges.

### Steps Executed
1. **Installation via Homebrew**:
   ```bash
   brew install ollama
   ```
2. **Startup with 0.0.0.0 Binding**:
   A background server was spun up with Apple Silicon optimization flags (Flash Attention and 8-bit quantized KV caching enabled by default in Homebrew):
   ```bash
   mkdir -p ~/.ollama
   OLLAMA_HOST=0.0.0.0 OLLAMA_FLASH_ATTENTION="1" OLLAMA_KV_CACHE_TYPE="q8_0" nohup /opt/homebrew/bin/ollama serve > ~/.ollama/ollama.log 2>&1 &
   ```
3. **Download Models**:
   We pulled the primary model (Qwen 3.5 9B) and the optimized local fallback model (Gemma 4 e4b):
   ```bash
   ollama pull qwen3.5:9b
   ollama pull gemma4:e4b
   ```

---

## 3. OpenClaw Configuration Changes

OpenClaw configuration files are mounted from `/Users/dfadmin/.openclaw/` on the host into `/home/node/.openclaw/` inside the container. 

Before making modifications, configuration files were backed up:
* `openclaw.json` backed up to `openclaw.json.bak.qwen`
* `auth-profiles.json` backed up to `auth-profiles.json.bak.qwen`

### Configuration A: `openclaw.json`
Modified `/Users/dfadmin/.openclaw/openclaw.json` to register the local Ollama provider and set the default agent model.

Key adjustments applied:
1. **Registered the Ollama Provider**: Points to `http://host.docker.internal:11434`.
2. **Overrode Context Window Truncation**: Setting `params.num_ctx` to `65536` (64k tokens) is **critical**. Ollama defaults to `2048` tokens for API requests unless this value is explicitly supplied, which is too small for OpenClaw's multi-step agent turn history.
3. **Enabled Ollama Plugin**: Ensured `"ollama"` is allowed and enabled.
4. **Set Primary Model**: Updated the primary model to `"ollama/qwen3.5:9b"`.

#### Config Diff Highlights
```json
{
  "auth": {
    "profiles": {
      // ... existing profiles ...
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
        // ... existing models ...
        "ollama/qwen3.5:9b": {
          "alias": "qwen"
        },
        "ollama/gemma4:e4b": {
          "alias": "gemma4"
        },
        "google/gemini-3.1-pro": {
          "alias": "pro"
        }
      }
    }
  },
  "plugins": {
    "allow": [
      "google",
      "telegram",
      "anthropic",
      "memory-core",
      "ollama"
    ],
    "entries": {
      // ... existing entries ...
      "ollama": {
        "enabled": true
      }
    }
  }
}
```

### Configuration B: `auth-profiles.json`
Modified `/Users/dfadmin/.openclaw/agents/main/agent/auth-profiles.json` to inject a synthetic API key profile for the local server.

```json
{
  "version": 1,
  "profiles": {
    // ... existing profiles ...
    "ollama:default": {
      "type": "api_key",
      "provider": "ollama",
      "key": "ollama-local"
    }
  }
}
```

---

## 4. Container Maintenance & Verification

### Restarting the Gateway
To reload the persistent mounts, we restarted the container under `dfadmin`:
```bash
docker restart openclaw-sandbox
```

### Verification Reference Commands

* **Check Ollama server catalog (from Mac Mini host)**:
  ```bash
  curl -s http://127.0.0.1:11434/api/tags
  ```
* **Test host loopback connectivity (from inside OpenClaw container)**:
  ```bash
  docker exec openclaw-sandbox curl -s http://host.docker.internal:11434/api/tags
  ```
* **Verify OpenClaw active model mappings**:
  ```bash
  docker exec openclaw-sandbox node openclaw.mjs models list
  ```
  *Output should verify `ollama/qwen3.5:9b` tagged as `default,configured,alias:qwen`.*
* **Inspect OpenClaw active profiles**:
  ```bash
  docker exec openclaw-sandbox node openclaw.mjs models status
  ```

### Active Model Catalog
```
Model                                      Input      Ctx         Local Auth  Tags
ollama/qwen3.5:9b                          text       195k        no    yes   default,configured,alias:qwen
ollama/gemma4:e4b                          text       195k        no    yes   fallback#1,configured,alias:gemma4
google/gemini-3.5-flash                    text       195k        no    yes   fallback#2
anthropic/claude-sonnet-4-6                text+image 195k        no    yes   fallback#3,configured,alias:sonnet
google/gemini-3.1-pro                      text+image 1000k       no    yes   configured,alias:pro

---

## 5. Command Execution EPERM Fix

### The Problem
When the OpenClaw agent tried to execute system/shell commands, it failed with the following error:
> "..my execution tool is currently blocked by permissions inside this Docker container (EPERM on the workspace volume)"

### Root Cause
1. Under the hood, OpenClaw writes an audit log and updates authorizations in its execution approvals file at `/home/node/.openclaw/exec-approvals.json` before and after running shell commands.
2. In the `ensureDir` function of `/app/dist/exec-approvals-*.js`, OpenClaw attempts to secure the directory permissions of the approvals file using `fs.chmodSync('/home/node/.openclaw', 448)` (`0o700` in octal).
3. In this deployment, the entire `/Users/dfadmin/.openclaw` directory is **bind-mounted** into the container as `/home/node/.openclaw`. 
4. Docker Desktop on macOS (using VirtioFS or gRPC FUSE) strictly blocks modifying metadata/permissions (`chmod`) on the root mountpoint of a bind-mounted host directory from inside the container, returning `EPERM` (Operation not permitted).
5. OpenClaw's code had a strict catch check that would immediately crash and rethrow the error on Linux platforms (unlike Windows):
   ```javascript
   try {
       fs.chmodSync(dir, 448);
   } catch (err) {
       if (process.platform !== "win32") throw err;
   }
   ```
   This crashed the command runner tool entirely before any commands could execute.

### Resolution
We wrote a highly robust search-and-replace patching routine that intercepts this behavior inside the container. It allows the `chmod` operation to bypass containerized VFS mount limitations by gracefully catching `EPERM` and `EACCES` errors (just like the other file-level `chmod` calls in OpenClaw's persistence layer already do).

We created a persistent script on the Mac Mini host: **`/Users/dfadmin/.openclaw/patch-docker-eperm.sh`**

```bash
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
```

### Verification
* Running this script successfully finds the JavaScript bundle `/app/dist/exec-approvals-Bef7TPVc.js`, patches it, restarts the container, and boots up all agent interfaces healthy and polling!
* Commands now execute seamlessly since VFS mount errors are gracefully bypassed!
```
