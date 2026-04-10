#!/usr/bin/env bash
# ======================================================================
#  bot-manager-linux.sh  —  Discord Chatbot Service Manager (Linux/systemd)
#
#  Manages the Discord bot as a persistent systemd service with:
#    • Auto-start on system reboot
#    • Automatic restart on failure
#    • Integrated logging with journalctl
#    • Start/stop/restart/status management
#    • Interactive menu interface
#
#  Requirements: bash 4.3+, systemd, Node.js, npm
#  Usage: bash scripts/bot-manager-linux.sh
# ======================================================================

set -uo pipefail

# ── PATHS ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${HOME}/.config/discord-bot"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
BOT_LOG="${CONFIG_DIR}/bot.log"
BOT_STATE="${CONFIG_DIR}/bot.state"
BOT_SERVICE="discord-bot"
BOT_UNIT_FILE="${SYSTEMD_USER_DIR}/${BOT_SERVICE}.service"

mkdir -p "$CONFIG_DIR" "$SYSTEMD_USER_DIR"

# ── DEFAULTS ─────────────────────────────────────────────────────────
BOT_NAME="Discord Chatbot"
DEFAULT_AUTO_RESTART="true"
DEFAULT_RESTART_DELAY="5s"

# ── COLORS ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'  GRN=$'\033[0;32m'  YLW=$'\033[0;33m'
    BLU=$'\033[0;34m'  MAG=$'\033[0;35m'  CYN=$'\033[0;36m'
    BOLD=$'\033[1m'    DIM=$'\033[2m'      RST=$'\033[0m'
    REV=$'\033[7m'     CLR=$'\033[K'
else
    RED='' GRN='' YLW='' BLU='' MAG='' CYN=''
    BOLD='' DIM='' RST='' REV='' CLR=''
fi

TW=$(tput cols 2>/dev/null || echo 72)
(( TW < 64  )) && TW=64
(( TW > 104 )) && TW=104

# ======================================================================
# UI HELPERS
# ======================================================================
hr()  { printf "${DIM}%${TW}s${RST}\n" '' | tr ' ' '─'; }
h2()  { printf "${DIM}%${TW}s${RST}\n" '' | tr ' ' '╌'; }

