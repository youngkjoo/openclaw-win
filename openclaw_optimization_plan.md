# OpenClaw Optimization Execution Plan

## 1. Background & Rationale
This machine is an Apple Silicon Mac mini (M4). The primary objective of this configuration is to prevent the Unified Memory from spilling over into SSD swap space during extended inference sessions with `gemma4:12b-qat`. 

Because a 12B parameter model quantized to 4-bit consumes roughly 7.5GB of RAM, large context windows or combined embedding workloads will quickly exceed available hardware limits, causing severe latency degradation. 

**Architectural Changes:**
1. **Hardware-Locked KV Cache:** We are strictly binding the context window (`num_ctx`) to 8192 tokens to prevent runtime memory bloat.
2. **Embedding Isolation:** We are offloading vectorization (memory processing) from the main 12B model to a sub-1GB dedicated embedder (`nomic-embed-text`). This preserves Mac mini memory bandwidth for the primary logic loop.
3. **QMD Choking:** We are limiting OpenClaw's Quantum Memory Directory (QMD) retrieval limit to prevent it from overwhelming the 8192-token context ceiling.

---

## 2. Execution Instructions
Please execute the following operations in order via SSH.

### Step 2.1: Provision the Embedding Model
Pull the dedicated embedding model into the local Ollama registry:
```bash
ollama pull nomic-embed-text
```

### Step 2.2: Create the Hardware-Locked Alias Model
1. Create a file named `Modelfile` in your current working directory with the following exact contents:
```dockerfile
FROM gemma4:12b-it-qat
PARAMETER num_ctx 8192
PARAMETER temperature 0.0
PARAMETER num_gpu 1
PARAMETER stop "<end_of_turn>"
```
2. Build the new constrained model alias:
```bash
ollama create gemma4:12b-qat-claw -f Modelfile
```

### Step 2.3: Reconfigure OpenClaw Gateway
Open the OpenClaw configuration file (`~/.openclaw/openclaw.json`) and apply the following updates to the `agents` and `memory` structures. Merge these keys into the existing JSON5 structure:

```json5
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/gemma4:12b-qat-claw"
      },
      "memorySearch": {
        "provider": "ollama",
        "model": "nomic-embed-text"
      }
    }
  },
  "memory": {
    "backend": "qmd",
    "qmd": {
      "searchMode": "query",
      "limits": {
        "maxResults": 4,
        "maxSnippetChars": 700
      }
    }
  }
}
```

### Step 2.4: Restart the Service
Restart the gateway so the QMD sidecar registers the new configuration:
```bash
openclaw gateway restart
```

---

## 3. Validation Protocol
After completing the execution steps, perform this sequence to verify that the Nomic embedding model is successfully routing and retrieving semantic memory.

### Test 1: Verify Deep Connection
Run the following diagnostic command:
```bash
openclaw memory status --deep
```
**Success Condition:** The output must display `provider: ollama`, `model: nomic-embed-text`, and indicate that the vector store is online and responsive.

### Test 2: Inject a Semantic Fact
Using the OpenClaw CLI or chat interface, send the following exact message:
> "Remember that my top-secret project name is Project BlueFalcon."
**Expected Behavior:** The agent should acknowledge the statement. OpenClaw will silently vector-encode this into the daily Markdown memory log.

### Test 3: Semantic Retrieval Test
Run a memory search using conceptually similar terms (avoiding exact keyword matches):
```bash
openclaw memory search "what was the name of my hidden project?"
```
**Success Condition:** The system must return the specific sentence referencing `Project BlueFalcon`. This proves the Nomic model's mathematical vector retrieval is functioning.

### Test 4: Live Context Integration
Enable the debug trace monitor and ask the agent a question:
```bash
# In the OpenClaw chat interface:
/trace on
> "What project am I working on?"
```
**Success Condition:** Before the agent begins to stream its response, the console output must display an `Active Memory Debug:` line containing the BlueFalcon fact, proving that QMD successfully intercepted the query, used Nomic to retrieve the memory, and appended it to the Gemma context window.