#!/bin/bash
# ============================================================
# OpenClaw Bootstrap — Universal Router
#
# 自动检测系统类型，下载并执行对应的 bootstrap 脚本
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap.sh)
# ============================================================
set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

OS="$(uname -s)"

case "$OS" in
    Darwin)
        echo -e "${CYAN}[INFO]${NC}  Detected macOS — downloading macOS bootstrap..."
        exec bash <(curl -fsSL "$BASE_URL/bootstrap-macos.sh")
        ;;
    Linux)
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian|pop|linuxmint|elementary|zorin|kali|raspbian)
                    echo -e "${CYAN}[INFO]${NC}  Detected $PRETTY_NAME — downloading Ubuntu/Debian bootstrap..."
                    exec bash <(curl -fsSL "$BASE_URL/bootstrap-ubuntu.sh")
                    ;;
                *)
                    # Check if it's a Debian derivative
                    if [ -n "${ID_LIKE:-}" ] && echo "$ID_LIKE" | grep -q "debian\|ubuntu"; then
                        echo -e "${CYAN}[INFO]${NC}  Detected $PRETTY_NAME (Debian-based) — downloading Ubuntu/Debian bootstrap..."
                        exec bash <(curl -fsSL "$BASE_URL/bootstrap-ubuntu.sh")
                    else
                        echo -e "${RED}[FAIL]${NC}  Unsupported Linux distro: $PRETTY_NAME ($ID)"
                        echo -e "  Supported: Ubuntu, Debian, and Debian-based distros"
                        echo -e "  ${YELLOW}Want to try the Ubuntu script anyway?${NC}"
                        read -p "  Continue? [y/N] " -r REPLY </dev/tty
                        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                            exec bash <(curl -fsSL "$BASE_URL/bootstrap-ubuntu.sh")
                        fi
                        exit 1
                    fi
                    ;;
            esac
        else
            echo -e "${RED}[FAIL]${NC}  Cannot detect Linux distribution (no /etc/os-release)"
            exit 1
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo -e "${RED}[FAIL]${NC}  Windows detected. Please run from WSL instead:"
        echo -e "  ${GREEN}wsl bash <(curl -fsSL $BASE_URL/bootstrap.sh)${NC}"
        exit 1
        ;;
    *)
        echo -e "${RED}[FAIL]${NC}  Unsupported OS: $OS"
        exit 1
        ;;
esac
