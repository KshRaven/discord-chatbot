# ======================================================================
#  bot-manager-windows.ps1  —  Discord Chatbot Service Manager (Windows)
#
#  Manages the Discord bot as a persistent Windows service with:
#    • Auto-start on system reboot
#    • Automatic restart on failure
#    • Event log integration
#    • Service lifecycle management (start/stop/restart)
#    • Interactive menu interface
#
#  Requirements: PowerShell 5.0+, Node.js, npm, NSSM (recommended)
#  Usage: powershell -ExecutionPolicy Bypass -File bot-manager-windows.ps1
#
#  Note: Run as Administrator for service operations
# ======================================================================

#Requires -Version 5.0

param(
    [switch]$Admin = $false
)

# ======================================================================
# CONFIGURATION
# ======================================================================
$Script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Script:ScriptDir = Split-Path $PSScriptRoot -Parent
$Script:ConfigDir = "$env:APPDATA\discord-bot"
$Script:BotName = "Discord Chatbot"
$Script:ServiceName = "DiscordChatbot"
$Script:BotLogPath = "$ConfigDir\bot.log"
$Script:BotExe = "node.exe"
$Script:MainScript = "$ProjectRoot\index.js"
$Script:NssmUrl = "https://nssm.cc/download"

# Ensure config dir exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# ======================================================================
# FUNCTIONS: UI & FORMATTING
# ======================================================================

function Write-Banner {
    param([string]$Text, [ConsoleColor]$Color = "Cyan")
    $width = $Host.UI.RawUI.WindowSize.Width
    $width = [Math]::Min($width, 100)
    $width = [Math]::Max($width, 50)
    
    $padding = [Math]::Max(0, ($width - $Text.Length) / 2)
    Write-Host "`n" -NoNewline
    Write-Host ("=" * $width) -ForegroundColor DarkGray
    Write-Host (' ' * $padding) $Text -ForegroundColor $Color -BackgroundColor Black
    Write-Host ("=" * $width) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-OK {
    param([string]$Message)
    Write-Host "  ✓  " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠  " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "  ✗  " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "  ·  " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Read-Menu {
    param(
        [array]$Options,
        [string]$Prompt = "Select an option"
    )
    
    while ($true) {
        Write-Host ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host "  $($i)  $($Options[$i])"
        }
        Write-Host ""
        $selection = Read-Host "$Prompt (0-$($Options.Count - 1))"
        
        if ([int]::TryParse($selection, [ref]$null) -and [int]$selection -ge 0 -and [int]$selection -lt $Options.Count) {
            return [int]$selection
        }
        Write-Error2 "Invalid selection"
    }
}

function Confirm-Action {
    param([string]$Message = "Are you sure?")
    $response = Read-Host "$Message (y/N)"
    return $response -eq 'y' -or $response -eq 'Y'
}

function Request-AdminPrivilege {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warn "This operation requires administrator privileges"
        Write-Info "Attempting to elevate..."
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Admin" -Verb RunAs
        exit 0
    }
}

function Log-Action {
    param([string]$Action)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $Script:BotLogPath -Value "[$timestamp] $Action"
}

# ======================================================================
# FUNCTIONS: PREREQUISITE CHECKING
# ======================================================================

