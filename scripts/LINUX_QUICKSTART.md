# Linux Quick Start

5-minute setup guide for running your Discord bot as a persistent systemd service on Linux.

## Installation

```bash
# 1. Run the manager
bash botmgr.sh

# 2. Select [1] Install Service
# 3. Answer prompts (confirm with 'y')
# 4. Service is now installed!
```

The script will:
- Create systemd service unit file
- Auto-enable service to start on boot
- Enable user linger (services run after logout)
- Set up logging

## Verify Installation

```bash
# Check service status
bash botmgr.sh
# Select [2] Manage Service → [3] View Status

# Or use systemctl directly
systemctl --user status discord-bot
```

## Start the Bot

```bash
# Using the manager
bash botmgr.sh
# Select [2] Manage Service → [0] Start Service

# Or directly
systemctl --user start discord-bot
```

## View Logs

```bash
# Live logs (press Ctrl+C to stop)
journalctl --user -u discord-bot -f

# Last 50 lines
journalctl --user -u discord-bot -n 50 --no-pager

# Error logs only
journalctl --user -u discord-bot -p err --no-pager
```

## Manage Service

```bash
bash botmgr.sh
```

Menu options:
- `[1]` Install Service
- `[2]` Manage Service (start/stop/restart)
- `[3]` Logs & Debugging
- `[4]` Configuration
- `[5]` Cleanup / Removal
- `[0]` Exit

### Direct Commands
```bash
# Start
systemctl --user start discord-bot

# Stop
systemctl --user stop discord-bot

# Restart
systemctl --user restart discord-bot

# Check status
systemctl --user status discord-bot
```

## Troubleshooting

### Service won't start
```bash
# Run diagnostics
bash botmgr.sh
# → [3] Logs & Debugging → [3] Diagnose Service Issues

# Or check logs manually
journalctl --user -u discord-bot -n 50 --no-pager
```

### Check if bot runs manually
```bash
cd /path/to/discord-chatbot
node index.js
# You should see bot startup messages
# Press Ctrl+C to stop
```

### Common issues
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions.

## Service Details

- **Service file:** `~/.config/systemd/user/discord-bot.service`
- **Config directory:** `~/.config/discord-bot/`
- **Log file:** `~/.config/discord-bot/bot.log` (action history)
- **Auto-restart:** 5-second delay on failure
- **Boot start:** Enabled with user linger

## Uninstall

```bash
bash botmgr.sh
# → [5] Cleanup / Removal → [2] Uninstall Service Completely
```

This preserves:
- Source code and scripts
- Configuration directory (`~/.config/discord-bot/`)
- .env file

## Next Steps

- Review [README.md](README.md) for advanced usage
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if issues arise
- Monitor logs regularly: `journalctl --user -u discord-bot -f`
journalctl --user -u discord-bot -f
```

## What Gets Installed

- **systemd unit file:** `~/.config/systemd/user/discord-bot.service`
- **Config directory:** `~/.config/discord-bot/`
- **Logs:** `~/.config/discord-bot/bot.log`

## Verification

After installation, verify it works:

```bash
# Should show "active (running)"
systemctl --user status discord-bot

# Should show recent bot startup logs
journalctl --user -u discord-bot -n 5 --no-pager
```

## Troubleshooting

Bot not starting?
```bash
# Check for errors
journalctl --user -u discord-bot --no-pager -n 30

# Try running manually to see real errors
cd /path/to/bot && node index.js
```

Can't access logs?
```bash
# Ensure user lingering is enabled
loginctl enable-linger $(id -un)

# Then try again
journalctl --user -u discord-bot -f
```

## Uninstall

```bash
bash scripts/bot-manager-linux.sh  # → [5] Cleanup / Removal → [2] Uninstall
```
