# openclaw-setup

A unified, interactive setup script for [OpenClaw](https://openclaw.ai) — the open-source personal AI assistant. One script handles native macOS + Docker deployments, with presets for personal assistants, developers, and autonomous agents.

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
./agent-monitor.sh         # Monitor all running agents (CPU, RAM, status)
./agent-monitor.sh --watch # Live dashboard, refreshes every 30s
./agent-security-audit.sh  # Run security audit on all agents
```

---

## Presets

The setup starts by asking you to choose a preset. Each preset configures features, workspace files, autonomy level, and defaults tailored to your use case.

| Preset | Best for | What's enabled |
|--------|----------|----------------|
| **personal-assistant** | Non-technical users who want a smart daily assistant | Messaging, email, calendar, web search, memory. No coding tools, shell access, or CLI prompts. |
| **developer** | Software engineers and technical users | Full coding environment: shell, file access, sandbox, Claude Code, GitHub backup. |
| **autonomous-agent** | Autonomous SaaS agents that run a product | Everything: code, social media, email, browser, cron jobs, all skills, approval gates. |
| **custom** | Power users who want full control | Start from defaults and toggle each feature manually. |

After selecting a preset, you can optionally customize individual features.

---

## Interactive UI

The setup wizard uses a modern terminal UI:

- **Single-select lists** (deployment mode, model provider, presets, autonomy level): navigate with **arrow keys**, confirm with **Enter**
- **Multi-select checkboxes** (features, channels): navigate with **arrow keys**, toggle with **Space**, confirm with **Enter**
- All interactive widgets fall back to numbered/y/N input when running non-interactively (piped input, CI)

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

1. **Run the setup script** and select **native mode**.
2. **Name your instance** (e.g., `personal`) — config goes to `~/.openclaw/`.
3. **Choose a preset** — optionally customize features with the checkbox UI.
4. **Select channels** — multi-select checkbox (WhatsApp, Telegram, Discord, Slack, Signal, iMessage). Credential prompts for selected channels only. Voice note transcription offered if any audio-capable channel selected.
5. **Select model provider** — 7 options with credential prompting.
6. **Configure persona** — agent name, personality, emoji, backstory, your name/timezone/role, autonomy level, communication style. All flow into workspace files.
7. **Optional: Google Workspace, Obsidian vault, GitHub backup.**
8. **Start OpenClaw:** `openclaw gateway --force`

#### Generated Files (Native)

```
~/.openclaw/
├── openclaw.json              # Main config
├── credentials/               # API keys (chmod 700)
├── workspace/
│   ├── SOUL.md                # Mission, personality, autonomy gates
│   ├── IDENTITY.md            # Name, type, vibe, emoji, backstory
│   ├── USER.md                # Your name, timezone, role
│   ├── AGENTS.md              # Operating rules, voice transcription
│   ├── TOOLS.md               # Available CLIs, voice note instructions
│   └── HEARTBEAT.md           # Periodic checks (preset-specific)
└── vault-sync.sh              # Git auto-sync (if backup enabled)
```

---

### Option B: Docker Setup

Docker mode runs OpenClaw in an isolated container. Best for work agents, multi-account setups, or autonomous agents. Containers use `agent-<name>` naming.

#### Prerequisites

| Requirement | Install |
|-------------|---------|
| macOS or Linux | - |
| [Docker](https://www.docker.com) / [OrbStack](https://orbstack.dev) | `brew install --cask orbstack` |
| [Ollama](https://ollama.com) | `brew install ollama` (runs on host, shared by all agents) |

#### Steps

1. **Run the setup script** and select **Docker mode**.
2. **Name your instance** (e.g., `seekrjobs`, `tailhq`) — container named `agent-<name>`.
3. **Set base directory** (default: `~/openclaw-instances`).
4. **Choose a preset** — Docker hides irrelevant options (sandbox auto-enabled, voice/Claude sync hidden).
5. **Select CLI tools** (skipped for personal-assistant): gh, doctl, supabase, gog, xurl. Generates custom Dockerfile.
6. **Select channels** — multi-select. WhatsApp prompts for your phone number (restricted to self-chat via allowlist). Voice note transcription offered with local (whisper-cpp, free) or cloud (OpenAI API) options.
7. **Configure persona** — full identity setup with autonomy level:
   - **supervised**: ask before most actions
   - **semi-autonomous**: act freely on internal, ask for external
   - **autonomous**: act freely on everything, only ask for irreversible/financial
8. **Network mode**: host (recommended for OrbStack) or bridged.
9. **Optional sidecars**: Telegram watchdog, Tailscale, daily backups.
10. **Optional: Obsidian vault** — use existing shared vault (preserves files, appends tag) or create new.
11. **Optional: GitHub backup** — auto-detects existing `.git`, skips redundant setup.
12. **Start:** `cd ~/openclaw-instances/<name> && docker compose up -d`

#### Post-Setup

```bash
# Check logs
docker compose logs -f agent-<name>

# Pair WhatsApp
docker compose exec agent-<name> openclaw channels login --channel whatsapp

# Auth CLIs
docker exec -it agent-<name> gh auth login
docker exec -it agent-<name> doctl auth init
docker exec -it agent-<name> supabase login
```

#### Google Workspace Setup (gog CLI)

1. Create a project in [Google Cloud Console](https://console.cloud.google.com)
2. Enable APIs: Gmail, Calendar, Drive, Sheets, Docs, People
3. Create OAuth consent screen:
   - **Google Workspace** (`you@company.com`): select **Internal**
   - **Personal Gmail** (`you@gmail.com`): select **External**, add your email under **Test users**
4. Create OAuth client ID (Desktop app), download JSON
5. Auth:
   ```bash
   cp ~/Downloads/client_secret_*.json ~/openclaw-instances/<name>/google-credentials/credentials.json
   docker exec -it agent-<name> gog auth credentials /home/node/.config/gogcli/credentials.json
   docker exec -it agent-<name> gog auth add you@example.com --services gmail,calendar,drive,contacts,docs,sheets --manual
   ```
6. Open the URL, authorize, copy the redirect URL, paste back
7. Add keyring passphrase to `.env`: `echo 'GOG_PASSPHRASE=xxx' >> .env`

#### Generated Files (Docker)

```
~/openclaw-instances/<name>/
├── docker-compose.yml         # Docker Compose (with sidecars)
├── Dockerfile                 # Custom image (browser, CLIs, whisper-cpp)
├── .env                       # Environment variables
├── gitconfig                  # Safe copy from host
├── config/
│   ├── openclaw.json          # Main config
│   ├── credentials/           # API keys (chmod 700)
│   ├── cron/jobs.json         # Scheduled tasks
│   └── workspace/
│       ├── SOUL.md            # Mission, personality, autonomy gates
│       ├── IDENTITY.md        # Name, type, vibe, emoji, backstory, autonomy
│       ├── USER.md            # Your name, timezone, role
│       ├── AGENTS.md          # Operating rules
│       ├── TOOLS.md           # CLIs, voice transcription instructions
│       └── HEARTBEAT.md       # Periodic checks
├── workspace/                 # Agent workspace (mounted)
├── chrome-profile/            # Persistent browser sessions
├── google-credentials/        # Google OAuth tokens
└── backups/                   # Daily backups
```

#### Docker Networking Notes

**OrbStack on macOS**: Node.js inside containers may fail to reach external APIs (e.g., Telegram) when using bridged networking. **Use host networking** (`network_mode: host`) to avoid this.

When using host networking:
- Gateway listens directly on the host at the configured port
- `OLLAMA_HOST` automatically set to `http://localhost:11434`
- Tailscale sidecar not needed
- Healthcheck port matches the configured gateway port

#### Shared Vaults

Multiple agents can share a single Obsidian vault:
- Answer "Do you have an existing Obsidian vault?" with **Yes**
- Workspace files (SOUL.md, IDENTITY.md, etc.) are **not overwritten** — each agent keeps its own
- Taxonomy: existing `_taxonomy.md` preserved, new `#project/<agent-name>` tag appended
- GitHub backup: existing `.git` auto-detected, just pulls latest

---

## Persona Setup

The persona step collects detailed identity and behavior configuration:

| Section | Questions |
|---------|-----------|
| **Identity** | Agent name, personality/vibe, signature emoji, one-line backstory |
| **About You** | Your name, timezone, role/title, additional notes |
| **Mission** | What the agent should do (preset-specific default) |
| **Communication** | Response length (concise/balanced/detailed), tone (professional/friendly/direct) |
| **Autonomy Level** | supervised / semi-autonomous / autonomous |
| **Preset-specific** | Product name/URL/description (autonomous), languages/repo (developer) |

### Autonomy Levels

| Level | GREEN (do freely) | YELLOW (ask first) | RED (never) |
|-------|-------------------|-------------------|-------------|
| **supervised** | Read, research, draft | Send messages, commit code, modify config | Delete data, force-push, spend money |
| **semi-autonomous** | Read, research, draft, commit code, create branches, respond to chat | Publish posts, send emails, open PRs, merge to main | Delete data, force-push, spend money |
| **autonomous** | All of the above + publish posts, send routine emails, install deps | Merge to main, deploy, pricing changes | Delete data, force-push, spend money |

All settings flow into SOUL.md with clearly defined GREEN/YELLOW/RED gates.

---

## Voice Note Transcription

When a voice note arrives on WhatsApp, Telegram, or Discord, the agent automatically transcribes it before responding.

| Method | Cost | Speed | Setup |
|--------|------|-------|-------|
| **Local (whisper-cpp)** | Free | ~500ms on Apple Silicon | `brew install whisper-cpp ffmpeg` (native) or auto-installed in Docker |
| **Cloud (OpenAI Whisper API)** | $0.006/min | ~1-2s | Requires `OPENAI_API_KEY` |

The agent's TOOLS.md contains mandatory instructions to execute `ffmpeg` + `whisper-cli` whenever `<media:audio>` appears in a message.

---

## Operations & Monitoring

### Agent Monitor

```bash
./agent-monitor.sh          # One-shot status
./agent-monitor.sh --watch  # Live dashboard (30s refresh)
```

Shows all running agents with CPU, memory, status, color-coded by usage. Includes capacity estimates for adding more agents.

### Daily Automated Tasks

| Time | Job | Log |
|------|-----|-----|
| 4:00 AM | Browser restart (Chromium memory cleanup) | `/tmp/browser-restart.log` |
| 5:00 AM | Security audit (7-point check) | `/tmp/agent-security-audit.log` |

Install both crons:
```bash
crontab -e
0 4 * * * /path/to/browser-restart-cron.sh >> /tmp/browser-restart.log 2>&1
0 5 * * * /path/to/agent-security-audit.sh >> /tmp/agent-security-audit.log 2>&1
```

### Security Audit

The daily audit checks 7 areas across all running agents:

1. **Container health** — running, healthy, crash-looping
2. **Credential permissions** — .env chmod 600, credentials/ chmod 700
3. **Secret exposure** — no inline API keys, no hardcoded tokens
4. **Git safety** — no sensitive files in workspace/
5. **Network exposure** — gateway bound to loopback only
6. **Container security** — non-root user, no-new-privileges
7. **Suspicious activity** — force-push attempts, destructive commands, credential access

Run manually: `./agent-security-audit.sh`

### Capacity Planning (16GB Mac Mini)

| Agent Type | RAM per agent | Max agents |
|-----------|---------------|------------|
| No browser (idle) | ~400 MB | 8-10 |
| With browser (active) | ~2 GB | 3-4 |
| With browser (after daily restart) | ~400 MB | 8-10 |

All agents share one Ollama instance — models aren't duplicated. Containers run 24/7 with `restart: unless-stopped`. The 4 AM browser restart reclaims ~1.2GB per browser-enabled agent.

---

## Docker vs Native: Feature Comparison

| Feature | Native | Docker | Notes |
|---------|:------:|:------:|-------|
| Browser automation | Yes | Yes (headless) | Chromium auto-installed via Dockerfile |
| Voice transcription | Yes (whisper-cpp) | Yes (whisper-cpp in Docker) | Local, free, ~500ms |
| Sandbox | Yes | Auto-enabled | Container is already sandboxed |
| Voice/TTS | Yes | No | macOS `say` not available |
| iMessage | Yes | No | Requires Messages.app |
| Claude Sync | Yes | No | Can't access host sessions |
| GitHub backup | launchd | Container cron | Both auto-sync every 10 min |
| Google Workspace | Browser OAuth | Manual OAuth (`--manual`) | Both use gog CLI |
| CLI tools wizard | N/A | Yes | Generates custom Dockerfile |
| Telegram watchdog | N/A | Yes | Auto-restarts on connectivity loss |
| Agent name prefix | Yes | Yes | `[AgentName]` on all messages |
| Shared vault | Yes | Yes | Preserves existing files, appends tags |
| All other features | Yes | Yes | Full support |

## Architecture

### Multi-Instance Setup

```
Mac Mini (M4, 16GB)
├── Native: Samurai (Personal Assistant)
│   ├── Preset: personal-assistant, autonomy: semi-autonomous
│   ├── Obsidian vault (shared brain)
│   ├── WhatsApp (self-chat) + Telegram
│   └── Voice transcription (whisper-cpp)
│
├── Docker: agent-seekrjobs (Autonomous SaaS Agent)
│   ├── Preset: autonomous-agent, autonomy: semi-autonomous
│   ├── CLIs: gh, doctl, supabase, gog, xurl
│   ├── Source code repo mounted
│   ├── Telegram + watchdog sidecar
│   ├── Cron: daily report, content drafts, site health, email monitor
│   └── Browser (Chromium, restarted daily at 4 AM)
│
├── Docker: agent-tailhq (Developer Agent)
│   ├── Preset: developer, autonomy: supervised
│   ├── Telegram
│   └── Shared Obsidian vault
│
├── Docker: openclaw-rartisanal (Personal Assistant)
│   ├── Preset: personal-assistant
│   ├── WhatsApp (self-chat)
│   └── Google Workspace (gog)
│
├── Shared: Ollama (native, localhost:11434)
│   └── Models: glm-5:cloud, kimi-k2.5:cloud
│
├── Daily crons:
│   ├── 4 AM: browser-restart-cron.sh
│   └── 5 AM: agent-security-audit.sh
│
└── GitHub: Private brain repo
    └── Auto-sync every 10 min (launchd + container cron)
```

## Security

- Input validation on all user inputs (rejects control chars, path traversal, shell injection)
- Credentials stored with `chmod 600`/`700` permissions
- API keys entered via hidden input (`read -s`)
- WhatsApp restricted via allowlist (owner's phone number only)
- Docker containers: `no-new-privileges`, non-root user, healthchecks
- Gateway bound to loopback by default
- Unique auth tokens auto-generated per instance
- Safe `.gitconfig` handling (copied to instance dir, not bind-mounted)
- Daily automated security audit (7 checks)
- Agent name prefix on all messages (distinguishes agent from user in self-chat)
- Autonomy levels with explicit GREEN/YELLOW/RED approval gates

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
