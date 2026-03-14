#!/usr/bin/env bash
# =============================================================================
#  repair.sh — SETFOP Daemon Repair Tool
#  Usage: sudo bash repair.sh
#  Checks installed files against GitHub and restores if modified/corrupted
# =============================================================================

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
BINARY_DEST="/usr/local/bin/setfop-daemon"
CONFIG_DEST="/etc/setfop/setfop-daemon.config"
SERVICE_DEST="/etc/systemd/system/setfop-daemon.service"
BASELINE_FILE="/var/lib/setfop/baseline.setfop"

# ── GitHub Raw URLs ───────────────────────────────────────────────────────────
GITHUB_BINARY_URL="https://github.com/SETFOP/setfop/raw/refs/heads/main/setfop-daemon-linux/setfop-daemon.py"
GITHUB_CONFIG_URL="https://raw.githubusercontent.com/SETFOP/setfop/main/setfop-daemon-linux/setfop-daemon.config"
GITHUB_SERVICE_URL="https://raw.githubusercontent.com/SETFOP/setfop/main/setfop-daemon-linux/setfop-daemon.service"
GITHUB_VERSION_URL="https://raw.githubusercontent.com/SETFOP/setfop/main/setfop-daemon-linux/VERSION"

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

trap 'echo ""; warn "Repair interrupted."; exit 1' INT TERM TSTP

