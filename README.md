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
```

---

## Presets

The setup starts by asking you to choose a preset. Each preset configures features, workspace files, and defaults tailored to your use case.

| Preset | Best for | What's enabled |
|--------|----------|----------------|
| **personal-assistant** | Non-technical users who want a smart daily assistant | Messaging, email, calendar, web search, memory. No coding tools, shell access, or sandboxing. |
| **developer** | Software engineers and technical users | Full coding environment: shell, file access, sandbox, Claude Code, GitHub backup. |
| **autonomous-agent** | Autonomous SaaS agents that run a product | Everything: code, social media, email, browser, cron jobs, all skills, approval gates. |
| **custom** | Power users who want full control | Start from defaults and toggle each feature manually. |

After selecting a preset, you can optionally customize individual features.

---

## Interactive UI

The setup wizard uses a modern terminal UI:

- **Single-select lists** (deployment mode, model provider, presets): navigate with **arrow keys**, confirm with **Enter**
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

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

2. **Select native mode** when prompted.

3. **Name your instance** (e.g., `personal`) — config goes to `~/.openclaw/`.

4. **Choose a preset** — select personal-assistant, developer, autonomous-agent, or custom. Optionally customize individual features with the checkbox UI.

5. **Select channels** — use the multi-select checkbox to pick channels (WhatsApp, Telegram, Discord, Slack, Signal, iMessage). Credential prompts appear only for selected channels.

6. **Select model provider** — 7 options with credential prompting.

7. **Configure persona** — name your agent, set your name/timezone, define its purpose. Workspace files (SOUL.md, IDENTITY.md, USER.md, TOOLS.md, HEARTBEAT.md) are generated from preset-specific templates.

8. **Optional: Google Workspace / Gmail** — if enabled, the script will guide you through OAuth setup. You'll need a Google Cloud project with OAuth credentials (see the Docker setup section for detailed steps on creating OAuth credentials for both Workspace and personal Gmail accounts).

9. **Optional: Obsidian vault** — creates unified brain folder structure.

10. **Optional: GitHub backup** — creates private repo + launchd auto-sync every 10 min.

11. **Start OpenClaw:**
    ```bash
    openclaw start
    ```

#### Generated Files (Native)

```
~/.openclaw/
├── openclaw.json              # Main config
├── credentials/               # API keys (chmod 700)
├── workspace/
│   ├── SOUL.md                # Agent persona (preset-specific)
│   ├── IDENTITY.md            # Agent name, vibe, emoji
│   ├── USER.md                # Your name, timezone
│   ├── AGENTS.md              # Agent behavior rules
│   ├── TOOLS.md               # Available tools reference
│   └── HEARTBEAT.md           # Periodic check tasks (preset-specific)
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

2. **Select Docker mode.**

3. **Name your instance** (e.g., `seekrjobs`, `work-brand-a`).

4. **Set base directory** (default: `~/openclaw-instances`).

5. **Set gateway port** (random port suggested, or choose your own).