function Check-Prerequisites {
    Clear-Host
    Write-Banner "DISCORD BOT MANAGER — PREREQUISITE CHECK" "Cyan"
    
    $allPass = $true
    
    # 1. Node.js
    Write-Host "[1/4] Node.js" -ForegroundColor White -BackgroundColor Black
    $nodeVersion = node --version 2>$null
    if ($nodeVersion) {
        Write-OK "Node.js: $nodeVersion"
    } else {
        Write-Error2 "Node.js not found"
        Write-Info "Download from https://nodejs.org/"
        $allPass = $false
    }
    Write-Host ""
    
    # 2. npm
    Write-Host "[2/4] npm" -ForegroundColor White -BackgroundColor Black
    $npmVersion = npm --version 2>$null
    if ($npmVersion) {
        Write-OK "npm: $npmVersion"
    } else {
        Write-Error2 "npm not found"
        $allPass = $false
    }
    Write-Host ""
    
    # 3. Project files
    Write-Host "[3/4] Project Files" -ForegroundColor White -BackgroundColor Black
    if (Test-Path "$ProjectRoot\index.js") {
        Write-OK "index.js found"
    } else {
        Write-Error2 "index.js not found at $ProjectRoot\index.js"
        $allPass = $false
    }
    
    if (Test-Path "$ProjectRoot\package.json") {
        Write-OK "package.json found"
    } else {
        Write-Error2 "package.json not found"
        $allPass = $false
    }
    
    if (Test-Path "$ProjectRoot\.env") {
        Write-OK ".env file found"
    } else {
        Write-Warn ".env file not found — bot may fail if it requires environment variables"
    }
    Write-Host ""
    
    # 4. NSSM
    Write-Host "[4/4] NSSM (Non-Sucking Service Manager)" -ForegroundColor White -BackgroundColor Black
    $nssmPath = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmPath) {
        Write-OK "NSSM found: $($nssmPath.Source)"
    } else {
        Write-Warn "NSSM not found (recommended for service management)"
        Write-Info "Download from $Script:NssmUrl or run: choco install nssm"
    }
    Write-Host ""
    
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    if ($allPass) {
        Write-OK "All critical checks passed"
    } else {
        Write-Warn "Some checks failed — fix issues before proceeding"
    }
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    
    Read-Host "Press Enter to continue"
}

# ======================================================================
# FUNCTIONS: SERVICE MANAGEMENT
# ======================================================================

function Get-ServiceStatus {
    $service = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        return $service.Status.ToString()
    }
    return "NotInstalled"
}

function Install-Service {
    Clear-Host
    Write-Banner "INSTALL BOT SERVICE" "Cyan"
    
    # Check if already installed
    if ((Get-ServiceStatus) -ne "NotInstalled") {
        Write-Warn "Service already installed"
        Write-Info "Use 'Manage Service' to start/stop"
        Read-Host "Press Enter to continue"
        return
    }
    
    # Check for NSSM
    $nssmPath = Get-Command nssm -ErrorAction SilentlyContinue
    if (-not $nssmPath) {
        Write-Error2 "NSSM not found in PATH"
        Write-Info "Install NSSM from: $Script:NssmUrl"
        Write-Info "Or use: choco install nssm"
        Write-Info "Then add NSSM to your system PATH"
        Read-Host "Press Enter to continue"
        return
    }
    
    # Display configuration
    Write-Host "Setup Configuration:" -ForegroundColor White
    Write-Info "Project Root   : $ProjectRoot"
    Write-Info "Service Name   : $ServiceName"
    Write-Info "Main Script    : $MainScript"
    Write-Info "Auto Restart   : enabled"
    Write-Host ""
    
    if (-not (Confirm-Action "Install service?")) {
        Write-Info "Cancelled"
        Read-Host "Press Enter to continue"
        return
    }
    
    # Check for node_modules
    if (-not (Test-Path "$ProjectRoot\node_modules")) {
        Write-Info "Installing npm dependencies..."
        Push-Location $ProjectRoot
        if (npm install) {
            Write-OK "Dependencies installed"
        } else {
            Write-Error2 "Failed to install dependencies"
            Pop-Location
            Read-Host "Press Enter to continue"
            return
        }
        Pop-Location
    }
    
    Write-Host ""
    Write-Info "Creating service (requires admin)..."
    Request-AdminPrivilege
    
    # Get Node.js path
    $nodePath = (Get-Command node).Source
    
    # Install with NSSM
    Write-Info "Registering service with NSSM..."
    $nssm = (Get-Command nssm).Source
    
    & $nssm install $ServiceName $nodePath $MainScript
    & $nssm set $ServiceName AppDirectory $ProjectRoot
    & $nssm set $ServiceName AppRestartDelay 5000
    & $nssm set $ServiceName AppStdout $BotLogPath
    & $nssm set $ServiceName AppStderr $BotLogPath
    & $nssm set $ServiceName AppRotateFiles 1
    & $nssm set $ServiceName AppRotateOnline 1
    & $nssm set $ServiceName AppRotateSeconds 3600
    & $nssm set $ServiceName AppExit Default Restart
    
    Write-OK "Service installed and configured"
    Write-Info "Start the service: [2] Manage Service → Start"
    Log-Action "Service installed"
    
    Read-Host "Press Enter to continue"
}

