# Troubleshooting Guide

Solutions for common Discord Bot service manager issues.

## Service Won't Start

### Symptoms
- "Service failed to start or exited immediately"
- Service appears in Stopped state
- Exit code 216 or 1

### Diagnosis
Run the built-in diagnostics:
```bash
bash botmgr.sh
# [3] Logs & Debugging → [3] Diagnose Service Issues
```

Or manually:
```bash
# Linux
journalctl --user -u discord-bot -n 50 --no-pager

# Windows
Get-EventLog -LogName System -Source nssm -Newest 20
```

### Common Root Causes

**Missing dependencies (`npm install`)**
```bash
cd /path/to/project
npm install
# Then restart service
```

**Corrupted or missing `.env` file**
```bash
# Check if file exists
ls -la .env  # Linux
dir .env    # Windows

# Verify it's readable
cat .env | head  # Linux
Get-Content .env  # Windows
```

**Node.js not in PATH**
```bash
# Verify Node.js works
node --version
npm --version

# Linux: If not found, might need to activate NVM
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
```

**Broken project files**
```bash
# Test bot manually
node index.js
# Should output startup messages
# Press Ctrl+C to stop
```

**Permission issues (Linux)**
```bash
# Fix permissions
chmod -R u+r ~/.config/discord-bot
chmod u+x ~/.config/systemd/user/discord-bot.service

# Enable linger (run services after logout)
loginctl enable-linger $(id -un)
```

**Corrupted service configuration**
```bash
# Uninstall and reinstall
bash botmgr.sh
# [5] Cleanup → [2] Uninstall Service Completely
# [1] Install Service
```

## Service Starts But Bot Isn't Responding

### Check Service Status
```bash
# Linux
systemctl --user status discord-bot
journalctl --user -u discord-bot -f

# Windows
Get-Service -Name DiscordChatbot
Get-EventLog -LogName System -Source nssm -Newest 20
```

### Verify Logs
**Linux:**
```bash
journalctl --user -u discord-bot -n 100 --no-pager | grep -i error
```

**Windows:**
```powershell
Get-Content "$env:APPDATA\discord-bot\bot.log" -Tail 50
```

### Check Environment Variables
```bash
# Linux
cat .env

# Windows
Get-Content .env
```

Verify these are set:
- `DISCORD_TOKEN` — Your Discord bot token
- `GEMINI_API_KEY` — Your Google Generative AI key

## NSSM Not Found (Windows)

### Error Message
"'nssm' is not recognized as an internal or external command"

### Solutions

**Option 1: Install via Chocolatey**
```powershell
choco install nssm
```

