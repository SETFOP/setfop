#!/usr/bin/env bash
# =============================================================================
#  setfop-help.sh — SETFOP Daemon Help & Reference
#  Usage: setfop-help.sh
#  Shows version, file locations, and quick usage tips
# =============================================================================

# ── Paths ─────────────────────────────────────────────────────────────────────
BINARY="/usr/local/bin/setfop-daemon"
CONFIG="/etc/setfop/setfop-daemon.config"
BASELINE="/var/lib/setfop/baseline.setfop"
LOGDIR="/var/log/setfop"
SERVICE="/etc/systemd/system/setfop-daemon.service"
PIDFILE="/var/run/setfop.pid"

# ── Colors ────────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Get version from local binary ─────────────────────────────────────────────
get_version() {
    if [[ -f "$BINARY" ]]; then
        grep -m1 '^VERSION\s*=' "$BINARY" 2>/dev/null | sed "s/VERSION\s*=\s*['\"]\([^'\"]*\)['\"]/\1/" | tr -d '[:space:]'
    else
        echo "unknown"
    fi
}

VERSION=$(get_version)

# ── Output ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   SETFOP Daemon — Help & Reference     ║${RESET}"
echo -e "${BOLD}╚════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${CYAN}📦 Version:${RESET} ${GREEN}${VERSION}${RESET}"
echo ""

echo -e "${BOLD}📁 File Locations & Purpose:${RESET}"
echo "─────────────────────────────────────"
echo -e "${YELLOW}setfop-daemon-linux/ (GitHub source)${RESET}"
echo "  ├── setfop-daemon.py       # Main daemon script"
echo "  ├── setfop-daemon.config   # Default config template"
echo "  ├── setfop-daemon.service  # Systemd service template"
echo "  └── VERSION                # Version number file"
echo ""
echo -e "${YELLOW}/etc/setfop/${RESET}"
echo "  └── setfop-daemon.config   # Active configuration"
echo ""
echo -e "${YELLOW}/var/lib/setfop/${RESET}"
echo "  └── baseline.setfop        # File integrity database"
echo ""
echo -e "${YELLOW}/var/log/setfop/${RESET}"
echo "  ├── drift.log              # Current change log"
echo "  ├── drift.log.1            # Rotated log (older)"
echo "  └── drift.log.2 ...        # Additional rotations"
echo ""
echo -e "${YELLOW}/usr/local/bin/${RESET}"
echo "  ├── setfop-daemon          # Installed daemon binary"
echo "  ├── setfop-help.sh         # This help script"
echo "  ├── install-setfop-daemon.sh   # Installer"
echo "  ├── repair-setfop-daemon.sh    # Repair tool"
echo "  └── uninstall-setfop-daemon.sh # Uninstaller"
echo ""
echo -e "${YELLOW}/etc/systemd/system/${RESET}"
echo "  └── setfop-daemon.service  # Systemd unit file"
echo ""
echo -e "${YELLOW}/var/run/${RESET}"
echo "  └── setfop.pid             # Process ID (when running)"
echo ""

echo -e "${BOLD}⚡ Quick Commands:${RESET}"
echo "─────────────────────────────────────"
echo -e "  Start:     ${BOLD}systemctl start setfop-daemon${RESET}"
echo -e "  Stop:      ${BOLD}systemctl stop setfop-daemon${RESET}"
echo -e "  Status:    ${BOLD}systemctl status setfop-daemon${RESET}"
echo -e "  Logs:      ${BOLD}tail -f /var/log/setfop/drift.log${RESET}"
echo -e "             # Watch file changes in real-time"
echo ""

echo -e "${BOLD}🔧 Management Scripts (all in /usr/local/bin/):${RESET}"
echo "─────────────────────────────────────"
echo -e "  ${BOLD}install-setfop-daemon.sh${RESET}   # Install or update"
echo -e "  ${BOLD}repair-setfop-daemon.sh${RESET}    # Fix corrupted files"
echo -e "  ${BOLD}uninstall-setfop-daemon.sh${RESET} # Remove SETFOP"
echo -e "  ${BOLD}setfop-help.sh${RESET}             # Show this help"
echo ""

echo -e "${CYAN}📚 Full Documentation:${RESET}"
echo "  https://github.com/SETFOP/setfop/tree/main/docs"
echo ""