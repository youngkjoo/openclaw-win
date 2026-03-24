# WSL Backup and Restore Instructions

These instructions walk through safely backing up an existing WSL instance to a `.tar` archive and recreating a brand new instance from scratch. 

Run all commands below from your native **Windows PowerShell**.

## 1. Export (Backup) the Current Instance
This packages your entire `Ubuntu` instance (including all files, logs, and Docker containers) into a single archive on your Windows Desktop.

```powershell
# Shut down the instance completely first to ensure a safe backup
wsl --shutdown

# Export it to your Desktop (this may take a few minutes depending on size)
wsl --export Ubuntu "$env:USERPROFILE\Desktop\Ubuntu_Archive.tar"
```

## 2. Destroy and Recreate Fresh
Once you verify that `Ubuntu_Archive.tar` is safely on your Desktop, you can wipe the slate clean and install a fresh instance. 

*WARNING: Make sure your backup succeeded before unregistering!*

```powershell
# Delete the old instance permanently
wsl --unregister Ubuntu

# Re-download and install a fresh instance
wsl --install -d Ubuntu
```
*(Windows might ask you to create a new UNIX username and password for the fresh instance when it finishes installing).*

## 3. How to Access the Backup Archive Later
If you ever need to retrieve old files (like your OpenClaw `config.json`), you can "import" the `.tar` file as a completely separate, secondary WSL instance. It will run side-by-side without overwriting your new one.

```powershell
# Create a folder to hold the imported backup's virtual hard drive
mkdir "$env:USERPROFILE\Documents\WSL_Old_Backup"

# Import the .tar file as a separate instance named "Ubuntu_Old"
wsl --import Ubuntu_Old "$env:USERPROFILE\Documents\WSL_Old_Backup" "$env:USERPROFILE\Desktop\Ubuntu_Archive.tar"
```

### Accessing the old files:
Once imported, you can access both environments simultaneously:
- You can drop into the old shell via PowerShell: `wsl -d Ubuntu_Old`
- Or visually browse the archived files by opening Windows File Explorer and typing `\\wsl$\Ubuntu_Old` in the address bar!

## 4. Windows Host Resource Hardening (.wslconfig)
Since you are starting fresh, it is highly recommended to verify or re-apply the WSL resource limits. This protects your Windows laptop from memory leaks and CPU spikes inside the Linux VM.

Run this in Windows PowerShell at any time to explicitly cap WSL to **12GB RAM** and **4 CPU cores**:

```powershell
$WslConfig = @"
[wsl2]
memory=12GB
processors=4
swap=4GB
"@
Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value $WslConfig

wsl --shutdown
```
