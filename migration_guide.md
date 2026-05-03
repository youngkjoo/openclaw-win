# OpenClaw Migration Guide (WSL to Mac Mini)

This guide covers the end-to-end process of migrating your OpenClaw instance from your Windows WSL environment to a new Mac Mini. It ensures that all of your configurations, multi-agent memories (`main` and `sysadmin`), Telegram bot state, and automated backup schedules are perfectly preserved while adapting to macOS differences.

---

## Phase 1: Decommissioning WSL Persistence

We must completely dismantle the automation on your Windows machine to ensure it doesn't "wake up" and fight the Mac Mini for control of your Telegram bots.

### 1. Kill the Persistence Layer (Windows PowerShell)
On your **Windows Host** (not inside WSL), open PowerShell as **Administrator** and run these commands to stop the background "Keep-Alive" tasks:

```powershell
# Stop and delete the Scheduled Task
Stop-ScheduledTask -TaskName "KeepWSLAlive" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "KeepWSLAlive" -Confirm:$false -ErrorAction SilentlyContinue

# Reset WSL Idle timeout to default (allow it to shut down)
$WslConfig = Get-Content "$env:USERPROFILE\.wslconfig"
$WslConfig = $WslConfig | Where-Object { $_ -notmatch "vmIdleTimeout" }
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value $WslConfig
```

### 2. Stop the OpenClaw Container & Clean Bash (WSL)
Now, enter your **WSL terminal** and run:

1. **Stop the container:**
   ```bash
   docker stop openclaw-sandbox
   ```
2. **Remove the container (Optional but recommended):**
   ```bash
   docker rm openclaw-sandbox
   ```
3. **Clean up .bashrc:** Open `~/.bashrc` and delete the "Auto-start Docker" block you added previously. This prevents the Docker daemon from starting every time you accidentally open a terminal.

### 3. Final WSL Shutdown (Windows PowerShell)
Return to your **Windows Host PowerShell** and force a complete shutdown of the Linux subsystem:
```powershell
wsl --shutdown
```
> [!IMPORTANT]
> **WSL is now truly dead.** It will not restart until you manually open a WSL terminal. This is the only way to guarantee Telegram bot stability.


---

## Phase 2: Environment Preparation (Mac Mini)

Before moving any data, you must prepare the Mac Mini to act as a secure, efficient server. Following the **Principle of Least Privilege**, we will split roles between two users.

### 1. Create the Account Hierarchy
*   **Admin Account (e.g., `admin`)**: Used exclusively for system maintenance, software installation, and security configuration. 
*   **Standard Account (e.g., `openclaw`)**: A restricted, non-administrator account. This is where OpenClaw will run. It has no permission to modify system settings or access other users' files.

> [!TIP]
> **Efficiency Tip:** In *System Settings > Users & Groups*, enable **Automatic Login** for the **Standard Account**. This ensures that if the Mac Mini power cycles, it will automatically boot into the restricted account and start your agents without requiring a physical keyboard/monitor.

### 2. Security Hardening (Admin Account)
Log in as the **Admin** and apply these baseline protections:
*   **FileVault:** Enable in *System Settings > Privacy & Security*. This ensures that if the Mac is physically stolen, your agent's memories remain encrypted.
*   **Firewall (Stealth Mode):** Enable in *System Settings > Network > Firewall*. Go to *Options* and check **"Enable stealth mode"**. This makes your Mac ignore "ping" requests and port scans from the network.
*   **Remote Login (SSH):** Enable in *Sharing*. 
    *   **Security Tip:** Click the info icon and restrict access to **Only the Admin account**. If you need to run commands as the Standard user, SSH as Admin first, then use `su - openclaw`.

### 3. Energy & Efficiency
*   **Energy Saver:** Enable **"Start up automatically after a power failure"** and **"Wake for network access"**.
*   **Display:** Set "Turn display off on battery/power adapter" to a short interval, but ensure **"Prevent automatic sleeping when the display is off"** is toggled **ON** in the Advanced/Energy Saver settings.

---

## Phase 3: Packaging & Transferring Data

Now that the source machine is safely silenced, we can package the data. (Since WSL is stopped, you will need to start it **one last time** to run these commands, then immediately shut it down again).

### 1. Export Cron Jobs (Backup Schedule)

Save your current automated backup schedule to a text file:
```bash
crontab -l > ~/openclaw-cron-backup.txt
```

