# oc-bootstrap

One-line scripts to bootstrap a new device for OpenClaw onboarding.

## What it does

1. Enables SSH access on the target device
2. Injects the buddy agent's public key
3. Outputs connection info to send to your buddy agent

**That's it.** Everything else (Node.js, OpenClaw, config, A2A) is handled by the buddy agent after SSH is established.

## Usage

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-macos.sh | bash
```

### Linux (Ubuntu/Debian) — coming soon

```bash
curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-linux.sh | bash
```

### Windows (WSL) — coming soon

```powershell
irm https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-windows.ps1 | iex
```

## Flow

```
Human runs curl | bash on new device
         │
         ▼
   ┌──────────────┐
   │ Enable SSH    │
   │ Inject key    │
   │ Print info    │
   └──────┬───────┘
          │
          │ "ssh user@ip"
          ▼
   ┌──────────────────┐
   │ Buddy Agent      │ (e.g. KUMA 小墨)
   │ SSH → new device │
   │ Install Node     │
   │ Install OpenClaw │
   │ Configure all    │
   │ Start Gateway    │
   │ Verify A2A       │
   └──────────────────┘
```

## Security

- The buddy agent's public key is embedded in the script
- SSH only (no password auth needed)
- The bootstrap script requires `sudo` for enabling Remote Login on macOS
