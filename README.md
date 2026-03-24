# Automated Guide: Securely Hosting OpenClaw and Ollama (Gemma) on Windows

This guide uses automation scripts to drastically simplify the setup required to turn your Windows 11 laptop (ROG Zephyrus G14) into a secure, 24/7 personal AI Telegram server.

Because we are creating a secure "computer-inside-a-computer" using WSL (Windows Subsystem for Linux), this process is split into two phases: **Phase A** (automating the Windows host) and **Phase B** (automating the Linux environment from your Macbook).

---

## Phase A: The Windows Host Automation (Done on the laptop)

### 1. Manual Bootstrap (Install Gemini CLI)
Before we can automate anything, the Windows laptop needs the Gemini CLI installed natively.
1. Open PowerShell as Administrator and install **Node.js for Windows** (LTS version) using the Windows Package Manager:
   ```powershell
   winget install -e --id OpenJS.NodeJS.LTS
   ```
   *(You may need to close and reopen PowerShell after this installs).*
2. Open PowerShell and install the CLI globally:
   ```powershell
   npm install -g @google/gemini-cli
   ```
3. Authenticate with your Google account:
   ```powershell
   gemini auth
   ```
   *(Note: Run this directly on the physical laptop so the browser can open and authenticate).*

### 2. Auto-Configure Windows
We will now hand the reins over to Gemini CLI. 

> [!WARNING]
> When Gemini CLI installs the OpenSSH server, it may pause for 5-10 minutes if Windows is doing background updates. If it gets completely stuck, you can cancel it with `Ctrl+C`, install OpenSSH manually via **Settings > Optional Features**, and then run the `gemini` command again.

1. Download the [`windows_automation_instructions.md`](./windows_automation_instructions.md) file to your laptop.
2. In PowerShell, tell Gemini to read and execute the instructions:
   ```powershell
   gemini run windows_automation_instructions.md
   ```
   *Gemini will automatically configure your laptop's power settings for 24/7 uptime, install the OpenSSH server, set WSL as the default SSH shell, and initiate the `wsl --install` process.*

### 3. Manual Reboot & SSH Key Transfer
1. **Restart your Windows laptop** so the WSL installation can finish.
2. **On your Macbook**, open Terminal and generate an SSH key (if you don't have one):
   ```bash
   ssh-keygen -t ed25519
   cat ~/.ssh/id_ed25519.pub
   ```
3. Copy the output.
4. Go back to your **Windows laptop**, open PowerShell as Administrator, and run:
   ```powershell
   mkdir $env:USERPROFILE\.ssh
   notepad $env:USERPROFILE\.ssh\authorized_keys
   ```
5. Paste the public key into Notepad, save it, and securely lock the file:
   ```powershell
   icacls.exe "$env:USERPROFILE\.ssh\authorized_keys" /inheritance:r /grant "Administrators:F" /grant "$($env:USERNAME):F"
   ```
6. Open your SSH configuration in Notepad:
   ```powershell
   notepad C:\ProgramData\ssh\sshd_config
   ```
7. Apply the following two critical security changes inside the file:
   - **Disable Password Logins:** Find `PasswordAuthentication yes` and change it to `PasswordAuthentication no`.
   - **Fix Administrator Keys:** Scroll to the very bottom and add a `#` to comment out these two lines so your SSH key isn't ignored:
     ```text
     # Match Group administrators
     #       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
     ```
8. Save the file (`Ctrl+S`), close Notepad, and restart the SSH service:
   ```powershell
   Restart-Service sshd
   ```

---

## Phase B: The Linux Automation (Done remotely from your Macbook)

### 1. Connect via SSH
From your Macbook's terminal, connect to your Windows laptop's native PowerShell. Once connected, type `wsl` to drop into your Linux instance!
```bash
ssh your_windows_username@<laptop_ip_address>
wsl
```

### 2. Auto-Configure Air-Gapped AI Sandbox (Docker)
To achieve maximum security, we are skipping raw Node.js installations entirely! The script will now containerize OpenClaw inside Docker and lock down your network.
1. Copy the commands from the [`wsl_automation_instructions.md`](./wsl_automation_instructions.md) script.
2. Paste them sequentially into your Linux terminal.
   *This will sever the Windows drive bridge, install Docker, and launch a pristine, secure OpenClaw inside its own impenetrable sandbox.*
3. Because the automount bridge was severed, you **MUST reboot WSL** after the script finishes by typing `exit` to leave SSH. On your physical laptop, run `wsl --shutdown` in PowerShell, then SSH back in from your Mac.

### 3. Manual Configuration (Gemini & Telegram)
1. Since you already ran the setup script, OpenClaw is currently running silently in the background as a generic Docker container. You can configure it manually from WSL!
2. SSH into WSL and open your persistent configuration file (the JSON will be blank or non-existent, so create it):
   ```bash
   nano ~/.openclaw/config.json
   ```
3. Add your Gemini API Key and Telegram bot token (from @BotFather) to the configuration:
   ```json
   {
     "llmProvider": "gemini",
     "gemini": {
       "apiKey": "YOUR_GEMINI_API_KEY"
     },
     "channels": {
       "telegram": {
         "token": "YOUR_BOTFATHER_TOKEN_HERE",
         "groupPolicy": "all"
       }
     }
   }
   ```
4. Install the Gemini and Telegram plugins inside your sandbox and restart the container:
   ```bash
   docker exec -it openclaw-sandbox bash -c "export PATH=/home/node/.npm-global/bin:\$PATH && openclaw plugin install @openclaw/gemini && openclaw plugin install @openclaw/telegram"
   docker restart openclaw-sandbox
   ```

---

## Phase C: Simple End-to-End Test

1. Because OpenClaw is thoroughly containerized and auto-restarting, you can safely close your Mac terminal. Your Windows laptop is fully secured and disconnected from the C: drive.
2. Open Telegram on your phone and send a message to your new Bot:
   *"Hi! What is 10 plus 15? Please answer as a pirate."*
3. Inside its Docker prison, OpenClaw will route the request securely to Google's Gemini API.
4. Your phone will receive the reply: *"Ahoy matey! The answer be 25! Arrr!"*
5. If you ever want to see what the bot is doing behind the scenes, just SSH in and type: 
   ```bash
   docker logs -f openclaw-sandbox
   ```
