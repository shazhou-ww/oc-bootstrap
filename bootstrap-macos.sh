#!/bin/bash
# ============================================================
# OpenClaw Bootstrap — macOS
# 
# 开 SSH + 通过 Cloudflare Quick Tunnel 暴露给 buddy agent
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-macos.sh)
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
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🌌 OpenClaw Bootstrap — macOS          ║${NC}"
echo -e "${CYAN}║   Enables SSH + Tunnel for buddy agent   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
step 1 "Enable SSH (Remote Login)"
# ============================================================

SSH_ON=false
if sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
    SSH_ON=true
elif launchctl list 2>/dev/null | grep -q "com.openssh.sshd"; then
    SSH_ON=true
elif nc -z localhost 22 2>/dev/null; then
    SSH_ON=true
fi

if [ "$SSH_ON" = true ]; then
    ok "SSH already enabled"
else
    info "Trying to enable SSH..."
    if sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null; then
        ok "SSH enabled via launchctl"
    else
        echo ""
        echo -e "${YELLOW}  ⚠️  Could not enable SSH automatically.${NC}"
        echo -e "  Please enable it manually:"
        echo -e "  ${CYAN}System Settings → General → Sharing → Remote Login → ON${NC}"
        echo ""
        read -p "  Press Enter after you've enabled SSH (or Ctrl+C to cancel)..." _ </dev/tty
        if nc -z localhost 22 2>/dev/null; then
            ok "SSH is now running"
        else
            fail "SSH still not detected on port 22. Please enable Remote Login and try again."
        fi
    fi
fi

# ============================================================
step 2 "Inject buddy agent SSH key"
# ============================================================

SSH_DIR="$HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$AUTH_KEYS" ] && grep -qF "$BUDDY_KEY" "$AUTH_KEYS"; then
    ok "Buddy key already present"
else
    echo "$BUDDY_KEY" >> "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    ok "Buddy key added"
fi

# ============================================================
step 3 "Install cloudflared"
# ============================================================

if command -v cloudflared &>/dev/null; then
    ok "cloudflared already installed ($(cloudflared --version 2>&1 | head -1))"
else
    if command -v brew &>/dev/null; then
        info "Installing cloudflared via Homebrew..."
        brew install cloudflared
    else
        info "Downloading cloudflared binary..."
        ARCH=$(uname -m)
        if [ "$ARCH" = "arm64" ]; then
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz"
        else
            CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
        fi
        curl -fsSL "$CF_URL" -o /tmp/cloudflared.tgz
        tar -xzf /tmp/cloudflared.tgz -C /tmp/
        sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
        sudo chmod +x /usr/local/bin/cloudflared
        rm -f /tmp/cloudflared.tgz
    fi
    ok "cloudflared installed ($(cloudflared --version 2>&1 | head -1))"
fi

# ============================================================
step 4 "Start Quick Tunnel"
# ============================================================

info "Starting Cloudflare Quick Tunnel (no account needed)..."
info "This gives you a temporary public URL for SSH access."
echo ""

# Start quick tunnel in background, capture the URL
TUNNEL_LOG="/tmp/oc-bootstrap-tunnel.log"
cloudflared tunnel --url ssh://localhost:22 &>"$TUNNEL_LOG" &
TUNNEL_PID=$!

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
    warn "Could not detect tunnel URL. Check: cat $TUNNEL_LOG"
    fail "Quick Tunnel failed to start."
fi

# Extract hostname from URL
SSH_HOST=$(echo "$SSH_URL" | sed 's|https://||')
LOCAL_USER=$(whoami)

ok "Tunnel running (PID: $TUNNEL_PID)"

# ============================================================
step 5 "Summary"
# ============================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ Bootstrap Complete!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}User:${NC}       $LOCAL_USER"
echo -e "  ${CYAN}Tunnel:${NC}     $SSH_HOST"
echo -e "  ${CYAN}PID:${NC}        $TUNNEL_PID"
echo ""
echo -e "  ${YELLOW}📋 Send this to your buddy agent:${NC}"
echo ""
echo -e "  ${BOLD}${GREEN}ssh -o ProxyCommand=\"cloudflared access ssh --hostname ${SSH_HOST}\" ${LOCAL_USER}@${SSH_HOST}${NC}"
echo ""
echo -e "  ${CYAN}Notes:${NC}"
echo -e "  • This URL is ${YELLOW}temporary${NC} — it changes if the tunnel restarts"
echo -e "  • Keep this terminal open (or the tunnel will stop)"
echo -e "  • Your buddy agent will set up a permanent tunnel later"
echo ""
