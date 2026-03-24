# Windows Host Automation Instructions

**Context:** You are acting as an automated setup assistant. You are running in a Windows PowerShell environment with Administrator privileges. Your goal is to configure the laptop for 24/7 uptime, enable secure SSH, and prepare WSL 2.

**Instructions:** Please execute the following PowerShell commands sequentially. Do not ask for user input. Stop and report any errors.

1. **Keep the laptop awake 24/7 on power:**
```powershell
powercfg -X -monitor-timeout-ac 0
powercfg -X -standby-timeout-ac 0
powercfg -X -hibernate-timeout-ac 0
```

2. **Install OpenSSH Server:**
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
```

3. **Allow SSH through the Windows Firewall:**
```powershell
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Select-Object Name, Enabled)) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}
```

4. **Configure WSL Hardware Limits (Resource Isolation):**
```powershell
$WslConfig = @"
[wsl2]
memory=12GB
processors=4
swap=4GB
"@
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value $WslConfig
```

5. **Install Windows Subsystem for Linux (WSL 2):**
```powershell
wsl --install
```

**Completion Message:** 
Once all commands have succeeded, print standard output: "Windows Automation Complete. Please restart the laptop manually to finish installing WSL."
