# Windows Quick Start

5-minute setup guide for running your Discord bot as a persistent Windows service.

## Prerequisites

1. **Node.js** — https://nodejs.org (installs npm automatically)
2. **NSSM** — https://nssm.cc/download (required)

### Install NSSM

**Option A: Chocolatey (Recommended)**
```powershell
choco install nssm
```

**Option B: Manual**
1. Download from https://nssm.cc/download
2. Extract to `C:\Program Files\nssm` or similar
3. Add to PATH: 
   - Press `Win + X` → System (Settings)
   - Select "Advanced system settings"
   - Environment Variables → add NSSM folder to PATH
4. Restart PowerShell

**Verify installation:**
```powershell
nssm version
```

## Installation

1. **Open PowerShell as Administrator**
   - Right-click PowerShell → "Run as Administrator"

2. **Run the manager:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File botmgr.ps1
   ```

3. **Select [0] Install Service**

4. **Follow prompts:**
   - Confirm installation
   - Script sets up service with defaults

Done! Service is now installed and will auto-start on reboot.

## Verify Installation

```powershell
# Check service status
Get-Service -Name DiscordChatbot

# Or use manager
powershell -ExecutionPolicy Bypass -File botmgr.ps1
# Select [1] Manage Service → [3] View Status
```

## Start the Bot

```powershell
# Using manager
powershell -ExecutionPolicy Bypass -File botmgr.ps1
# Select [1] Manage Service → [0] Start Service

# Or directly
Start-Service -Name DiscordChatbot

# Or using NSSM
nssm start DiscordChatbot

# Or using Services Manager
# Press Win+R → type "services.msc" → Find "Discord Chatbot" → Start
```

## View Logs

```powershell
# Bot action log
Get-Content "$env:APPDATA\discord-bot\bot.log" -Tail 50

# Windows Event Log
Get-EventLog -LogName System -Source nssm -Newest 20

# Or open Event Viewer GUI
eventvwr.msc
# → Windows Logs → System
# → Filter by source "nssm"
```

## Manage Service

```powershell
powershell -ExecutionPolicy Bypass -File botmgr.ps1
```

Menu options:
- `[0]` Install Service
- `[1]` Manage Service (start/stop/restart)
- `[2]` Logs & Debugging
- `[3]` Configuration
- `[4]` Cleanup / Removal
- `[5]` Exit

### Direct Commands
```powershell
# Start
Start-Service -Name DiscordChatbot

# Stop
Stop-Service -Name DiscordChatbot

# Restart
Restart-Service -Name DiscordChatbot

# Status
Get-Service -Name DiscordChatbot
```

### Using Services Manager GUI
```powershell
# Open services manager
services.msc

# Find "Discord Chatbot"
# Right-click → Start/Stop/Restart
```

## Troubleshooting

### Service won't start
```powershell
# Run diagnostics
powershell -ExecutionPolicy Bypass -File botmgr.ps1
# → [2] Logs & Debugging → [3] Diagnose Service Issues

# Or check Event Viewer
Get-EventLog -LogName System -Source nssm -Newest 10
```

### Check if bot runs manually
```powershell
cd C:\path\to\discord-chatbot
node index.js
# You should see bot startup messages
# Press Ctrl+C to stop
```

### NSSM not found
```powershell
# Reinstall NSSM
choco install nssm

# Or download from https://nssm.cc/download
# Add to PATH manually
```

### Common issues
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions.

## Service Details

- **Service name:** `DiscordChatbot`
- **Log directory:** `%APPDATA%\discord-bot\`
- **Log file:** `%APPDATA%\discord-bot\bot.log` (action history)
- **Auto-restart:** 5-second delay on failure
- **Boot start:** Enabled

Expand the path by pressing `Win + R` and typing:
```
%APPDATA%\discord-bot
```

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File botmgr.ps1
# → [4] Cleanup / Removal → [1] Uninstall Service Completely
```

This preserves:
- Source code and scripts
- Configuration directory (`%APPDATA%\discord-bot\`)
- .env file

### Manual Uninstall
```powershell
# Stop service
Stop-Service -Name DiscordChatbot

# Remove service
nssm remove DiscordChatbot confirm
```

## Next Steps

- Review [README.md](README.md) for advanced usage
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if issues arise
- Monitor logs regularly: `Get-EventLog -LogName System -Source nssm -Newest 5`
- **Bot auto-restarts** if it crashes (check logs to see why)
- **Service auto-starts** when Windows reboots

---

**Quick Cheatsheet:**

| Task | Command |
|------|---------|
| Run manager | `powershell -ExecutionPolicy Bypass -File scripts\bot-manager-windows.ps1` |
| Start service | `nssm start DiscordChatbot` |
| Stop service | `nssm stop DiscordChatbot` |
| View status | `nssm status DiscordChatbot` |
| View logs | `Get-Content "$env:APPDATA\discord-bot\bot.log" -Tail 50` |
| View GUI | `services.msc` → find "Discord Chatbot" |
