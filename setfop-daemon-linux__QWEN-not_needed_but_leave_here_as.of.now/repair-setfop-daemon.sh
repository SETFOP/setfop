#!/usr/bin/env bash
# =============================================================================
#  repair-setfop-daemon.sh — SETFOP Daemon Repair Tool
#  Usage: sudo bash repair-setfop-daemon.sh [--force]
#  Checks installed files against GitHub and restores if corrupted
# =============================================================================

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
BINARY_DEST="/usr/local/bin/setfop-daemon"
CONFIG_DEST="/etc/setfop/setfop-daemon.config"
SERVICE_DEST="/etc/systemd/system/setfop-daemon.service"
HELP_DEST="/usr/local/bin/setfop-help.sh"
BASELINE_FILE="/var/lib/setfop/baseline.setfop"

# ── GitHub URLs ───────────────────────────────────────────────────────────────
GITHUB_BASE="https://raw.githubusercontent.com/SETFOP/setfop/main/setfop-daemon-linux"
GITHUB_BINARY_URL="$GITHUB_BASE/setfop-daemon.py"
GITHUB_CONFIG_URL="$GITHUB_BASE/setfop-daemon.config"
GITHUB_SERVICE_URL="$GITHUB_BASE/setfop-daemon.service"
GITHUB_HELP_URL="$GITHUB_BASE/setfop-help.sh"
GITHUB_VERSION_URL="$GITHUB_BASE/VERSION"

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
ask()     { [[ "$FORCE_MODE" == "true" ]] && return 0; read -rp "  $* [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]; }

trap 'echo ""; warn "Repair interrupted."; exit 1' INT TERM TSTP

[[ "$EUID" -ne 0 ]] && die "Must run as root: sudo bash repair-setfop-daemon.sh"

echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${BOLD}   SETFOP Daemon Repair Tool           ${RESET}"
echo -e "${BOLD}=======================================${RESET}"
[[ "$FORCE_MODE" == "true" ]] && echo -e "${YELLOW}  ⚡ Force mode: no prompts${RESET}"
echo ""

# ── Download helper ───────────────────────────────────────────────────────────
download_file() {
    local url="$1" dest="$2" name="$3" perms="${4:-644}"
    local tmp=$(mktemp) ok=false
    command -v curl &>/dev/null && curl -fsSL --max-time 60 "$url" -o "$tmp" && ok=true
    command -v wget &>/dev/null && [[ "$ok" != "true" ]] && wget -qO "$tmp" --timeout=60 "$url" && ok=true
    [[ "$ok" != "true" ]] && { rm -f "$tmp"; return 1; }
    [[ "$dest" == *".py" ]] && ! head -1 "$tmp" | grep -q "python" && { rm -f "$tmp"; return 1; }
    mv "$tmp" "$dest"
    chmod "$perms" "$dest" 2>/dev/null || true
    chown root:root "$dest" 2>/dev/null || true
    return 0
}

# ── Validation functions ──────────────────────────────────────────────────────
validate_python() {
    [[ ! -f "$1" ]] && return 1
    head -1 "$1" | grep -q "python" || return 1
    python3 -m py_compile "$1" 2>/dev/null || return 1
    return 0
}

validate_service() {
    [[ ! -f "$1" ]] && return 1
    grep -q "^\[Unit\]" "$1" && grep -q "ExecStart=" "$1" || return 1
    return 0
}

validate_config() {
    [[ ! -f "$1" ]] && return 1
    python3 -m json.tool "$1" &>/dev/null || return 1
    return 0
}

# ── Repair logic ──────────────────────────────────────────────────────────────
repair_file() {
    local file="$1" url="$2" name="$3" validator="$4" perms="${5:-644}"
    
    [[ ! -f "$file" ]] && { warn "$name missing: $file"; ask "Download from GitHub?" && download_file "$url" "$file" "$name" "$perms" && success "$name restored" || warn "Skipped $name"; return; }
    
    if $validator "$file" 2>/dev/null; then
        success "$name is valid"
    else
        warn "$name appears corrupted"
        if ask "Restore $name from GitHub?"; then
            cp "$file" "${file}.bak.$(date +%Y%m%d%H%M)"
            warn "Backup: ${file}.bak.*"
            download_file "$url" "$file" "$name" "$perms" && success "$name repaired" || error "Failed to restore $name"
        else
            warn "Skipped repair for $name"
        fi
    fi
}

# ── Run repairs ───────────────────────────────────────────────────────────────
info "Checking installed files..."
echo ""

repair_file "$BINARY_DEST" "$GITHUB_BINARY_URL" "setfop-daemon.py" validate_python "750"
repair_file "$SERVICE_DEST" "$GITHUB_SERVICE_URL" "setfop-daemon.service" validate_service "644"
repair_file "$CONFIG_DEST" "$GITHUB_CONFIG_URL" "setfop-daemon.config" validate_config "640"
repair_file "$HELP_DEST" "$GITHUB_HELP_URL" "setfop-help.sh" 'true' "755"

# ── Fix permissions ───────────────────────────────────────────────────────────
info "Verifying permissions..."
[[ -f "$BINARY_DEST" ]] && { [[ "$(stat -c '%a' "$BINARY_DEST")" != "750" || "$(stat -c '%U:%G' "$BINARY_DEST")" != "root:root" ]] && { chmod 750 "$BINARY_DEST"; chown root:root "$BINARY_DEST"; success "Fixed binary permissions"; }; }
[[ -f "$SERVICE_DEST" ]] && { [[ "$(stat -c '%a' "$SERVICE_DEST")" != "644" ]] && { chmod 644 "$SERVICE_DEST"; chown root:root "$SERVICE_DEST"; success "Fixed service permissions"; }; }
[[ -f "$CONFIG_DEST" ]] && { [[ "$(stat -c '%a' "$CONFIG_DEST")" != "640" ]] && { chmod 640 "$CONFIG_DEST"; chown root:root "$CONFIG_DEST"; success "Fixed config permissions"; }; }

# ── Reload & restart ──────────────────────────────────────────────────────────
echo ""
info "Reloading systemd..."
systemctl daemon-reload

if systemctl is-enabled --quiet setfop-daemon 2>/dev/null; then
    if ask "Restart setfop-daemon service?"; then
        systemctl restart setfop-daemon
        sleep 2
        systemctl is-active --quiet setfop-daemon && success "Service restarted" || warn "Service failed. Check: journalctl -u setfop-daemon -n 20"
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}=======================================${RESET}"
echo -e "${GREEN}${BOLD}  Repair complete!${RESET}"
echo -e "${BOLD}=======================================${RESET}"
echo ""
echo -e "  Check status: ${BOLD}systemctl status setfop-daemon${RESET}"
echo -e "  Watch logs:   ${BOLD}tail -f /var/log/setfop/drift.log${RESET}"
echo -e "  Get help:     ${BOLD}setfop-help.sh${RESET}"
echo ""