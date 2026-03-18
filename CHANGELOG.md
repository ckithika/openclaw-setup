# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-03-18

### Added
- **Obsidian vault setup** — Creates 8-folder unified brain structure, points OpenClaw workspace at vault
- **Tag taxonomy** — Configurable life areas and project tags, generates `_taxonomy.md`, adds tagging rules to AGENTS.md
- **Claude knowledge sync** — Session retention fix (disables 30-day deletion), symlinks Claude Code memory, guides Claude Vault and Extractor install
- **Skills setup** — 6 toggleable categories (Productivity, Social Media, Research, Security, Communication, Meetings) with 13+ skills, batch install (native) or install script (Docker)
- **Memory configuration** — `softThresholdTokens: 40000` (up from 4000), `distillToMemory` enabled, optional Mem0 and Cognee plugin blocks in config
- **GitHub backup** — Create or clone private repo, `.gitignore`, optional `git-crypt`, `launchd` plist for 10-minute auto-sync, multi-Mac clone flow
- 12 new feature toggles (26 total)
- `agents.defaults.workspace` set to vault path when enabled
- Plugins block in `openclaw.json` for Mem0/Cognee
- Docker volume mount for vault and Google credentials
- Skills install script generation for Docker mode

## [2.0.0] - 2026-03-18

### Added
- Channel credential prompting — real Telegram, Discord, Slack tokens during setup
- WhatsApp QR code pairing flow and Signal device linking
- Input validation (control chars, path traversal, injection)
- Post-setup health checks — JSON validation, credential permissions, connectivity, Docker
- API key verification against provider endpoints (Anthropic, OpenAI)
- Daily backup service for Docker instances (7-day retention)
- Credential file writing with `chmod 600`
- `--reconfigure` flag
- `--version` and `--help` flags
- 3 new providers: OpenRouter, Google Gemini, Groq
- Google Workspace integration (gog, MCP, OAuth methods)
- Per-model context windows for Anthropic/OpenAI
- Ollama version check for cloud model support
- Custom Ollama host option

### Fixed
- `set -e` crash when `MODEL_FALLBACK` was empty
- EOF handling in all `ask_*` functions
- Backup service heredoc escaping

## [1.0.0] - 2026-03-18

### Added
- Initial release
- Native macOS and Docker deployment modes
- 13 toggleable features
- Ollama cloud model selection with fallback
- Tailscale sidecar per Docker instance
- Docker Compose generation with security hardening
- 7 channel support (WebChat, WhatsApp, Telegram, Discord, Slack, Signal, iMessage)
