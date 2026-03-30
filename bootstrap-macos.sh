#!/bin/bash
# ============================================================
# OpenClaw Bootstrap — macOS
# 
# 一行命令：开 SSH + 建 Cloudflare Tunnel + 注入 buddy 公钥
# 用法: curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-macos.sh | bash
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
step 3 "Install & configure Cloudflare Tunnel"
# ============================================================

# Install cloudflared
if command -v cloudflared &>/dev/null; then
    ok "cloudflared already installed ($(cloudflared --version 2>&1 | head -1))"
else
    if command -v brew &>/dev/null; then
        info "Installing cloudflared via Homebrew..."
        brew install cloudflared
    else
        info "Homebrew not found, downloading cloudflared binary directly..."
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

# Login to Cloudflare (requires browser)
if [ -f "$HOME/.cloudflared/cert.pem" ]; then
    ok "Already logged in to Cloudflare"
else
    echo ""
    echo -e "${YELLOW}  🌐 A browser window will open for Cloudflare login.${NC}"
    echo -e "  ${YELLOW}Select the domain you want to use (e.g. shazhou.work)${NC}"
    echo ""
    cloudflared tunnel login
    ok "Cloudflare login complete"
fi

# Ask for tunnel name
echo ""
read -p "  Enter a name for this tunnel (e.g. sora): " TUNNEL_NAME </dev/tty
TUNNEL_NAME=${TUNNEL_NAME:-sora}

# Create tunnel (or use existing)
TUNNEL_ID=""
EXISTING=$(cloudflared tunnel list 2>/dev/null | grep -i "$TUNNEL_NAME" | awk '{print $1}' || true)
if [ -n "$EXISTING" ]; then
    TUNNEL_ID="$EXISTING"
    ok "Tunnel '$TUNNEL_NAME' already exists (ID: $TUNNEL_ID)"
else
    info "Creating tunnel '$TUNNEL_NAME'..."
    TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
    TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oE '[0-9a-f-]{36}' | head -1)
    if [ -z "$TUNNEL_ID" ]; then
        echo "$TUNNEL_OUTPUT"
        fail "Could not create tunnel. See output above."
    fi
    ok "Tunnel created (ID: $TUNNEL_ID)"
fi

# Ask for hostname
echo ""
echo -e "  ${CYAN}What hostname should point to this machine's SSH?${NC}"
echo -e "  Example: ${GREEN}sora-ssh.shazhou.work${NC}"
echo ""
read -p "  Hostname: " SSH_HOSTNAME </dev/tty
SSH_HOSTNAME=${SSH_HOSTNAME:-sora-ssh.shazhou.work}

# Write tunnel config
CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
CONFIG_FILE="$HOME/.cloudflared/config.yml"

if [ -f "$CONFIG_FILE" ]; then
    warn "Config file already exists at $CONFIG_FILE"
    echo -e "  Backing up to ${CONFIG_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

cat > "$CONFIG_FILE" <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED_FILE}

ingress:
  - hostname: ${SSH_HOSTNAME}
    service: ssh://localhost:22
  - service: http_status:404
EOF

ok "Tunnel config written to $CONFIG_FILE"

# Create DNS record
info "Creating DNS record for $SSH_HOSTNAME..."
cloudflared tunnel route dns "$TUNNEL_NAME" "$SSH_HOSTNAME" 2>&1 || warn "DNS record may already exist (that's fine)"
ok "DNS configured: $SSH_HOSTNAME → tunnel $TUNNEL_NAME"

# Start tunnel
info "Starting tunnel..."
echo -e "  ${CYAN}(This will run in the background. Use Ctrl+C later to stop.)${NC}"
echo ""

# Try to install as service first
if cloudflared service install 2>/dev/null; then
    ok "Tunnel installed as system service (auto-start on boot)"
else
    warn "Could not install as service. Starting in background..."
    nohup cloudflared tunnel run "$TUNNEL_NAME" &>/tmp/cloudflared.log &
    sleep 3
    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        ok "Tunnel running (PID: $(pgrep -f "cloudflared tunnel run" | head -1))"
    else
        warn "Tunnel may not have started. Check: cat /tmp/cloudflared.log"
    fi
fi

# ============================================================
step 4 "Summary"
# ============================================================

LOCAL_USER=$(whoami)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✅ Bootstrap Complete!            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}User:${NC}         $LOCAL_USER"
echo -e "  ${CYAN}Tunnel:${NC}       $TUNNEL_NAME ($TUNNEL_ID)"
echo -e "  ${CYAN}SSH Host:${NC}     $SSH_HOSTNAME"
echo ""
echo -e "  ${YELLOW}📋 Send this to your buddy agent:${NC}"
echo ""
echo -e "  ${BOLD}${GREEN}ssh -o ProxyCommand=\"cloudflared access ssh --hostname ${SSH_HOSTNAME}\" ${LOCAL_USER}@${SSH_HOSTNAME}${NC}"
echo ""
echo -e "  ${CYAN}Or if buddy uses standard SSH with cloudflared config:${NC}"
echo -e "  Add to buddy's ~/.ssh/config:"
echo ""
echo -e "    Host ${SSH_HOSTNAME}"
echo -e "      ProxyCommand cloudflared access ssh --hostname %h"
echo -e "      User ${LOCAL_USER}"
echo ""
echo -e "  ${CYAN}Then simply:${NC} ${GREEN}ssh ${SSH_HOSTNAME}${NC}"
echo ""
