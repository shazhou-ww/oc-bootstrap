#!/bin/bash
# ============================================================
# OpenClaw Bootstrap — Ubuntu / Debian
#
# 开 SSH + 通过 Cloudflare Quick Tunnel 暴露给 buddy agent
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-ubuntu.sh)
# ============================================================
set -euo pipefail

BUDDY_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEW7ztxi0oT2BmXr/cbt7bJWiDi+sPfirx9+YQxgdZpU azureuser@kuma-vm-west"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
step()  { echo ""; echo -e "${BOLD}── Step $1: $2 ──${NC}"; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🌌 OpenClaw Bootstrap — Ubuntu / Debian    ║${NC}"
echo -e "${CYAN}║   Enables SSH + Tunnel for buddy agent       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
step 1 "Check privileges"
# ============================================================

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    ok "Running as root"
else
    SUDO="sudo"
    info "Running as $(whoami), will use sudo when needed"
    # Test sudo access early
    if ! $SUDO -n true 2>/dev/null; then
        info "sudo password may be required..."
        $SUDO true || fail "sudo access required. Please run with sudo or enter your password."
    fi
    ok "sudo access confirmed"
fi

# ============================================================
step 2 "Install and enable SSH server"
# ============================================================

if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
    ok "SSH server already running"
elif nc -z localhost 22 2>/dev/null; then
    ok "SSH already listening on port 22"
else
    info "Installing openssh-server..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq openssh-server

    # Enable and start
    if systemctl list-unit-files | grep -q "sshd.service"; then
        $SUDO systemctl enable --now sshd
    else
        $SUDO systemctl enable --now ssh
    fi

    # Verify
    sleep 1
    if nc -z localhost 22 2>/dev/null; then
        ok "SSH server installed and running"
    else
        fail "SSH server installed but not listening on port 22. Check: systemctl status ssh"
    fi
fi

# ============================================================
step 3 "Inject buddy agent SSH key"
# ============================================================

# Determine target user (prefer non-root if running as sudo)
TARGET_USER="${SUDO_USER:-$(whoami)}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

SSH_DIR="$TARGET_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

# Create .ssh dir if missing
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$SSH_DIR"
fi
chmod 700 "$SSH_DIR"

if [ -f "$AUTH_KEYS" ] && grep -qF "$BUDDY_KEY" "$AUTH_KEYS"; then
    ok "Buddy key already present"
else
    echo "$BUDDY_KEY" >> "$AUTH_KEYS"
    chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    ok "Buddy key added for user: $TARGET_USER"
fi

# Ensure PubkeyAuthentication is enabled
SSHD_CONFIG="/etc/ssh/sshd_config"
if grep -qE '^\s*PubkeyAuthentication\s+no' "$SSHD_CONFIG" 2>/dev/null; then
    warn "PubkeyAuthentication is disabled in $SSHD_CONFIG"
    info "Enabling PubkeyAuthentication..."
    $SUDO sed -i 's/^\s*PubkeyAuthentication\s\+no/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    $SUDO systemctl reload sshd 2>/dev/null || $SUDO systemctl reload ssh 2>/dev/null || true
    ok "PubkeyAuthentication enabled"
fi

# ============================================================
step 4 "Install cloudflared"
# ============================================================

if command -v cloudflared &>/dev/null; then
    ok "cloudflared already installed ($(cloudflared --version 2>&1 | head -1))"
else
    info "Installing cloudflared..."

    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$ARCH" in
        amd64|x86_64)
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
            ;;
        arm64|aarch64)
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
            ;;
        armhf|armv7l)
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm.deb"
            ;;
        *)
            fail "Unsupported architecture: $ARCH"
            ;;
    esac

    DEB_FILE="/tmp/cloudflared.deb"
    info "Downloading from: $CF_URL"
    curl -fsSL "$CF_URL" -o "$DEB_FILE"
    $SUDO dpkg -i "$DEB_FILE"
    rm -f "$DEB_FILE"

    if command -v cloudflared &>/dev/null; then
        ok "cloudflared installed ($(cloudflared --version 2>&1 | head -1))"
    else
        fail "cloudflared installation failed"
    fi
fi

# ============================================================
step 5 "Start Quick Tunnel"
# ============================================================

info "Starting Cloudflare Quick Tunnel (no account needed)..."
info "This gives you a temporary public URL for SSH access."
echo ""

# Start quick tunnel in background, capture the URL
TUNNEL_LOG="/tmp/oc-bootstrap-tunnel.log"

# Kill any existing bootstrap tunnel
if [ -f /tmp/oc-bootstrap-tunnel.pid ]; then
    OLD_PID=$(cat /tmp/oc-bootstrap-tunnel.pid 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        info "Killing previous tunnel (PID: $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
    fi
fi

cloudflared tunnel --url tcp://localhost:22 --protocol http2 &>"$TUNNEL_LOG" &
TUNNEL_PID=$!
echo "$TUNNEL_PID" > /tmp/oc-bootstrap-tunnel.pid

# Wait for the URL to appear
SSH_URL=""
for i in $(seq 1 30); do
    SSH_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1 || true)
    if [ -n "$SSH_URL" ]; then
        break
    fi
    sleep 1
done

if [ -z "$SSH_URL" ]; then
    warn "Could not detect tunnel URL after 30s."
    warn "Check log: cat $TUNNEL_LOG"
    fail "Quick Tunnel failed to start."
fi

# Extract hostname from URL
SSH_HOST=$(echo "$SSH_URL" | sed 's|https://||')

ok "Tunnel running (PID: $TUNNEL_PID)"

# ============================================================
step 6 "Summary"
# ============================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ Bootstrap Complete!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}User:${NC}       $TARGET_USER"
echo -e "  ${CYAN}Tunnel:${NC}     $SSH_HOST"
echo -e "  ${CYAN}PID:${NC}        $TUNNEL_PID"
echo ""
echo -e "  ${YELLOW}📋 Send this to your buddy agent:${NC}"
echo ""
echo -e "  ${BOLD}${GREEN}Tunnel: ${SSH_HOST}${NC}"
echo -e "  ${BOLD}${GREEN}User:   ${TARGET_USER}${NC}"
echo ""
echo -e "  ${CYAN}Buddy agent connects with:${NC}"
echo -e "  ${GREEN}cloudflared access tcp --hostname ${SSH_HOST} --url localhost:2222 &${NC}"
echo -e "  ${GREEN}ssh -p 2222 ${TARGET_USER}@localhost${NC}"
echo ""
echo -e "  ${CYAN}Notes:${NC}"
echo -e "  • This URL is ${YELLOW}temporary${NC} — it changes if the tunnel restarts"
echo -e "  • Keep this terminal open (or the tunnel will stop)"
echo -e "  • Your buddy agent will set up a permanent connection later"
echo ""
echo -e "  ${CYAN}To stop the tunnel later:${NC}"
echo -e "  ${GREEN}kill $TUNNEL_PID${NC}"
echo ""