### 3. Create the Complete Migration Archive
Run this command in WSL to bundle your OpenClaw configurations, runtime data, backup scripts, and your `rclone` Google Drive tokens:
```bash
tar -czvf ~/openclaw-migration.tar.gz \
  -C /home/young \
  .openclaw \
  openclaw-win \
  .config/rclone \
  openclaw-cron-backup.txt
```
*(Note: Because we are copying the entire `~/.openclaw` directory, both your `main` and `sysadmin` agents, along with their respective Telegram bot bindings and `auth-profiles.json`, will migrate together seamlessly.)*

### 4. Transfer the Archive (via Google Drive)
Because Windows WSL runs behind an internal virtual network, transferring files directly via local `scp` can be highly problematic (often resulting in `Connection reset by peer` errors).

The most seamless and foolproof method is to use the `rclone` tool that is already perfectly configured on your WSL machine to push the archive to your Google Drive!

Run this exact command in your **WSL terminal**:
```bash
rclone copy ~/openclaw-migration.tar.gz agent-drive:openclaw-backups/migration/
```

Then, **log into your OpenClaw standard account** on the Mac Mini, open a web browser, log into your Google Drive, navigate to the `openclaw-backups/migration/` folder, and download `openclaw-migration.tar.gz` to your standard user's Home folder (`~/`).

---

## Phase 4: Importing Data on the Mac Mini


macOS has different underlying tooling, paths, and permissions compared to Ubuntu/WSL. Follow these steps carefully to maintain your strict security posture.

### 1. Setup Docker Desktop (Dual-Account Workflow)
On macOS, Docker Desktop runs a virtual machine within the user's session. To keep it isolated:

1.  **Installation (Admin Account):** Log in as your **Admin** user. Download and install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/). 
2.  **Initial Run:** Launch Docker once as Admin to allow it to install its privileged helper (it will prompt for your admin password).
3.  **Privileged Tasks:** In Docker Settings, ensure "Allow the default Docker socket to be used" is enabled. This allows the Standard user to communicate with the daemon.
4.  **Runtime (Standard Account):** Log out and **log into your Standard Account** (e.g., `openclaw`).
5.  **Launch Docker:** Launch Docker Desktop from the Applications folder. It should now run under your restricted user's context.
6.  **Set as Login Item:** Open *System Settings > General > Login Items* and add **Docker** to the list. This ensures it starts automatically when the Standard user logs in (via the Automatic Login we set in Phase 0).
7.  **Maintain the Air-Gap:** Open Docker Desktop -> **Settings** -> **Resources** -> **File sharing**.
    - Remove all default paths (like `/Users`, `/Volumes`, `/tmp`).
    - Add **only** the specific OpenClaw data path: `/Users/<standard-username>/.openclaw`.
8.  **Hardware Resource Limits:** The strict 12GB RAM cap you used on Windows was necessary due to a severe WSL2 disk caching bug (`vmmem`). On an Apple Silicon Mac, Docker uses the highly optimized Apple Virtualization Framework which manages memory dynamically. Because OpenClaw is lightweight (< 300MB RAM), **you can safely leave Docker Desktop on its default resource settings**.

### 2. Install Additional Mac Dependencies
Because your OpenClaw account is a standard user, Homebrew installation is restricted. Follow this sequence:

1.  **Log into your Admin account.**
2.  Install Homebrew if not already present: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`.
3.  Install the required migration tools system-wide:
    ```bash
    brew install rclone gnu-tar
    ```
4.  **Log back into your Standard account.** Your scripts can now access these tools at `/opt/homebrew/bin/rclone` and `/opt/homebrew/bin/gtar`.


### 3. Extract the Archive
Place `openclaw-migration.tar.gz` in your Mac's Home folder (`~/`), then extract it:
```bash
cd ~
tar -xzvf ~/openclaw-migration.tar.gz -C ~/
```

### 4. Update File Paths & OpenClaw Configuration (CRITICAL)
Your WSL home directory was `/home/young`, but your Mac home directory is `/Users/<your-standard-username>`. **You must update all hardcoded paths.**

1. **Fix macOS Network Binding:** Apple Silicon Macs sometimes struggle with Docker's IPv6 loopback routing, which can cause the OpenClaw API gateway to silently hang on boot.
   - Open `~/.openclaw/openclaw.json` in a text editor.
   - Find the `"gateway"` section (around line 120) and change `"bind": "loopback"` to `"bind": "all"`. *(This is completely safe because the Mac Firewall is active and the port is not exposed to the LAN).*

2. **Edit Backup Scripts**: Open `~/openclaw-win/scripts/openclaw-backup.sh` (and `antigravity-backup.sh` if used).
   - Change `SOURCE_DIR="/home/young/.openclaw"` to `/Users/<your-mac-username>/.openclaw`
   - Change `LOG_FILE="/home/young/.openclaw/...` to `/Users/<your-mac-username>/.openclaw/...`
   - Change `/usr/bin/tar` to the GNU tar installed by Homebrew: `/opt/homebrew/bin/gtar` (or `/usr/local/bin/gtar` on Intel Macs).
   - Change `/usr/bin/rclone` to the Homebrew rclone: `/opt/homebrew/bin/rclone` (or `/usr/local/bin/rclone`).
   - Change the `-C /home/young .openclaw` tar argument to `-C /Users/<your-mac-username> .openclaw`
   