**Option 2: Manual Installation**
1. Download from https://nssm.cc/download
2. Extract to a folder (e.g., `C:\Program Files\nssm\`)
3. Add to PATH:
   - Press `Win + X` → System (Settings)
   - Edit system environment variables
   - Add NSSM folder to PATH
4. Restart PowerShell

**Option 3: Use Full Path**
```powershell
& "C:\path\to\nssm.exe" status DiscordChatbot
```

## Permission Errors (Linux)

### Error: "Failed to determine supplementary groups: Operation not permitted"

This was caused by the old systemd configuration. It's been fixed in the latest version.

**If you're seeing this error:**
```bash
# Uninstall old service
bash botmgr.sh
[5] Cleanup → [2] Uninstall Service Completely

# Reinstall with fixed config
[1] Install Service
```

The new configuration:
- ✅ Removed problematic `User=` directive
- ✅ Removed unnecessary memory limits
- ✅ Uses simplified, proven settings

## Logs Not Generated

### Linux

**journalctl shows nothing:**
```bash
# Verify service name
systemctl --user list-units | grep discord

# Check service file
cat ~/.config/systemd/user/discord-bot.service

# Force reload
systemctl --user daemon-reload
```

**No action log file:**
The action log is created on first service action. It will appear at:
```
~/.config/discord-bot/bot.log
```

### Windows

**No log entries in Event Viewer:**
1. Open Event Viewer: `eventvwr.msc`
2. Navigate to: Windows Logs → System
3. Filter by Source: nssm

**No bot log file:**
Create the directory manually:
```powershell
mkdir "$env:APPDATA\discord-bot" -Force
```

## Service Stops Unexpectedly

### Check Restart Configuration

**Linux:**
```bash
# View service config
cat ~/.config/systemd/user/discord-bot.service | grep -i restart
```

Should show:
```
Restart=on-failure
RestartSec=5s
```

**Windows:**
```powershell
nssm get DiscordChatbot AppRestartDelay
# Should be 5000ms (5 seconds)
```

### Check for Exit Codes

**Linux:**
```bash
journalctl --user -u discord-bot -p err
```

**Windows:**
```powershell
Get-EventLog -LogName System -Source nssm -Newest 30 |
  Where-Object {$_.EntryType -eq "Error"}
```

### Common Exit Codes
- **0** — Normal exit
- **1** — General error (check bot logs)
- **127** — Command not found (Node.js path issue)
- **216/GROUP** — Permission issue (fixed in latest release)

## Service Won't Uninstall

### Linux
```bash
# Force remove
systemctl --user stop discord-bot 2>/dev/null
systemctl --user disable discord-bot 2>/dev/null
rm -f ~/.config/systemd/user/discord-bot.service
systemctl --user daemon-reload
systemctl --user reset-failed
```

### Windows
```powershell
# Force remove
Stop-Service -Name DiscordChatbot -Force -ErrorAction SilentlyContinue
$nssm = (Get-Command nssm).Source
& $nssm remove DiscordChatbot confirm force
```

## Service Restarts Frequently

### Check Logs for Errors
```bash
# Linux
journalctl --user -u discord-bot -p err -n 30

# Windows
Get-EventLog -LogName System -Source nssm | Where-Object {$_.EntryType -eq "Error"}
```

### Common Causes
1. **Bot crashing** — Check `index.js` for runtime errors
2. **Memory issues** — Monitor resource usage:
   ```bash
   # Linux
   systemctl --user show discord-bot | grep Memory
   
   # Windows
   Get-Process | Where-Object {$_.Name -like "*node*"}
   ```
3. **API quota** — Check `.env` for valid API keys
4. **Network issues** — Verify internet connectivity

### Prevent Restart Loop
If bot crashes immediately:
```bash
# Stop service
bash botmgr.sh  # or botmgr.ps1
[2] Manage Service → [1] Stop Service

# Test manually
node index.js

# Fix bot issues, then restart service
```

## High Memory Usage

### Monitor Memory
```bash
# Linux
watch -n 1 systemctl --user show discord-bot -p MemoryCurrent

# Windows
Get-Process node | Select-Object Name, WorkingSet -AutoSize
```

### Reduce Memory Usage
1. **Comment out debug logging** in bot code
2. **Reduce message cache** if applicable
3. **Use lighter libraries** or remove unused dependencies
4. **Restart service daily** if memory leaks exist:
   ```bash
   # Linux: Add to crontab
   30 2 * * * systemctl --user restart discord-bot
   ```

## Diagnostics Tool Not Working

### Run Manual Checks

**Linux:**
```bash
# 1. Check unit file
cat ~/.config/systemd/user/discord-bot.service

# 2. Check Node.js
node --version

# 3. Check project files
ls -la index.js package.json .env

# 4. Check service status
systemctl --user status discord-bot

# 5. Check logs
journalctl --user -u discord-bot -n 20
```

**Windows:**
```powershell
# 1. Check Node.js
node --version

# 2. Check project files
dir index.js, package.json, .env

# 3. Check service status
Get-Service -Name DiscordChatbot

# 4. Check event log
Get-EventLog -LogName System -Source nssm -Newest 10
```

## Need More Help?

1. **Collect diagnostics info:**
   - Run: `bash botmgr.sh → [3] → [3]` (Linux)
   - Run: `botmgr.ps1 → [2] → [3]` (Windows)
   - Copy all output

2. **Collect logs:**
   - Linux: `journalctl --user -u discord-bot -n 100 > logs.txt`
   - Windows: `Get-EventLog -LogName System -Source nssm -Newest 100 | Export-Csv logs.csv`

3. **Test manually:**
   ```bash
   cd /path/to/project
   node index.js
   ```

4. **Check bot code:**
   - Verify `index.js` has no syntax errors
   - Test on a different machine if possible
   - Check for dependency version conflicts

---

**Last Updated:** April 10, 2026
