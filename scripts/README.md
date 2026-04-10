# Discord Bot Service Manager

Service management for the Discord Bot, enabling persistent auto-restarting services on Linux and Windows.

## Quick Start

### Linux
```bash
bash botmgr.sh
```
Then: `[1] Install Service` → `[2] Start Service`

**Requirements:** bash 4.3+, systemd, Node.js, npm

### Windows
```powershell
powershell -ExecutionPolicy Bypass -File botmgr.ps1
```
Then: `[0] Install Service` → `[0] Start Service`

**Requirements:** PowerShell 5.0+, Node.js, npm, [NSSM](https://nssm.cc/download)

## Documentation

### Getting Started
- [Linux Quick Start](LINUX_QUICKSTART.md) — Setup for Linux systems
- [Windows Quick Start](WINDOWS_QUICKSTART.md) — Setup for Windows systems
- [Troubleshooting](TROUBLESHOOTING.md) — Common issues and solutions

### Script Files
- [botmgr.sh](botmgr.sh) — Linux service manager (systemd)
- [botmgr.ps1](botmgr.ps1) — Windows service manager (NSSM)

## Features

✅ **Persistent Services** — Auto-restarts on failure (5-second delay)
✅ **Boot Persistence** — Starts automatically on system reboot
✅ **Real Status Verification** — Confirms services actually start
✅ **Integrated Logging** — journalctl (Linux) / Event Viewer (Windows)
✅ **Built-in Diagnostics** — Automatic troubleshooting tools
✅ **Easy Management** — Interactive menu interface
✅ **Clean Configuration** — Simplified, proven settings

## Direct Commands (Advanced)

### Linux
```bash
# View service status
systemctl --user status discord-bot

# View logs
journalctl --user -u discord-bot -n 50 --no-pager
journalctl --user -u discord-bot -f  # Follow live

# Manual control (after installation)
systemctl --user start discord-bot
systemctl --user stop discord-bot
systemctl --user restart discord-bot
```

### Windows
```powershell
# View service status
Get-Service -Name DiscordChatbot

# View logs
Get-EventLog -LogName System -Source nssm -Newest 20

# Manual control (after installation)
Start-Service -Name DiscordChatbot
Stop-Service -Name DiscordChatbot
Restart-Service -Name DiscordChatbot
```

## Configuration

### Linux
- **Service File:** `~/.config/systemd/user/discord-bot.service`
- **Log Directory:** `~/.config/discord-bot/`
- **Log File:** `~/.config/discord-bot/bot.log`

### Windows
- **Log Directory:** `%APPDATA%\discord-bot\`
- **Log File:** `%APPDATA%\discord-bot\bot.log`
- **Registry:** Services stored in Windows Registry (view via `services.msc`)

## Uninstall

### Linux
```bash
bash botmgr.sh
# → [5] Cleanup / Removal → [2] Uninstall Service Completely

# Optional: Remove all config
rm -rf ~/.config/discord-bot
```

### Windows
```powershell
powershell -ExecutionPolicy Bypass -File botmgr.ps1
# → [4] Cleanup / Removal → [1] Uninstall Service Completely

# Optional: Remove all config
rmdir $env:APPDATA\discord-bot -Recurse
```

## Prerequisites

### Linux
- bash 4.3+
- systemd (standard on all modern distros)
- Node.js & npm
- Basic utilities (systemctl, journalctl)

### Windows
- PowerShell 5.0+
- Node.js & npm
- NSSM ([download](https://nssm.cc/download) or `choco install nssm`)
- Administrator permissions (for service operations)

## Troubleshooting

For common issues and solutions, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

Quick diagnostic check in the menu:
- **[3] Logs & Debugging** → **[3] Diagnose Service Issues**

This will automatically check:
- System requirements (Node.js, npm)
- Project files (index.js, package.json, node_modules)
- Configuration files (.env)
- Permissions and service status
- Recent error logs

## Support

1. **Run diagnostics** — Use menu option [3] → [3]
2. **Check logs** — [3] → [0] or [1]
3. **Test manually** — Run `node index.js` directly
4. **Review TROUBLESHOOTING.md** — Common solutions documented  
**Last Updated:** 2024  
**Tested on:** Linux (Ubuntu 20.04+, Debian), Windows 10/11

**Ready to get started? Pick your platform:**
- 🐧 **[Linux Quick Start](LINUX_QUICKSTART.md)**
- 🪟 **[Windows Quick Start](WINDOWS_QUICKSTART.md)**
