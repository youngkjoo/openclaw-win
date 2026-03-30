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

6. **Auto-Start Docker on WSL Boot:**
Docker does **not** auto-start on WSL2. If Windows sleeps, hibernates, reboots, or if `wsl --shutdown` is run, Docker will be stopped when WSL comes back — and OpenClaw will be down until Docker is manually restarted. Add this to your `.bashrc` to auto-start Docker on every WSL session:
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
WSL2 automatically shuts down when there are no active sessions (all terminals/SSH closed). This kills Docker and OpenClaw. To keep WSL alive 24/7, create a Windows Scheduled Task that runs a persistent process inside WSL.

First, create the keep-alive script inside WSL:
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

Then run each of these commands **one at a time** in **PowerShell as Administrator** (PowerShell breaks multi-line commands if pasted as a block):
```powershell
$a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-e /home/young/keep-alive.sh"
```
```powershell
$t = New-ScheduledTaskTrigger -AtStartup
```
```powershell
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -Hidden
```
```powershell
$p = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
```
```powershell
Register-ScheduledTask -TaskName "KeepWSLAlive" -Action $a -Trigger $t -Settings $s -Principal $p -Description "Keeps WSL alive"
```

Start the task immediately (without rebooting):
```powershell
Start-ScheduledTask -TaskName "KeepWSLAlive"
```

Verify it's running (`LastTaskResult` should be `267009` = "task is running"):
```powershell
Get-ScheduledTaskInfo -TaskName "KeepWSLAlive" | Select-Object LastRunTime, LastTaskResult
```

> **How it works:** The task runs `sleep infinity` inside WSL, which keeps the WSL instance permanently alive. The script also starts Docker on launch. Combined with the `.bashrc` Docker auto-start (step 6) and the container's `unless-stopped` restart policy, OpenClaw stays running 24/7.

> **Important gotchas discovered during debugging:**
> - `wsl -e /bin/true` (a short-lived ping) does NOT work — WSL shuts down between pings because `.bashrc` doesn't run for non-interactive shells, so Docker never starts.
> - Running the task as `SYSTEM` does NOT work — WSL distributions are per-user, so SYSTEM can't access your WSL instance.
> - Running as your user without `S4U` opens a visible console window that can be accidentally closed. The `S4U` logon type + `-Hidden` runs it invisibly.
> - PowerShell's `Register-ScheduledTask` breaks if you try to pass all parameters in a single pasted line — run each variable assignment separately.

> **To remove later:** `Unregister-ScheduledTask -TaskName "KeepWSLAlive" -Confirm:$false`

**Completion Message:**
Once everything succeeds, reboot the WSL instance immediately to permanently sever the Windows drive bridge. Type `exit` to leave your SSH session. Then, on your Windows laptop natively, run `wsl --shutdown` in PowerShell. You are safely sandboxed! (After rebooting, you can just type `oc setup` to start configuring).
