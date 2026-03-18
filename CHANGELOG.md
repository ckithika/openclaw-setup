# Changelog

## [2.0.0] - 2026-03-18

### Added
- Channel credential prompting — asks for real Telegram, Discord, Slack tokens during setup
- WhatsApp QR code pairing flow — guides user through pairing post-setup
- Signal device linking flow
- Input validation on all user inputs (rejects control chars, path traversal, injection)
- Post-setup health checks — validates JSON, credentials, connectivity, Docker
- API key verification against provider endpoints (Anthropic, OpenAI)
- Daily backup service for Docker instances (optional, 7-day retention)
- Credential file writing with proper permissions (chmod 600)
- `--reconfigure` flag to modify an existing instance
- `--version` and `--help` flags
- Channel credential status in summary output
- Docker healthcheck in compose file
- Token format validation (Telegram bot token, Discord token length)

### Changed
- Channel setup now includes inline instructions for getting tokens
- API keys entered via hidden input (`read -s`)
- `.env` files created with chmod 600
- ask_choice validates numeric input range
- Summary shows credential status per channel

## [1.0.0] - 2026-03-18

### Added
- Initial release
- Native macOS and Docker deployment modes
- 13 toggleable features
- Ollama cloud model selection with fallback
- Tailscale sidecar per Docker instance
- Docker Compose generation with security hardening
- WebChat, WhatsApp, Telegram, Discord, Slack, Signal, iMessage channel support