function Start-BotService {
    $status = Get-ServiceStatus
    
    if ($status -eq "NotInstalled") {
        Write-Error2 "Service not installed. Install it first."
        Read-Host "Press Enter to continue"
        return
    }
    
    if ($status -eq "Running") {
        Write-Warn "Service is already running"
        Read-Host "Press Enter to continue"
        return
    }
    
    Request-AdminPrivilege
    
    Write-Info "Starting $BotName..."
    if (Start-Service -Name $ServiceName -ErrorAction SilentlyContinue 2>$null) {
        Start-Sleep -Seconds 2
        $newStatus = Get-ServiceStatus
        
        if ($newStatus -eq "Running") {
            Write-OK "Service started successfully"
            Log-Action "Service started"
        } else {
            Write-Error2 "Service failed to start or exited immediately"
            Write-Info "Current status: $newStatus"
            Write-Info "Checking NSSM status..."
            Write-Host ""
            $nssm = (Get-Command nssm -ErrorAction SilentlyContinue).Source
            if ($nssm) {
                & $nssm status $ServiceName
            }
            Write-Host ""
            Write-Info "Check Event Viewer: Windows Logs → System (filter by source 'nssm')"
        }
    } else {
        Write-Error2 "Failed to start service"
        Write-Info "Verify service is installed: nssm status $ServiceName"
    }
    
    Read-Host "Press Enter to continue"
}

function Stop-BotService {
    $status = Get-ServiceStatus
    
    if ($status -eq "NotInstalled" -or $status -eq "Stopped") {
        Write-Warn "Service is not running"
        Read-Host "Press Enter to continue"
        return
    }
    
    Request-AdminPrivilege
    
    Write-Info "Stopping $BotName..."
    Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
    
    Write-OK "Service stopped"
    Log-Action "Service stopped"
    
    Read-Host "Press Enter to continue"
}

function Restart-BotService {
    $status = Get-ServiceStatus
    
    if ($status -eq "NotInstalled") {
        Write-Error2 "Service not installed"
        Read-Host "Press Enter to continue"
        return
    }
    
    Request-AdminPrivilege
    
    Write-Info "Restarting $BotName..."
    if (Restart-Service -Name $ServiceName -ErrorAction SilentlyContinue 2>$null) {
        Start-Sleep -Seconds 2
        $newStatus = Get-ServiceStatus
        
        if ($newStatus -eq "Running") {
            Write-OK "Service restarted successfully"
            Log-Action "Service restarted"
        } else {
            Write-Error2 "Service restarted but failed to start"
            Write-Info "Current status: $newStatus"
            Write-Info "Check Event Viewer for errors (Windows Logs → System)"
        }
    } else {
        Write-Error2 "Failed to restart service"
    }
    
    Read-Host "Press Enter to continue"
}

function Show-ServiceStatus {
    Clear-Host
    Write-Banner "SERVICE STATUS" "Cyan"
    
    $status = Get-ServiceStatus
    
    if ($status -eq "NotInstalled") {
        Write-Warn "Service not installed"
    } else {
        $service = Get-Service -Name $ServiceName
        Write-Info "Name: $($service.DisplayName)"
        Write-Info "Status: $status"
        Write-Info "Start Type: $($service.StartType)"
        Write-Info "Process ID: $($service.Id)"
        Write-Host ""
        Write-Info "Event Log Summary (last 10 entries):"
        Write-Host ""
        
        Get-EventLog -LogName System -Source nssm -Newest 10 -ErrorAction SilentlyContinue | 
            ForEach-Object { Write-Info "$($_.TimeGenerated) - $($_.Message)" }
    }
    
    Read-Host "Press Enter to continue"
}

# ======================================================================
# LOGGING & DEBUGGING
# ======================================================================

