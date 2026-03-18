# openclaw-setup

A unified, interactive setup script for [OpenClaw](https://openclaw.ai) — the open-source personal AI assistant. One script handles native macOS + Docker deployments, 26 feature toggles, 7 model providers, unified Obsidian brain, Claude knowledge sync, and multi-Mac GitHub backup.

Built for **Apple Silicon** (M4/M3/M2/M1) but works on any macOS or Linux system.

## Quick Start

```bash
git clone https://github.com/ckithika/openclaw-setup.git
cd openclaw-setup
./setup.sh
```

## Usage

```bash
./setup.sh                 # Fresh interactive setup
./setup.sh --reconfigure   # Modify an existing instance
./setup.sh --version       # Show version (v3.0.0)
./setup.sh --help          # Show help
```

## What This Does

The setup wizard walks you through 13 phases:

```
 1.  Pre-flight checks         Hardware, Ollama, Docker, Node.js, disk
 2.  Deployment mode           Native macOS or Docker container
 3.  Instance config           Name, directories, ports
 4.  Feature toggles           26 toggleable capabilities
 5.  Channels                  WhatsApp, Telegram, Discord, Slack, Signal, iMessage
 6.  Model provider            7 providers with credential prompting
 7.  Google Workspace          Gmail, Calendar, Drive via gog/MCP/OAuth
 8.  Obsidian vault            Unified brain — single source of truth
 9.  Tag taxonomy              Auto-tagging with life areas and projects
10.  Claude knowledge sync     Web + Code session export, retention fix
11.  Skills                    6 categories, 13+ skills
12.  Memory config             Compaction fix, Mem0, Cognee
13.  GitHub backup             Private repo, auto-sync, multi-Mac
```

## Feature Toggles

### Core (26 toggles)

| Feature | Default | Description |
|---------|---------|-------------|
| Browser automation | ON | Chromium via CDP |
| Sandbox | ON | Docker-based tool isolation |
| Cron jobs | ON | Scheduled tasks |
| Persistent memory | ON | Cross-session memory |
| Skills marketplace | ON | ClawHub skills |
| Code execution | ON | Python/Node.js sandboxes |
| Web search | ON | Internet search |
| Web fetch | ON | Read web pages |
| File access | ON | Read/write filesystem |
| Shell execution | ON | System commands |
| Messaging | ON | Cross-session messaging |
| Voice/TTS | OFF | macOS native only |
| Claude Code (ACP) | OFF | Agent Client Protocol |
| Google Workspace | OFF | Gmail, Calendar, Drive |
| Obsidian vault | OFF | Unified brain |
| Claude sync | OFF | Export Claude conversations |
| Tag taxonomy | OFF | Auto-tagging system |
| GitHub backup | OFF | Private repo + multi-Mac sync |
| Mem0 | OFF | External vector memory |
| Cognee | OFF | Knowledge graph |
| Skills: Productivity | OFF | GitHub, Obsidian, Notion, Summarize |
| Skills: Social Media | OFF | Upload-Post, Genviral, Mixpost |
| Skills: Research | OFF | Tavily search |
| Skills: Security | OFF | SecureClaw |
| Skills: Communication | OFF | AgentMail, Slack |
| Granola | OFF | Meeting notes sync |

### Model Providers

| Provider | Models | Cost |
|----------|--------|------|
| **Ollama Cloud** | GLM-5, Kimi K2.5, DeepSeek V3.2 | Free |
| Ollama Local | Devstral, Nemotron, Qwen, DeepSeek | Free |
| Anthropic | Claude Sonnet/Opus/Haiku | Paid |
| OpenAI | GPT-5.4, GPT-5-mini, GPT-4o | Paid |
| OpenRouter | 100+ models, one API key | Paid |
| Google | Gemini 3.1 Pro, Flash | Free tier |
| Groq | Llama 4, DeepSeek R1, Qwen | Free tier |

### Channels

| Channel | Auth | Notes |
|---------|------|-------|
| WebChat | None | Always available |
| WhatsApp | QR code | Script guides pairing |
| Telegram | Bot token | Prompts from @BotFather |
| Discord | Bot token | Developer Portal |
| Slack | Bot + App tokens | Socket Mode |
| Signal | Device linking | Post-setup |
| iMessage | macOS native | Native mode only |

## Architecture

### Unified Brain

When Obsidian vault is enabled, all knowledge flows into one place:

```
INPUTS                              OBSIDIAN VAULT
──────                              ──────────────
Claude.ai (web/desktop/mobile) ──→  /claude-web/
Claude Code sessions ─────────────→ /claude-code/
Claude Code memory (symlink) ─────→ /claude-memory/
Granola meetings ─────────────────→ /meetings/
Gmail (via gog) ──────────────────→ /emails/
OpenClaw session memory ──────────→ /memory/
OpenClaw daily distills ──────────→ /daily/
Your notes ───────────────────────→ /projects/
                                         │
                                    Cognee Graph
                                    (relationships)
                                         │
                                    OpenClaw Recall
                                    (injects context)
```

### Personal + Work Agent Setup

```
Mac Mini (M4, 16GB)
├── Native: Personal OpenClaw
│   ├── Obsidian vault (unified brain)
│   ├── Ollama cloud model (GLM-5)
│   ├── Google Workspace (gog)
│   └── WebChat + WhatsApp + iMessage
│
├── Docker: Work Agent 1 (Brand A)
│   ├── Tailscale sidecar
│   ├── Isolated Chrome profile
│   ├── Social media skills
│   └── Daily backups
│
├── Docker: Work Agent 2 (Brand B)
│   ├── Tailscale sidecar
│   ├── Isolated Chrome profile
│   └── Discord + scheduling
│
├── Shared: Ollama (native, localhost:11434)
│
└── GitHub: Private brain repo
    └── Auto-sync every 10 min across all Macs
```

### Multi-Mac Sync

```
First Mac:   ./setup.sh → "Existing brain repo?" → No  → Creates + pushes
Second Mac:  ./setup.sh → "Existing brain repo?" → Yes → Clones + configures
```

### Generated Files

**With Obsidian vault enabled:**
```
~/obsidian-vault/                    # Single brain
├── _taxonomy.md                     # Tag reference
├── .gitignore                       # Git exclusions
├── AGENTS.md                        # OpenClaw instructions + tagging rules
├── claude-web/                      # Claude Vault sync
├── claude-code/                     # Claude Extractor
├── claude-memory/ → ~/.claude/...   # Symlink
├── meetings/                        # Granola
├── emails/                          # Gmail
├── memory/                          # OpenClaw memory
├── daily/                           # Session distills
└── projects/                        # Your notes

~/.openclaw/
├── openclaw.json                    # Config (workspace → vault)
├── credentials/                     # API keys (chmod 700)
└── vault-sync.sh                    # Git auto-sync script

~/Library/LaunchAgents/
└── com.openclaw.vault-sync.plist    # 10-min auto-sync
```

**Docker mode:**
```
~/openclaw-instances/work-agent-1/
├── config/openclaw.json
├── workspace/                       # Or vault mount
├── chrome-profile/
├── google-credentials/
├── backups/
├── docker-compose.yml
├── install-skills.sh                # Auto-generated
└── .env
```

## Memory Architecture

The script fixes OpenClaw's known memory compaction issue:

| Setting | Default | This Script | Effect |
|---------|---------|-------------|--------|
| `softThresholdTokens` | 4000 | **40000** | Agent has room to save before compaction |
| `distillToMemory` | false | **true** | Sessions auto-save to daily files |
| `sessionRetention` | 30 days | **unlimited** | Claude Code stops deleting logs |

Optional memory plugins:

| Plugin | What It Does | How |
|--------|-------------|-----|
| **Mem0** | Stores memories outside context window — survives compaction | Self-hosted or cloud vector DB |
| **Cognee** | Knowledge graph across all vault content — finds relationships | Graph traversal, auto-index |

## Security

- Input validation on all user inputs (rejects control chars, path traversal, shell injection)
- Credentials stored with `chmod 600`/`700` permissions
- API keys entered via hidden input (`read -s`)
- Docker containers: `cap_drop: ALL`, `no-new-privileges`, healthchecks
- Gateway bound to loopback by default
- Unique auth tokens auto-generated per instance
- Token format validation (Telegram, Discord)
- API key verification against provider endpoints
- Optional `git-crypt` for sensitive vault folders
- Claude Code session retention fix (prevents data loss)

## Prerequisites

| Requirement | Required For | Install |
|-------------|-------------|---------|
| macOS or Linux | All | - |
| Bash 3.2+ | All | Pre-installed |
| [Ollama](https://ollama.com) | Cloud/local models | `brew install ollama` |
| [Docker](https://www.docker.com) / [OrbStack](https://orbstack.dev) | Docker mode | `brew install --cask orbstack` |
| Node.js 18+ | Native mode | `brew install node` |
| jq | Config generation | Auto-installed |
| [Tailscale](https://tailscale.com) | Remote access | `brew install tailscale` |
| [GitHub CLI](https://cli.github.com) | GitHub backup | `brew install gh` |
| Python 3 | Claude sync tools | Pre-installed on macOS |

## Comparison

| Capability | **This Script** | Official docker-setup.sh | RareCloudio VPS | Coolabs Docker |
|---|---|---|---|---|
| Multi-instance | Yes | No | No | No |
| Native + Docker | Yes | Docker only | Native only | Docker only |
| Feature toggles | 26 interactive | Env vars | CLI flags | Env vars |
| Model providers | 7 with menus | Manual CLI | Manual CLI | Env vars |
| Channel credentials | Prompted + validated | Manual | Manual | Env vars |
| WhatsApp QR pairing | Guided | No | No | No |
| API key verification | Yes | No | No | No |
| Unified brain (Obsidian) | Yes | No | No | No |
| Claude knowledge sync | Yes | No | No | No |
| Tag taxonomy | Yes | No | No | No |
| Skills categories | 6 toggleable | No | No | No |
| Memory compaction fix | Yes | No | No | No |
| Mem0/Cognee plugins | Yes | No | No | No |
| GitHub backup | Yes | No | No | No |
| Multi-Mac sync | Yes | No | No | No |
| Backups | Docker daily | No | Daily | No |
| Health checks | Yes | No | No | No |
| Reconfigure mode | Yes | No | No | No |
| Tailscale integration | Per-instance | No | No | No |
| Input validation | Yes | Yes | Yes | Moderate |
| Security hardening | Docker-level | Docker-level | OS-level (8 layers) | Auth + ACLs |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/name`)
3. Run `bash -n setup.sh` (syntax check)
4. Test with a dry run
5. Submit a PR

## License

[MIT](LICENSE)
