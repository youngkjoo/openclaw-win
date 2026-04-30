# OpenClaw Migration Guide (WSL to Mac Mini)

This guide covers the end-to-end process of migrating your OpenClaw instance from your Windows WSL environment to a new Mac Mini. It ensures that all of your configurations, multi-agent memories (`main` and `sysadmin`), Telegram bot state, and automated backup schedules are perfectly preserved while adapting to macOS differences.

## Phase 1: Exporting Data from the Current Windows/WSL Machine

We need to safely package all OpenClaw-related data while the agent is stopped so no new state is written.

### 1. Stop the OpenClaw Container
Stop the currently running OpenClaw instance in WSL:
```bash
docker stop openclaw-sandbox
```
> [!CAUTION]
> **Never run the WSL container and the Mac container at the same time.** Telegram uses an active polling mechanism. If both machines are running, they will aggressively compete for your messages, causing erratic behavior where half your messages go to the old machine and half to the new one. Keep the WSL container permanently stopped from this point forward.

### 2. Export Cron Jobs (Backup Schedule)
Save your current automated backup schedule to a text file:
```bash
crontab -l > ~/openclaw-cron-backup.txt
```

### 3. Create the Complete Migration Archive
Run this command in WSL to bundle your OpenClaw configurations, runtime data, backup scripts, your `rclone` Google Drive tokens, and your Gemini CLI credentials:
```bash
tar -czvf ~/openclaw-migration.tar.gz \
  -C /home/young \
  .openclaw \
  openclaw-win \
  .config/rclone \
  .config/geminiacli \
  openclaw-cron-backup.txt
```
*(Note: Because we are copying the entire `~/.openclaw` directory, both your `main` and `sysadmin` agents, along with their respective Telegram bot bindings and `auth-profiles.json`, will migrate together seamlessly.)*

> [!IMPORTANT]
> The resulting `~/openclaw-migration.tar.gz` file contains highly sensitive information, including your Gemini API Keys, Telegram Bot tokens, and Google Drive access tokens. Transfer it securely via a USB drive or local network transfer (`scp`) to your Mac Mini.

Since you have SSH access to both machines, you can securely transfer the archive directly over your local network using `scp`. 

Run this command from your **Mac Mini** terminal to pull the file directly from the WSL machine:
```bash
scp <wsl_username>@<wsl_ip_address>:~/openclaw-migration.tar.gz ~/
```
*(Alternatively, you can run `scp ~/openclaw-migration.tar.gz <mac_username>@<mac_ip_address>:~/` from your WSL machine to push it to the Mac.)*

---

## Phase 2: Importing Data on the Mac Mini

macOS has different underlying tooling, paths, and permissions compared to Ubuntu/WSL. Follow these steps carefully on the Mac to preserve your strict security posture.

### 1. Setup Docker Desktop & Preserve the Sandbox (CRITICAL)
On Windows, you deliberately avoided Docker Desktop to keep your `C:\` drive physically isolated from the container. On macOS, Docker Desktop is required, but it shares your entire home directory by default!

1. Download and install [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop/). **Do not use the Linux `get-docker.sh` script.**
2. **Maintain the Air-Gap:** Open Docker Desktop -> **Settings** -> **Resources** -> **File sharing**.
   - Remove all default paths (like `/Users`, `/Volumes`, `/tmp`).
   - Add **only** your specific OpenClaw data path: `/Users/<your-mac-username>/.openclaw`.
3. **Hardware Resource Limits:** The strict 12GB RAM cap you used on Windows was necessary due to a severe WSL2 disk caching bug (`vmmem`). On an Apple Silicon Mac, Docker uses the highly optimized Apple Virtualization Framework which manages memory dynamically. Because OpenClaw is lightweight (< 300MB RAM), **you can safely leave Docker Desktop on its default resource settings** (unless you plan to run heavy local LLMs like Ollama inside Docker later).

### 2. Install Additional Mac Dependencies
If you don't have Homebrew installed, open macOS Terminal and run:
`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

macOS comes with BSD `tar`, but your backup scripts rely on GNU `tar` extensions (like `--transform`). Install GNU Tar and rclone:
```bash
brew install rclone gnu-tar
```

### 3. Extract the Archive
Place `openclaw-migration.tar.gz` in your Mac's Home folder (`~/`), then extract it:
```bash
cd ~
tar -xzvf ~/openclaw-migration.tar.gz -C ~/
```

### 4. Update File Paths & Scripts (CRITICAL)
Your WSL home directory was `/home/young`, but your Mac home directory is `/Users/<your-mac-username>`. **You must update all hardcoded paths.**

1. **Edit Backup Scripts**: Open `~/openclaw-win/scripts/openclaw-backup.sh` (and `antigravity-backup.sh` if used).
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
To verify the migration was flawless, simply run `docker logs openclaw-sandbox`. If you see `[telegram] [main] starting provider`, the container has successfully reattached to your memories and state.

### 7. Grant macOS Cron Permissions
macOS privacy settings block `cron` from reading the Documents, Desktop, and Home folders by default. Your automated backups will fail if you skip this step.
1. Open **System Settings** -> **Privacy & Security** -> **Full Disk Access**.
2. Click the `+` button.
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

You can verify OpenClaw is running healthy by checking `docker ps` and testing both your `@JooJJBot` (main) and `@DF_Sysop_Bot` (sysadmin) Telegram bots!
