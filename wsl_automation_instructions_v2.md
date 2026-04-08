# Secure Linux (WSL) Automation Instructions (v2)

**Context:** You are acting as an automated setup assistant. You are running in a Linux (Ubuntu WSL) environment. Your goal is to strictly lock down the environment, install Docker for sandboxing, configure Ollama securely, and deploy OpenClaw in a trapped container using the official Docker image.

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

# Run OpenClaw isolated on the Docker bridge using the official image, blocking privilege escalation.
docker run -d \
  --name openclaw-sandbox \
  --restart always \
  --user 1000:1000 \
  --security-opt no-new-privileges:true \
  -v ~/.openclaw:/home/node/.openclaw \
  -e HOME=/home/node \
  ghcr.io/openclaw/openclaw:latest
```

> **Design note — native restarts:** We now use the official pre-packaged Docker image instead of manually installing OpenClaw inside a raw node container. This natively resolves gateway crash loops because Docker's `--restart always` policy cleanly restarts the failed process automatically!

4. **Create Shortcuts (Bash Functions & Aliases):**
*(These create a permanent `oc` shortcut to easily run OpenClaw commands within the container.)*
```bash
cat >> ~/.bashrc << 'EOF'

# OpenClaw shortcuts
oc() { docker exec -it openclaw-sandbox openclaw "$@"; }
alias oc-upgrade="docker pull ghcr.io/openclaw/openclaw:latest && docker stop openclaw-sandbox && docker rm openclaw-sandbox && docker run -d --name openclaw-sandbox --restart always --user 1000:1000 --security-opt no-new-privileges:true -v ~/.openclaw:/home/node/.openclaw -e HOME=/home/node ghcr.io/openclaw/openclaw:latest"
EOF
```

> **Upgrading OpenClaw:** Because we use the official Docker image, the new `oc-upgrade` alias simply pulls the newest image and recreates your isolated container, instantly updating the agent while perfectly preserving your configuration mapped from `~/.openclaw`.

5. **Post-Setup: Verify API Key Consistency:**
After running `oc setup` or `oc configure`, the runtime creates `~/.openclaw/agents/main/agent/auth-profiles.json` with its own copy of your API key. Verify both files have the same key:
```bash
# Check config.json key
grep apiKey ~/.openclaw/config.json

# Check runtime auth-profiles key
docker exec openclaw-sandbox cat /home/node/.openclaw/agents/main/agent/auth-profiles.json | grep key
```

6. **Auto-Start Docker on WSL Boot:**
Docker does **not** auto-start on WSL2. Add this to your `.bashrc` to auto-start Docker on every WSL session:
```bash
cat >> ~/.bashrc << 'AUTOSTART'
# Auto-start Docker daemon if not running
if ! pgrep -x dockerd > /dev/null 2>&1; then
  sudo service docker start > /dev/null 2>&1
fi
AUTOSTART
```
> **Note:** This requires passwordless sudo for the `docker` service. To set that up:
> ```bash
> echo "$USER ALL=(ALL) NOPASSWD: /usr/sbin/service docker *" | sudo tee /etc/sudoers.d/docker-service
> ```

7. **Prevent WSL Idle Shutdown (Windows Task Scheduler):**
WSL2 automatically shuts down when there are no active sessions. First, create the keep-alive script inside WSL:
```bash
cat > ~/keep-alive.sh << 'EOF'
#!/bin/bash
sudo service docker start > /dev/null 2>&1
sleep infinity
EOF
chmod +x ~/keep-alive.sh
```

Then, add the `vmIdleTimeout` setting to prevent WSL from idling out. Run in **PowerShell**:
```powershell
Add-Content -Path "$env:USERPROFILE\.wslconfig" -Value "vmIdleTimeout=-1"
```

Then run each of these commands **one at a time** in **PowerShell as Administrator**:
```powershell
$a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-u <your_wsl_username> -- bash /home/<your_wsl_username>/keep-alive.sh"
$t1 = New-ScheduledTaskTrigger -AtStartup
$t2 = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -Hidden -ExecutionTimeLimit 0
$p = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
Register-ScheduledTask -TaskName "KeepWSLAlive" -Action $a -Trigger @($t1, $t2) -Settings $s -Principal $p -Description "Keeps WSL alive"
Start-ScheduledTask -TaskName "KeepWSLAlive"
```

**Completion Message:**
Once everything succeeds, reboot the WSL instance immediately to permanently sever the Windows drive bridge. Type `exit` to leave your SSH session. Then, on your Windows laptop natively, run `wsl --shutdown` in PowerShell. You are safely sandboxed!