banner() {
    local txt="$1" color="${2:-$CYN}"
    local inner=$(( TW - 2 )) pad=$(( (TW - 2 - ${#txt}) / 2 ))
    printf "${color}${BOLD}%*s%s%*s${RST}\n" \
        $(( pad + 1 )) '' "$txt" $(( inner - pad - ${#txt} + 1 )) ''
}

ok()   { printf "  ${GRN}✓${RST}  %s\n" "$*"; }
warn() { printf "  ${YLW}⚠${RST}  %s\n" "$*"; }
err()  { printf "  ${RED}✗${RST}  %s\n" "$*"; }
info() { printf "  ${BLU}·${RST}  %s\n" "$*"; }

anykey() {
    echo
    printf "  ${DIM}Press any key to continue…${RST}"
    read -r -s -n1; echo
}

confirm() {
    printf "  ${YLW}?${RST}  %s [y/N] " "${1:-Are you sure?}"
    local r; read -r r
    [[ "${r,,}" =~ ^(y|yes)$ ]]
}

ask() {
    printf "  %-30s [${DIM}%s${RST}]: " "$1" "$2"
    local v; read -r v
    printf -v "$3" '%s' "${v:-$2}"
}

# ======================================================================
# KEY READER & MENU NAVIGATION
# ======================================================================
read_key() {
    local k seq
    IFS= read -r -s -n1 k
    if [[ "$k" == $'\x1b' ]]; then
        IFS= read -r -s -n2 -t 0.15 seq 2>/dev/null || seq=""
        k="${k}${seq}"
    fi
    printf '%s' "$k"
}

navigate_submenu() {
    local -n __ns_items="$1"
    local -n __ns_sel="$2"
    local __mode="${3:-direct}"
    local __n=${#__ns_items[@]}
    local __w=$(( TW - 6 ))

    (( __n == 0 )) && return
    __ns_sel=0
    tput civis 2>/dev/null

    local __j __item
    for (( __j = 0; __j < __n; __j++ )); do
        __item="${__ns_items[$__j]}"
        (( ${#__item} > __w )) && __item="${__item:0:$(( __w - 1 ))}…"
        if (( __j == __ns_sel )); then
            printf "  ${REV}${BOLD} %-*s ${RST}${CLR}\n" "$__w" "$__item"
        else
            printf "    %-*s  ${CLR}\n" "$__w" "$__item"
        fi
    done

    while true; do
        local __k; __k=$(read_key)
        case "$__k" in
            $'\x1b[A')   (( __ns_sel > 0 )) && (( __ns_sel-- )) ;;
            $'\x1b[B')   (( __ns_sel < __n - 1 )) && (( __ns_sel++ )) ;;
            $'\n'|$'\r'|'')  tput cnorm 2>/dev/null; return ;;
            [0-9])
                local __t
                if [[ "$__mode" == "main" ]]; then
                    [[ "$__k" == "0" ]] && __t=$(( __n - 1 )) || __t=$(( __k - 1 ))
                else
                    __t=$(( __k ))
                fi
                if (( __t >= 0 && __t < __n )); then
                    __ns_sel=$__t; tput cnorm 2>/dev/null; return
                fi
                continue ;;
            q|Q)
                __ns_sel=$(( __n - 1 )); tput cnorm 2>/dev/null; return ;;
            *) continue ;;
        esac

        tput cuu "$__n" 2>/dev/null
        for (( __j = 0; __j < __n; __j++ )); do
            __item="${__ns_items[$__j]}"
            (( ${#__item} > __w )) && __item="${__item:0:$(( __w - 1 ))}…"
            if (( __j == __ns_sel )); then
                printf "  ${REV}${BOLD} %-*s ${RST}${CLR}\n" "$__w" "$__item"
            else
                printf "    %-*s  ${CLR}\n" "$__w" "$__item"
            fi
        done
    done
}

# ======================================================================
# PREREQUISITE CHECK
# ======================================================================
check_prereqs() {
    clear; echo
    printf "${BOLD}${CYN}"; hr; banner "DISCORD BOT MANAGER — PREREQUISITE CHECK"; hr
    printf "${RST}\n\n"
    local all_pass=true

    # 1. Node.js
    printf "${BOLD}[1/3] Node.js${RST}\n"
    if command -v node &>/dev/null; then
        ok "Node.js: $(node --version)"
    else
        err "Node.js not found"
        info "Install from https://nodejs.org/"
        all_pass=false
    fi; echo

    # 2. npm
    printf "${BOLD}[2/3] npm${RST}\n"
    if command -v npm &>/dev/null; then
        ok "npm: $(npm --version)"
    else
        err "npm not found"
        all_pass=false
    fi; echo

    # 3. Project files
    printf "${BOLD}[3/3] Project Setup${RST}\n"
    if [[ -f "${PROJECT_ROOT}/index.js" ]]; then
        ok "index.js found"
    else
        err "index.js not found at: ${PROJECT_ROOT}/index.js"
        all_pass=false
    fi

    if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        ok "package.json found"
    else
        err "package.json not found"
        all_pass=false
    fi

    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        ok ".env file found (will be used by bot)"
    else
        warn ".env file not found — bot may fail if it requires environment variables"
    fi; echo

    hr
    if $all_pass; then
        printf "  ${GRN}${BOLD}All checks passed.${RST}\n"
    else
        printf "  ${YLW}${BOLD}Some checks failed — fix issues before proceeding.${RST}\n"
    fi
    hr; anykey
}

# ======================================================================
# STATUS & STATE MANAGEMENT
# ======================================================================

get_bot_status() {
    if systemctl --user is-active "$BOT_SERVICE" &>/dev/null 2>&1; then
        printf 'running'
    else
        printf 'stopped'
    fi
}

get_bot_uptime() {
    local started
    started=$(systemctl --user show "$BOT_SERVICE" -p ExecMainStartTimestamp --value 2>/dev/null)
    if [[ -n "$started" && "$started" != "n/a" ]]; then
        echo "$started"
    else
        echo "unknown"
    fi
}

get_restart_count() {
    systemctl --user show "$BOT_SERVICE" -p NRestarts --value 2>/dev/null || echo "0"
}

log_action() {
    local action="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $action" >> "$BOT_LOG"
}

# ======================================================================
# SYSTEMD UNIT FILE MANAGEMENT
# ======================================================================

create_unit_file() {
    local node_path
    node_path=$(command -v node)

    cat > "$BOT_UNIT_FILE" << UNITEOF
[Unit]
Description=Discord Chatbot Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${PROJECT_ROOT}
ExecStart=${node_path} ${PROJECT_ROOT}/index.js
Restart=on-failure
RestartSec=${DEFAULT_RESTART_DELAY}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNITEOF
    systemctl --user daemon-reload 2>/dev/null
    ok "Unit file created: $BOT_UNIT_FILE"
}

# ======================================================================
# BOT OPERATIONS
# ======================================================================

do_install() {
    clear; echo
    printf "${BOLD}${CYN}"; hr; banner "INSTALL BOT SERVICE"; hr; printf "${RST}\n\n"

    if [[ -f "$BOT_UNIT_FILE" ]]; then
        warn "Service already installed"
        info "Use [2] Manage Service to start/stop"
        anykey; return
    fi

    printf "  ${BOLD}Setup:${RST}\n"
    printf "    Project    : %s\n" "$PROJECT_ROOT"
    printf "    Service    : %s.service\n" "$BOT_SERVICE"
    printf "    Auto Start : enabled\n"
    printf "    Auto Restart: on-failure\n"
    echo

    confirm "Install service?" || { info "Cancelled"; anykey; return; }

    # Check for npm dependencies
    if [[ ! -d "${PROJECT_ROOT}/node_modules" ]]; then
        echo
        info "Installing npm dependencies..."
        cd "$PROJECT_ROOT" || { err "Cannot cd to $PROJECT_ROOT"; anykey; return; }
        if npm install; then
            ok "Dependencies installed"
        else
            err "Failed to install dependencies"
            anykey; return
        fi
    fi

    echo
    create_unit_file
    systemctl --user enable "$BOT_SERVICE" 2>/dev/null
    loginctl enable-linger "$(id -un)" 2>/dev/null || true

    log_action "Service installed"
    ok "Service installed and enabled"
    info "Start with: [2] Manage Service → Start"
    anykey
}

do_start() {
    if [[ ! -f "$BOT_UNIT_FILE" ]]; then
        err "Service not installed. Use [1] Install Service first."
        anykey; return
    fi

    if [[ $(get_bot_status) == "running" ]]; then
        warn "Service is already running"
        anykey; return
    fi

    info "Starting $BOT_NAME..."
    if systemctl --user start "$BOT_SERVICE" 2>/dev/null; then
        sleep 2
        local final_status; final_status=$(get_bot_status)
        if [[ "$final_status" == "running" ]]; then
            ok "Service started"
            log_action "Service started"
        else
            err "Service failed to start or exited immediately"
            info "Checking systemd status..."
            echo ""
            systemctl --user status "$BOT_SERVICE" --no-pager 2>/dev/null || true
            echo ""
            info "Try: journalctl --user -u $BOT_SERVICE -n 50 --no-pager"
        fi
    else
        err "Failed to start service"
        info "Check: journalctl --user -u $BOT_SERVICE -n 20"
    fi
    anykey
}

do_stop() {
    if [[ $(get_bot_status) == "stopped" ]]; then
        warn "Service is not running"
        anykey; return
    fi

    info "Stopping $BOT_NAME..."
    if systemctl --user stop "$BOT_SERVICE" 2>/dev/null; then
        ok "Service stopped"
        log_action "Service stopped"
    else
        err "Failed to stop service"
    fi
    anykey
}

do_restart() {
    if [[ ! -f "$BOT_UNIT_FILE" ]]; then
        err "Service not installed"
        anykey; return
    fi

    info "Restarting $BOT_NAME..."
    if systemctl --user restart "$BOT_SERVICE" 2>/dev/null; then
        sleep 2
        local final_status; final_status=$(get_bot_status)
        if [[ "$final_status" == "running" ]]; then
            ok "Service restarted"
            log_action "Service restarted"
        else
            err "Service restarted but is not running"
            info "Check status with [3] View Status"
        fi
    else
        err "Failed to restart service"
    fi
    anykey
}

# ======================================================================
# MANAGEMENT MENU
# ======================================================================

menu_manage_service() {
    while true; do
        clear; echo
        printf "${BOLD}${CYN}"; hr; banner "MANAGE SERVICE"; hr; printf "${RST}\n\n"

        if [[ -f "$BOT_UNIT_FILE" ]]; then
            local status; status=$(get_bot_status)
            printf "  ${BOLD}Status${RST}\n"
            if [[ "$status" == "running" ]]; then
                printf "    State     : ${GRN}● running${RST}\n"
                printf "    Started   : %s\n" "$(get_bot_uptime)"
                printf "    Restarts  : %s\n" "$(get_restart_count)"
            else
                printf "    State     : ${DIM}○ stopped${RST}\n"
            fi
            echo
        fi

        local -a opts=("Start Service" "Stop Service" "Restart Service" \
                       "View Status" "← Back")
        local sel=0; navigate_submenu opts sel; echo

        case $sel in
            0) do_start ;;
            1) do_stop ;;
            2) do_restart ;;
            3)
                systemctl --user status "$BOT_SERVICE" --no-pager 2>/dev/null || err "Service not found"
                anykey ;;
            4) return ;;
        esac
    done
}

# ======================================================================
# DIAGNOSTIC FUNCTION
# ======================================================================

diagnose_service_issues() {
    clear; echo
    printf "${BOLD}${CYN}"; hr; banner "DIAGNOSE SERVICE ISSUES"; hr; printf "${RST}\n"

    local has_issues=false

    # Check 1: Unit file exists
    printf "\n${BOLD}[1] Unit File${RST}\n"
    if [[ -f "$BOT_UNIT_FILE" ]]; then
        ok "Unit file exists: $BOT_UNIT_FILE"
        printf "  Content:\n"
        sed 's/^/    /' "$BOT_UNIT_FILE"
    else
        err "Unit file not found"
        has_issues=true
    fi

    # Check 2: Node.js
    printf "\n${BOLD}[2] Node.js${RST}\n"
    if command -v node &>/dev/null; then
        ok "Node.js: $(node --version)"
    else
        err "Node.js not found in PATH"
        has_issues=true
    fi

    # Check 3: Project files
    printf "\n${BOLD}[3] Project Files${RST}\n"
    if [[ -f "${PROJECT_ROOT}/index.js" ]]; then
        ok "index.js found"
    else
        err "index.js not found at $PROJECT_ROOT/index.js"
        has_issues=true
    fi

    if [[ -f "${PROJECT_ROOT}/package.json" ]]; then
        ok "package.json found"
    else
        err "package.json not found"
        has_issues=true
    fi

    if [[ -d "${PROJECT_ROOT}/node_modules" ]]; then
        ok "node_modules directory exists"
    else
        warn "node_modules not found (install with: npm install)"
        has_issues=true
    fi

    # Check 4: .env file
    printf "\n${BOLD}[4] Environment File${RST}\n"
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        ok ".env file found"
        if [[ -r "${PROJECT_ROOT}/.env" ]]; then
            ok ".env is readable"
        else
            err ".env exists but not readable (check permissions)"
            has_issues=true
        fi
    else
        warn ".env file not found (bot may fail without required env vars)"
    fi

    # Check 5: Permissions
    printf "\n${BOLD}[5] Permissions${RST}\n"
    if [[ -r "$PROJECT_ROOT" ]]; then
        ok "Project directory is readable"
    else
        err "Project directory is not readable"
        has_issues=true
    fi

    # Check 6: Recent errors
    printf "\n${BOLD}[6] Recent Service Errors${RST}\n"
    local recent_errors
    recent_errors=$(journalctl --user -u "$BOT_SERVICE" -p err -n 10 --no-pager 2>/dev/null | head -5)
    if [[ -n "$recent_errors" ]]; then
        printf "  ${YLW}%s${RST}\n" "Recent errors found:"
        echo "$recent_errors" | sed 's/^/    /'
        has_issues=true
    else
        ok "No recent errors in logs"
    fi

    # Check 7: Service status
    printf "\n${BOLD}[7] Service Status${RST}\n"
    local svc_status; svc_status=$(get_bot_status)
    if [[ "$svc_status" == "running" ]]; then
        ok "Service is RUNNING"
    else
        err "Service is STOPPED or in other state"
        printf "  ${DIM}Full status:${RST}\n"
        systemctl --user status "$BOT_SERVICE" --no-pager 2>/dev/null | sed 's/^/    /'
        has_issues=true
    fi

    # Summary
    printf "\n${BOLD}SUMMARY${RST}\n"
    if $has_issues; then
        printf "  ${YLW}⚠${RST}  Issues detected above\n"
        printf "\n${BOLD}Common fixes:${RST}\n"
        printf "    1. Install dependencies: ${DIM}npm install${RST}\n"
        printf "    2. Check .env file: ${DIM}cat .env | head${RST}\n"
        printf "    3. Test bot manually: ${DIM}node index.js${RST}\n"
        printf "    4. View detailed logs: ${DIM}journalctl --user -u $BOT_SERVICE -n 100${RST}\n"
    else
        ok "No obvious issues detected"
    fi
}

# ======================================================================
# LOGGING & DEBUGGING
# ======================================================================

menu_logs() {
    while true; do
        clear; echo
        printf "${BOLD}${CYN}"; hr; banner "LOGS & DEBUGGING"; hr; printf "${RST}\n\n"

        local -a opts=(
            "View Recent Logs (last 50 lines)"
            "Follow Live Logs (Ctrl+C to exit)"
            "View Error Logs Only"
            "Diagnose Service Issues"
            "View Full Log File"
            "Clear Action Log"
            "← Back"
        )
        local sel=0; navigate_submenu opts sel; echo

        case $sel in
            0)
                journalctl --user -u "$BOT_SERVICE" --no-pager -n 50 2>/dev/null || warn "No logs"
                anykey ;;
            1)
                printf "  ${DIM}Ctrl+C to stop following${RST}\n\n"
                journalctl --user -u "$BOT_SERVICE" -f --no-pager 2>/dev/null || true
                anykey ;;
            2)
                journalctl --user -u "$BOT_SERVICE" --no-pager -p err 2>/dev/null || warn "No errors"
                anykey ;;
            3)
                diagnose_service_issues
                anykey ;;
            4)
                if [[ -f "$BOT_LOG" ]]; then
                    less "$BOT_LOG" || cat "$BOT_LOG"
                else
                    warn "No action log file yet"
                    anykey
                fi ;;
            5)
                confirm "Clear action log?" && {
                    > "$BOT_LOG"
                    ok "Log cleared"
                } || info "Cancelled"
                anykey ;;
            6) return ;;
        esac
    done
}