function Show-Logs {
    while ($true) {
        Clear-Host
        Write-Banner "LOGS & DEBUGGING" "Cyan"
        
        $options = @(
            "View Recent Logs (last 50 lines)",
            "View Bot Log File",
            "View Windows Event Log",
            "Diagnose Service Issues",
            "Clear Bot Log",
            "Back"
        )
        
        $choice = Read-Menu $options "Select option"
        
        Write-Host ""
        
        switch ($choice) {
            0 {
                # Recent logs
                if (Test-Path $BotLogPath) {
                    Get-Content $BotLogPath -Tail 50
                } else {
                    Write-Warn "No logs found yet"
                }
                Read-Host "Press Enter to continue"
            }
            1 {
                # Full log file
                if (Test-Path $BotLogPath) {
                    & notepad $BotLogPath
                } else {
                    Write-Warn "No logs found"
                    Read-Host "Press Enter to continue"
                }
            }
            2 {
                # Event log
                Get-EventLog -LogName System -Source nssm -Newest 50 -ErrorAction SilentlyContinue |
                    Format-Table -AutoSize TimeGenerated, EventID, Message |
                    Out-Host
                Read-Host "Press Enter to continue"
            }
            3 {
                # Diagnose
                Diagnose-ServiceIssues
                Read-Host "Press Enter to continue"
            }
            4 {
                # Clear logs
                if (Confirm-Action "Clear bot log?") {
                    Clear-Content -Path $BotLogPath -ErrorAction SilentlyContinue
                    Write-OK "Log cleared"
                } else {
                    Write-Info "Cancelled"
                }
                Read-Host "Press Enter to continue"
            }
            5 {
                return
            }
        }
    }
}

function Diagnose-ServiceIssues {
    Clear-Host
    Write-Banner "DIAGNOSE SERVICE ISSUES" "Cyan"
    
    Write-Host ""
    
    # Check 1: Node.js
    Write-Host "[1] Node.js" -ForegroundColor White -BackgroundColor Black
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-OK "Node.js: $(node --version)"
    } else {
        Write-Error2 "Node.js not found in PATH"
    }
    Write-Host ""
    
    # Check 2: Project files
    Write-Host "[2] Project Files" -ForegroundColor White -BackgroundColor Black
    if (Test-Path "$ProjectRoot\index.js") {
        Write-OK "index.js found"
    } else {
        Write-Error2 "index.js not found at $ProjectRoot\index.js"
    }
    
    if (Test-Path "$ProjectRoot\package.json") {
        Write-OK "package.json found"
    } else {
        Write-Error2 "package.json not found"
    }
    
    if (Test-Path "$ProjectRoot\node_modules") {
        Write-OK "node_modules exists"
    } else {
        Write-Warn "node_modules not found (run: npm install)"
    }
    Write-Host ""
    
    # Check 3: .env file
    Write-Host "[3] Environment File" -ForegroundColor White -BackgroundColor Black
    if (Test-Path "$ProjectRoot\.env") {
        Write-OK ".env file found"
    } else {
        Write-Warn ".env file not found"
    }
    Write-Host ""
    
    # Check 4: Service status
    Write-Host "[4] Service Status" -ForegroundColor White -BackgroundColor Black
    $svcStatus = Get-ServiceStatus
    if ($svcStatus -eq "Running") {
        Write-OK "Service is RUNNING"
    } else {
        Write-Error2 "Service is $svcStatus"
    }
    
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Info "Start Type: $($service.StartType)"
    }
    Write-Host ""
    
    # Check 5: Recent events
    Write-Host "[5] Recent Events" -ForegroundColor White -BackgroundColor Black
    $recentErrors = Get-EventLog -LogName System -Source nssm -Newest 5 -ErrorAction SilentlyContinue
    if ($recentErrors) {
        $hasErrors = $false
        foreach ($evt in $recentErrors) {
            if ($evt.EntryType -eq "Error") {
                Write-Error2 "$($evt.TimeGenerated): $($evt.Message)"
                $hasErrors = $true
            } else {
                Write-Info "$($evt.TimeGenerated): $($evt.Message)"
            }
        }
        if (-not $hasErrors) {
            Write-OK "No recent errors found"
        }
    } else {
        Write-OK "No recent events found"
    }
    Write-Host ""
    
    Write-Host "Recommended Actions:" -ForegroundColor White
    Write-Info "1. Install dependencies: npm install"
    Write-Info "2. Check .env file: notepad .env"
    Write-Info "3. Test bot manually: node index.js"
    Write-Info "4. View detailed event log: eventvwr.msc (filter source: nssm)"
    Write-Info "5. Uninstall and reinstall service: Use [5] Cleanup → Uninstall, then [0] Install"
}

# ======================================================================
# MANAGEMENT MENU
# ======================================================================

function Menu-ManageService {
    while ($true) {
        Clear-Host
        Write-Banner "MANAGE SERVICE" "Cyan"
        
        $status = Get-ServiceStatus
        Write-Info "Current Status: $status"
        Write-Host ""
        
        $options = @(
            "Start Service",
            "Stop Service",
            "Restart Service",
            "View Status",
            "Back"
        )
        
        $choice = Read-Menu $options "Select option"
        
        switch ($choice) {
            0 { Start-BotService }
            1 { Stop-BotService }
            2 { Restart-BotService }
            3 { Show-ServiceStatus }
            4 { return }
        }
    }
}

