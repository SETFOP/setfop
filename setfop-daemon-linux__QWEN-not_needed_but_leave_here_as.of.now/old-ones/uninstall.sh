#!/usr/bin/env bash
# =============================================================================
#  uninstall.sh — SETFOP Daemon Uninstaller
#  Usage: sudo bash uninstall.sh
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

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[setfop]${RESET} $*"; }
success() { echo -e "${GREEN}[setfop]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[setfop]${RESET} $*"; }
error()   { echo -e "${RED}[setfop] ERROR:${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

trap 'echo ""; warn "Uninstall interrupted."; exit 1' INT TERM TSTP

# ── Root Check ────────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    die "Must run as root: sudo bash uninstall.sh"
fi

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${BOLD}   SETFOP Daemon Uninstaller           ${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""

# ── Step 1: Stop Service ──────────────────────────────────────────────────────
if systemctl is-active --quiet setfop-daemon 2>/dev/null; then
    info "Stopping setfop-daemon service..."
    systemctl stop setfop-daemon
    success "Service stopped"
fi

if systemctl is-enabled --quiet setfop-daemon 2>/dev/null; then
    info "Disabling setfop-daemon service..."
    systemctl disable setfop-daemon
    success "Service disabled"
fi

# ── Step 2: Remove Files ──────────────────────────────────────────────────────
info "Removing installed files..."

# Binary
if [[ -f "$BINARY_DEST" ]]; then
    rm -f "$BINARY_DEST"
    success "Removed: $BINARY_DEST"
fi

# Service file
if [[ -f "$SERVICE_DEST" ]]; then
    rm -f "$SERVICE_DEST"
    success "Removed: $SERVICE_DEST"
fi

# Config (ask first)
if [[ -f "$CONFIG_DEST" ]]; then
    echo ""
    read -rp "  Keep config file $CONFIG_DEST? [y/N]: " KEEP_CONFIG
    if [[ "$KEEP_CONFIG" =~ ^[Yy]$ ]]; then
        warn "Keeping config file (user choice)"
    else
        rm -f "$CONFIG_DEST"
        success "Removed: $CONFIG_DEST"
    fi
fi

# Baseline (ask first)
if [[ -f "$BASELINE_FILE" ]]; then
    echo ""
    read -rp "  Keep baseline file $BASELINE_FILE? [y/N]: " KEEP_BASELINE
    if [[ "$KEEP_BASELINE" =~ ^[Yy]$ ]]; then
        warn "Keeping baseline file (user choice)"
    else
        rm -f "$BASELINE_FILE"
        success "Removed: $BASELINE_FILE"
    fi
fi

# PID file
if [[ -f "$PID_FILE" ]]; then
    rm -f "$PID_FILE"
    success "Removed: $PID_FILE"
fi

# ── Step 3: Remove Directories (if empty) ─────────────────────────────────────
info "Cleaning up directories..."

for dir in "$LOG_DIR" "$LIB_DIR" "$CONFIG_DIR"; do
    if [[ -d "$dir" ]]; then
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            rmdir "$dir"
            success "Removed empty directory: $dir"
        else
            warn "Directory not empty, keeping: $dir"
        fi
    fi
done

# ── Step 4: Reload systemd ────────────────────────────────────────────────────
info "Reloading systemd daemon..."
systemctl daemon-reload
success "systemd reloaded"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${GREEN}${BOLD}  Uninstallation complete!${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""
echo -e "  SETFOP daemon has been removed."
echo -e "  Optional: Manually delete logs in ${LOG_DIR}/ if needed."
echo ""
