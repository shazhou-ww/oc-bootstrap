# oc-bootstrap

One-line scripts to bootstrap a new device for OpenClaw onboarding.

## What it does

1. Enables SSH access on the target device
2. Injects the buddy agent's public key
3. Sets up a Cloudflare Tunnel (interactive — you choose the tunnel name and hostname)
4. Outputs the SSH command to send to your buddy agent

**That's it.** Everything else (Node.js, OpenClaw, config, A2A) is handled by the buddy agent after SSH is established.

## Usage

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/shazhou-ww/oc-bootstrap/main/bootstrap-macos.sh | bash
```

The script will interactively ask you for:
- **Tunnel name** — any name you like (e.g. `mypc`, `studio`, `homelab`)
- **SSH hostname** — a subdomain on your Cloudflare domain (e.g. `mypc-ssh.example.com`)

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
   ┌──────────────────────────┐
   │ 1. Enable SSH             │
   │ 2. Inject buddy key       │
   │ 3. Setup CF Tunnel        │  ← interactive: name + hostname
   │ 4. Print SSH command      │
   └────────────┬─────────────┘
                │
                │ send SSH command to buddy
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

## Security

- The buddy agent's public key is embedded in the script
- All traffic goes through Cloudflare Tunnel (encrypted, no open ports)
- SSH key-based auth only (no passwords)
- The bootstrap script requires `sudo` for enabling Remote Login on macOS

## Customization

To use a different buddy agent key, fork the repo and replace the `BUDDY_KEY` variable at the top of the script.