# ======================================================================
# CONFIGURATION MENU
# ======================================================================

function Menu-Configuration {
    while ($true) {
        Clear-Host
        Write-Banner "CONFIGURATION" "Cyan"
        
        Write-Info "Project Root: $ProjectRoot"
        Write-Info "Config Dir: $ConfigDir"
        Write-Info "Service Name: $ServiceName"
        Write-Host ""
        
        $options = @(
            "View Service Configuration",
            "Open Config Directory",
            "View .env File",
            "Back"
        )
        
        $choice = Read-Menu $options "Select option"
        
        switch ($choice) {
            0 {
                Clear-Host
                $nssm = (Get-Command nssm -ErrorAction SilentlyContinue).Source
                if ($nssm) {
                    & $nssm dump $ServiceName
                } else {
                    Write-Error2 "NSSM not available"
                }
                Read-Host "Press Enter to continue"
            }
            1 {
                Invoke-Item $ConfigDir -ErrorAction SilentlyContinue
                Read-Host "Press Enter to continue"
            }
            2 {
                if (Test-Path "$ProjectRoot\.env") {
                    Get-Content "$ProjectRoot\.env"
                } else {
                    Write-Warn ".env file not found"
                }
                Read-Host "Press Enter to continue"
            }
            3 { return }
        }
    }
}

# ======================================================================
# CLEANUP & REMOVAL
# ======================================================================

function Menu-Cleanup {
    while ($true) {
        Clear-Host
        Write-Banner "CLEANUP / REMOVAL" "Red"
        Write-Warn "Some operations below are destructive"
        Write-Info "Note: Management scripts will NOT be deleted"
        
        $options = @(
            "Stop Service",
            "Uninstall Service Completely",
            "Clear All Logs",
            "Back"
        )
        
        $choice = Read-Menu $options "Select option"
        
        switch ($choice) {
            0 {
                Stop-BotService
            }
            1 {
                if (Confirm-Action "Uninstall service completely? This cannot be undone") {
                    Request-AdminPrivilege
                    
                    Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
                    
                    $nssm = (Get-Command nssm -ErrorAction SilentlyContinue).Source
                    if ($nssm) {
                        & $nssm remove $ServiceName confirm
                        Write-OK "Service uninstalled"
                        Write-Info "Configuration directory preserved: $ConfigDir"
                        Write-Info "Scripts preserved: $ScriptDir"
                        Log-Action "Service uninstalled"
                    } else {
                        Write-Error2 "NSSM not available"
                    }
                } else {
                    Write-Info "Cancelled"
                }
                Read-Host "Press Enter to continue"
            }
            2 {
                if (Confirm-Action "Delete ALL logs?") {
                    Remove-Item $BotLogPath -ErrorAction SilentlyContinue
                    Write-OK "Logs deleted"
                } else {
                    Write-Info "Cancelled"
                }
                Read-Host "Press Enter to continue"
            }
            3 { return }
        }
    }
}

# ======================================================================
# MAIN MENU
# ======================================================================

function Main-Menu {
    while ($true) {
        Clear-Host
        Write-Banner "⚡  DISCORD BOT MANAGER (Windows)" "Cyan"
        
        $status = Get-ServiceStatus
        if ($status -eq "NotInstalled") {
            Write-Warn "Service not installed"
        } elseif ($status -eq "Running") {
            Write-OK "Service running"
        } else {
            Write-Info "Service stopped"
        }
        Write-Host ""
        
        $options = @(
            "Install Service",
            "Manage Service (start/stop/restart)",
            "Logs & Debugging",
            "Configuration",
            "Cleanup / Removal",
            "Exit"
        )
        
        $choice = Read-Menu $options "Select option"
        
        switch ($choice) {
            0 { Install-Service }
            1 { Menu-ManageService }
            2 { Show-Logs }
            3 { Menu-Configuration }
            4 { Menu-Cleanup }
            5 {
                Write-Host "`n" -NoNewline
                Write-OK "Goodbye"
                Write-Host "`n"
                exit 0
            }
        }
    }
}

# ======================================================================
# ENTRY POINT
# ======================================================================

Clear-Host
Check-Prerequisites
Main-Menu