# ======================================================================
# CONFIGURATION MENU
# ======================================================================

menu_config() {
    while true; do
        clear; echo
        printf "${BOLD}${CYN}"; hr; banner "CONFIGURATION"; hr; printf "${RST}\n\n"

        printf "  ${BOLD}Current Configuration${RST}\n"
        printf "    Project Root   : %s\n" "$PROJECT_ROOT"
        printf "    Auto Restart   : %s\n" "$DEFAULT_AUTO_RESTART"
        printf "    Restart Delay  : %s\n" "$DEFAULT_RESTART_DELAY"
        printf "    Config Dir     : %s\n" "$CONFIG_DIR"
        echo

        local -a opts=(
            "View Unit File"
            "View .env File"
            "Reinstall Service (preserve config)"
            "← Back"
        )
        local sel=0; navigate_submenu opts sel; echo

        case $sel in
            0)
                if [[ -f "$BOT_UNIT_FILE" ]]; then
                    cat "$BOT_UNIT_FILE"
                else
                    warn "Unit file not found"
                fi
                anykey ;;
            1)
                if [[ -f "${PROJECT_ROOT}/.env" ]]; then
                    cat "${PROJECT_ROOT}/.env"
                else
                    warn ".env file not found"
                fi
                anykey ;;
            2)
                confirm "Reinstall service unit file?" && {
                    create_unit_file
                    ok "Service reinstalled"
                } || info "Cancelled"
                anykey ;;
            3) return ;;
        esac
    done
}

