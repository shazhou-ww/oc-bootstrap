#!/bin/bash
# ============================================================
# OpenClaw Bootstrap — macOS
# 
# 一行命令让 buddy agent 能 SSH 进来。
# 用法: curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-macos.sh | bash
# ============================================================
set -euo pipefail

BUDDY_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEW7ztxi0oT2BmXr/cbt7bJWiDi+sPfirx9+YQxgdZpU azureuser@kuma-vm-west"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🌌 OpenClaw Bootstrap — macOS      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# --- Step 1: Check SSH ---
info "Checking SSH (Remote Login)..."

SSH_ON=false
if sudo systemsetup -getremotelogin 2>/dev/null | grep -q "On"; then
    SSH_ON=true
    ok "SSH already enabled"
elif ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no localhost true 2>/dev/null; then
    SSH_ON=true
    ok "SSH is running"
fi

if [ "$SSH_ON" = false ]; then
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW} SSH (Remote Login) is not enabled.${NC}"
    echo -e "${YELLOW} Please enable it manually, then re-run this script:${NC}"
    echo ""
    echo -e "  ${CYAN}macOS Ventura+:${NC}"
    echo -e "    System Settings → General → Sharing → Remote Login → ON"
    echo ""
    echo -e "  ${CYAN}Or via terminal:${NC}"
    echo -e "    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo ""
    fail "Enable SSH first, then run this script again."
fi

# --- Step 2: Inject buddy public key ---
info "Setting up buddy agent SSH key..."

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

# --- Step 3: Collect connection info ---
info "Gathering connection info..."

LOCAL_USER=$(whoami)
HOSTNAME=$(hostname)

# Get local IP (prefer en0 Wi-Fi, fallback to any)
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unknown")

# Get public IP
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "unknown")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✅ Bootstrap Complete!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}User:${NC}       $LOCAL_USER"
echo -e "  ${CYAN}Hostname:${NC}   $HOSTNAME"
echo -e "  ${CYAN}Local IP:${NC}   $LOCAL_IP"
echo -e "  ${CYAN}Public IP:${NC}  $PUBLIC_IP"
echo ""
echo -e "  ${YELLOW}📋 Send this to your buddy agent:${NC}"
echo ""
echo -e "  ${GREEN}ssh ${LOCAL_USER}@${LOCAL_IP}${NC}"
echo ""
echo -e "  If buddy is remote (different network):"
echo -e "  ${GREEN}ssh ${LOCAL_USER}@${PUBLIC_IP}${NC}"
echo -e "  (requires port 22 forwarded or tunnel configured)"
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo -e "  1. If on same network → send the local IP line above to buddy"
echo -e "  2. If remote → set up a tunnel (Cloudflare/Tailscale/port forward)"
echo -e "     then send the public IP or tunnel hostname"
echo -e "  3. Buddy agent will SSH in and complete the rest 🚀"
echo ""
