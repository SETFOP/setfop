#!/usr/bin/env bash
# =============================================================================
#  install-setfop-daemon.sh — SETFOP Daemon Installer (Standalone)
#  Part of the SETFOP project: https://github.com/SETFOP/setfop
#
#  Usage: sudo bash install-setfop-daemon.sh
#  Note: This script downloads all files from GitHub and copies itself to /usr/local/bin/
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
HELP_DEST="/usr/local/bin/setfop-help.sh"

# ── GitHub Raw URLs ───────────────────────────────────────────────────────────
GITHUB_BASE="https://raw.githubusercontent.com/SETFOP/setfop/main/setfop-daemon-linux"
GITHUB_BINARY_URL="$GITHUB_BASE/setfop-daemon.py"
GITHUB_VERSION_URL="$GITHUB_BASE/VERSION"
GITHUB_CONFIG_URL="$GITHUB_BASE/setfop-daemon.config"
GITHUB_SERVICE_URL="$GITHUB_BASE/setfop-daemon.service"
GITHUB_HELP_URL="$GITHUB_BASE/setfop-help.sh"

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

trap 'echo ""; warn "Installer interrupted. No changes were committed."; exit 1' INT TERM TSTP

# ── Root Check ────────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    die "This installer must be run as root.\n  Try: sudo bash install-setfop-daemon.sh"
fi

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${BOLD}   SETFOP Daemon Installer             ${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""

# ── Step 1: Check python3 ─────────────────────────────────────────────────────
info "Checking for python3..."
if ! command -v python3 &>/dev/null; then
    die "python3 is not installed. Please install it first.\n  e.g. apt install python3"
fi
success "python3 found: $(python3 --version)"

# ── Step 2: Check/install inotify_simple ──────────────────────────────────────
info "Checking for inotify_simple Python package..."
if ! python3 -c "import inotify_simple" &>/dev/null; then
    warn "inotify_simple not found. Installing..."
    if ! pip3 install inotify_simple --break-system-packages -q; then
        die "Failed to install inotify_simple. Please install manually:\n  pip3 install inotify_simple --break-system-packages"
    fi
    success "inotify_simple installed"
else
    success "inotify_simple already present"
fi

# ── Step 3: Detect installed version ──────────────────────────────────────────
INSTALLED_VERSION=""
if [[ -f "$BINARY_DEST" ]]; then
    INSTALLED_VERSION=$(grep -m1 '^VERSION\s*=' "$BINARY_DEST" 2>/dev/null \
        | sed 's/VERSION\s*=\s*["\x27]\(.*\)["\x27]/\1/' \
        | tr -d '[:space:]') || INSTALLED_VERSION=""
fi

# ── Step 4: Fetch latest version from GitHub ──────────────────────────────────
LATEST_VERSION=""
info "Fetching latest version info from GitHub..."
if command -v curl &>/dev/null; then
    LATEST_VERSION=$(curl -fsSL --max-time 10 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]') || LATEST_VERSION=""
elif command -v wget &>/dev/null; then
    LATEST_VERSION=$(wget -qO- --timeout=10 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]') || LATEST_VERSION=""
fi

# ── Step 5: Version decision menu ─────────────────────────────────────────────
INSTALL_MODE="fresh"

if [[ -n "$INSTALLED_VERSION" ]]; then
    echo ""
    echo -e "${BOLD}  Existing installation detected:${RESET}"
    echo -e "    Installed version : ${YELLOW}${INSTALLED_VERSION}${RESET}"
    [[ -n "$LATEST_VERSION" ]] && echo -e "    Latest version    : ${GREEN}${LATEST_VERSION}${RESET}" || warn "Could not fetch latest version (offline)."

    echo ""
    echo -e "  What would you like to do?"
    echo -e "    ${BOLD}1${RESET} — Reinstall current version (${INSTALLED_VERSION})"
    [[ -n "$LATEST_VERSION" ]] && echo -e "    ${BOLD}2${RESET} — Update to latest version (${LATEST_VERSION})" || echo -e "    ${YELLOW}2${RESET} — Update to latest ${YELLOW}(unavailable)${RESET}"
    echo -e "    ${BOLD}3${RESET} — Quit"
    echo ""

    while true; do
        if ! read -rp "  Enter your choice [1/2/3]: " CHOICE; then echo ""; warn "No input. Exiting."; exit 0; fi
        case "$CHOICE" in
            1) INSTALL_MODE="reinstall"; info "Reinstalling v${INSTALLED_VERSION}..."; break ;;
            2) [[ -z "$LATEST_VERSION" ]] && { warn "Cannot update — offline."; continue; }; INSTALL_MODE="update"; info "Updating to v${LATEST_VERSION}..."; break ;;
            3) info "Quitting. No changes."; exit 0 ;;
            *) warn "Invalid choice. Enter 1, 2, or 3." ;;
        esac
    done
else
    info "No existing installation. Proceeding with fresh install..."
fi

echo ""

# ── Step 6: Stop daemon if running ────────────────────────────────────────────
if systemctl is-active --quiet setfop-daemon 2>/dev/null; then
    info "Stopping running setfop-daemon service..."
    systemctl stop setfop-daemon
    success "Service stopped"
fi

# ── Step 7: Download helper function ──────────────────────────────────────────
download_from_github() {
    local url="$1" dest="$2" name="$3" perms="${4:-644}"
    local tmp=$(mktemp) ok=false
    info "Downloading ${name}..."
    command -v curl &>/dev/null && curl -fsSL --max-time 60 "$url" -o "$tmp" && ok=true
    command -v wget &>/dev/null && [[ "$ok" != "true" ]] && wget -qO "$tmp" --timeout=60 "$url" && ok=true
    [[ "$ok" != "true" ]] && { rm -f "$tmp"; return 1; }
    [[ "$dest" == *".py" ]] && ! head -1 "$tmp" | grep -q "python" && { rm -f "$tmp"; return 1; }
    mv "$tmp" "$dest"
    chmod "$perms" "$dest" 2>/dev/null || true
    chown root:root "$dest" 2>/dev/null || true
    return 0
}

