# openclaw-setup

A unified, interactive setup script for [OpenClaw](https://openclaw.ai) — the open-source personal AI assistant. One script handles native macOS + Docker deployments, feature toggles, model providers, unified Obsidian brain, Claude knowledge sync, and GitHub backup.

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

---

## Complete Setup Guide

### Option A: Native macOS Setup

Native mode runs OpenClaw directly on your Mac with full system access (iMessage, GPU, filesystem, Voice/TTS).

#### Prerequisites

| Requirement | Install |
|-------------|---------|
| macOS (Apple Silicon recommended) | - |
| [Ollama](https://ollama.com) | `brew install ollama` |
| Node.js 18+ | `brew install node` |
| [Docker](https://www.docker.com) / [OrbStack](https://orbstack.dev) | `brew install --cask orbstack` (for sandbox feature) |
| [GitHub CLI](https://cli.github.com) | `brew install gh` (optional, for GitHub backup) |
| Python 3 | Pre-installed on macOS (for Claude sync tools) |

`jq` is auto-installed via Homebrew if missing.

#### Steps

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

2. **Select native mode** when prompted (option 1).

3. **Name your instance** (e.g., `personal`) — config goes to `~/.openclaw/`.

4. **Toggle features** — all 26 features are available in native mode including:
   - Voice/TTS (macOS native `say` command)
   - iMessage channel
   - Sandbox (Docker-based tool isolation)
   - Claude Sync (session retention fix + symlinks)

5. **Configure channels** — enter bot tokens when prompted:
   - WhatsApp (QR code pairing guided)
   - Telegram (from @BotFather)
   - Discord, Slack, Signal
   - iMessage (native only)

6. **Select model provider** — 7 options with credential prompting.

7. **Optional: Obsidian vault** — creates unified brain folder structure.

8. **Optional: GitHub backup** — creates private repo + launchd auto-sync every 10 min.

9. **Start OpenClaw:**
   ```bash
   openclaw start
   ```

#### Generated Files (Native)

```
~/.openclaw/
├── openclaw.json              # Main config
├── credentials/               # API keys (chmod 700)
├── workspace/
│   ├── SOUL.md                # Agent persona
│   ├── IDENTITY.md            # Agent identity
│   ├── USER.md                # User info
│   ├── AGENTS.md              # Agent behavior rules
│   └── TOOLS.md               # Environment-specific notes
└── vault-sync.sh              # Git auto-sync (if backup enabled)

~/Library/LaunchAgents/
└── com.openclaw.vault-sync.plist  # 10-min auto-sync (if backup enabled)
```

---

### Option B: Docker Setup

Docker mode runs OpenClaw in an isolated container. Best for work agents, multi-account setups, or autonomous agents.

#### Prerequisites

| Requirement | Install |
|-------------|---------|
| macOS or Linux | - |
| [Docker](https://www.docker.com) / [OrbStack](https://orbstack.dev) | `brew install --cask orbstack` |
| [Ollama](https://ollama.com) | `brew install ollama` (runs on host, accessed by container) |

`jq` is auto-installed if missing (via Homebrew on macOS, apt on Linux).

#### Steps

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

2. **Select Docker mode** (option 2).

3. **Name your instance** (e.g., `seekrjobs`, `work-brand-a`).

4. **Set base directory** (default: `~/openclaw-instances`).

5. **Set gateway port** (random port suggested, or choose your own).

6. **Toggle features** — Docker-specific behavior:
   - **Sandbox**: auto-enabled, not shown (container is already sandboxed)
   - **Voice/TTS**: not shown (not available in containers)
   - **Claude Sync**: not shown (can't access host Claude settings)
   - **Browser**: runs headless with `noSandbox: true` automatically; Chromium is auto-installed via a generated Dockerfile
   - All other features work normally

7. **Select CLI tools** — the script generates a custom Dockerfile with your selections:
   - `gh` (GitHub CLI) — repo management, PRs, issues
   - `doctl` (DigitalOcean CLI) — infrastructure management
   - `supabase` — database management
   - `gog` (Google Workspace CLI) — auto-selected if Google Workspace enabled
   - `xurl` (Twitter/X CLI) — social media posting
   - Config directories are pre-created to avoid permission errors

8. **Configure channels** — same as native (tokens prompted).

9. **Network mode** — you'll be asked:
   - **Host networking** (recommended for OrbStack on macOS): `network_mode: host` — avoids known Node.js networking issues with OrbStack's bridged network
   - **Bridged networking** (default): standard Docker networking with port mapping, DNS set to `8.8.8.8` and `1.1.1.1`

10. **Optional: Telegram watchdog** — if Telegram is enabled, a sidecar monitors for connectivity loss and auto-restarts the container (recommended for OrbStack).

11. **Optional: Tailscale sidecar** — adds VPN for remote access (skipped if using host networking).

12. **Optional: Daily backups** — Alpine sidecar container, 7-day retention.

13. **Optional: GitHub backup auto-sync** — uses OpenClaw's built-in cron (every 10 min) instead of macOS launchd.

12. **Set your environment variables** in the generated `.env` file:
    ```bash
    nano ~/openclaw-instances/<name>/.env
    ```
    Add `TS_AUTHKEY` if using Tailscale.

13. **Start the instance:**
    ```bash
    cd ~/openclaw-instances/<name>
    docker compose up -d
    ```

14. **Check logs:**
    ```bash
    docker compose logs -f openclaw-<name>
    ```

15. **Install skills** (if any were selected):
    ```bash
    docker exec openclaw-<name> bash /home/node/openclaw/workspace/install-skills.sh
    ```

16. **Pair channels** (e.g., WhatsApp):
    ```bash
    docker compose exec openclaw-<name> openclaw channels login whatsapp
    ```

#### Generated Files (Docker)

```
~/openclaw-instances/<name>/
├── docker-compose.yml         # Docker Compose config (with sidecars)
├── Dockerfile                 # Custom image (if browser or CLIs selected)
├── .env                       # Environment variables (Tailscale, GOG passphrase, etc.)
├── gitconfig                  # Copied from host (safe mount, not a directory)
├── config/
│   ├── openclaw.json          # Main config
│   ├── credentials/           # API keys (chmod 700)
│   └── workspace/
│       ├── SOUL.md            # Agent persona
│       ├── IDENTITY.md        # Agent identity
│       ├── USER.md            # User info
│       ├── AGENTS.md          # Agent behavior rules
│       └── TOOLS.md           # Environment-specific notes
├── workspace/                 # Agent workspace (mounted volume)
├── chrome-profile/            # Persistent browser sessions (if browser enabled)
├── google-credentials/        # Google OAuth tokens (if Google Workspace enabled)
├── backups/                   # Daily backups (if enabled)
└── install-skills.sh          # Auto-generated skill installer
```

#### Docker Networking Notes

**OrbStack on macOS**: Node.js inside containers may fail to reach external APIs (e.g., Telegram) when using bridged networking. This is a known OrbStack issue where `curl` works but Node.js `fetch` times out. **Use host networking** (`network_mode: host`) to avoid this.

When using host networking:
- Ports are not mapped — the gateway listens directly on the host at the configured port
- `OLLAMA_HOST` is automatically set to `http://localhost:11434` (not `host.docker.internal`)
- Tailscale sidecar is not needed (use host Tailscale instead)
- `cap_drop: ALL` is not applied (unnecessary with host networking)

#### Extending the Docker Image

The setup script **automatically generates a Dockerfile** when you select browser automation or CLI tools. The generated `docker-compose.yml` uses `build: .` to build from it. To add tools later, edit the generated `Dockerfile` in your instance directory and run `docker compose build`.

#### Mounting Source Code Repos

To give the agent access to a local codebase:

```yaml
volumes:
  # ... existing volumes
  - /path/to/your/repo:/home/node/openclaw/workspace/repo-name
  - ~/.ssh:/home/node/.ssh:ro           # SSH keys for git push
  - ~/.gitconfig:/home/node/.gitconfig:ro  # Git config
```

---

## Docker vs Native: Feature Comparison

| Feature | Native | Docker | Notes |
|---------|:------:|:------:|-------|
| Browser automation | Yes | Yes (headless) | Docker auto-sets `headless: true`, `noSandbox: true` |
| Sandbox | Yes | Auto-enabled | Container is already sandboxed |
| Voice/TTS | Yes | No | macOS `say` command not available |
| iMessage | Yes | No | Requires macOS Messages.app |
| Claude Sync | Yes | No | Can't access host Claude settings/sessions |
| GitHub backup (git) | Yes | Yes | Git operations work in both modes |
| GitHub backup (auto-sync) | launchd | Container cron | Docker uses OpenClaw cron instead of macOS launchd |
| Google Workspace OAuth | Browser flow | Manual/headless | Docker needs `--manual` OAuth flag |
| apple-notes skill | Yes | No | macOS native only |
| All other features | Yes | Yes | Full support |

## What This Does

The setup wizard walks you through 13 phases:

```
 1.  Pre-flight checks         Hardware, Ollama, Docker, Node.js, disk
 2.  Deployment mode           Native macOS or Docker container
 3.  Instance config           Name, directories, ports
 4.  Feature toggles           Context-aware (Docker hides N/A options)
 5.  Channels                  WhatsApp, Telegram, Discord, Slack, Signal, iMessage
 6.  Model provider            7 providers with credential prompting
 7.  Google Workspace          Gmail, Calendar, Drive via gog/MCP/OAuth
 8.  Obsidian vault            Unified brain — single source of truth
 9.  Tag taxonomy              Auto-tagging with life areas and projects
10.  Claude knowledge sync     Web + Code session export, retention fix (native only)
11.  Skills                    6 categories, 13+ skills
12.  Memory config             Mem0, Cognee plugins
13.  GitHub backup             Private repo, auto-sync (launchd or container cron)
```

## Feature Toggles

| Feature | Default | Description |
|---------|---------|-------------|
| Browser automation | ON | Chromium via CDP |
| Sandbox | ON | Docker-based tool isolation (auto-enabled in Docker mode) |
| Cron jobs | ON | Scheduled tasks |
| Persistent memory | ON | Cross-session memory |
| Skills marketplace | ON | ClawHub skills |
| Code execution | ON | Python/Node.js sandboxes |
| Web search | ON | Internet search |
| Web fetch | ON | Read web pages |
| File access | ON | Read/write filesystem |
| Shell execution | ON | System commands |
| Messaging | ON | Cross-session messaging |
| Voice/TTS | OFF | macOS native only (hidden in Docker) |
| Claude Code (ACP) | OFF | Agent Client Protocol |
| Google Workspace | OFF | Gmail, Calendar, Drive |
| Obsidian vault | OFF | Unified brain |
| Claude sync | OFF | Export Claude conversations (native only) |
| Tag taxonomy | OFF | Auto-tagging system |
| GitHub backup | OFF | Private repo + auto-sync |
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

| Channel | Auth | Native | Docker |
|---------|------|:------:|:------:|
| WebChat | None | Yes | Yes |
| WhatsApp | QR code | Yes | Yes (via `docker compose exec`) |
| Telegram | Bot token | Yes | Yes |
| Discord | Bot token | Yes | Yes |
| Slack | Bot + App tokens | Yes | Yes |
| Signal | Device linking | Yes | Yes (via `docker compose exec`) |
| iMessage | macOS native | Yes | No |

## Architecture

### Unified Brain

When Obsidian vault is enabled, all knowledge flows into one place:

```
INPUTS                              OBSIDIAN VAULT
──────                              ──────────────
Claude.ai (web/desktop/mobile) ──→  /claude-web/
Claude Code sessions ─────────────→ /claude-code/
Claude Code memory (symlink) ─────→ /claude-memory/     (native only)
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

### Multi-Instance Setup

```
Mac (Apple Silicon)
├── Native: Personal OpenClaw
│   ├── Obsidian vault (unified brain)
│   ├── Claude Sync (session retention fix)
│   ├── Google Workspace (gog)
│   └── WebChat + WhatsApp + iMessage
│
├── Docker: Work Agent 1 (Brand A)
│   ├── Host networking (OrbStack)
│   ├── Isolated Chrome profile
│   ├── Source code repo mounted
│   ├── Social media skills
│   └── Daily backups
│
├── Docker: Work Agent 2 (Brand B)
│   ├── Host networking (OrbStack)
│   ├── Isolated Chrome profile
│   └── Discord + scheduling
│
├── Shared: Ollama (native, localhost:11434)
│
└── GitHub: Private brain repo
    └── Auto-sync every 10 min (launchd native, cron Docker)
```

### Multi-Mac Sync

```
First Mac:   ./setup.sh → "Existing brain repo?" → No  → Creates + pushes
Second Mac:  ./setup.sh → "Existing brain repo?" → Yes → Clones + configures
```

## Security

- Input validation on all user inputs (rejects control chars, path traversal, shell injection)
- Credentials stored with `chmod 600`/`700` permissions
- API keys entered via hidden input (`read -s`)
- Docker containers (bridged mode): `cap_drop: ALL`, `no-new-privileges`, healthchecks, explicit DNS
- Docker containers (host mode): `no-new-privileges`, healthchecks
- Gateway bound to loopback by default
- Unique auth tokens auto-generated per instance
- Token format validation (Telegram, Discord)
- API key verification against provider endpoints
- Optional `git-crypt` for sensitive vault folders
- Claude Code session retention fix (prevents data loss, native only)

## Testing

```bash
# Syntax check
bash -n setup.sh

# Run bats test suite (35 tests)
npx bats test/setup.bats

# Docker smoke tests
docker build -f Dockerfile.test -t openclaw-setup-test .
docker run --rm openclaw-setup-test /test/run.sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/name`)
3. Run `bash -n setup.sh` (syntax check)
4. Run `npx bats test/setup.bats` (test suite)
5. Submit a PR

## License

[MIT](LICENSE)
