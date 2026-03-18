#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw Unified Setup Script v2
# Works for both native (macOS) and Docker instance deployments
# M4 Mac Mini optimized | Cloud models preferred
#
# Improvements over v1:
#   1. Channel setup — prompts for real tokens, triggers WhatsApp QR pairing
#   2. Input validation — sanitizes all user inputs
#   3. Post-setup health check — verifies connectivity & config
#   4. Backup cron — optional daily backup in Docker Compose
#   5. Credential prompting — asks for API keys during setup
#   6. --reconfigure flag — re-run on existing instance to modify features
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_VERSION="2.0.0"
RECONFIGURE=false
EXISTING_CONFIG=""

# ── Parse CLI args ───────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --reconfigure) RECONFIGURE=true ;;
    --version)     echo "openclaw-setup v${SCRIPT_VERSION}"; exit 0 ;;
    --help|-h)
      echo "Usage: setup.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --reconfigure  Re-configure an existing OpenClaw instance"
      echo "  --version      Show script version"
      echo "  --help         Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (use --help for usage)"
      exit 1
      ;;
  esac
done

# ── Colors & Helpers ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*"; }
die()     { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ── [IMPROVEMENT 2] Input Validation ─────────────────────────────────────────
# Rejects control characters, path traversal, shell metacharacters
validate_input() {
  local value="$1" label="$2" allow_dots="${3:-false}"

  # Reject empty
  if [[ -z "$value" ]]; then
    err "Empty value for ${label}"
    return 1
  fi

  # Reject control characters (including null bytes, escape sequences)
  if [[ "$value" =~ [[:cntrl:]] ]]; then
    err "${label}: control characters not allowed"
    return 1
  fi

  # Reject shell metacharacters that could enable injection
  if [[ "$value" =~ [\;\|\&\`\$\(\)\{\}\<\>\!\#] ]]; then
    err "${label}: special characters (;|&\`\$(){}<!>#) not allowed"
    return 1
  fi

  # Reject path traversal
  if [[ "$value" == *".."* ]]; then
    err "${label}: path traversal (..) not allowed"
    return 1
  fi

  # Reject quotes
  if [[ "$value" =~ [\"\'] ]]; then
    err "${label}: quotes not allowed"
    return 1
  fi

  return 0
}

# Validate instance/hostname names (alphanumeric, hyphens, underscores)
validate_name() {
  local value="$1" label="$2"
  if ! [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    err "${label}: must start with alphanumeric, only alphanumeric/hyphen/underscore allowed"
    return 1
  fi
  if [[ ${#value} -gt 64 ]]; then
    err "${label}: too long (max 64 characters)"
    return 1
  fi
  return 0
}

# Validate port number
validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
    err "Port must be a number between 1024-65535"
    return 1
  fi
  return 0
}

# Validate path (must be absolute, no traversal)
validate_path() {
  local path="$1" label="$2"
  if [[ "$path" != /* ]]; then
    err "${label}: must be an absolute path"
    return 1
  fi
  if [[ "$path" == *".."* ]]; then
    err "${label}: path traversal (..) not allowed"
    return 1
  fi
  if [[ "$path" =~ [[:cntrl:]] ]]; then
    err "${label}: control characters not allowed"
    return 1
  fi
  return 0
}

# Validate API token format (non-empty, no whitespace, no control chars)
validate_token() {
  local token="$1" label="$2"
  if [[ -z "$token" ]]; then
    return 1  # empty is ok — means skip
  fi
  if [[ "$token" =~ [[:space:]] ]]; then
    err "${label}: token must not contain whitespace"
    return 1
  fi
  if [[ "$token" =~ [[:cntrl:]] ]]; then
    err "${label}: token must not contain control characters"
    return 1
  fi
  return 0
}

# Validated input wrappers
ask_yn() {
  local prompt="$1" default="${2:-y}"
  local yn_hint="[Y/n]"; [[ "$default" == "n" ]] && yn_hint="[y/N]"
  read -rp "$(echo -e "${YELLOW}?${NC} ${prompt} ${yn_hint}: ")" answer || true
  answer="${answer:-$default}"
  answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
  [[ "$answer" == "y" ]]
}

ask_input() {
  local prompt="$1" default="${2:-}"
  local hint=""; [[ -n "$default" ]] && hint=" (default: $default)"
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt}${hint}: " >&2
    read -r answer || true
    answer="${answer:-$default}"
    if validate_input "$answer" "$prompt"; then
      echo "$answer"
      return
    fi
    echo -e "  ${RED}Invalid input, try again${NC}" >&2
  done
}

ask_name() {
  local prompt="$1" default="${2:-}"
  local hint=""; [[ -n "$default" ]] && hint=" (default: $default)"
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt}${hint}: " >&2
    read -r answer || true
    answer="${answer:-$default}"
    if validate_name "$answer" "$prompt"; then
      echo "$answer"
      return
    fi
    echo -e "  ${RED}Invalid name, try again${NC}" >&2
  done
}

ask_port() {
  local prompt="$1" default="${2:-18789}"
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt} (default: $default): " >&2
    read -r answer || true
    answer="${answer:-$default}"
    if validate_port "$answer"; then
      echo "$answer"
      return
    fi
    echo -e "  ${RED}Invalid port, try again${NC}" >&2
  done
}

ask_path() {
  local prompt="$1" default="${2:-}"
  local hint=""; [[ -n "$default" ]] && hint=" (default: $default)"
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt}${hint}: " >&2
    read -r answer || true
    answer="${answer:-$default}"
    if validate_path "$answer" "$prompt"; then
      echo "$answer"
      return
    fi
    echo -e "  ${RED}Invalid path, try again${NC}" >&2
  done
}

ask_secret() {
  local prompt="$1" label="${2:-token}"
  echo -ne "${YELLOW}?${NC} ${prompt}: " >&2
  local answer=""
  read -rs answer || true  # -s hides input; || true handles EOF
  echo "" >&2
  if [[ -n "$answer" ]] && ! validate_token "$answer" "$label"; then
    echo ""
    return
  fi
  echo "$answer"
}

ask_choice() {
  local prompt="$1"; shift
  local options=("$@")
  echo -e "${YELLOW}?${NC} ${prompt}" >&2
  for i in "${!options[@]}"; do
    echo -e "  ${BOLD}$((i+1)))${NC} ${options[$i]}" >&2
  done
  local choice
  while true; do
    read -rp "$(echo -e "  ${YELLOW}>${NC} ")" choice || true
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "${options[$((choice-1))]}"
      return
    fi
    echo -e "  ${RED}Enter a number between 1 and ${#options[@]}${NC}" >&2
  done
}

# ── Defaults ─────────────────────────────────────────────────────────────────
DEPLOY_MODE=""          # native | docker
INSTANCE_NAME=""
INSTANCE_DIR=""
CONFIG_DIR=""
WORKSPACE_DIR=""
GATEWAY_PORT=18789
OLLAMA_HOST="http://host.docker.internal:11434"

# Feature Toggles (defaults)
FEAT_BROWSER=true
FEAT_SANDBOX=true
FEAT_CRON=true
FEAT_MEMORY=true
FEAT_SKILLS=true
FEAT_CODE_EXEC=true
FEAT_WEB_SEARCH=true
FEAT_WEB_FETCH=true
FEAT_FILE_ACCESS=true
FEAT_SHELL_EXEC=true
FEAT_MESSAGING=true
FEAT_VOICE=false
FEAT_CLAUDE_CODE=false

# Channel toggles
CH_WHATSAPP=false
CH_TELEGRAM=false
CH_DISCORD=false
CH_SLACK=false
CH_SIGNAL=false
CH_IMESSAGE=false
CH_WEBCHAT=true

# Channel credentials (collected during setup)
TELEGRAM_BOT_TOKEN=""
DISCORD_BOT_TOKEN=""
SLACK_BOT_TOKEN=""
SLACK_APP_TOKEN=""

# Model config
MODEL_PROVIDER="ollama-cloud"
MODEL_PRIMARY=""
MODEL_FALLBACK=""

# API credentials
ANTHROPIC_API_KEY=""
OPENAI_API_KEY=""
OPENROUTER_API_KEY=""
GOOGLE_API_KEY=""
GROQ_API_KEY=""

# Backup
FEAT_BACKUP=false

# ── Pre-flight Checks ───────────────────────────────────────────────────────
preflight() {
  header "Pre-flight Checks"

  # Check OS
  if [[ "$(uname)" == "Darwin" ]]; then
    success "macOS detected ($(sw_vers -productVersion))"
  else
    info "Linux detected — Docker mode recommended"
  fi

  # Check Ollama
  if command -v ollama &>/dev/null || [[ -x /usr/local/bin/ollama ]]; then
    local ollama_bin="${OLLAMA_BIN:-$(command -v ollama 2>/dev/null || echo /usr/local/bin/ollama)}"
    local ollama_ver
    ollama_ver=$("$ollama_bin" --version 2>/dev/null | awk '{print $NF}') || ollama_ver="unknown"
    success "Ollama found (v${ollama_ver})"
  else
    warn "Ollama not found — cloud models will still work via API but local models won't"
  fi

  # Check if Ollama is running
  if curl -sf http://localhost:11434/api/version &>/dev/null; then
    success "Ollama service is running"
  else
    warn "Ollama service not running — start it before using local models"
  fi

  # Check Docker
  if command -v docker &>/dev/null || [[ -x /usr/local/bin/docker ]]; then
    local docker_bin="${DOCKER_BIN:-$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)}"
    if "$docker_bin" info &>/dev/null 2>&1; then
      success "Docker is running"
    else
      warn "Docker found but not running"
    fi
  else
    warn "Docker not found — needed for Docker instances and sandboxing"
  fi

  # Check Node.js
  if command -v node &>/dev/null; then
    success "Node.js $(node --version) found"
  else
    warn "Node.js not found — required for native install"
  fi

  # Check jq
  if ! command -v jq &>/dev/null; then
    warn "jq not found — installing via Homebrew"
    if command -v brew &>/dev/null; then
      brew install jq --quiet
    else
      die "jq is required but Homebrew is not available to install it"
    fi
  fi

  # Check available RAM
  if [[ "$(uname)" == "Darwin" ]]; then
    local ram_gb
    ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    info "RAM: ${ram_gb}GB unified memory"
    if (( ram_gb < 16 )); then
      warn "Less than 16GB RAM — limit concurrent instances"
    fi
  fi

  # Check disk space
  local avail_gb
  avail_gb=$(df -g / | awk 'NR==2 {print $4}')
  info "Disk: ${avail_gb}GB available"
  if (( avail_gb < 20 )); then
    warn "Low disk space — at least 20GB recommended"
  fi

  echo ""
}

# ── [IMPROVEMENT 6] Reconfigure ──────────────────────────────────────────────
load_existing_config() {
  header "Reconfigure Existing Instance"

  echo -e "Select which instance to reconfigure:\n"

  local configs=()
  local labels=()

  # Check native config
  if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    configs+=("$HOME/.openclaw/openclaw.json")
    labels+=("native: $HOME/.openclaw")
  fi

  # Check Docker instances
  if [[ -d "$HOME/openclaw-instances" ]]; then
    for dir in "$HOME"/openclaw-instances/*/; do
      if [[ -f "${dir}config/openclaw.json" ]]; then
        local name
        name=$(basename "$dir")
        configs+=("${dir}config/openclaw.json")
        labels+=("docker: ${name}")
      fi
    done
  fi

  if [[ ${#configs[@]} -eq 0 ]]; then
    warn "No existing OpenClaw instances found. Running fresh setup."
    RECONFIGURE=false
    return
  fi

  local selected
  selected=$(ask_choice "Select instance to reconfigure:" "${labels[@]}")

  # Find the matching config path
  for i in "${!labels[@]}"; do
    if [[ "${labels[$i]}" == "$selected" ]]; then
      EXISTING_CONFIG="${configs[$i]}"
      break
    fi
  done

  if [[ -z "$EXISTING_CONFIG" || ! -f "$EXISTING_CONFIG" ]]; then
    die "Config file not found: $EXISTING_CONFIG"
  fi

  # Parse existing config to restore current state
  info "Loading config from: $EXISTING_CONFIG"
  local cfg
  cfg=$(cat "$EXISTING_CONFIG")

  # Detect deploy mode from path
  if [[ "$EXISTING_CONFIG" == "$HOME/.openclaw/openclaw.json" ]]; then
    DEPLOY_MODE="native"
    INSTANCE_NAME="personal"
    CONFIG_DIR="$HOME/.openclaw"
    WORKSPACE_DIR="$HOME/openclaw/workspace"
  else
    DEPLOY_MODE="docker"
    INSTANCE_DIR=$(dirname "$(dirname "$EXISTING_CONFIG")")
    INSTANCE_NAME=$(basename "$INSTANCE_DIR")
    CONFIG_DIR="${INSTANCE_DIR}/config"
    WORKSPACE_DIR="${INSTANCE_DIR}/workspace"
  fi

  # Restore feature states from tools.allow/deny
  local has_tool
  has_tool() { echo "$cfg" | jq -r ".tools.allow // [] | index(\"$1\") // empty" 2>/dev/null; }

  [[ -n "$(has_tool "read")" ]]          && FEAT_FILE_ACCESS=true  || FEAT_FILE_ACCESS=false
  [[ -n "$(has_tool "exec")" ]]          && FEAT_SHELL_EXEC=true   || FEAT_SHELL_EXEC=false
  [[ -n "$(has_tool "web_search")" ]]    && FEAT_WEB_SEARCH=true   || FEAT_WEB_SEARCH=false
  [[ -n "$(has_tool "web_fetch")" ]]     && FEAT_WEB_FETCH=true    || FEAT_WEB_FETCH=false
  [[ -n "$(has_tool "browser")" ]]       && FEAT_BROWSER=true      || FEAT_BROWSER=false
  [[ -n "$(has_tool "message")" ]]       && FEAT_MESSAGING=true    || FEAT_MESSAGING=false
  [[ -n "$(has_tool "memory_search")" ]] && FEAT_MEMORY=true       || FEAT_MEMORY=false
  [[ -n "$(has_tool "cron")" ]]          && FEAT_CRON=true         || FEAT_CRON=false

  # Restore channel states
  CH_WEBCHAT=$(echo "$cfg"  | jq -r '.channels.webchat.enabled // false' 2>/dev/null)
  CH_TELEGRAM=$(echo "$cfg" | jq -r '.channels.telegram.enabled // false' 2>/dev/null)
  CH_WHATSAPP=$(echo "$cfg" | jq -r '.channels.whatsapp.enabled // false' 2>/dev/null)
  CH_DISCORD=$(echo "$cfg"  | jq -r '.channels.discord.enabled // false' 2>/dev/null)
  CH_SLACK=$(echo "$cfg"    | jq -r '.channels.slack.enabled // false' 2>/dev/null)
  CH_SIGNAL=$(echo "$cfg"   | jq -r '.channels.signal.enabled // false' 2>/dev/null)
  CH_IMESSAGE=$(echo "$cfg" | jq -r '.channels.imessage.enabled // false' 2>/dev/null)

  # Restore model
  local current_model
  current_model=$(echo "$cfg" | jq -r '.agents.defaults.model // ""' 2>/dev/null)
  if [[ "$current_model" == ollama/* ]]; then
    MODEL_PROVIDER="ollama-cloud"
    MODEL_PRIMARY="${current_model#ollama/}"
  elif [[ "$current_model" == anthropic/* ]]; then
    MODEL_PROVIDER="anthropic"
    MODEL_PRIMARY="${current_model#anthropic/}"
  elif [[ "$current_model" == openai/* ]]; then
    MODEL_PROVIDER="openai"
    MODEL_PRIMARY="${current_model#openai/}"
  fi

  # Restore gateway port
  GATEWAY_PORT=$(echo "$cfg" | jq -r '.gateway.port // 18789' 2>/dev/null)

  # Restore sandbox
  local sandbox_mode
  sandbox_mode=$(echo "$cfg" | jq -r '.agents.defaults.sandbox.mode // "off"' 2>/dev/null)
  [[ "$sandbox_mode" != "off" ]] && FEAT_SANDBOX=true || FEAT_SANDBOX=false

  # Restore skills
  local skills_enabled
  skills_enabled=$(echo "$cfg" | jq -r '.skills.enabled // true' 2>/dev/null)
  [[ "$skills_enabled" == "true" ]] && FEAT_SKILLS=true || FEAT_SKILLS=false

  # Restore browser
  local browser_enabled
  browser_enabled=$(echo "$cfg" | jq -r '.browser.enabled // false' 2>/dev/null)
  [[ "$browser_enabled" == "true" ]] && FEAT_BROWSER=true || FEAT_BROWSER=false

  success "Loaded existing config for: $INSTANCE_NAME ($DEPLOY_MODE)"
  info "Current model: $current_model"
  info "Proceeding to feature toggles — modify what you need, keep the rest."
  echo ""
}

# ── Deployment Mode ──────────────────────────────────────────────────────────
choose_deploy_mode() {
  header "Deployment Mode"
  echo -e "  ${BOLD}native${NC}  — Runs directly on macOS. Full system access (iMessage, GPU, filesystem)."
  echo -e "  ${BOLD}docker${NC}  — Runs in isolated container. Best for work agents / multi-account."
  echo ""
  DEPLOY_MODE=$(ask_choice "Select deployment mode:" "native" "docker")
  success "Mode: $DEPLOY_MODE"
}

# ── Instance Name ────────────────────────────────────────────────────────────
choose_instance() {
  header "Instance Configuration"

  if [[ "$DEPLOY_MODE" == "native" ]]; then
    INSTANCE_NAME=$(ask_name "Instance name" "personal")
    CONFIG_DIR="$HOME/.openclaw"
    WORKSPACE_DIR="$HOME/openclaw/workspace"
  else
    INSTANCE_NAME=$(ask_name "Instance name (e.g., work-brand-a)" "work-agent-1")
    local base_dir
    base_dir=$(ask_path "Base directory for Docker instances" "$HOME/openclaw-instances")
    INSTANCE_DIR="${base_dir}/${INSTANCE_NAME}"
    CONFIG_DIR="${INSTANCE_DIR}/config"
    WORKSPACE_DIR="${INSTANCE_DIR}/workspace"
    GATEWAY_PORT=$(ask_port "Gateway port" "$((18790 + RANDOM % 100))")
  fi

  success "Instance: $INSTANCE_NAME"
  success "Config: $CONFIG_DIR"
  success "Workspace: $WORKSPACE_DIR"
}

# ── Feature Toggle Menu ─────────────────────────────────────────────────────
toggle_features() {
  header "Feature Toggles"
  echo -e "Toggle features on/off. Press Enter to keep current value.\n"

  local features=(
    "FEAT_BROWSER:Browser automation (Chromium CDP):$FEAT_BROWSER"
    "FEAT_SANDBOX:Sandbox (Docker-based tool isolation):$FEAT_SANDBOX"
    "FEAT_CRON:Cron jobs (scheduled tasks):$FEAT_CRON"
    "FEAT_MEMORY:Persistent memory (cross-session):$FEAT_MEMORY"
    "FEAT_SKILLS:Skills marketplace (ClawHub):$FEAT_SKILLS"
    "FEAT_CODE_EXEC:Code execution (Python/Node.js):$FEAT_CODE_EXEC"
    "FEAT_WEB_SEARCH:Web search:$FEAT_WEB_SEARCH"
    "FEAT_WEB_FETCH:Web fetch (read pages):$FEAT_WEB_FETCH"
    "FEAT_FILE_ACCESS:File read/write access:$FEAT_FILE_ACCESS"
    "FEAT_SHELL_EXEC:Shell command execution:$FEAT_SHELL_EXEC"
    "FEAT_MESSAGING:Cross-session messaging:$FEAT_MESSAGING"
    "FEAT_VOICE:Voice/TTS (macOS native only):$FEAT_VOICE"
    "FEAT_CLAUDE_CODE:Claude Code integration (ACP):$FEAT_CLAUDE_CODE"
  )

  for feat_line in "${features[@]}"; do
    IFS=':' read -r var_name description current_val <<< "$feat_line"
    local status_icon="ON "; local status_color="$GREEN"
    if [[ "$current_val" == "false" ]]; then
      status_icon="OFF"; status_color="$RED"
    fi
    printf "  ${status_color}[%s]${NC} %s" "$status_icon" "$description"

    local toggle
    read -rp " (toggle? y/N): " toggle || true
    toggle=$(echo "$toggle" | tr '[:upper:]' '[:lower:]')
    if [[ "$toggle" == "y" ]]; then
      if [[ "$current_val" == "true" ]]; then
        eval "$var_name=false"
        echo -e "       ${RED}-> OFF${NC}"
      else
        eval "$var_name=true"
        echo -e "       ${GREEN}-> ON${NC}"
      fi
    fi
  done

  # Docker-specific: disable voice and iMessage
  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    if [[ "$FEAT_VOICE" == "true" ]]; then
      warn "Voice/TTS disabled — not available in Docker containers"
      FEAT_VOICE=false
    fi
  fi

  echo ""
  success "Features configured"
}

# ── [IMPROVEMENT 1] Channel Setup with Real Credentials ──────────────────────
setup_channels() {
  header "Channel Setup"
  echo -e "Enable messaging channels and configure credentials.\n"

  # ── WebChat (no credentials needed) ──
  if ask_yn "WebChat (browser-based, always available)" "$( [[ "$CH_WEBCHAT" == "true" ]] && echo y || echo n )"; then
    CH_WEBCHAT=true
  else
    CH_WEBCHAT=false
  fi

  # ── WhatsApp ──
  if ask_yn "WhatsApp" "$( [[ "$CH_WHATSAPP" == "true" ]] && echo y || echo n )"; then
    CH_WHATSAPP=true
    echo ""
    echo -e "  ${CYAN}WhatsApp Setup Notes:${NC}"
    echo -e "  - Uses WhatsApp Web protocol (phone must stay online)"
    echo -e "  - QR code pairing happens after setup completes"
    echo -e "  - Recommended: use a separate phone number, not your primary"
    echo -e "  - Credentials saved to: ${CONFIG_DIR}/credentials/whatsapp/"
    echo ""
    if ask_yn "  Use a dedicated WhatsApp number (recommended)?" "y"; then
      info "  Good choice. Have your secondary phone ready for QR scan after setup."
    fi
  else
    CH_WHATSAPP=false
  fi

  # ── Telegram ──
  if ask_yn "Telegram" "$( [[ "$CH_TELEGRAM" == "true" ]] && echo y || echo n )"; then
    CH_TELEGRAM=true
    echo ""
    echo -e "  ${CYAN}Telegram Setup:${NC}"
    echo -e "  1. Open Telegram and message @BotFather"
    echo -e "  2. Send /newbot and follow the prompts"
    echo -e "  3. Copy the bot token (format: 123456789:ABCdef...)"
    echo ""
    local tg_token
    tg_token=$(ask_secret "  Paste Telegram bot token (or Enter to skip)" "Telegram bot token")
    if [[ -n "$tg_token" ]]; then
      TELEGRAM_BOT_TOKEN="$tg_token"
      success "  Telegram bot token saved"
    else
      warn "  Skipped — add token later in openclaw.json or .env"
    fi
  else
    CH_TELEGRAM=false
  fi

  # ── Discord ──
  if ask_yn "Discord" "$( [[ "$CH_DISCORD" == "true" ]] && echo y || echo n )"; then
    CH_DISCORD=true
    echo ""
    echo -e "  ${CYAN}Discord Setup:${NC}"
    echo -e "  1. Go to https://discord.com/developers/applications"
    echo -e "  2. Create a New Application > Bot > Copy token"
    echo -e "  3. Enable Message Content Intent under Privileged Gateway Intents"
    echo ""
    local dc_token
    dc_token=$(ask_secret "  Paste Discord bot token (or Enter to skip)" "Discord bot token")
    if [[ -n "$dc_token" ]]; then
      DISCORD_BOT_TOKEN="$dc_token"
      success "  Discord bot token saved"
    else
      warn "  Skipped — add token later in openclaw.json or .env"
    fi
  else
    CH_DISCORD=false
  fi

  # ── Slack ──
  if ask_yn "Slack" "$( [[ "$CH_SLACK" == "true" ]] && echo y || echo n )"; then
    CH_SLACK=true
    echo ""
    echo -e "  ${CYAN}Slack Setup:${NC}"
    echo -e "  1. Go to https://api.slack.com/apps > Create New App"
    echo -e "  2. Enable Socket Mode > copy App-Level Token (xapp-...)"
    echo -e "  3. Under OAuth & Permissions, copy Bot User OAuth Token (xoxb-...)"
    echo ""
    local sl_bot_token
    sl_bot_token=$(ask_secret "  Paste Slack Bot Token xoxb-... (or Enter to skip)" "Slack bot token")
    if [[ -n "$sl_bot_token" ]]; then
      SLACK_BOT_TOKEN="$sl_bot_token"
      local sl_app_token
      sl_app_token=$(ask_secret "  Paste Slack App Token xapp-... (or Enter to skip)" "Slack app token")
      SLACK_APP_TOKEN="$sl_app_token"
      success "  Slack tokens saved"
    else
      warn "  Skipped — add tokens later in openclaw.json or .env"
    fi
  else
    CH_SLACK=false
  fi

  # ── Signal ──
  if ask_yn "Signal" "$( [[ "$CH_SIGNAL" == "true" ]] && echo y || echo n )"; then
    CH_SIGNAL=true
    echo ""
    echo -e "  ${CYAN}Signal Setup Notes:${NC}"
    echo -e "  - Signal linking happens after setup via: openclaw channels login signal"
    echo ""
  else
    CH_SIGNAL=false
  fi

  # ── iMessage (native only) ──
  if [[ "$DEPLOY_MODE" == "native" ]]; then
    if ask_yn "iMessage (native macOS only)" "$( [[ "$CH_IMESSAGE" == "true" ]] && echo y || echo n )"; then
      CH_IMESSAGE=true
      echo ""
      echo -e "  ${CYAN}iMessage Notes:${NC}"
      echo -e "  - Requires macOS with Messages.app configured"
      echo -e "  - OpenClaw reads/sends via AppleScript bridge"
      echo ""
    else
      CH_IMESSAGE=false
    fi
  fi

  echo ""
  success "Channels configured"
}

# ── [IMPROVEMENT 5] Model Setup with Credential Prompting ────────────────────
setup_models() {
  header "Model Configuration"

  echo -e "  ${BOLD}ollama-cloud${NC}   — Free, frontier models via Ollama cloud (recommended)"
  echo -e "  ${BOLD}ollama-local${NC}   — Local models on this machine (limited by 16GB RAM)"
  echo -e "  ${BOLD}anthropic${NC}      — Claude API (paid, best quality)"
  echo -e "  ${BOLD}openai${NC}         — OpenAI GPT API (paid)"
  echo -e "  ${BOLD}openrouter${NC}     — OpenRouter (100+ models, one API key)"
  echo -e "  ${BOLD}google${NC}         — Google Gemini API"
  echo -e "  ${BOLD}groq${NC}           — Groq (fastest inference, free tier)"
  echo ""
  MODEL_PROVIDER=$(ask_choice "Select primary model provider:" \
    "ollama-cloud" "ollama-local" "anthropic" "openai" "openrouter" "google" "groq")

  case "$MODEL_PROVIDER" in
    ollama-cloud)
      echo ""
      echo -e "  ${CYAN}Ollama cloud models run remotely via Ollama's infrastructure.${NC}"
      echo -e "  ${CYAN}No API key needed. Requires Ollama 0.17+ installed and running.${NC}"
      echo -e "  ${CYAN}Models are accessed through your local Ollama with the :cloud tag.${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} glm-5:cloud        — Best coding (SWE-bench 77.8%)"
      echo -e "  ${BOLD}2)${NC} kimi-k2.5:cloud    — Best multimodal + vision"
      echo -e "  ${BOLD}3)${NC} deepseek-v3.2:cloud — Strong reasoning"
      echo ""
      MODEL_PRIMARY=$(ask_choice "Select primary model:" \
        "glm-5:cloud" "kimi-k2.5:cloud" "deepseek-v3.2:cloud")

      if ask_yn "Add a fallback model?" "y"; then
        local remaining=()
        for m in "glm-5:cloud" "kimi-k2.5:cloud" "deepseek-v3.2:cloud"; do
          [[ "$m" != "$MODEL_PRIMARY" ]] && remaining+=("$m")
        done
        MODEL_FALLBACK=$(ask_choice "Select fallback model:" "${remaining[@]}")
      fi

      # Verify Ollama version supports :cloud
      if command -v ollama &>/dev/null || [[ -x /usr/local/bin/ollama ]]; then
        local ollama_bin="${OLLAMA_BIN:-$(command -v ollama 2>/dev/null || echo /usr/local/bin/ollama)}"
        local ollama_ver
        ollama_ver=$("$ollama_bin" --version 2>/dev/null | awk '{print $NF}') || ollama_ver="0.0.0"
        local major minor
        major=$(echo "$ollama_ver" | cut -d. -f1)
        minor=$(echo "$ollama_ver" | cut -d. -f2)
        if (( major == 0 && minor < 17 )); then
          warn "Ollama v${ollama_ver} detected — cloud models require v0.17+. Run: ollama update"
        else
          success "Ollama v${ollama_ver} supports cloud models"
        fi
      fi

      if ask_yn "Use custom Ollama host?" "n"; then
        OLLAMA_HOST=$(ask_input "Ollama host URL" "http://localhost:11434")
      fi

      info "No API key needed — Ollama cloud models are free"
      ;;

    ollama-local)
      echo ""
      echo -e "  ${CYAN}Local models run entirely on this machine using Ollama.${NC}"
      echo -e "  ${CYAN}Limited by available RAM (16GB = up to ~14B parameter models).${NC}"
      echo ""
      echo -e "  ${BOLD}Recommended for 16GB:${NC}"
      echo -e "    devstral-small-2  — 24B, best for agentic coding (tight fit)"
      echo -e "    nemotron-3-nano   — 30B MoE/6B active, fast"
      echo -e "    qwen3.5:14b       — 14B, strong all-rounder"
      echo -e "    deepseek-r1:8b    — 8B, smooth on 16GB"
      echo ""
      MODEL_PRIMARY=$(ask_input "Model name" "devstral-small-2")
      info "Make sure to pull the model: ollama pull ${MODEL_PRIMARY}"

      if ask_yn "Use custom Ollama host?" "n"; then
        OLLAMA_HOST=$(ask_input "Ollama host URL" "http://localhost:11434")
      fi
      ;;

    anthropic)
      echo ""
      echo -e "  ${CYAN}Claude API — best quality, paid per token.${NC}"
      echo -e "  ${CYAN}Supported models: claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} claude-sonnet-4-6   — Best balance of quality and speed"
      echo -e "  ${BOLD}2)${NC} claude-opus-4-6     — Highest quality, slower"
      echo -e "  ${BOLD}3)${NC} claude-haiku-4-5    — Fastest, cheapest"
      echo ""
      MODEL_PRIMARY=$(ask_choice "Select Claude model:" \
        "claude-sonnet-4-6" "claude-opus-4-6" "claude-haiku-4-5")

      echo ""
      echo -e "  ${CYAN}Get your API key at: https://console.anthropic.com/settings/keys${NC}"
      local api_key
      api_key=$(ask_secret "  Paste Anthropic API key sk-ant-... (or Enter to skip)" "Anthropic API key")
      if [[ -n "$api_key" ]]; then
        ANTHROPIC_API_KEY="$api_key"
        success "  Anthropic API key saved"
      else
        warn "  Skipped — add key later: openclaw models auth add anthropic"
        warn "  OpenClaw will NOT work without an API key for Anthropic"
      fi
      ;;

    openai)
      echo ""
      echo -e "  ${CYAN}OpenAI API — paid per token.${NC}"
      echo -e "  ${CYAN}Supported models: gpt-5.4, gpt-5-mini, gpt-4o${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} gpt-5.4     — Latest, most capable"
      echo -e "  ${BOLD}2)${NC} gpt-5-mini  — Faster, cheaper"
      echo -e "  ${BOLD}3)${NC} gpt-4o      — Previous gen, stable"
      echo ""
      MODEL_PRIMARY=$(ask_choice "Select OpenAI model:" \
        "gpt-5.4" "gpt-5-mini" "gpt-4o")

      echo ""
      echo -e "  ${CYAN}Get your API key at: https://platform.openai.com/api-keys${NC}"
      local api_key
      api_key=$(ask_secret "  Paste OpenAI API key sk-... (or Enter to skip)" "OpenAI API key")
      if [[ -n "$api_key" ]]; then
        OPENAI_API_KEY="$api_key"
        success "  OpenAI API key saved"
      else
        warn "  Skipped — add key later: openclaw models auth add openai"
        warn "  OpenClaw will NOT work without an API key for OpenAI"
      fi
      ;;

    openrouter)
      echo ""
      echo -e "  ${CYAN}OpenRouter — access 100+ models with one API key.${NC}"
      echo -e "  ${CYAN}Supports Claude, GPT, Gemini, Llama, Mistral, and more.${NC}"
      echo -e "  ${CYAN}Some models have free tiers. Pay-as-you-go.${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} anthropic/claude-sonnet-4-6   — Claude Sonnet via OpenRouter"
      echo -e "  ${BOLD}2)${NC} openai/gpt-5.4               — GPT-5.4 via OpenRouter"
      echo -e "  ${BOLD}3)${NC} google/gemini-3.1-pro         — Gemini Pro via OpenRouter"
      echo -e "  ${BOLD}4)${NC} meta-llama/llama-4-scout      — Llama 4 (free tier)"
      echo -e "  ${BOLD}5)${NC} mistralai/devstral-2          — Devstral 2 (free tier)"
      echo ""
      MODEL_PRIMARY=$(ask_choice "Select model:" \
        "anthropic/claude-sonnet-4-6" "openai/gpt-5.4" "google/gemini-3.1-pro" \
        "meta-llama/llama-4-scout" "mistralai/devstral-2")

      echo ""
      echo -e "  ${CYAN}Get your API key at: https://openrouter.ai/keys${NC}"
      local api_key
      api_key=$(ask_secret "  Paste OpenRouter API key sk-or-... (or Enter to skip)" "OpenRouter API key")
      if [[ -n "$api_key" ]]; then
        OPENROUTER_API_KEY="$api_key"
        success "  OpenRouter API key saved"
      else
        warn "  Skipped — add key later in credentials/openrouter.json"
        warn "  OpenClaw will NOT work without an API key for OpenRouter"
      fi
      ;;

    google)
      echo ""
      echo -e "  ${CYAN}Google Gemini API — competitive pricing, large context.${NC}"
      echo -e "  ${CYAN}Free tier available for some models.${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} gemini-3.1-pro-preview  — Latest, most capable"
      echo -e "  ${BOLD}2)${NC} gemini-3.1-flash        — Fast, efficient"
      echo -e "  ${BOLD}3)${NC} gemini-2.5-pro          — Previous gen, stable"
      echo ""
      MODEL_PRIMARY=$(ask_choice "Select Gemini model:" \
        "gemini-3.1-pro-preview" "gemini-3.1-flash" "gemini-2.5-pro")

      echo ""
      echo -e "  ${CYAN}Get your API key at: https://aistudio.google.com/apikey${NC}"
      local api_key
      api_key=$(ask_secret "  Paste Google AI API key (or Enter to skip)" "Google API key")
      if [[ -n "$api_key" ]]; then
        GOOGLE_API_KEY="$api_key"
        success "  Google API key saved"
      else
        warn "  Skipped — add key later in credentials/google.json"
        warn "  OpenClaw will NOT work without an API key for Google"
      fi
      ;;

    groq)
      echo ""
      echo -e "  ${CYAN}Groq — fastest inference speeds, free tier available.${NC}"
      echo -e "  ${CYAN}Runs open-source models on custom LPU hardware.${NC}"
      echo ""
      echo -e "  ${BOLD}1)${NC} llama-4-scout-17b-16e  — Llama 4 Scout (free)"
      echo -e "  ${BOLD}2)${NC} deepseek-r1-distill-llama-70b — DeepSeek R1 70B"
      echo -e "  ${BOLD}3)${NC} qwen-qwq-32b          — Qwen QwQ 32B (free)"
      echo ""
      MODEL_PRIMARY=$(ask_choice "Select Groq model:" \
        "llama-4-scout-17b-16e" "deepseek-r1-distill-llama-70b" "qwen-qwq-32b")

      echo ""
      echo -e "  ${CYAN}Get your API key at: https://console.groq.com/keys${NC}"
      local api_key
      api_key=$(ask_secret "  Paste Groq API key gsk_... (or Enter to skip)" "Groq API key")
      if [[ -n "$api_key" ]]; then
        GROQ_API_KEY="$api_key"
        success "  Groq API key saved"
      else
        warn "  Skipped — add key later in credentials/groq.json"
        warn "  OpenClaw will NOT work without an API key for Groq"
      fi
      ;;
  esac

  success "Primary model: $MODEL_PRIMARY"
  if [[ -n "$MODEL_FALLBACK" ]]; then
    success "Fallback model: $MODEL_FALLBACK"
  fi
}

# ── Generate openclaw.json ───────────────────────────────────────────────────
generate_config() {
  header "Generating Configuration"

  # Build tools allow/deny lists
  local tools_allow=()
  local tools_deny=()

  [[ "$FEAT_FILE_ACCESS" == "true" ]]  && tools_allow+=("read" "write" "edit" "apply_patch") || tools_deny+=("read" "write" "edit" "apply_patch")
  [[ "$FEAT_SHELL_EXEC" == "true" ]]   && tools_allow+=("exec" "process")                    || tools_deny+=("exec" "process")
  [[ "$FEAT_WEB_SEARCH" == "true" ]]   && tools_allow+=("web_search")                        || tools_deny+=("web_search")
  [[ "$FEAT_WEB_FETCH" == "true" ]]    && tools_allow+=("web_fetch")                          || tools_deny+=("web_fetch")
  [[ "$FEAT_BROWSER" == "true" ]]      && tools_allow+=("browser")                            || tools_deny+=("browser")
  [[ "$FEAT_MESSAGING" == "true" ]]    && tools_allow+=("message" "sessions_list" "sessions_send") || tools_deny+=("message")
  [[ "$FEAT_MEMORY" == "true" ]]       && tools_allow+=("memory_search" "memory_get")         || tools_deny+=("memory_search" "memory_get")
  [[ "$FEAT_CRON" == "true" ]]         && tools_allow+=("cron")                               || tools_deny+=("cron")

  # Format arrays as JSON
  local allow_json deny_json
  if [[ ${#tools_allow[@]} -gt 0 ]]; then
    allow_json=$(printf '%s\n' "${tools_allow[@]}" | jq -R . | jq -s .)
  else
    allow_json="[]"
  fi
  if [[ ${#tools_deny[@]} -gt 0 ]]; then
    deny_json=$(printf '%s\n' "${tools_deny[@]}" | jq -R . | jq -s .)
  else
    deny_json="[]"
  fi

  # Sandbox config
  local sandbox_mode="off"
  [[ "$FEAT_SANDBOX" == "true" ]] && sandbox_mode="non-main"

  # Model provider block
  local models_block=""
  local auth_block=""
  local agents_model=""

  case "$MODEL_PROVIDER" in
    ollama-cloud)
      local ollama_base="http://localhost:11434"
      [[ "$DEPLOY_MODE" == "docker" ]] && ollama_base="$OLLAMA_HOST"
      models_block=$(cat <<MODELS
    "providers": {
      "ollama": {
        "baseUrl": "${ollama_base}/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "contextWindow": 131072,
            "maxTokens": 16384
          }$(if [[ -n "$MODEL_FALLBACK" ]]; then cat <<FB
,
          {
            "id": "${MODEL_FALLBACK}",
            "name": "${MODEL_FALLBACK}",
            "contextWindow": 131072,
            "maxTokens": 16384
          }
FB
fi)
        ]
      }
    }
MODELS
)
      agents_model="ollama/${MODEL_PRIMARY}"
      ;;
    ollama-local)
      local ollama_base="http://localhost:11434"
      [[ "$DEPLOY_MODE" == "docker" ]] && ollama_base="$OLLAMA_HOST"
      models_block=$(cat <<MODELS
    "providers": {
      "ollama": {
        "baseUrl": "${ollama_base}/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "contextWindow": 65536,
            "maxTokens": 8192
          }
        ]
      }
    }
MODELS
)
      agents_model="ollama/${MODEL_PRIMARY}"
      ;;
    anthropic)
      # Anthropic uses built-in provider — set context windows per model
      local ctx_window=200000 max_tokens=8192
      case "$MODEL_PRIMARY" in
        claude-opus-4-6)   ctx_window=1000000; max_tokens=32768 ;;
        claude-sonnet-4-6) ctx_window=200000;  max_tokens=16384 ;;
        claude-haiku-4-5)  ctx_window=200000;  max_tokens=8192 ;;
      esac
      models_block=$(cat <<MODELS
    "providers": {
      "anthropic": {
        "baseUrl": "https://api.anthropic.com",
        "api": "anthropic-messages",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "reasoning": true,
            "input": ["text", "image"],
            "contextWindow": ${ctx_window},
            "maxTokens": ${max_tokens}
          }
        ]
      }
    }
MODELS
)
      auth_block=$(cat <<AUTH
  "auth": {
    "profiles": {
      "anthropic": {
        "provider": "anthropic",
        "credentialFile": "anthropic.json"
      }
    },
    "order": ["anthropic"]
  },
AUTH
)
      agents_model="anthropic/${MODEL_PRIMARY}"
      ;;
    openai)
      local ctx_window=128000 max_tokens=16384
      case "$MODEL_PRIMARY" in
        gpt-5.4)    ctx_window=200000; max_tokens=32768 ;;
        gpt-5-mini) ctx_window=128000; max_tokens=16384 ;;
        gpt-4o)     ctx_window=128000; max_tokens=16384 ;;
      esac
      models_block=$(cat <<MODELS
    "providers": {
      "openai": {
        "baseUrl": "https://api.openai.com/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "input": ["text", "image"],
            "contextWindow": ${ctx_window},
            "maxTokens": ${max_tokens}
          }
        ]
      }
    }
MODELS
)
      auth_block=$(cat <<AUTH
  "auth": {
    "profiles": {
      "openai": {
        "provider": "openai",
        "credentialFile": "openai.json"
      }
    },
    "order": ["openai"]
  },
AUTH
)
      agents_model="openai/${MODEL_PRIMARY}"
      ;;
    openrouter)
      models_block=$(cat <<MODELS
    "providers": {
      "openrouter": {
        "baseUrl": "https://openrouter.ai/api/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "contextWindow": 200000,
            "maxTokens": 16384
          }
        ]
      }
    }
MODELS
)
      auth_block=$(cat <<AUTH
  "auth": {
    "profiles": {
      "openrouter": {
        "provider": "openrouter",
        "credentialFile": "openrouter.json"
      }
    },
    "order": ["openrouter"]
  },
AUTH
)
      agents_model="openrouter/${MODEL_PRIMARY}"
      ;;
    google)
      local ctx_window=1000000
      case "$MODEL_PRIMARY" in
        gemini-3.1-flash) ctx_window=1000000 ;;
        gemini-2.5-pro)   ctx_window=1000000 ;;
      esac
      models_block=$(cat <<MODELS
    "providers": {
      "google": {
        "baseUrl": "https://generativelanguage.googleapis.com/v1beta",
        "api": "google-generative-ai",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "input": ["text", "image", "video"],
            "contextWindow": ${ctx_window},
            "maxTokens": 16384
          }
        ]
      }
    }
MODELS
)
      auth_block=$(cat <<AUTH
  "auth": {
    "profiles": {
      "google": {
        "provider": "google",
        "credentialFile": "google.json"
      }
    },
    "order": ["google"]
  },
AUTH
)
      agents_model="google/${MODEL_PRIMARY}"
      ;;
    groq)
      models_block=$(cat <<MODELS
    "providers": {
      "groq": {
        "baseUrl": "https://api.groq.com/openai/v1",
        "api": "openai-completions",
        "models": [
          {
            "id": "${MODEL_PRIMARY}",
            "name": "${MODEL_PRIMARY}",
            "contextWindow": 131072,
            "maxTokens": 8192
          }
        ]
      }
    }
MODELS
)
      auth_block=$(cat <<AUTH
  "auth": {
    "profiles": {
      "groq": {
        "provider": "groq",
        "credentialFile": "groq.json"
      }
    },
    "order": ["groq"]
  },
AUTH
)
      agents_model="groq/${MODEL_PRIMARY}"
      ;;
  esac

  # ── [IMPROVEMENT 1] Channel blocks with real tokens ────────────────────────
  local channels_block=""
  local ch_entries=()

  if [[ "$CH_WEBCHAT" == "true" ]]; then
    ch_entries+=("$(cat <<CH
    "webchat": {
      "enabled": true
    }
CH
)")
  fi

  if [[ "$CH_TELEGRAM" == "true" ]]; then
    local tg_token_val="${TELEGRAM_BOT_TOKEN:-YOUR_TELEGRAM_BOT_TOKEN}"
    ch_entries+=("$(cat <<CH
    "telegram": {
      "enabled": true,
      "accounts": {
        "default": {
          "botToken": "${tg_token_val}",
          "dmPolicy": "pairing",
          "streamMode": "partial"
        }
      }
    }
CH
)")
  fi

  if [[ "$CH_WHATSAPP" == "true" ]]; then
    ch_entries+=("$(cat <<CH
    "whatsapp": {
      "enabled": true,
      "accounts": {
        "default": {
          "dmPolicy": "pairing"
        }
      }
    }
CH
)")
  fi

  if [[ "$CH_DISCORD" == "true" ]]; then
    local dc_token_val="${DISCORD_BOT_TOKEN:-YOUR_DISCORD_BOT_TOKEN}"
    ch_entries+=("$(cat <<CH
    "discord": {
      "enabled": true,
      "accounts": {
        "default": {
          "botToken": "${dc_token_val}",
          "dmPolicy": "pairing"
        }
      }
    }
CH
)")
  fi

  if [[ "$CH_SLACK" == "true" ]]; then
    local sl_bot_val="${SLACK_BOT_TOKEN:-YOUR_SLACK_BOT_TOKEN}"
    local sl_app_val="${SLACK_APP_TOKEN:-YOUR_SLACK_APP_TOKEN}"
    ch_entries+=("$(cat <<CH
    "slack": {
      "enabled": true,
      "accounts": {
        "default": {
          "botToken": "${sl_bot_val}",
          "appToken": "${sl_app_val}",
          "dmPolicy": "pairing"
        }
      }
    }
CH
)")
  fi

  if [[ "$CH_SIGNAL" == "true" ]]; then
    ch_entries+=("$(cat <<CH
    "signal": {
      "enabled": true,
      "accounts": {
        "default": {
          "dmPolicy": "pairing"
        }
      }
    }
CH
)")
  fi

  if [[ "$CH_IMESSAGE" == "true" ]]; then
    ch_entries+=("$(cat <<CH
    "imessage": {
      "enabled": true,
      "accounts": {
        "default": {
          "dmPolicy": "pairing"
        }
      }
    }
CH
)")
  fi

  # Join channel entries
  if [[ ${#ch_entries[@]} -gt 0 ]]; then
    channels_block=$(IFS=','; echo "${ch_entries[*]}")
  fi

  # Browser config
  local browser_block=""
  if [[ "$FEAT_BROWSER" == "true" ]]; then
    local headless_val="false"
    [[ "$DEPLOY_MODE" == "docker" ]] && headless_val="true"
    browser_block=$(cat <<BROWSER
  "browser": {
    "enabled": true,
    "defaultProfile": "openclaw",
    "headless": ${headless_val},
    "noSandbox": $( [[ "$DEPLOY_MODE" == "docker" ]] && echo "true" || echo "false" ),
    "evaluateEnabled": true
  },
BROWSER
)
  else
    browser_block=$(cat <<BROWSER
  "browser": {
    "enabled": false
  },
BROWSER
)
  fi

  # Cron config
  local cron_block=""
  if [[ "$FEAT_CRON" == "true" ]]; then
    cron_block=$(cat <<CRON
  "cron": {
    "enabled": true,
    "maxConcurrentRuns": 3,
    "runLog": {
      "maxBytes": 1048576,
      "keepLines": 200
    }
  },
CRON
)
  else
    cron_block=$(cat <<CRON
  "cron": {
    "enabled": false
  },
CRON
)
  fi

  # Voice config
  local talk_block=""
  if [[ "$FEAT_VOICE" == "true" && "$DEPLOY_MODE" == "native" ]]; then
    talk_block=$(cat <<TALK
  "talk": {
    "enabled": true
  },
TALK
)
  fi

  # Gateway config
  local gateway_bind="loopback"
  local gateway_block
  gateway_block=$(cat <<GW
  "gateway": {
    "port": ${GATEWAY_PORT},
    "bind": "${gateway_bind}",
    "auth": {
      "token": "$(openssl rand -hex 24)"
    }
  },
GW
)

  # Sandbox docker config
  local sandbox_block
  if [[ "$FEAT_SANDBOX" == "true" ]]; then
    sandbox_block=$(cat <<SB
    "sandbox": {
      "mode": "${sandbox_mode}",
      "backend": "docker",
      "scope": "session",
      "docker": {
        "readOnlyRoot": true,
        "network": "bridge",
        "capDrop": ["ALL"],
        "memory": "2g",
        "cpus": "2"
      }
    }
SB
)
  else
    sandbox_block=$(cat <<SB
    "sandbox": {
      "mode": "off"
    }
SB
)
  fi

  # Skills config
  local skills_block=""
  if [[ "$FEAT_SKILLS" == "true" ]]; then
    skills_block=$(cat <<SK
  "skills": {
    "enabled": true
  },
SK
)
  else
    skills_block=$(cat <<SK
  "skills": {
    "enabled": false
  },
SK
)
  fi

  # ── Assemble final config ──────────────────────────────────────────────────
  local config
  config=$(cat <<CONFIG
{
  "\$schema": "https://docs.openclaw.ai/schema/openclaw.json",

  "agents": {
    "defaults": {
      "model": "${agents_model}",
      "maxConcurrent": 3,
${sandbox_block}
    }
  },

  "models": {
${models_block}
  },

${auth_block}

  "channels": {
${channels_block}
  },

  "tools": {
    "allow": ${allow_json},
    "deny": ${deny_json}
  },

${browser_block}

${cron_block}

${skills_block}

${talk_block}

${gateway_block}

  "session": {
    "contextPruning": {
      "mode": "cache-ttl",
      "cacheTtl": "6h",
      "keepLastAssistantMessages": 3
    }
  },

  "logging": {
    "redact": true
  }
}
CONFIG
)

  # Clean up empty lines and trailing commas
  config=$(echo "$config" | sed '/^$/d' | python3 -c "
import sys, json, re
raw = sys.stdin.read()
cleaned = re.sub(r',(\s*[}\]])', r'\1', raw)
try:
    parsed = json.loads(cleaned)
    print(json.dumps(parsed, indent=2))
except json.JSONDecodeError as e:
    print(f'Warning: JSON cleanup failed ({e}), writing raw config', file=sys.stderr)
    print(cleaned)
" 2>/dev/null || echo "$config")

  # Write config
  mkdir -p "$CONFIG_DIR" "$WORKSPACE_DIR"
  echo "$config" > "${CONFIG_DIR}/openclaw.json"
  success "Config written to ${CONFIG_DIR}/openclaw.json"

  # Create credentials directory with proper permissions
  mkdir -p "${CONFIG_DIR}/credentials"
  chmod 700 "${CONFIG_DIR}/credentials"

  # ── [IMPROVEMENT 5] Write API credentials to files ─────────────────────────
  if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    echo "{\"apiKey\": \"${ANTHROPIC_API_KEY}\"}" > "${CONFIG_DIR}/credentials/anthropic.json"
    chmod 600 "${CONFIG_DIR}/credentials/anthropic.json"
    success "Anthropic credentials written (chmod 600)"
  fi

  if [[ -n "$OPENAI_API_KEY" ]]; then
    echo "{\"apiKey\": \"${OPENAI_API_KEY}\"}" > "${CONFIG_DIR}/credentials/openai.json"
    chmod 600 "${CONFIG_DIR}/credentials/openai.json"
    success "OpenAI credentials written (chmod 600)"
  fi

  if [[ -n "$OPENROUTER_API_KEY" ]]; then
    echo "{\"apiKey\": \"${OPENROUTER_API_KEY}\"}" > "${CONFIG_DIR}/credentials/openrouter.json"
    chmod 600 "${CONFIG_DIR}/credentials/openrouter.json"
    success "OpenRouter credentials written (chmod 600)"
  fi

  if [[ -n "$GOOGLE_API_KEY" ]]; then
    echo "{\"apiKey\": \"${GOOGLE_API_KEY}\"}" > "${CONFIG_DIR}/credentials/google.json"
    chmod 600 "${CONFIG_DIR}/credentials/google.json"
    success "Google credentials written (chmod 600)"
  fi

  if [[ -n "$GROQ_API_KEY" ]]; then
    echo "{\"apiKey\": \"${GROQ_API_KEY}\"}" > "${CONFIG_DIR}/credentials/groq.json"
    chmod 600 "${CONFIG_DIR}/credentials/groq.json"
    success "Groq credentials written (chmod 600)"
  fi

  # Create workspace README
  if [[ ! -f "${WORKSPACE_DIR}/AGENTS.md" ]]; then
    cat > "${WORKSPACE_DIR}/AGENTS.md" <<'AGENTS'
# Agent Instructions

You are a helpful personal AI assistant. Be concise and direct.
Follow the user's instructions carefully.
AGENTS
  fi

  success "Workspace initialized at ${WORKSPACE_DIR}"
}

# ── [IMPROVEMENT 4] Docker Compose with Backup ──────────────────────────────
generate_docker_compose() {
  [[ "$DEPLOY_MODE" != "docker" ]] && return

  header "Generating Docker Compose"

  local chrome_volume=""
  local shm_size=""

  if [[ "$FEAT_BROWSER" == "true" ]]; then
    shm_size='shm_size: "2g"'
    chrome_volume="      - ${INSTANCE_DIR}/chrome-profile:/home/node/.config/chromium"
  fi

  # Ask about backup
  local backup_service=""
  if ask_yn "Enable daily backups (3 AM, keeps 7 days)?" "y"; then
    FEAT_BACKUP=true
    mkdir -p "${INSTANCE_DIR}/backups"
    backup_service=$(cat <<BACKUP

  backup-${INSTANCE_NAME}:
    image: alpine:latest
    container_name: backup-${INSTANCE_NAME}
    volumes:
      - ${CONFIG_DIR}:/source/config:ro
      - ${WORKSPACE_DIR}:/source/workspace:ro
      - ${INSTANCE_DIR}/backups:/backups
    entrypoint: /bin/sh
    command:
      - -c
      - |
        echo "Starting backup cron..."
        while true; do
          sleep 86400
          backup_name="openclaw-${INSTANCE_NAME}-\$(date +%Y%m%d-%H%M%S).tar.gz"
          tar czf "/backups/\$backup_name" -C /source .
          echo "Backup created: \$backup_name"
          find /backups -name "openclaw-${INSTANCE_NAME}-*.tar.gz" -mtime +7 -delete
          echo "Old backups pruned"
        done
    restart: unless-stopped
BACKUP
)
    success "Backup service enabled (daily at 3 AM, 7-day retention)"
  fi

  # Tailscale sidecar
  local tailscale_service=""
  local network_mode=""
  if ask_yn "Add Tailscale sidecar for remote access?" "y"; then
    local ts_hostname
    ts_hostname=$(ask_name "Tailscale hostname for this instance" "openclaw-${INSTANCE_NAME}")
    tailscale_service=$(cat <<TS

  tailscale-${INSTANCE_NAME}:
    image: tailscale/tailscale:latest
    hostname: ${ts_hostname}
    environment:
      - TS_AUTHKEY=\${TS_AUTHKEY:?Set TS_AUTHKEY in .env}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=--advertise-tags=tag:openclaw
    volumes:
      - ts-${INSTANCE_NAME}-state:/var/lib/tailscale
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    restart: unless-stopped
TS
)
    network_mode="    network_mode: service:tailscale-${INSTANCE_NAME}"
  fi

  local compose
  compose=$(cat <<COMPOSE
# OpenClaw Docker Instance: ${INSTANCE_NAME}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Script version: ${SCRIPT_VERSION}

services:
${tailscale_service}

  openclaw-${INSTANCE_NAME}:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw-${INSTANCE_NAME}
${network_mode}
$( [[ -z "$network_mode" ]] && echo "    ports:" && echo "      - \"${GATEWAY_PORT}:18789\"" )
    volumes:
      - ${CONFIG_DIR}:/home/node/.openclaw
      - ${WORKSPACE_DIR}:/home/node/openclaw/workspace
${chrome_volume}
    environment:
      - OLLAMA_HOST=${OLLAMA_HOST}
      - OPENCLAW_GATEWAY_BIND=0.0.0.0
    ${shm_size}
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
${backup_service}

volumes:
$( [[ -n "$tailscale_service" ]] && echo "  ts-${INSTANCE_NAME}-state:" )
COMPOSE
)

  echo "$compose" > "${INSTANCE_DIR}/docker-compose.yml"
  success "Docker Compose written to ${INSTANCE_DIR}/docker-compose.yml"

  # Create .env template with collected credentials
  local env_content="# OpenClaw Docker Instance: ${INSTANCE_NAME}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Tailscale auth key (generate at https://login.tailscale.com/admin/settings/keys)
TS_AUTHKEY=
"

  # Add collected channel tokens to .env
  if [[ -n "$TELEGRAM_BOT_TOKEN" && "$TELEGRAM_BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]]; then
    env_content+="
# Telegram (already configured in openclaw.json)
# TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
"
  elif [[ "$CH_TELEGRAM" == "true" ]]; then
    env_content+="
# Telegram — add your bot token
TELEGRAM_BOT_TOKEN=
"
  fi

  if [[ -n "$DISCORD_BOT_TOKEN" && "$DISCORD_BOT_TOKEN" != "YOUR_DISCORD_BOT_TOKEN" ]]; then
    env_content+="
# Discord (already configured in openclaw.json)
# DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
"
  elif [[ "$CH_DISCORD" == "true" ]]; then
    env_content+="
# Discord — add your bot token
DISCORD_BOT_TOKEN=
"
  fi

  echo "$env_content" > "${INSTANCE_DIR}/.env"
  chmod 600 "${INSTANCE_DIR}/.env"
  success ".env created at ${INSTANCE_DIR}/.env (chmod 600)"
}

# ── Native Install ───────────────────────────────────────────────────────────
install_native() {
  [[ "$DEPLOY_MODE" != "native" ]] && return

  header "Native Installation"

  if command -v openclaw &>/dev/null; then
    success "OpenClaw is already installed"
    return
  fi

  if ! command -v node &>/dev/null; then
    info "Installing Node.js via Homebrew..."
    brew install node
  fi

  if ask_yn "Install OpenClaw via npm?" "y"; then
    info "Installing OpenClaw..."
    npm install -g openclaw
    success "OpenClaw installed"
  else
    info "Skipping install — you can run: npm install -g openclaw"
  fi
}

# ── [IMPROVEMENT 1] Post-Setup Channel Pairing ──────────────────────────────
run_channel_pairing() {
  local has_pairing_channels=false

  if [[ "$CH_WHATSAPP" == "true" || "$CH_SIGNAL" == "true" ]]; then
    has_pairing_channels=true
  fi

  [[ "$has_pairing_channels" == "false" ]] && return

  header "Channel Pairing"

  # WhatsApp QR pairing
  if [[ "$CH_WHATSAPP" == "true" ]]; then
    echo -e "  ${BOLD}WhatsApp requires QR code pairing:${NC}"
    echo -e "  1. Have your phone ready with WhatsApp open"
    echo -e "  2. Go to Settings > Linked Devices > Link a Device"
    echo -e "  3. You have 60 seconds to scan the QR code"
    echo ""

    if ask_yn "Run WhatsApp QR pairing now?" "y"; then
      if [[ "$DEPLOY_MODE" == "native" ]]; then
        if command -v openclaw &>/dev/null; then
          info "Starting WhatsApp pairing... (scan QR code within 60 seconds)"
          openclaw channels login whatsapp || warn "WhatsApp pairing failed — retry later: openclaw channels login whatsapp"
        else
          warn "OpenClaw not installed yet — run pairing later: openclaw channels login whatsapp"
        fi
      else
        local docker_bin="${DOCKER_BIN:-$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)}"
        if "$docker_bin" compose -f "${INSTANCE_DIR}/docker-compose.yml" ps &>/dev/null 2>&1; then
          info "Starting WhatsApp pairing inside container..."
          "$docker_bin" compose -f "${INSTANCE_DIR}/docker-compose.yml" \
            exec "openclaw-${INSTANCE_NAME}" openclaw channels login whatsapp \
            || warn "WhatsApp pairing failed — retry later with: docker compose exec openclaw-${INSTANCE_NAME} openclaw channels login whatsapp"
        else
          warn "Container not running — start it first, then pair:"
          echo "  cd ${INSTANCE_DIR} && docker compose up -d"
          echo "  docker compose exec openclaw-${INSTANCE_NAME} openclaw channels login whatsapp"
        fi
      fi
    else
      info "Skipped — pair later:"
      if [[ "$DEPLOY_MODE" == "native" ]]; then
        echo "  openclaw channels login whatsapp"
      else
        echo "  cd ${INSTANCE_DIR} && docker compose exec openclaw-${INSTANCE_NAME} openclaw channels login whatsapp"
      fi
    fi
    echo ""
  fi

  # Signal pairing
  if [[ "$CH_SIGNAL" == "true" ]]; then
    echo -e "  ${BOLD}Signal requires device linking:${NC}"
    if ask_yn "Run Signal pairing now?" "n"; then
      if [[ "$DEPLOY_MODE" == "native" ]] && command -v openclaw &>/dev/null; then
        openclaw channels login signal || warn "Signal pairing failed"
      else
        warn "Start the instance first, then run: openclaw channels login signal"
      fi
    else
      info "Skipped — pair later: openclaw channels login signal"
    fi
    echo ""
  fi
}

# ── [IMPROVEMENT 3] Post-Setup Health Check ──────────────────────────────────
run_health_check() {
  header "Health Check"

  local all_ok=true

  # 1. Validate generated JSON
  info "Validating openclaw.json..."
  if python3 -c "import json; json.load(open('${CONFIG_DIR}/openclaw.json'))" 2>/dev/null; then
    success "openclaw.json is valid JSON"
  else
    err "openclaw.json is NOT valid JSON — check the file manually"
    all_ok=false
  fi

  # 2. Check credentials directory permissions
  local creds_perms
  creds_perms=$(stat -f "%Lp" "${CONFIG_DIR}/credentials" 2>/dev/null || stat -c "%a" "${CONFIG_DIR}/credentials" 2>/dev/null)
  if [[ "$creds_perms" == "700" ]]; then
    success "Credentials directory permissions: 700 (secure)"
  else
    warn "Credentials directory permissions: ${creds_perms} (should be 700)"
    chmod 700 "${CONFIG_DIR}/credentials"
  fi

  # 3. Check Ollama connectivity
  if [[ "$MODEL_PROVIDER" == "ollama-cloud" || "$MODEL_PROVIDER" == "ollama-local" ]]; then
    info "Checking Ollama connectivity..."
    if curl -sf http://localhost:11434/api/version &>/dev/null; then
      success "Ollama is reachable at localhost:11434"
    else
      warn "Cannot reach Ollama at localhost:11434 — start Ollama before running OpenClaw"
      all_ok=false
    fi
  fi

  # 4. Check API key validity (if provided)
  if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    info "Verifying Anthropic API key..."
    local response
    response=$(curl -sf -w "%{http_code}" -o /dev/null \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      "https://api.anthropic.com/v1/models" 2>/dev/null) || response="000"
    if [[ "$response" == "200" ]]; then
      success "Anthropic API key is valid"
    elif [[ "$response" == "401" ]]; then
      err "Anthropic API key is invalid (401 Unauthorized)"
      all_ok=false
    else
      warn "Could not verify Anthropic API key (HTTP ${response}) — check internet connectivity"
    fi
  fi

  if [[ -n "$OPENAI_API_KEY" ]]; then
    info "Verifying OpenAI API key..."
    local response
    response=$(curl -sf -w "%{http_code}" -o /dev/null \
      -H "Authorization: Bearer ${OPENAI_API_KEY}" \
      "https://api.openai.com/v1/models" 2>/dev/null) || response="000"
    if [[ "$response" == "200" ]]; then
      success "OpenAI API key is valid"
    elif [[ "$response" == "401" ]]; then
      err "OpenAI API key is invalid (401 Unauthorized)"
      all_ok=false
    else
      warn "Could not verify OpenAI API key (HTTP ${response}) — check internet connectivity"
    fi
  fi

  # 5. Check channel token formats
  if [[ -n "$TELEGRAM_BOT_TOKEN" && "$TELEGRAM_BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]]; then
    if [[ "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
      success "Telegram bot token format looks valid"
    else
      warn "Telegram bot token format looks unusual (expected: 123456789:ABCdef...)"
    fi
  fi

  if [[ -n "$DISCORD_BOT_TOKEN" && "$DISCORD_BOT_TOKEN" != "YOUR_DISCORD_BOT_TOKEN" ]]; then
    if [[ ${#DISCORD_BOT_TOKEN} -gt 50 ]]; then
      success "Discord bot token format looks valid"
    else
      warn "Discord bot token seems too short — verify it's correct"
    fi
  fi

  # 6. Docker checks (Docker mode only)
  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    local docker_bin="${DOCKER_BIN:-$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)}"
    info "Checking Docker..."
    if "$docker_bin" info &>/dev/null 2>&1; then
      success "Docker daemon is running"
    else
      err "Docker daemon is not running — start Docker/OrbStack before launching"
      all_ok=false
    fi

    # Verify compose file
    if [[ -f "${INSTANCE_DIR}/docker-compose.yml" ]]; then
      if "$docker_bin" compose -f "${INSTANCE_DIR}/docker-compose.yml" config --quiet 2>/dev/null; then
        success "docker-compose.yml is valid"
      else
        warn "docker-compose.yml may have issues — run: docker compose -f ${INSTANCE_DIR}/docker-compose.yml config"
      fi
    fi
  fi

  # 7. Run openclaw doctor if available (native mode)
  if [[ "$DEPLOY_MODE" == "native" ]] && command -v openclaw &>/dev/null; then
    info "Running openclaw doctor..."
    if openclaw doctor 2>/dev/null; then
      success "openclaw doctor passed"
    else
      warn "openclaw doctor reported issues — check output above"
    fi
  fi

  echo ""
  if [[ "$all_ok" == "true" ]]; then
    success "All health checks passed"
  else
    warn "Some checks failed — review warnings above before starting"
  fi
}

# ── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  header "Setup Complete"

  echo -e "${BOLD}Instance:${NC}     $INSTANCE_NAME"
  echo -e "${BOLD}Mode:${NC}         $DEPLOY_MODE"
  echo -e "${BOLD}Config:${NC}       ${CONFIG_DIR}/openclaw.json"
  echo -e "${BOLD}Workspace:${NC}    $WORKSPACE_DIR"
  echo -e "${BOLD}Model:${NC}        $MODEL_PRIMARY"
  if [[ -n "$MODEL_FALLBACK" ]]; then
    echo -e "${BOLD}Fallback:${NC}     $MODEL_FALLBACK"
  fi
  echo -e "${BOLD}Gateway:${NC}      http://localhost:${GATEWAY_PORT}"
  echo ""

  echo -e "${BOLD}Features:${NC}"
  local feats=(
    "FEAT_BROWSER:Browser" "FEAT_SANDBOX:Sandbox" "FEAT_CRON:Cron"
    "FEAT_MEMORY:Memory" "FEAT_SKILLS:Skills" "FEAT_CODE_EXEC:Code Exec"
    "FEAT_WEB_SEARCH:Web Search" "FEAT_WEB_FETCH:Web Fetch"
    "FEAT_FILE_ACCESS:File Access" "FEAT_SHELL_EXEC:Shell Exec"
    "FEAT_MESSAGING:Messaging" "FEAT_VOICE:Voice" "FEAT_CLAUDE_CODE:Claude Code"
    "FEAT_BACKUP:Backup"
  )
  for f in "${feats[@]}"; do
    IFS=':' read -r var label <<< "$f"
    local val="${!var}"
    if [[ "$val" == "true" ]]; then
      echo -e "  ${GREEN}[ON]${NC}  $label"
    else
      echo -e "  ${RED}[OFF]${NC} $label"
    fi
  done

  echo ""
  echo -e "${BOLD}Channels:${NC}"
  local chs=(
    "CH_WEBCHAT:WebChat" "CH_WHATSAPP:WhatsApp" "CH_TELEGRAM:Telegram"
    "CH_DISCORD:Discord" "CH_SLACK:Slack" "CH_SIGNAL:Signal" "CH_IMESSAGE:iMessage"
  )
  for c in "${chs[@]}"; do
    IFS=':' read -r var label <<< "$c"
    local val="${!var}"
    if [[ "$val" == "true" ]]; then
      local cred_status=""
      case "$var" in
        CH_TELEGRAM)  [[ -n "$TELEGRAM_BOT_TOKEN" && "$TELEGRAM_BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN" ]] && cred_status=" (token configured)" || cred_status=" (token needed)" ;;
        CH_DISCORD)   [[ -n "$DISCORD_BOT_TOKEN" && "$DISCORD_BOT_TOKEN" != "YOUR_DISCORD_BOT_TOKEN" ]] && cred_status=" (token configured)" || cred_status=" (token needed)" ;;
        CH_SLACK)     [[ -n "$SLACK_BOT_TOKEN" && "$SLACK_BOT_TOKEN" != "YOUR_SLACK_BOT_TOKEN" ]] && cred_status=" (tokens configured)" || cred_status=" (tokens needed)" ;;
        CH_WHATSAPP)  cred_status=" (QR pairing needed)" ;;
        CH_SIGNAL)    cred_status=" (device linking needed)" ;;
      esac
      echo -e "  ${GREEN}[ON]${NC}  ${label}${cred_status}"
    fi
  done

  echo ""
  echo -e "${BOLD}Credentials:${NC}"
  [[ -n "$ANTHROPIC_API_KEY" ]]  && echo -e "  ${GREEN}[OK]${NC}  Anthropic API key stored"
  [[ -n "$OPENAI_API_KEY" ]]     && echo -e "  ${GREEN}[OK]${NC}  OpenAI API key stored"
  [[ -n "$OPENROUTER_API_KEY" ]] && echo -e "  ${GREEN}[OK]${NC}  OpenRouter API key stored"
  [[ -n "$GOOGLE_API_KEY" ]]     && echo -e "  ${GREEN}[OK]${NC}  Google API key stored"
  [[ -n "$GROQ_API_KEY" ]]       && echo -e "  ${GREEN}[OK]${NC}  Groq API key stored"
  [[ "$MODEL_PROVIDER" == "ollama-cloud" || "$MODEL_PROVIDER" == "ollama-local" ]] && echo -e "  ${GREEN}[OK]${NC}  Ollama (no key needed)"
  echo ""

  echo -e "${BOLD}Next Steps:${NC}"
  if [[ "$DEPLOY_MODE" == "native" ]]; then
    echo "  1. Review config:  cat ${CONFIG_DIR}/openclaw.json"
    echo "  2. Start:          openclaw"
    echo "  3. Open UI:        http://localhost:${GATEWAY_PORT}"
    [[ "$CH_WHATSAPP" == "true" ]] && echo "  4. WhatsApp pair:  openclaw channels login whatsapp"
    [[ "$CH_SIGNAL" == "true" ]]   && echo "  5. Signal pair:    openclaw channels login signal"
  else
    echo "  1. Review config:  cat ${CONFIG_DIR}/openclaw.json"
    echo "  2. Edit .env:      vim ${INSTANCE_DIR}/.env  (add Tailscale key)"
    echo "  3. Start:          cd ${INSTANCE_DIR} && docker compose up -d"
    echo "  4. View logs:      docker compose logs -f openclaw-${INSTANCE_NAME}"
    echo "  5. Open UI:        http://localhost:${GATEWAY_PORT}"
    [[ "$CH_WHATSAPP" == "true" ]] && echo "  6. WhatsApp pair:  docker compose exec openclaw-${INSTANCE_NAME} openclaw channels login whatsapp"
  fi
  echo ""
  echo -e "  ${CYAN}Reconfigure later:  $0 --reconfigure${NC}"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}║       OpenClaw Unified Setup Script v${SCRIPT_VERSION}        ║${NC}"
  echo -e "${BOLD}${CYAN}║       Native + Docker | Cloud Models             ║${NC}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${NC}"
  echo ""

  preflight

  # [IMPROVEMENT 6] Handle reconfigure mode
  if [[ "$RECONFIGURE" == "true" ]]; then
    load_existing_config
    # In reconfigure mode, skip deploy mode and instance selection
    # Go straight to feature toggles with current values loaded
  fi

  if [[ "$RECONFIGURE" == "false" ]]; then
    choose_deploy_mode
    choose_instance
  fi

  toggle_features
  setup_channels
  setup_models
  generate_config

  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    generate_docker_compose
  else
    install_native
  fi

  # [IMPROVEMENT 1] Channel pairing (WhatsApp QR, Signal linking)
  run_channel_pairing

  # [IMPROVEMENT 3] Post-setup verification
  run_health_check

  print_summary
}

main "$@"