# ── Step 8: Download/Update binary ────────────────────────────────────────────
if [[ "$INSTALL_MODE" == "reinstall" && -n "$INSTALLED_VERSION" ]]; then
    TAG_URL="https://github.com/SETFOP/setfop/raw/refs/tags/v${INSTALLED_VERSION}/setfop-daemon-linux/setfop-daemon.py"
    if ! download_from_github "$TAG_URL" "$BINARY_DEST" "setfop-daemon.py v${INSTALLED_VERSION}" "750"; then
        warn "Tag v${INSTALLED_VERSION} not found. Falling back to latest..."
        download_from_github "$GITHUB_BINARY_URL" "$BINARY_DEST" "setfop-daemon.py (latest)" "750" || die "Download failed."
    fi
else
    download_from_github "$GITHUB_BINARY_URL" "$BINARY_DEST" "setfop-daemon.py" "750" || die "Binary download failed."
fi
success "Binary installed: $BINARY_DEST"

# ── Step 9: Create directories ────────────────────────────────────────────────
info "Creating directories..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$LIB_DIR"
chown root:root "$CONFIG_DIR" "$LOG_DIR" "$LIB_DIR"
chmod 750 "$CONFIG_DIR" "$LOG_DIR" "$LIB_DIR"
success "Directories ready"

# ── Step 10: Install config (with fallback) ───────────────────────────────────
if [[ ! -f "$CONFIG_DEST" ]]; then
    info "Installing default config..."
    if ! download_from_github "$GITHUB_CONFIG_URL" "$CONFIG_DEST" "config" "640"; then
        warn "Could not download config. Using inline default..."
        cat > "$CONFIG_DEST" <<'EOF'
{
    "watch_paths": ["/opt"],
    "baseline_path": "/var/lib/setfop/baseline.setfop",
    "log_path": "/var/log/setfop/drift.log",
    "log_max_bytes": 10485760,
    "log_backup_count": 5,
    "snapshot_interval": 3600
}
EOF
        chmod 640 "$CONFIG_DEST"; chown root:root "$CONFIG_DEST"
    fi
    success "Config: $CONFIG_DEST"
else
    warn "Config exists: $CONFIG_DEST (preserved)"
fi

# ── Step 11: Install service file (with fallback) ─────────────────────────────
info "Installing systemd service..."
if ! download_from_github "$GITHUB_SERVICE_URL" "$SERVICE_DEST" "service" "644"; then
    warn "Could not download service. Using inline default..."
    cat > "$SERVICE_DEST" <<'EOF'
[Unit]
Description=SETFOP File Integrity Monitoring Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/setfop-daemon
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$SERVICE_DEST"; chown root:root "$SERVICE_DEST"
fi
success "Service: $SERVICE_DEST"

# ── Step 12: Install setfop-help.sh ───────────────────────────────────────────
info "Installing setfop-help.sh..."
download_from_github "$GITHUB_HELP_URL" "$HELP_DEST" "setfop-help.sh" "755" || warn "Could not install help script"

# ── Step 13: Self-relocate installer to /usr/local/bin ────────────────────────
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
INSTALLER_NAME="install-setfop-daemon.sh"
if [[ -f "$SCRIPT_PATH" && "$SCRIPT_PATH" != "/usr/local/bin/$INSTALLER_NAME" ]]; then
    info "Copying installer to /usr/local/bin/..."
    cp "$SCRIPT_PATH" "/usr/local/bin/$INSTALLER_NAME"
    chmod 755 "/usr/local/bin/$INSTALLER_NAME"
    success "Installer available at: /usr/local/bin/$INSTALLER_NAME"
fi

# ── Step 14: Reload systemd ───────────────────────────────────────────────────
info "Reloading systemd..."
systemctl daemon-reload
success "systemd reloaded"

# ── Step 15: Restart if previously enabled ────────────────────────────────────
if [[ "$INSTALL_MODE" != "fresh" ]] && systemctl is-enabled --quiet setfop-daemon 2>/dev/null; then
    info "Restarting service..."
    systemctl start setfop-daemon
    sleep 2
    systemctl is-active --quiet setfop-daemon && success "Service restarted" || warn "Service failed. Check: journalctl -u setfop-daemon -n 20"
fi

# ── DONE ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""

if [[ "$INSTALL_MODE" == "fresh" ]]; then
    echo -e "  To enable/start the daemon:"
    echo -e "    ${BOLD}systemctl enable setfop-daemon${RESET}"
    echo -e "    ${BOLD}systemctl start  setfop-daemon${RESET}"
    echo ""
    echo -e "  Check status: ${BOLD}systemctl status setfop-daemon${RESET}"
    echo -e "  Watch logs:   ${BOLD}tail -f /var/log/setfop/drift.log${RESET}"
fi

echo ""
echo -e "${CYAN}📦 Helper scripts installed to /usr/local/bin/:${RESET}"
echo -e "  • ${BOLD}install-setfop-daemon.sh${RESET}  — Re-run installer"
echo -e "  • ${BOLD}repair-setfop-daemon.sh${RESET}   — Fix corrupted files"
echo -e "  • ${BOLD}uninstall-setfop-daemon.sh${RESET} — Remove SETFOP"
echo -e "  • ${BOLD}setfop-help.sh${RESET}            — View file locations & usage"
echo ""
echo -e "  Run any of them directly, e.g.: ${BOLD}setfop-help.sh${RESET}"
echo ""