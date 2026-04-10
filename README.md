# oc-bootstrap

One-line scripts to bootstrap a new device for OpenClaw onboarding.

## What it does

1. Enables SSH access on the target device
2. Injects the buddy agent's public key
3. Sets up a Cloudflare Quick Tunnel (temporary, no account needed)
4. Outputs the SSH command to send to your buddy agent

**That's it.** Everything else (Node.js, OpenClaw, config, A2A) is handled by the buddy agent after SSH is established.

## Quick Start

### Universal (auto-detects OS)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap.sh)
```

### macOS

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-macos.sh)
```

### Ubuntu / Debian

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-ubuntu.sh)
```

### Windows — use WSL

```bash
wsl bash <(curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap.sh)
```

## Supported Systems

| OS | Script | Status |
|:---|:-------|:-------|
| macOS (Intel + Apple Silicon) | `bootstrap-macos.sh` | ✅ |
| Ubuntu 20.04+ / Debian 11+ | `bootstrap-ubuntu.sh` | ✅ |
| Debian-based (Pop!_OS, Mint, etc.) | `bootstrap-ubuntu.sh` | ✅ |
| Windows (WSL2) | via `bootstrap-ubuntu.sh` | ✅ |
| Other Linux (Fedora, Arch, etc.) | — | ❌ Coming soon |

## Flow

```
Human runs bootstrap on new device
         │
         ▼
   ┌──────────────────────────┐
   │ 1. Enable SSH             │
   │ 2. Inject buddy key       │
   │ 3. Start Quick Tunnel     │  ← temporary, no CF account needed
   │ 4. Print SSH command      │
   └────────────┬─────────────┘
                │
                │ send tunnel address + user to buddy
                ▼
   ┌──────────────────────────┐
   │ Buddy Agent               │
   │ SSH → new device          │
   │ Install Node + OpenClaw   │
   │ Configure everything      │
   │ Start Gateway             │
   │ Verify A2A                │
   └──────────────────────────┘
```

## For Buddy Agents

When you receive a tunnel address and username:

```bash
# 1. Start local proxy (background)
cloudflared access tcp --hostname <tunnel-host>.trycloudflare.com --url localhost:2222 &

# 2. SSH in
ssh -p 2222 <username>@localhost
```

## Security

- The buddy agent's public key is embedded in the script
- All traffic goes through Cloudflare Tunnel (encrypted, no open ports)
- SSH key-based auth only (no passwords)
- Quick Tunnel URLs are temporary — they die when the process stops
- The bootstrap script requires `sudo` for enabling SSH / installing packages

## Customization

To use a different buddy agent key, fork the repo and replace the `BUDDY_KEY` variable at the top of each script.
