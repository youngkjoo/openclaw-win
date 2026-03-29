# Secure Linux (WSL) Automation Instructions

**Context:** You are acting as an automated setup assistant. You are running in a Linux (Ubuntu WSL) environment. Your goal is to strictly lock down the environment, install Docker for sandboxing, configure Ollama securely, and deploy OpenClaw in a trapped container.

**Instructions:** Please execute the following bash commands sequentially. *(Note: Since you are running `sudo` for the first time, Linux may ask you to type your password!)*

1. **Sever Windows Drive Automount (Critical Security):**
```bash
sudo mkdir -p /etc
echo -e "[automount]\nenabled = false\n[interop]\nappendWindowsPath = false" | sudo tee /etc/wsl.conf
```

2. **Install Docker (For Sandboxing the Agent):**
*(Note: During installation, the script will output a warning: "WSL DETECTED: We recommend using Docker Desktop for Windows." **Ignore this entirely!** Installing Docker Desktop breaks the air-gap isolation we are building. The script correctly installs the raw Linux Engine instead).*
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo service docker start
```

3. **Configure & Deploy OpenClaw inside the Docker Sandbox:**
```bash
# Prepare the explicit directory structure for the non-root 'node' user (UID 1000)
mkdir -p ~/.openclaw

# Create the initial configuration file with placeholders
cat << 'EOF' > ~/.openclaw/config.json
{
  "llmProvider": "gemini",
  "gemini": {
    "apiKey": "YOUR_GEMINI_API_KEY_HERE"
  },
  "channels": {
    "telegram": {
      "token": "YOUR_BOTFATHER_TOKEN_HERE",
      "groupPolicy": "all"
    }
  }
}
EOF

# Ensure proper permissions are applied to the generated config
sudo chown -R 1000:1000 ~/.openclaw

# Run OpenClaw isolated on the Docker bridge, strictly as non-root, blocking privilege escalation.
# This container will also pre-install the gemini and telegram plugins upon booting!
docker run -d \
  --name openclaw-sandbox \
  --restart unless-stopped \
  --user 1000:1000 \
  --security-opt no-new-privileges:true \
  -v ~/.openclaw:/home/node/.openclaw \
  -e HOME=/home/node \
  node:22-slim \
  bash -c "mkdir -p /home/node/.npm-global && npm config set prefix '/home/node/.npm-global' && export PATH=/home/node/.npm-global/bin:\$PATH && npm install -g openclaw && (openclaw gateway || sleep infinity)"
```

> **Known Issue — npm ENOTEMPTY on restart:** The container runs `npm install -g openclaw` on every boot. If a previous boot was interrupted, a stale temp directory can cause repeated `ENOTEMPTY` errors and the container will restart in a loop. Fix by exec'ing into the container and removing the stale directory:
> ```bash
> docker exec openclaw-sandbox rm -rf /home/node/.npm-global/lib/node_modules/.openclaw-*
> docker restart openclaw-sandbox
> ```

4. **Create a Shortcut (Bash Function) for Easier Access:**
*(This final step creates a permanent `oc` shortcut that properly passes all your arguments through to the container!)*
```bash
cat >> ~/.bashrc << 'EOF'
oc() { docker exec -it openclaw-sandbox bash -c "export PATH=/home/node/.npm-global/bin:\$PATH && openclaw $*"; }
EOF
```

5. **Post-Setup: Verify API Key Consistency:**
After running `oc setup` or `oc configure`, the runtime creates `~/.openclaw/agents/main/agent/auth-profiles.json` with its own copy of your API key. Verify both files have the same key:
```bash
# Check config.json key
grep apiKey ~/.openclaw/config.json

# Check runtime auth-profiles key
docker exec openclaw-sandbox cat /home/node/.openclaw/agents/main/agent/auth-profiles.json | grep key
```
If these diverge, the agent will fail with `API_KEY_INVALID` (400) errors. See `openclaw-setup-guide.md` for detailed troubleshooting.

**Completion Message:** 
Once everything succeeds, reboot the WSL instance immediately to permanently sever the Windows drive bridge. Type `exit` to leave your SSH session. Then, on your Windows laptop natively, run `wsl --shutdown` in PowerShell. You are safely sandboxed! (After rebooting, you can just type `oc setup` to start configuring).
