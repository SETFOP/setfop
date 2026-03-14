#!/usr/bin/env bash
# =============================================================================
#  install.sh — SETFOP Daemon Installer
#  Part of the SETFOP project: https://github.com/SETFOP/setfop
#
#  Usage: sudo bash install.sh
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

# ── GitHub raw URLs ───────────────────────────────────────────────────────────
GITHUB_BINARY_URL="https://github.com/SETFOP/setfop/raw/refs/heads/main/setfop-daemon-linux/setfop-daemon.py"
GITHUB_VERSION_URL="https://raw.githubusercontent.com/SETFOP/setfop/main/setfop-daemon-linux/VERSION"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# =============================================================================
#  HELPERS
# =============================================================================

info()    { echo -e "${CYAN}[setfop]${RESET} $*"; }
success() { echo -e "${GREEN}[setfop]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[setfop]${RESET} $*"; }
error()   { echo -e "${RED}[setfop] ERROR:${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# Clean exit on Ctrl+C, Ctrl+D, or Ctrl+Z
trap 'echo ""; warn "Installer interrupted. No changes were committed."; exit 1' INT TERM TSTP

# =============================================================================
#  STEP 0 — Root check
# =============================================================================

if [[ "$EUID" -ne 0 ]]; then
    die "This installer must be run as root.\n  Try: sudo bash install.sh"
fi

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${BOLD}   SETFOP Daemon Installer             ${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""

# =============================================================================
#  STEP 1 — Check python3
# =============================================================================

info "Checking for python3..."
if ! command -v python3 &>/dev/null; then
    die "python3 is not installed. Please install it first.\n  e.g. apt install python3"
fi
success "python3 found: $(python3 --version)"

# =============================================================================
#  STEP 2 — Check / install inotify_simple
# =============================================================================

info "Checking for inotify_simple Python package..."
if ! python3 -c "import inotify_simple" &>/dev/null; then
    warn "inotify_simple not found. Installing..."
    if ! pip3 install inotify_simple --break-system-packages -q; then
        die "Failed to install inotify_simple. Please install it manually:\n  pip3 install inotify_simple --break-system-packages"
    fi
    success "inotify_simple installed"
else
    success "inotify_simple already present"
fi

# =============================================================================
#  STEP 3 — Detect installed version (if any)
# =============================================================================

INSTALLED_VERSION=""
if [[ -f "$BINARY_DEST" ]]; then
    INSTALLED_VERSION=$(grep -m1 '^VERSION\s*=' "$BINARY_DEST" 2>/dev/null \
        | sed 's/VERSION\s*=\s*["\x27]\(.*\)["\x27]/\1/' \
        | tr -d '[:space:]') || INSTALLED_VERSION=""
fi

# =============================================================================
#  STEP 4 — Fetch latest version from GitHub
# =============================================================================

LATEST_VERSION=""
info "Fetching latest version info from GitHub..."
if command -v curl &>/dev/null; then
    LATEST_VERSION=$(curl -fsSL --max-time 10 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]') || LATEST_VERSION=""
elif command -v wget &>/dev/null; then
    LATEST_VERSION=$(wget -qO- --timeout=10 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]') || LATEST_VERSION=""
fi

# =============================================================================
#  STEP 5 — Version decision
# =============================================================================

INSTALL_MODE="fresh"   # fresh | reinstall | update

if [[ -n "$INSTALLED_VERSION" ]]; then
    # Already installed — present options to user
    echo ""
    echo -e "${BOLD}  Existing installation detected:${RESET}"
    echo -e "    Installed version : ${YELLOW}${INSTALLED_VERSION}${RESET}"

    if [[ -n "$LATEST_VERSION" ]]; then
        echo -e "    Latest version    : ${GREEN}${LATEST_VERSION}${RESET}"
    else
        warn "Could not reach GitHub to check latest version (no internet?)."
        echo -e "    Latest version    : ${YELLOW}unknown${RESET}"
    fi

    echo ""
    echo -e "  What would you like to do?"
    echo -e "    ${BOLD}1${RESET} — Reinstall current version (${INSTALLED_VERSION})"

    if [[ -n "$LATEST_VERSION" ]]; then
        echo -e "    ${BOLD}2${RESET} — Update to latest version (${LATEST_VERSION})"
    else
        echo -e "    ${YELLOW}2${RESET} — Update to latest  ${YELLOW}(unavailable — no internet)${RESET}"
    fi

    echo -e "    ${BOLD}3${RESET} — Quit"
    echo ""

    CHOICE=""
    while true; do
        # read returns non-zero on EOF (Ctrl+D) — we treat that as quit
        if ! read -rp "  Enter your choice [1/2/3]: " CHOICE; then
            echo ""
            warn "No input received. Exiting installer."
            exit 0
        fi

        case "$CHOICE" in
            1)
                INSTALL_MODE="reinstall"
                info "Reinstalling version ${INSTALLED_VERSION}..."
                break
                ;;
            2)
                if [[ -z "$LATEST_VERSION" ]]; then
                    warn "Cannot update — GitHub version info unavailable. Please check your internet connection."
                    continue
                fi
                INSTALL_MODE="update"
                info "Updating to version ${LATEST_VERSION}..."
                break
                ;;
            3)
                info "Quitting installer. No changes made."
                exit 0
                ;;
            *)
                warn "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
else
    info "No existing installation found. Proceeding with fresh install..."
fi

echo ""

# =============================================================================
#  STEP 6 — Stop daemon if running (before we touch the binary)
# =============================================================================

if systemctl is-active --quiet setfop-daemon 2>/dev/null; then
    info "Stopping running setfop-daemon service..."
    systemctl stop setfop-daemon
    success "Service stopped"