# ── Root Check ────────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    die "Must run as root: sudo bash repair.sh"
fi

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${BOLD}   SETFOP Daemon Repair Tool           ${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""

# ── Step 1: Fetch Latest Version ──────────────────────────────────────────────
LATEST_VERSION=""
info "Fetching latest version from GitHub..."
if command -v curl &>/dev/null; then
    LATEST_VERSION=$(curl -fsSL --max-time 10 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]') || LATEST_VERSION=""
elif command -v wget &>/dev/null; then
    LATEST_VERSION=$(wget -qO- --timeout=10 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]') || LATEST_VERSION=""
fi

if [[ -n "$LATEST_VERSION" ]]; then
    success "Latest version: ${LATEST_VERSION}"
else
    warn "Could not fetch version (offline?)"
fi

# ── Step 2: Check & Repair Binary ─────────────────────────────────────────────
check_and_repair_file() {
    local file="$1"
    local url="$2"
    local name="$3"
    local is_config="${4:-false}"
    
    if [[ ! -f "$file" ]]; then
        warn "$name not found: $file"
        read -rp "  Download from GitHub? [Y/n]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Nn]$ ]]; then
            download_from_github "$url" "$file" "$name"
        fi
        return
    fi
    
    # For config files, don't auto-replace — ask user
    if [[ "$is_config" == "true" ]]; then
        info "Checking $name..."
        # Just validate JSON for config
        if [[ "$file" == *.config ]]; then
            if ! python3 -m json.tool "$file" &>/dev/null; then
                warn "$name has invalid JSON!"
                read -rp "  Restore default config? [y/N]: " RESTORE
                if [[ "$RESTORE" =~ ^[Yy]$ ]]; then
                    download_from_github "$url" "$file" "$name"
                fi
            else
                success "$name is valid"
            fi
        fi
        return
    fi
    
    # For binary/service: check if it looks like valid Python/systemd file
    local needs_repair=false
    
    if [[ "$file" == *".py" ]]; then
        # Check for Python shebang and basic syntax
        if ! head -1 "$file" | grep -q "python"; then
            warn "$name doesn't look like a Python script"
            needs_repair=true
        elif ! python3 -m py_compile "$file" 2>/dev/null; then
            warn "$name has Python syntax errors"
            needs_repair=true
        fi
    elif [[ "$file" == *".service" ]]; then
        # Check for [Unit] section
        if ! grep -q "^\[Unit\]" "$file"; then
            warn "$name doesn't look like a valid systemd service file"
            needs_repair=true
        fi
    fi
    
    if [[ "$needs_repair" == "true" ]]; then
        read -rp "  Repair $name from GitHub? [Y/n]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Nn]$ ]]; then
            # Backup first
            cp "$file" "${file}.bak.$(date +%Y%m%d%H%M)"
            warn "Backup created: ${file}.bak.*"
            download_from_github "$url" "$file" "$name"
        fi
    else
        success "$name appears intact"
    fi
}

download_from_github() {
    local url="$1"
    local dest="$2"
    local name="$3"
    
    info "Downloading $name..."
    local tmp_file=$(mktemp)
    local ok=false
    
    if command -v curl &>/dev/null; then
        curl -fsSL --max-time 60 "$url" -o "$tmp_file" && ok=true
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_file" --timeout=60 "$url" && ok=true
    fi
    
    if [[ "$ok" != "true" ]]; then
        rm -f "$tmp_file"
        error "Failed to download $name"
        return 1
    fi
    
    # Validate
    if [[ "$dest" == *".py" ]] && ! head -1 "$tmp_file" | grep -q "python"; then
        rm -f "$tmp_file"
        error "Downloaded file doesn't look like Python script"
        return 1
    fi
    
    mv "$tmp_file" "$dest"
    chmod 750 "$dest" 2>/dev/null || chmod 644 "$dest"
    chown root:root "$dest" 2>/dev/null || true
    success "$name restored"
}

# ── Run Checks ────────────────────────────────────────────────────────────────

info "Checking installed files..."
echo ""

# Binary
check_and_repair_file "$BINARY_DEST" "$GITHUB_BINARY_URL" "setfop-daemon.py"

# Service file
check_and_repair_file "$SERVICE_DEST" "$GITHUB_SERVICE_URL" "setfop-daemon.service"

# Config (special handling)
check_and_repair_file "$CONFIG_DEST" "$GITHUB_CONFIG_URL" "setfop-daemon.config" "true"

# ── Step 3: Fix Permissions ───────────────────────────────────────────────────
info "Verifying permissions..."

if [[ -f "$BINARY_DEST" ]]; then
    if [[ "$(stat -c '%a' "$BINARY_DEST")" != "750" ]] || [[ "$(stat -c '%U:%G' "$BINARY_DEST")" != "root:root" ]]; then
        warn "Binary has incorrect permissions/ownership"
        chmod 750 "$BINARY_DEST"
        chown root:root "$BINARY_DEST"
        success "Fixed binary permissions"
    fi
fi

if [[ -f "$SERVICE_DEST" ]]; then
    if [[ "$(stat -c '%a' "$SERVICE_DEST")" != "644" ]]; then
        chmod 644 "$SERVICE_DEST"
        chown root:root "$SERVICE_DEST"
        success "Fixed service file permissions"
    fi
fi

if [[ -f "$CONFIG_DEST" ]]; then
    if [[ "$(stat -c '%a' "$CONFIG_DEST")" != "640" ]]; then
        chmod 640 "$CONFIG_DEST"
        chown root:root "$CONFIG_DEST"
        success "Fixed config permissions"
    fi
fi

# ── Step 4: Reload & Restart Service ──────────────────────────────────────────
echo ""
info "Reloading systemd..."
systemctl daemon-reload

if systemctl is-enabled --quiet setfop-daemon 2>/dev/null; then
    read -rp "  Restart setfop-daemon service now? [Y/n]: " RESTART
    if [[ ! "$RESTART" =~ ^[Nn]$ ]]; then
        systemctl restart setfop-daemon
        sleep 2
        if systemctl is-active --quiet setfop-daemon; then
            success "Service restarted successfully"
        else
            warn "Service failed to start. Check: journalctl -u setfop-daemon -n 20"
        fi
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${GREEN}${BOLD}  Repair complete!${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""
echo -e "  Summary:"
echo -e "  • Binary: $BINARY_DEST"
echo -e "  • Config: $CONFIG_DEST"
echo -e "  • Service: $SERVICE_DEST"
echo -e ""
echo -e "  To check status: ${BOLD}systemctl status setfop-daemon${RESET}"
echo -e "  To watch logs:   ${BOLD}tail -f /var/log/setfop/drift.log${RESET}"
echo ""
