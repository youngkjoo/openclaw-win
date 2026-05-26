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
3. **Download Model**:
   ```bash
   ollama pull qwen3.5:9b
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
          "google/gemini-3.5-flash",
          "anthropic/claude-sonnet-4-6"
        ]
      },
      "models": {
        // ... existing models ...
        "ollama/qwen3.5:9b": {
          "alias": "qwen"
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
google/gemini-3.5-flash                    text       195k        no    yes   fallback#1
anthropic/claude-sonnet-4-6                text+image 195k        no    yes   fallback#2,configured,alias:sonnet
```