# ======================================================================
# CLEANUP & REMOVAL
# ======================================================================

menu_cleanup() {
    while true; do
        clear; echo
        printf "${BOLD}${RED}"; hr; banner "CLEANUP / REMOVAL"; hr; printf "${RST}\n"
        printf "  ${YLW}${BOLD}Some operations below are destructive.${RST}\n\n"

        local -a opts=(
            "Stop Service"
            "Disable Service (keep files)"
            "Uninstall Service Completely"
            "Remove All Logs"
            "← Back"
        )
        local sel=0; navigate_submenu opts sel; echo

        case $sel in
            0)
                do_stop ;;
            1)
                confirm "Disable service? (can be re-enabled)" && {
                    systemctl --user disable "$BOT_SERVICE" 2>/dev/null
                    ok "Service disabled"
                } || info "Cancelled"
                anykey ;;
            2)
                confirm "Uninstall service completely? This cannot be undone." || {
                    anykey; continue
                }
                systemctl --user stop "$BOT_SERVICE" 2>/dev/null || true
                systemctl --user disable "$BOT_SERVICE" 2>/dev/null || true
                rm -f "$BOT_UNIT_FILE"
                systemctl --user daemon-reload 2>/dev/null
                ok "Service uninstalled"
                info "Configuration directory preserved: $CONFIG_DIR"
                info "Scripts preserved: $SCRIPT_DIR"
                log_action "Service uninstalled"
                anykey ;;
            3)
                confirm "Delete ALL logs?" && {
                    rm -f "$BOT_LOG"
                    ok "Logs deleted"
                } || info "Cancelled"
                anykey ;;
            4) return ;;
        esac
    done
}