6. **Choose a preset** — Docker-specific behavior:
   - **Sandbox**: auto-enabled, not shown (container is already sandboxed)
   - **Voice/TTS**: not shown (not available in containers)
   - **Claude Sync**: not shown (can't access host Claude settings)
   - **Browser**: runs headless with `noSandbox: true`; Chromium auto-installed via generated Dockerfile
   - All other features work normally

7. **Select CLI tools** (skipped for personal-assistant preset):
   - `gh` (GitHub CLI) — repo management, PRs, issues
   - `doctl` (DigitalOcean CLI) — infrastructure management
   - `supabase` — database management
   - `gog` (Google Workspace CLI) — auto-selected if Google Workspace enabled
   - `xurl` (Twitter/X CLI) — social media posting
   - Config directories are pre-created to avoid permission errors
   - A custom Dockerfile is generated and `docker-compose.yml` uses `build: .`

8. **Select channels** — use the multi-select checkbox. Credential prompts for selected channels only. WhatsApp defaults to pairing mode (`dmPolicy: "pairing"`) — requires a pairing code before anyone can chat.

9. **Select model provider** — 7 options.

10. **Configure persona** — name your agent, set your name/timezone, define its purpose. Workspace files generated from preset-specific templates.

11. **Network mode:**
    - **Host networking** (recommended for OrbStack on macOS): `network_mode: host`
    - **Bridged networking** (default): port mapping, DNS set to `8.8.8.8` and `1.1.1.1`

12. **Optional: Telegram watchdog** — sidecar that monitors logs for connectivity failures and auto-restarts the container (recommended for OrbStack).

13. **Optional: Tailscale sidecar** — VPN for remote access (skipped if using host networking).

14. **Optional: Daily backups** — Alpine sidecar container, 7-day retention.

15. **Optional: GitHub backup auto-sync** — uses OpenClaw's built-in cron (every 10 min) instead of macOS launchd.

16. **Set your environment variables** in the generated `.env` file:
    ```bash
    nano ~/openclaw-instances/<name>/.env
    ```
    Add `TS_AUTHKEY` (Tailscale) and `GOG_PASSPHRASE` (Google Workspace) if needed.

17. **Start the instance:**
    ```bash
    cd ~/openclaw-instances/<name>
    docker compose up -d
    ```

18. **Check logs:**
    ```bash
    docker compose logs -f agent-<name>
    ```

19. **Pair channels** (e.g., WhatsApp):
    ```bash
    docker compose exec agent-<name> openclaw channels login --channel whatsapp
    ```

20. **Auth CLI tools** (if installed):
    ```bash
    docker exec -it agent-<name> gh auth login
    docker exec -it agent-<name> doctl auth init
    docker exec -it agent-<name> supabase login
    ```

21. **Set up Google Workspace / Gmail** (if gog CLI installed):

    First, create OAuth credentials in [Google Cloud Console](https://console.cloud.google.com):

    1. Create a new project (e.g., `my-openclaw-agent`)
    2. Go to **APIs & Services > Library** and enable:
       - Gmail API
       - Google Calendar API
       - Google Drive API
       - Google Sheets API
       - Google Docs API
       - People API
    3. Go to **APIs & Services > OAuth consent screen** and create:
       - **Google Workspace accounts** (`you@company.com`): select **Internal**
       - **Personal Gmail** (`you@gmail.com`): select **External**, then add your email under **Test users**
    4. Go to **APIs & Services > Credentials** > Create Credentials > **OAuth client ID**:
       - Application type: **Desktop app**
       - Download the JSON file
    5. Copy the credentials and authenticate:
       ```bash
       cp ~/Downloads/client_secret_*.json ~/openclaw-instances/<name>/google-credentials/credentials.json
       docker exec -it agent-<name> gog auth credentials /home/node/.config/gogcli/credentials.json
       docker exec -it agent-<name> gog auth add you@example.com --services gmail,calendar,drive,contacts,docs,sheets --manual
       ```
    6. Open the URL in your browser, sign in, authorize
    7. The browser will redirect to a page that won't load — copy the **full URL from the address bar** (contains `?code=...`) and paste it back into the terminal
    8. Set a keyring passphrase when prompted, then add it to `.env`:
       ```bash
       echo 'GOG_PASSPHRASE=your-passphrase' >> ~/openclaw-instances/<name>/.env
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
│       ├── SOUL.md            # Agent persona (preset-specific)
│       ├── IDENTITY.md        # Agent name, vibe, emoji
│       ├── USER.md            # Your name, timezone
│       ├── AGENTS.md          # Agent behavior rules
│       ├── TOOLS.md           # Available tools reference
│       └── HEARTBEAT.md       # Periodic check tasks (preset-specific)
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
- Healthcheck port matches the configured gateway port

#### Extending the Docker Image

The setup script **automatically generates a Dockerfile** when you select browser automation or CLI tools. The generated `docker-compose.yml` uses `build: .` to build from it. To add tools later, edit the generated `Dockerfile` in your instance directory and run `docker compose build`.

#### Mounting Source Code Repos

To give the agent access to a local codebase, add to docker-compose.yml:

```yaml
volumes:
  # ... existing volumes
  - /path/to/your/repo:/home/node/openclaw/workspace/repo-name
  - ~/.ssh:/home/node/.ssh:ro           # SSH keys for git push
```

---

## Persona Setup

After config generation, the script asks you to customize your agent's identity:

| Question | What it sets |
|----------|-------------|
| Agent name | IDENTITY.md name |
| Agent personality | IDENTITY.md vibe, SOUL.md tone |
| Your name | USER.md |
| Your timezone | USER.md |
| Agent purpose | SOUL.md mission statement |

Each preset generates different SOUL.md content:

| Preset | SOUL.md focus |
|--------|--------------|
| **personal-assistant** | Daily life: email, calendar, reminders, research. No code sections. |
| **developer** | Code review, debugging, project management, testing. |
| **autonomous-agent** | Growth, revenue, social media, approval gates, GEO+SEO strategy. |
| **custom** | Minimal template. |

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
| CLI tools wizard | N/A | Yes | Generates custom Dockerfile with selected tools |
| Telegram watchdog | N/A | Yes | Auto-restarts on OrbStack connectivity loss |
| All other features | Yes | Yes | Full support |

## What This Does

The setup wizard walks you through these phases:

```
 1.  Pre-flight checks         Hardware, Ollama, Docker, Node.js, disk
 2.  Deployment mode           Native macOS or Docker container
 3.  Instance config           Name, directories, ports
 4.  Feature preset            personal-assistant / developer / autonomous-agent / custom
 5.  Feature toggles           Interactive multi-select (Space to toggle, Enter to confirm)
 6.  Channels                  Multi-select + credential prompts for selected channels
 7.  Model provider            7 providers with credential prompting
 8.  Google Workspace          Gmail, Calendar, Drive via gog/MCP/OAuth
 9.  Obsidian vault            Unified brain — single source of truth
10.  Tag taxonomy              Auto-tagging with life areas and projects
11.  Claude knowledge sync     Session export, retention fix (native only)
12.  Skills                    6 categories, 13+ skills
13.  Memory config             Mem0, Cognee plugins
14.  GitHub backup             Private repo, auto-sync (launchd or container cron)
15.  Config generation         openclaw.json + credentials
16.  Persona setup             Agent identity, user info, workspace files
17.  Docker setup              Dockerfile, docker-compose, CLI tools, sidecars
18.  Channel pairing           WhatsApp QR, Signal linking
19.  Health check              Config validation, connectivity tests
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

| Channel | Auth | Default DM Policy | Native | Docker |
|---------|------|-------------------|:------:|:------:|
| WebChat | None | — | Yes | Yes |
| WhatsApp | QR code | pairing | Yes | Yes |
| Telegram | Bot token | pairing | Yes | Yes |
| Discord | Bot token | pairing | Yes | Yes |
| Slack | Bot + App tokens | pairing | Yes | Yes |
| Signal | Device linking | pairing | Yes | Yes |
| iMessage | macOS native | — | Yes | No |

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
├── Native: Personal Assistant
│   ├── Preset: personal-assistant
│   ├── Obsidian vault (unified brain)
│   ├── Google Workspace (gog)
│   └── WhatsApp (self-chat) + iMessage
│
├── Docker: Work Agent (SaaS Product)
│   ├── Preset: autonomous-agent
│   ├── CLIs: gh, doctl, supabase, gog, xurl
│   ├── Source code repo mounted
│   ├── Telegram watchdog sidecar
│   ├── Cron jobs: daily report, content drafts, site health
│   └── Daily backups
│
├── Docker: Dev Agent (Side Project)
│   ├── Preset: developer
│   ├── CLIs: gh, supabase
│   └── Discord + GitHub integration
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
- WhatsApp defaults to pairing mode (requires code exchange before chatting)
- Docker containers (bridged mode): `cap_drop: ALL`, `no-new-privileges`, healthchecks, explicit DNS
- Docker containers (host mode): `no-new-privileges`, healthchecks
- Gateway bound to loopback by default
- Unique auth tokens auto-generated per instance
- Token format validation (Telegram, Discord)
- API key verification against provider endpoints
- Safe `.gitconfig` handling (copied to instance dir, not bind-mounted from home)
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
