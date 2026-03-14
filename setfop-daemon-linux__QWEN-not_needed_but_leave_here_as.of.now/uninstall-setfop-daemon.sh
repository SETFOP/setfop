#!/usr/bin/env bash
# =============================================================================
#  uninstall-setfop-daemon.sh — SETFOP Daemon Uninstaller
#  Usage: sudo bash uninstall-setfop-daemon.sh [--force]
#  Removes all SETFOP components (asks before deleting user data unless --force)
# =============================================================================

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
BINARY_DEST="/usr/local/bin/setfop-daemon"
CONFIG_DIR="/etc/setfop"
CONFIG_DEST="$CONFIG_DIR/setfop-daemon.config"
SERVICE_DEST="/etc/systemd/system/setfop-daemon.service"
LOG_DIR="/var/log/setfop"
LIB_DIR="/var/lib/setfop"
PID_FILE="/var/run/setfop.pid"
BASELINE_FILE="$LIB_DIR/baseline.setfop"
HELP_DEST="/usr/local/bin/setfop-help.sh"
INSTALLER_DEST="/usr/local/bin/install-setfop-daemon.sh"
REPAIR_DEST="/usr/local/bin/repair-setfop-daemon.sh"
UNINSTALL_DEST="/usr/local/bin/uninstall-setfop-daemon.sh"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
FORCE_MODE=false
[[ "${1:-}" == "--force" ]] && FORCE_MODE=true

info()    { echo -e "${CYAN}[setfop]${RESET} $*"; }
success() { echo -e "${GREEN}[setfop]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[setfop]${RESET} $*"; }
error()   { echo -e "${RED}[setfop] ERROR:${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
ask()     { [[ "$FORCE_MODE" == "true" ]] && return 0; read -rp "  Do you want to delete \"$1\"? [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]; }

trap 'echo ""; warn "Uninstall interrupted."; exit 1' INT TERM TSTP

[[ "$EUID" -ne 0 ]] && die "Must run as root: sudo bash uninstall-setfop-daemon.sh [--force]"

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${BOLD}   SETFOP Daemon Uninstaller           ${RESET}"
echo -e "${BOLD}=======================================${RESET}"
[[ "$FORCE_MODE" == "true" ]] && echo -e "${RED}  ⚠️  FORCE MODE: Deleting without prompts!${RESET}"
echo ""

# ── Step 1: Stop service ──────────────────────────────────────────────────────
if systemctl is-active --quiet setfop-daemon 2>/dev/null; then
    info "Stopping setfop-daemon..."
    systemctl stop setfop-daemon
    success "Service stopped"
fi
systemctl is-enabled --quiet setfop-daemon 2>/dev/null && systemctl disable setfop-daemon && success "Service disabled"

# ── Step 2: Remove files (with prompts for user data) ─────────────────────────
info "Removing files..."
echo ""

# Binary (always remove)
[[ -f "$BINARY_DEST" ]] && { rm -f "$BINARY_DEST"; success "Removed: $BINARY_DEST"; }

# Service file (always remove)
[[ -f "$SERVICE_DEST" ]] && { rm -f "$SERVICE_DEST"; success "Removed: $SERVICE_DEST"; }

# Helper scripts (always remove)
for script in "$HELP_DEST" "$INSTALLER_DEST" "$REPAIR_DEST" "$UNINSTALL_DEST"; do
    [[ -f "$script" ]] && { rm -f "$script"; success "Removed: $script"; }
done

# Config (ask)
[[ -f "$CONFIG_DEST" ]] && { ask "$CONFIG_DEST" && { rm -f "$CONFIG_DEST"; success "Removed: $CONFIG_DEST"; } || warn "Kept: $CONFIG_DEST"; }

# Baseline (ask)
[[ -f "$BASELINE_FILE" ]] && { ask "$BASELINE_FILE" && { rm -f "$BASELINE_FILE"; success "Removed: $BASELINE_FILE"; } || warn "Kept: $BASELINE_FILE"; }

# PID file (always remove if exists)
[[ -f "$PID_FILE" ]] && { rm -f "$PID_FILE"; success "Removed: $PID_FILE"; }

# Log files (ask for each)
if [[ -d "$LOG_DIR" ]]; then
    for logfile in "$LOG_DIR"/drift.log*; do
        [[ -f "$logfile" ]] && { ask "$logfile" && { rm -f "$logfile"; success "Removed: $logfile"; } || warn "Kept: $logfile"; }
    done
fi

# ── Step 3: Remove directories if empty ───────────────────────────────────────
info "Cleaning directories..."
for dir in "$LOG_DIR" "$LIB_DIR" "$CONFIG_DIR"; do
    if [[ -d "$dir" && -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        rmdir "$dir" && success "Removed empty: $dir"
    fi
done

# ── Step 4: Reload systemd ────────────────────────────────────────────────────
info "Reloading systemd..."
systemctl daemon-reload
success "systemd reloaded"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${GREEN}${BOLD}  Uninstallation complete!${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""
echo -e "  SETFOP daemon has been removed."
[[ "$FORCE_MODE" != "true" ]] && echo -e "  Note: Config/baseline/logs were preserved (use ${BOLD}--force${RESET} to delete all)."
echo -e "  Optional: Manually clean ${LOG_DIR}/ if needed."
echo ""