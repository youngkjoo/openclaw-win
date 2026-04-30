# Mac Mini & OpenClaw Security Hardening Guide

Creating a dedicated, non-admin user account on your Mac Mini was a fantastic first step! Because OpenClaw runs autonomously and holds the keys to your Google Cloud / Anthropic billing accounts, securing the host operating system is critical.

Here is a checklist of advanced macOS and OpenClaw configurations to achieve a highly secure, zero-trust sandbox:

## 1. macOS System Hardening

### Enable the macOS Application Firewall
OpenClaw uses **outbound polling** to communicate with Telegram, meaning it requires absolutely **zero** inbound open network ports. 
- Go to **System Settings** -> **Network** -> **Firewall** and turn it **ON**.
- Click **Options...** and enable **"Block all incoming connections"**. 
- This makes your Mac Mini virtually invisible and impenetrable to other devices on your local network.

### Turn on FileVault (Full Disk Encryption)
Your `~/.openclaw/config.json` contains plaintext API keys. If someone were to physically steal your Mac Mini, they could easily extract the hard drive to read those keys.
- Go to **System Settings** -> **Privacy & Security** -> **FileVault** and turn it **ON**. 
- This encrypts your entire hard drive using your Mac login password.

### Restrict SSH and Sharing Services
Since you created a separate standard user for OpenClaw, you should severely restrict what that user can do remotely.
- Go to **System Settings** -> **General** -> **Sharing**.
- Ensure **File Sharing**, **Screen Sharing**, and **Remote Management** are toggled **OFF**.
- If you use **Remote Login (SSH)**, click the info `(i)` button next to it. Set **"Allow access for:"** to **"Only these users:"** and explicitly add your **Admin account**. *Do not allow your OpenClaw standard user to SSH into the machine!*

## 2. Docker Desktop Sandbox Enforcement

### Restrict File Sharing (The Air-Gap)
By default, Docker Desktop on Mac allows containers to read and write to your entire `/Users/` directory. You must manually restrict this to preserve the sandbox.
1. Open Docker Desktop -> **Settings** -> **Resources** -> **File sharing**.
2. Delete the default paths (`/Users`, `/Volumes`, `/tmp`).
3. Add **only** the absolute path to your OpenClaw folder: `/Users/<openclaw-username>/.openclaw`.
*(If the OpenClaw container is ever compromised, the attacker physically cannot read any files outside that single folder).*

## 3. OpenClaw Configuration Hardening

I reviewed your current `~/.openclaw/openclaw.json` and noticed an important setting you should change:

### Lock Down Telegram `groupPolicy`
Currently, your `channels.telegram.groupPolicy` is set to `"open"`. This means if a stranger discovers your `@JooJJBot` username, they can invite the bot to their own public Telegram group. Even though your `dmPolicy` is securely set to `"pairing"`, an `"open"` group policy acts as a loophole where strangers can `@mention` your bot in their groups and run up massive API bills.

**How to fix:**
1. Edit your `~/.openclaw/openclaw.json` file.
2. Change `"groupPolicy": "open"` to `"whitelist"` (if you want to manually specify allowed group IDs) or `"pairing"` (if you want groups to require a pairing code just like DMs).
3. Restart the container: `docker restart openclaw-sandbox`

### What You're Already Doing Right!
- `gateway.bind: "loopback"`: Your config correctly binds the OpenClaw API gateway strictly to `127.0.0.1`, meaning other computers on your network cannot access the internal API.
- `dmPolicy: "pairing"`: Strangers cannot DM your bot.
- `gateway.nodes.denyCommands`: You have successfully blocked dangerous system commands like `camera.snap`, `screen.record`, and `sms.send`.