2. **Edit Cron Tasks**: Open `~/openclaw-cron-backup.txt` and replace every instance of `/home/young/...` with `/Users/<your-mac-username>/...`

### 5. Restore Aliases (zsh instead of bash)
macOS uses `zsh` by default, not `bash`. Add your OpenClaw shortcuts to your `~/.zshrc`:
```bash
cat >> ~/.zshrc << 'EOF'

# OpenClaw shortcuts
oc() { docker exec -it openclaw-sandbox openclaw "$@"; }
alias oc-upgrade="docker pull ghcr.io/openclaw/openclaw:latest && docker stop openclaw-sandbox && docker rm openclaw-sandbox && docker run -d --name openclaw-sandbox --restart always --security-opt no-new-privileges:true -v ~/.openclaw:/home/node/.openclaw -e HOME=/home/node ghcr.io/openclaw/openclaw:latest"
EOF

source ~/.zshrc
```
*(Note: We intentionally removed `--user 1000:1000` from the Mac startup command. Docker Desktop on Mac automatically manages VirtioFS file permissions between the host and container. Enforcing UID 1000 can sometimes cause `EACCES` permission denied errors on macOS volume mounts).*

### 6. Start OpenClaw
Spin up your agent in its Docker sandbox:
```bash
docker run -d \
  --name openclaw-sandbox \
  --restart always \
  --security-opt no-new-privileges:true \
  -v ~/.openclaw:/home/node/.openclaw \
  -e HOME=/home/node \
  ghcr.io/openclaw/openclaw:latest
```

**Run the OpenClaw Doctor (Crucial for Upgrades):**
Because you are moving to the `latest` image version, you must let OpenClaw internally normalize its plugins and cron database to prevent the boot process from hanging:
```bash
docker exec -it openclaw-sandbox openclaw doctor --fix
docker restart openclaw-sandbox
```

To verify the migration was flawless, follow the live logs:
```bash
docker logs -f openclaw-sandbox
```
Wait a few seconds for the line `[telegram] [default] starting provider (@JooJJBot)`. If you see that, the container has successfully reattached to your memories and state!

### 7. Grant macOS Cron Permissions
macOS privacy settings block `cron` from reading the Documents, Desktop, and Home folders by default. Your automated backups will fail if you skip this step.
1. Open **System Settings** -> **Privacy & Security** -> **Full Disk Access**.
2. Click the `+` button. *(You will need to authenticate with your Admin credentials to unlock this menu)*.
3. Press `Cmd + Shift + G` and type `/usr/sbin/cron`, then select the `cron` executable.
4. Ensure the toggle next to `cron` is turned on.

### 8. Restore the Backup Schedule
Now that paths are updated and permissions are granted, load your cron jobs:
```bash
crontab ~/openclaw-cron-backup.txt
```

### 9. Disable Mac Sleep
Unlike WSL which needed a complex scheduled `keep-alive.sh` task, your Mac Mini just needs to stay awake physically:
- Go to **System Settings** -> **Displays** -> **Advanced...** (or **Energy Saver**) and turn on **"Prevent automatic sleeping when the display is off"**.

### 10. Apply Advanced Security Hardening
Before declaring the migration complete, please strictly follow the **[Mac Security Hardening Guide](./mac_security_hardening.md)** to lock down your macOS firewall, encrypt your disk, restrict Docker file sharing, and close Telegram policy loopholes.

You can verify OpenClaw is running healthy by checking `docker ps` and testing both your `@JooJJBot` (main) and `@DF_Sysop_Bot` (sysadmin) Telegram bots!