fi

# =============================================================================
#  STEP 7 — Download / copy binary
# =============================================================================

if [[ "$INSTALL_MODE" == "update" ]]; then
    # Download fresh copy from GitHub
    info "Downloading setfop-daemon from GitHub..."
    TMP_BINARY=$(mktemp /tmp/setfop-daemon.XXXXXX)

    DOWNLOAD_OK=false
    if command -v curl &>/dev/null; then
        curl -fsSL --max-time 60 "$GITHUB_BINARY_URL" -o "$TMP_BINARY" && DOWNLOAD_OK=true
    elif command -v wget &>/dev/null; then
        wget -qO "$TMP_BINARY" --timeout=60 "$GITHUB_BINARY_URL" && DOWNLOAD_OK=true
    fi

    if [[ "$DOWNLOAD_OK" != "true" ]]; then
        rm -f "$TMP_BINARY"
        die "Download failed. Check your internet connection and try again."
    fi

    # Verify it looks like a Python file
    if ! head -1 "$TMP_BINARY" | grep -q "python"; then
        rm -f "$TMP_BINARY"
        die "Downloaded file does not look like a valid Python script. Aborting."
    fi

    cp "$TMP_BINARY" "$BINARY_DEST"
    rm -f "$TMP_BINARY"
    success "Binary downloaded and installed"

else
    # fresh install or reinstall — use the local file next to install.sh
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOCAL_BINARY="$SCRIPT_DIR/setfop-daemon.py"

    if [[ ! -f "$LOCAL_BINARY" ]]; then
        die "setfop-daemon.py not found next to install.sh at:\n  $LOCAL_BINARY\n  Make sure you are running install.sh from the cloned repo directory."
    fi

    cp "$LOCAL_BINARY" "$BINARY_DEST"
    success "Binary copied from local repo"
fi

chmod 750 "$BINARY_DEST"
chown root:root "$BINARY_DEST"
success "Binary permissions set (750, root:root)"

# =============================================================================
#  STEP 8 — Create directories
# =============================================================================

info "Creating required directories..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$LIB_DIR"
chown root:root "$CONFIG_DIR" "$LOG_DIR" "$LIB_DIR"
chmod 750 "$CONFIG_DIR" "$LOG_DIR" "$LIB_DIR"
success "Directories ready"

# =============================================================================
#  STEP 9 — Install default config (never overwrites existing config)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CONFIG="$SCRIPT_DIR/setfop-daemon.config"

if [[ -f "$CONFIG_DEST" ]]; then
    warn "Existing config found at $CONFIG_DEST — leaving it untouched"
else
    if [[ -f "$LOCAL_CONFIG" ]]; then
        cp "$LOCAL_CONFIG" "$CONFIG_DEST"
    else
        # Write a minimal default config inline if no local file exists
        cat > "$CONFIG_DEST" <<'EOF'
{
    "watch_paths"       : ["/opt"],
    "baseline_path"     : "/var/lib/setfop/baseline.setfop",
    "log_path"          : "/var/log/setfop/drift.log",
    "log_max_bytes"     : 10485760,
    "log_backup_count"  : 5,
    "snapshot_interval" : 3600
}
EOF
    fi
    chmod 640 "$CONFIG_DEST"
    chown root:root "$CONFIG_DEST"
    success "Default config written to $CONFIG_DEST"
fi

# =============================================================================
#  STEP 10 — Install systemd service file
# =============================================================================

info "Installing systemd service file..."
LOCAL_SERVICE="$SCRIPT_DIR/setfop-daemon.service"

if [[ -f "$LOCAL_SERVICE" ]]; then
    cp "$LOCAL_SERVICE" "$SERVICE_DEST"
else
    die "setfop-daemon.service not found at:\n  $LOCAL_SERVICE\n  Make sure you are running install.sh from the cloned repo directory."
fi

chmod 644 "$SERVICE_DEST"
chown root:root "$SERVICE_DEST"
success "Service file installed at $SERVICE_DEST"

# =============================================================================
#  STEP 11 — Reload systemd
# =============================================================================

info "Reloading systemd daemon..."
systemctl daemon-reload
success "systemd reloaded"

# =============================================================================
#  STEP 12 — Restart service if it was previously enabled
# =============================================================================

if [[ "$INSTALL_MODE" == "update" || "$INSTALL_MODE" == "reinstall" ]]; then
    if systemctl is-enabled --quiet setfop-daemon 2>/dev/null; then
        info "Restarting setfop-daemon service..."
        systemctl start setfop-daemon
        sleep 2
        if systemctl is-active --quiet setfop-daemon; then
            success "setfop-daemon restarted successfully"
        else
            warn "Service did not start cleanly. Check logs:"
            warn "  journalctl -u setfop-daemon -n 30"
        fi
    fi
fi

# =============================================================================
#  DONE
# =============================================================================

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""

if [[ "$INSTALL_MODE" == "fresh" ]]; then
    echo -e "  To enable and start the daemon, run:"
    echo ""
    echo -e "    ${BOLD}systemctl enable setfop-daemon${RESET}"
    echo -e "    ${BOLD}systemctl start  setfop-daemon${RESET}"
    echo ""
    echo -e "  To check its status:"
    echo -e "    ${BOLD}systemctl status setfop-daemon${RESET}"
    echo ""
    echo -e "  To watch the drift log live:"
    echo -e "    ${BOLD}tail -f /var/log/setfop/drift.log${RESET}"
    echo ""
    echo -e "  Config file is at:"
    echo -e "    ${BOLD}$CONFIG_DEST${RESET}"
fi

echo ""
