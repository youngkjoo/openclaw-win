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
  --restart always \
  --user 1000:1000 \
  --security-opt no-new-privileges:true \
  -v ~/.openclaw:/home/node/.openclaw \
  -e HOME=/home/node \
  node:22-slim \
  bash -c 'mkdir -p /home/node/.npm-global && npm config set prefix "/home/node/.npm-global" && export PATH=/home/node/.npm-global/bin:$PATH && if ! command -v openclaw >/dev/null 2>&1; then npm install -g openclaw && cd /home/node/.npm-global/lib/node_modules/openclaw && npm install grammy @grammyjs/runner @grammyjs/transformer-throttler @grammyjs/types @buape/carbon @larksuiteoapi/node-sdk @slack/web-api; fi && (openclaw gateway --allow-unconfigured || sleep infinity)'
```

> **Design note — install-once boot:** The container only installs OpenClaw on first boot (when the binary doesn't exist yet). Subsequent restarts skip the install and go straight to `openclaw gateway`. This eliminates the npm ENOTEMPTY restart-loop bug that occurred when `npm install -g openclaw` was interrupted mid-install and left stale temp directories. To upgrade OpenClaw, use the `oc-upgrade` alias (see step 4).

> **Plugin dependency note:** The container CMD manually installs plugin dependencies on first boot because `npm install -g openclaw` does not include them (see [openclaw/openclaw#52719](https://github.com/openclaw/openclaw/issues/52719)). The `oc-upgrade` alias handles this automatically on upgrades too. **Do not use `openclaw update` directly** — it runs `npm install -g` which wipes the plugin deps, then the CLI crashes before it can sync them back. The `--allow-unconfigured` flag on `openclaw gateway` is required for newer versions that otherwise refuse to start without running `openclaw setup`.

4. **Create Shortcuts (Bash Functions & Aliases):**
*(These create a permanent `oc` shortcut for running OpenClaw commands and an `oc-upgrade` alias for upgrading OpenClaw inside the container.)*
```bash
cat >> ~/.bashrc << 'EOF'

# OpenClaw shortcuts
oc() { docker exec -it openclaw-sandbox bash -c "export PATH=/home/node/.npm-global/bin:\$PATH && openclaw $*"; }
alias oc-upgrade="docker exec openclaw-sandbox bash -c 'export PATH=/home/node/.npm-global/bin:\$PATH && npm install -g openclaw && cd /home/node/.npm-global/lib/node_modules/openclaw && npm install grammy @grammyjs/runner @grammyjs/transformer-throttler @grammyjs/types @buape/carbon @larksuiteoapi/node-sdk @slack/web-api && openclaw doctor && openclaw gateway restart'"
EOF
```

> **Upgrading OpenClaw:** Since the container no longer reinstalls on every boot, run `oc-upgrade` when you want to update to the latest version. This runs `npm install -g openclaw`, reinstalls plugin dependencies, runs `openclaw doctor`, and restarts the gateway. **Do not use `openclaw update` directly** — it wipes plugin deps during the npm reinstall, then crashes before it can sync them back ([#52719](https://github.com/openclaw/openclaw/issues/52719)).

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
$a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-u <your_wsl_username> -- bash /home/<your_wsl_username>/keep-alive.sh"
```
```powershell
$t1 = New-ScheduledTaskTrigger -AtStartup
```
```powershell
$t2 = New-ScheduledTaskTrigger -AtLogOn
```
```powershell
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -Hidden -ExecutionTimeLimit 0
```
```powershell
$p = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType S4U -RunLevel Highest
```
```powershell
Register-ScheduledTask -TaskName "KeepWSLAlive" -Action $a -Trigger @($t1, $t2) -Settings $s -Principal $p -Description "Keeps WSL alive"
```

> **Why two triggers?** `AtStartup` covers unattended reboots (e.g. Windows Update), `AtLogOn` covers normal login sessions. Without both, the task may not restart after a Windows Update reboot if no user is logged in.

Start the task immediately (without rebooting):
```powershell
Start-ScheduledTask -TaskName "KeepWSLAlive"
```

Verify it's running:
```powershell
Get-ScheduledTask -TaskName "KeepWSLAlive" | Select-Object State
Get-ScheduledTaskInfo -TaskName "KeepWSLAlive" | Select-Object LastRunTime, LastTaskResult
```
State should be `Running`. If `LastTaskResult` is `267014` ("terminated by user"), run `Start-ScheduledTask -TaskName "KeepWSLAlive"` to restart it.

> **How it works:** The task runs `sleep infinity` inside WSL, which keeps the WSL instance permanently alive. The script also starts Docker on launch. Combined with the `.bashrc` Docker auto-start (step 6) and the container's `always` restart policy, OpenClaw stays running 24/7.

> **Important gotchas discovered during debugging:**
> - `wsl -e /bin/true` (a short-lived ping) does NOT work — WSL shuts down between pings because `.bashrc` doesn't run for non-interactive shells, so Docker never starts.
> - Running the task as `SYSTEM` does NOT work — WSL distributions are per-user, so SYSTEM can't access your WSL instance.
> - Running as your user without `S4U` opens a visible console window that can be accidentally closed. The `S4U` logon type + `-Hidden` runs it invisibly.
> - PowerShell's `Register-ScheduledTask` breaks if you try to pass all parameters in a single pasted line — run each variable assignment separately.

> **To remove later:** `Unregister-ScheduledTask -TaskName "KeepWSLAlive" -Confirm:$false`

**Completion Message:**
Once everything succeeds, reboot the WSL instance immediately to permanently sever the Windows drive bridge. Type `exit` to leave your SSH session. Then, on your Windows laptop natively, run `wsl --shutdown` in PowerShell. You are safely sandboxed! (After rebooting, you can just type `oc setup` to start configuring).
