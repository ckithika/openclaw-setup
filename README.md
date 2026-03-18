# openclaw-setup

A unified, interactive setup script for [OpenClaw](https://openclaw.ai) — the open-source personal AI assistant. Supports both **native macOS** and **Docker** deployments from a single script, with full feature toggles, credential management, and multi-instance support.

Built for the **Apple Silicon Mac Mini** (M4/M3/M2/M1) but works on any macOS or Linux system.

## Why This Exists

Setting up OpenClaw involves configuring models, channels, security, sandboxing, browser automation, and more. Existing scripts either focus on a single deployment mode, lack feature granularity, or skip credential setup entirely.

This script gives you:

- **One script, two modes** — Native or Docker, same wizard
- **Multi-instance support** — Run a personal assistant natively + isolated work agents in Docker
- **13 toggleable features** — Browser, sandbox, cron, memory, skills, code execution, and more
- **Real credential setup** — Prompts for actual API keys and bot tokens during install
- **Channel pairing** — Guides you through WhatsApp QR scanning and Signal device linking
- **Post-setup health checks** — Validates config, credentials, and connectivity
- **Reconfigure mode** — Modify an existing instance without starting from scratch
- **Tailscale integration** — Per-instance remote access via sidecar containers
- **Daily backups** — Optional automated backup with 7-day retention (Docker mode)

## Quick Start

```bash
git clone https://github.com/ckithika/openclaw-setup.git
cd openclaw-setup
chmod +x setup.sh
./setup.sh
```

## Usage

```bash
# Fresh setup (interactive wizard)
./setup.sh

# Reconfigure an existing instance
./setup.sh --reconfigure

# Show version
./setup.sh --version

# Help
./setup.sh --help
```

## What It Configures

### Deployment Modes

| Mode | Best For |
|------|----------|
| **native** | Personal assistant on macOS with full system access (iMessage, GPU, filesystem) |
| **docker** | Work agents, multi-account isolation, sandboxed environments |

### Feature Toggles

| Feature | Default | Description |
|---------|---------|-------------|
| Browser automation | ON | Chromium via CDP for web interaction |
| Sandbox | ON | Docker-based tool isolation |
| Cron jobs | ON | Scheduled tasks and automation |
| Persistent memory | ON | Cross-session memory |
| Skills marketplace | ON | ClawHub skill installation |
| Code execution | ON | Python and Node.js sandboxes |
| Web search | ON | Internet search capability |
| Web fetch | ON | Read web pages |
| File access | ON | Read/write filesystem |
| Shell execution | ON | Run system commands |
| Messaging | ON | Cross-session agent messaging |
| Voice/TTS | OFF | macOS native only |
| Claude Code | OFF | ACP integration |

### Channels

| Channel | Auth Method | Notes |
|---------|-------------|-------|
| WebChat | None | Always available via browser |
| WhatsApp | QR code scan | Script guides pairing post-setup |
| Telegram | Bot token | Prompts for token from @BotFather |
| Discord | Bot token | Prompts for token from Developer Portal |
| Slack | Bot + App tokens | Prompts for both xoxb and xapp tokens |
| Signal | Device linking | Script triggers linking post-setup |
| iMessage | macOS native | Native mode only |

### Models

| Provider | Models | Cost |
|----------|--------|------|
| **Ollama Cloud** (recommended) | GLM-5, Kimi K2.5, DeepSeek V3.2 | Free |
| Ollama Local | Any model that fits in RAM | Free |
| Anthropic | Claude Sonnet/Opus | Paid |
| OpenAI | GPT-5.x | Paid |

## Architecture

### Personal + Work Agent Setup

```
Mac Mini (M4, 16GB)
├── Native: Personal OpenClaw
│   ├── Full macOS access (iMessage, GPU, filesystem)
│   ├── Ollama cloud model (GLM-5)
│   └── WebChat + WhatsApp + iMessage
│
├── Docker: Work Agent 1 (Brand A)
│   ├── Tailscale sidecar (openclaw-brand-a.ts.net)
│   ├── Isolated Chrome profile (Google Account A)
│   ├── Telegram + social media skills
│   └── Daily backups
│
├── Docker: Work Agent 2 (Brand B)
│   ├── Tailscale sidecar (openclaw-brand-b.ts.net)
│   ├── Isolated Chrome profile (Google Account B)
│   └── Discord + scheduling
│
└── Shared: Ollama (native, localhost:11434)
    └── All instances connect to the same Ollama
```

### Generated Files

**Native mode:**
```
~/.openclaw/
├── openclaw.json          # Main config
├── credentials/           # API keys (chmod 700)
│   ├── anthropic.json
│   └── openai.json
└── workspace/
    └── AGENTS.md
```

**Docker mode:**
```
~/openclaw-instances/work-agent-1/
├── config/
│   ├── openclaw.json
│   └── credentials/
├── workspace/
├── chrome-profile/        # Persistent Chrome data
├── backups/               # Daily backups (if enabled)
├── docker-compose.yml
└── .env                   # Tailscale key, channel tokens
```

## Security

- Input validation on all user inputs (rejects control chars, path traversal, shell metacharacters)
- Credentials stored with `chmod 600`/`700` permissions
- API keys entered via hidden input (not echoed to terminal)
- Docker containers run with `cap_drop: ALL`, `no-new-privileges`
- Gateway bound to loopback by default
- Unique auth tokens auto-generated per instance
- Token format validation for Telegram and Discord
- API key verification against provider endpoints

## Prerequisites

| Requirement | Required For | Install |
|-------------|-------------|---------|
| macOS or Linux | All | - |
| Bash 3.2+ | All | Pre-installed |
| [Ollama](https://ollama.com) | Cloud/local models | `brew install ollama` |
| [Docker](https://www.docker.com) / [OrbStack](https://orbstack.dev) | Docker mode + sandboxing | `brew install --cask orbstack` |
| Node.js 18+ | Native mode | `brew install node` |
| jq | Config generation | Auto-installed by script |
| [Tailscale](https://tailscale.com) | Remote access (optional) | `brew install tailscale` |

## Comparison with Other Setup Scripts

| Capability | **This Script** | Official docker-setup.sh | RareCloudio VPS | Coolabs Docker |
|---|---|---|---|---|
| Multi-instance | Yes | No | No | No |
| Native + Docker | Yes | Docker only | Native only | Docker only |
| Feature toggles | 13 interactive | Env vars | CLI flags | Env vars |
| Channel credentials | Prompted + validated | Manual post-setup | Manual post-setup | Env vars |
| WhatsApp QR pairing | Guided | No | No | No |
| API key verification | Yes | No | No | No |
| Input validation | Yes | Yes | Yes | Moderate |
| Security hardening | Docker-level | Docker-level | OS-level (8 layers) | Auth + ACLs |
| Backups | Optional daily | No | Yes (daily) | No |
| Health checks | Yes | No | No | No |
| Reconfigure mode | Yes | No | No | No |
| Tailscale integration | Per-instance sidecar | No | No | No |

## Contributing

Contributions are welcome. Please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes (`bash -n setup.sh` for syntax, then a dry run)
4. Commit your changes
5. Push to the branch
6. Open a Pull Request

## License

[MIT](LICENSE)