# ======================================================================
# STATUS BAR
# ======================================================================

draw_statusbar() {
    local status; status=$(get_bot_status)
    printf "  ${BOLD}Bot Status${RST}    : "
    if [[ "$status" == "running" ]]; then
        printf "${GRN}● running${RST}"
        printf "  (started: %s, restarts: %s)\n" "$(get_bot_uptime)" "$(get_restart_count)"
    else
        printf "${DIM}○ stopped${RST}\n"
    fi

    printf "  ${BOLD}Config Dir${RST}    : %s\n" "$CONFIG_DIR"
    printf "  ${BOLD}Unit File${RST}     : $(realpath "$BOT_UNIT_FILE" 2>/dev/null || echo "not found")\n"
}

# ======================================================================
# MAIN MENU
# ======================================================================

main_menu() {
    local -a items=(
        "[1]  Install Service"
        "[2]  Manage Service   (start / stop / restart)"
        "[3]  Logs & Debugging"
        "[4]  Configuration"
        "[5]  Cleanup / Removal"
        "[0]  Exit"
    )

    while true; do
        clear; echo
        printf "${BOLD}${CYN}"; hr; banner "⚡  DISCORD BOT MANAGER (Linux)"; hr; printf "${RST}\n"
        draw_statusbar
        echo; h2; echo

        local sel=0
        navigate_submenu items sel "main"

        case $sel in
            0) do_install ;;
            1) menu_manage_service ;;
            2) menu_logs ;;
            3) menu_config ;;
            4) menu_cleanup ;;
            5)
                clear
                printf "\n  ${GRN}${BOLD}Goodbye.${RST}\n\n"
                tput cnorm 2>/dev/null
                exit 0 ;;
        esac
    done
}

# ======================================================================
# ENTRY POINT
# ======================================================================

trap 'tput cnorm 2>/dev/null; stty echo 2>/dev/null; echo' EXIT INT TERM

main() {
    if (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3 ) )); then
        echo "ERROR: bash 4.3+ required (have $BASH_VERSION)" >&2
        exit 1
    fi
    check_prereqs
    main_menu
}

main "$@"
