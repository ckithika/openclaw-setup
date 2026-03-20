#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# OpenClaw Unified Setup Script v3
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
#
# v3 New Features (Unified Brain):
#   7. Obsidian vault — single source of truth for all knowledge
#   8. Claude knowledge sync — web + Code sessions into vault
#   9. Auto-tagging taxonomy — consistent tags across all sources
#  10. GitHub backup — private repo + multi-Mac sync via launchd
#  11. Mem0 external memory — survives context compaction
#  12. Cognee knowledge graph — relationship search across vault
#  13. Skills bundles — productivity, social, research, security, comms
#  14. Granola meeting notes — auto-sync into vault
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_VERSION="3.0.0"
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
  local _eof=false
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt}${hint}: " >&2
    read -r answer || _eof=true
    answer="${answer:-$default}"
    if [[ "$_eof" == "true" && -z "$answer" ]]; then
      echo "$default"
      return
    fi
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
  local _eof=false
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt}${hint}: " >&2
    read -r answer || _eof=true
    answer="${answer:-$default}"
    if [[ "$_eof" == "true" && -z "$answer" ]]; then echo "$default"; return; fi
    if validate_name "$answer" "$prompt"; then
      echo "$answer"
      return
    fi
    echo -e "  ${RED}Invalid name, try again${NC}" >&2
  done
}

ask_port() {
  local prompt="$1" default="${2:-18789}"
  local _eof=false
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt} (default: $default): " >&2
    read -r answer || _eof=true
    answer="${answer:-$default}"
    if [[ "$_eof" == "true" ]]; then echo "$default"; return; fi
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
  local _eof=false
  while true; do
    echo -ne "${YELLOW}?${NC} ${prompt}${hint}: " >&2
    read -r answer || _eof=true
    answer="${answer:-$default}"
    if [[ "$_eof" == "true" && -z "$answer" ]]; then echo "$default"; return; fi
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

# Interactive multi-select with arrow keys and spacebar
# Usage: multi_select "label1:var1:val1" "label2:var2:val2" ...
# Sets the named variables to "true" or "false" based on selection
multi_select() {
  local items=("$@")
  local count=${#items[@]}
  local cursor=0

  # Parse items into parallel arrays
  local labels=() varnames=() selected=()
  for item in "${items[@]}"; do
    IFS=':' read -r varname label val <<< "$item"
    labels+=("$label")
    varnames+=("$varname")
    if [[ "$val" == "true" ]]; then
      selected+=(1)
    else
      selected+=(0)
    fi
  done

  # Hide cursor
  printf '\e[?25l' >&2

  # Draw initial list
  for i in "${!labels[@]}"; do
    local check=" "; [[ "${selected[$i]}" -eq 1 ]] && check="x"
    local pointer="  "; [[ $i -eq $cursor ]] && pointer="${CYAN}> ${NC}"
    printf '%b[%s] %s\n' "$pointer" "$check" "${labels[$i]}" >&2
  done

  # Input loop
  while true; do
    # Read a keypress
    local key=""
    IFS= read -rsn1 key 2>/dev/null || true

    if [[ "$key" == $'\x1b' ]]; then
      # Escape sequence — read next 2 chars
      local seq=""
      IFS= read -rsn2 seq 2>/dev/null || true
      case "$seq" in
        '[A') # Up arrow
          (( cursor > 0 )) && (( cursor-- ))
          ;;
        '[B') # Down arrow
          (( cursor < count - 1 )) && (( cursor++ ))
          ;;
      esac
    elif [[ "$key" == " " ]]; then
      # Spacebar — toggle selection
      if [[ "${selected[$cursor]}" -eq 1 ]]; then
        selected[$cursor]=0
      else
        selected[$cursor]=1
      fi
    elif [[ "$key" == "" ]]; then
      # Enter — confirm
      break
    fi

    # Redraw — move cursor up by $count lines and redraw
    printf '\e[%dA' "$count" >&2
    for i in "${!labels[@]}"; do
      local check=" "; [[ "${selected[$i]}" -eq 1 ]] && check="${GREEN}x${NC}"
      local pointer="  "; [[ $i -eq $cursor ]] && pointer="${CYAN}> ${NC}"
      printf '\r\e[K%b[%b] %s\n' "$pointer" "$check" "${labels[$i]}" >&2
    done
  done

  # Show cursor
  printf '\e[?25h' >&2

  # Apply selections to variables
  for i in "${!varnames[@]}"; do
    if [[ "${selected[$i]}" -eq 1 ]]; then
      eval "${varnames[$i]}=true"
    else
      eval "${varnames[$i]}=false"
    fi
  done

}

# ── Defaults ─────────────────────────────────────────────────────────────────
DEPLOY_MODE=""          # native | docker
INSTANCE_NAME=""
INSTANCE_DIR=""
CONFIG_DIR=""
WORKSPACE_DIR=""
GATEWAY_PORT=18789
OLLAMA_HOST="http://localhost:11434"

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
FEAT_GOOGLE_WORKSPACE=false

# Persona config
AGENT_NAME=""
AGENT_VIBE=""
AGENT_PURPOSE=""
USER_NAME=""
USER_TIMEZONE=""
PRESET_NAME=""

# Google Workspace config
GOOGLE_WS_METHOD=""          # gog | mcp | oauth
GOOGLE_WS_SERVICES=()
GOOGLE_WS_EMAIL=""

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

# v3: Unified Brain
FEAT_OBSIDIAN_VAULT=false
FEAT_CLAUDE_SYNC=false
FEAT_TAG_TAXONOMY=false
FEAT_GITHUB_BACKUP=false
FEAT_MEM0=false
FEAT_COGNEE=false
FEAT_SKILLS_PRODUCTIVITY=false
FEAT_SKILLS_SOCIAL=false
FEAT_SKILLS_RESEARCH=false
FEAT_SKILLS_SECURITY=false
FEAT_SKILLS_COMMS=false
FEAT_GRANOLA=false

# Obsidian vault
VAULT_PATH=""
VAULT_IS_NEW=true

# Tag taxonomy
TAG_LIFE_AREAS=()
TAG_PROJECTS=()

# GitHub backup
GITHUB_BRAIN_REPO=""
GITHUB_BRAIN_EXISTS=false
FEAT_GIT_CRYPT=false

# Claude sync
CLAUDE_RETENTION_FIXED=false

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

  # Check Node.js (native only — Docker image includes it)
  if [[ "$DEPLOY_MODE" != "docker" ]]; then
    if command -v node &>/dev/null; then
      success "Node.js $(node --version) found"
    else
      warn "Node.js not found — required for native install"
    fi
  fi

  # Check jq (native only — Docker image includes it)
  if [[ "$DEPLOY_MODE" != "docker" ]]; then
    if ! command -v jq &>/dev/null; then
      warn "jq not found — installing via Homebrew"
      if command -v brew &>/dev/null; then
        brew install jq --quiet
      else
        die "jq is required but Homebrew is not available to install it"
      fi
    fi
  else
    # Ensure jq is available on the host for config generation
    if ! command -v jq &>/dev/null; then
      if command -v brew &>/dev/null; then
        brew install jq --quiet
      elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y jq 2>/dev/null || die "jq is required — install it manually"
      else
        die "jq is required — install it manually"
      fi
    fi
  fi

  # Check available RAM (macOS native only)
  if [[ "$(uname)" == "Darwin" ]]; then
    local ram_gb
    ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    info "RAM: ${ram_gb}GB unified memory"
    if (( ram_gb < 16 )); then
      warn "Less than 16GB RAM — limit concurrent instances"
    fi
  fi

  # Check disk space (portable)
  local avail_gb
  if [[ "$(uname)" == "Darwin" ]]; then
    avail_gb=$(df -g / | awk 'NR==2 {print $4}')
  else
    avail_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
  fi
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
  # webchat is auto-detected by the image — no config needed
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

  # Restore v3 plugin toggles (Mem0, Cognee)
  local mem0_enabled
  mem0_enabled=$(echo "$cfg" | jq -r '.plugins.mem0.enabled // false' 2>/dev/null)
  [[ "$mem0_enabled" == "true" ]] && FEAT_MEM0=true || FEAT_MEM0=false

  local cognee_enabled
  cognee_enabled=$(echo "$cfg" | jq -r '.plugins.cognee.enabled // false' 2>/dev/null)
  [[ "$cognee_enabled" == "true" ]] && FEAT_COGNEE=true || FEAT_COGNEE=false

  # Restore v3 session flags
  local memory_flush_enabled
  memory_flush_enabled=$(echo "$cfg" | jq -r '.session.memoryFlush.enabled // false' 2>/dev/null)
  # memoryFlush is always enabled in v3; no separate toggle needed

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

# ── Feature Presets ─────────────────────────────────────────────────────────
apply_preset() {
  local preset="$1"
  case "$preset" in
    personal-assistant)
      # Non-technical: messaging, calendar, email, web, memory — no code/shell/sandbox
      FEAT_BROWSER=true
      FEAT_SANDBOX=false
      FEAT_CRON=true
      FEAT_MEMORY=true
      FEAT_SKILLS=true
      FEAT_CODE_EXEC=false
      FEAT_WEB_SEARCH=true
      FEAT_WEB_FETCH=true
      FEAT_FILE_ACCESS=false
      FEAT_SHELL_EXEC=false
      FEAT_MESSAGING=true
      FEAT_VOICE=false
      FEAT_CLAUDE_CODE=false
      FEAT_GOOGLE_WORKSPACE=true
      FEAT_OBSIDIAN_VAULT=true
      FEAT_CLAUDE_SYNC=false
      FEAT_TAG_TAXONOMY=false
      FEAT_GITHUB_BACKUP=false
      FEAT_MEM0=false
      FEAT_COGNEE=false
      FEAT_SKILLS_PRODUCTIVITY=false
      FEAT_SKILLS_SOCIAL=false
      FEAT_SKILLS_RESEARCH=true
      FEAT_SKILLS_SECURITY=false
      FEAT_SKILLS_COMMS=true
      FEAT_GRANOLA=true
      ;;
    developer)
      # Full-stack developer: all code tools, shell, sandbox, file access
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
      FEAT_CLAUDE_CODE=true
      FEAT_GOOGLE_WORKSPACE=false
      FEAT_OBSIDIAN_VAULT=true
      FEAT_CLAUDE_SYNC=true
      FEAT_TAG_TAXONOMY=false
      FEAT_GITHUB_BACKUP=true
      FEAT_MEM0=false
      FEAT_COGNEE=false
      FEAT_SKILLS_PRODUCTIVITY=true
      FEAT_SKILLS_SOCIAL=false
      FEAT_SKILLS_RESEARCH=true
      FEAT_SKILLS_SECURITY=true
      FEAT_SKILLS_COMMS=false
      FEAT_GRANOLA=false
      ;;
    autonomous-agent)
      # Autonomous SaaS agent: everything on for maximum capability
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
      FEAT_CLAUDE_CODE=true
      FEAT_GOOGLE_WORKSPACE=true
      FEAT_OBSIDIAN_VAULT=true
      FEAT_CLAUDE_SYNC=false
      FEAT_TAG_TAXONOMY=true
      FEAT_GITHUB_BACKUP=true
      FEAT_MEM0=false
      FEAT_COGNEE=false
      FEAT_SKILLS_PRODUCTIVITY=true
      FEAT_SKILLS_SOCIAL=true
      FEAT_SKILLS_RESEARCH=true
      FEAT_SKILLS_SECURITY=true
      FEAT_SKILLS_COMMS=true
      FEAT_GRANOLA=false
      ;;
    custom)
      # Keep defaults, user will toggle individually
      ;;
  esac
}

# ── Feature Toggle Menu ─────────────────────────────────────────────────────
toggle_features() {
  header "Feature Toggles"

  # Offer presets first
  echo -e "  ${BOLD}Choose a preset to get started, then customize:${NC}\n"
  echo -e "  ${BOLD}personal-assistant${NC}  — Messaging, email, calendar, web search, memory."
  echo -e "                        No coding tools, shell access, or sandboxing."
  echo -e "                        ${CYAN}Best for: non-technical users who want a smart daily assistant.${NC}\n"
  echo -e "  ${BOLD}developer${NC}           — Full coding environment: shell, file access, sandbox,"
  echo -e "                        Claude Code, GitHub backup."
  echo -e "                        ${CYAN}Best for: software engineers and technical users.${NC}\n"
  echo -e "  ${BOLD}autonomous-agent${NC}    — Everything enabled. Code, social media, email, browser,"
  echo -e "                        cron jobs, all skills."
  echo -e "                        ${CYAN}Best for: autonomous SaaS agents that run a product.${NC}\n"
  echo -e "  ${BOLD}custom${NC}              — Start from defaults and toggle each feature manually.\n"

  local preset
  preset=$(ask_choice "Select a preset:" "personal-assistant" "developer" "autonomous-agent" "custom")
  PRESET_NAME="$preset"
  apply_preset "$preset"
  success "Preset applied: $preset"
  echo ""

  if ! ask_yn "Customize individual features?" "n"; then
    # Skip individual toggles, apply Docker overrides and return
    # Docker-specific overrides
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
      [[ "$FEAT_VOICE" == "true" ]] && { warn "Voice/TTS disabled — not available in Docker containers"; FEAT_VOICE=false; }
      info "Sandbox auto-enabled — agent is already running in a Docker container"
      FEAT_SANDBOX=true
    fi
    success "Features configured"
    return
  fi

  echo -e "  Use ${BOLD}↑/↓${NC} to navigate, ${BOLD}Space${NC} to toggle, ${BOLD}Enter${NC} to confirm.\n"

  local features=(
    "FEAT_BROWSER:Browser automation (Chromium CDP):$FEAT_BROWSER"
  )

  # Sandbox toggle only for native — Docker is already sandboxed
  if [[ "$DEPLOY_MODE" != "docker" ]]; then
    features+=("FEAT_SANDBOX:Sandbox (Docker-based tool isolation):$FEAT_SANDBOX")
  fi

  features+=(
    "FEAT_CRON:Cron jobs (scheduled tasks):$FEAT_CRON"
    "FEAT_MEMORY:Persistent memory (cross-session):$FEAT_MEMORY"
    "FEAT_SKILLS:Skills marketplace (ClawHub):$FEAT_SKILLS"
    "FEAT_CODE_EXEC:Code execution (Python/Node.js):$FEAT_CODE_EXEC"
    "FEAT_WEB_SEARCH:Web search:$FEAT_WEB_SEARCH"
    "FEAT_WEB_FETCH:Web fetch (read pages):$FEAT_WEB_FETCH"
    "FEAT_FILE_ACCESS:File read/write access:$FEAT_FILE_ACCESS"
    "FEAT_SHELL_EXEC:Shell command execution:$FEAT_SHELL_EXEC"
    "FEAT_MESSAGING:Cross-session messaging:$FEAT_MESSAGING"
  )

  # Voice only for native — not available in Docker
  if [[ "$DEPLOY_MODE" != "docker" ]]; then
    features+=("FEAT_VOICE:Voice/TTS (macOS native only):$FEAT_VOICE")
  fi

  features+=(
    "FEAT_CLAUDE_CODE:Claude Code integration (ACP):$FEAT_CLAUDE_CODE"
    "FEAT_GOOGLE_WORKSPACE:Google Workspace (Gmail, Calendar, Drive):$FEAT_GOOGLE_WORKSPACE"
    "FEAT_OBSIDIAN_VAULT:Obsidian unified brain (single source of truth):$FEAT_OBSIDIAN_VAULT"
  )

  # Claude Sync: session retention + symlinks are native-only
  if [[ "$DEPLOY_MODE" != "docker" ]]; then
    features+=("FEAT_CLAUDE_SYNC:Claude knowledge sync (web + Code sessions):$FEAT_CLAUDE_SYNC")
  fi

  features+=(
    "FEAT_TAG_TAXONOMY:Auto-tagging taxonomy system:$FEAT_TAG_TAXONOMY"
    "FEAT_GITHUB_BACKUP:GitHub private repo backup + sync:$FEAT_GITHUB_BACKUP"
    "FEAT_MEM0:Mem0 external memory (survives compaction):$FEAT_MEM0"
    "FEAT_COGNEE:Cognee knowledge graph (relationship search):$FEAT_COGNEE"
    "FEAT_SKILLS_PRODUCTIVITY:Skills: GitHub, Obsidian, Notion, Summarize:$FEAT_SKILLS_PRODUCTIVITY"
    "FEAT_SKILLS_SOCIAL:Skills: Upload-Post, Genviral, Mixpost:$FEAT_SKILLS_SOCIAL"
    "FEAT_SKILLS_RESEARCH:Skills: Tavily search:$FEAT_SKILLS_RESEARCH"
    "FEAT_SKILLS_SECURITY:Skills: SecureClaw:$FEAT_SKILLS_SECURITY"
    "FEAT_SKILLS_COMMS:Skills: AgentMail, Slack:$FEAT_SKILLS_COMMS"
    "FEAT_GRANOLA:Granola meeting notes sync:$FEAT_GRANOLA"
  )

  # Check if we have a TTY for interactive multi-select
  if [[ -t 0 ]]; then
    multi_select "${features[@]}"
  else
    # Non-interactive fallback (piped input) — use old y/N style
    for feat_line in "${features[@]}"; do
      IFS=':' read -r var_name description current_val <<< "$feat_line"
      local status_icon="ON "; [[ "$current_val" == "false" ]] && status_icon="OFF"
      printf "  [%s] %s" "$status_icon" "$description" >&2
      local toggle
      read -r toggle || true
      toggle=$(echo "$toggle" | tr '[:upper:]' '[:lower:]')
      if [[ "$toggle" == "y" ]]; then
        if [[ "$current_val" == "true" ]]; then eval "$var_name=false"
        else eval "$var_name=true"; fi
      fi
    done
  fi

  # Docker-specific overrides
  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    if [[ "$FEAT_VOICE" == "true" ]]; then
      warn "Voice/TTS disabled — not available in Docker containers"
      FEAT_VOICE=false
    fi
    # Sandbox is redundant in Docker — the agent is already containerized
    if [[ "$FEAT_SANDBOX" == "true" ]]; then
      info "Sandbox auto-enabled — agent is already running in a Docker container"
    fi
    FEAT_SANDBOX=true
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

# ── Google Workspace Setup ───────────────────────────────────────────────────
setup_google_workspace() {
  [[ "$FEAT_GOOGLE_WORKSPACE" != "true" ]] && return

  header "Google Workspace Integration"

  echo -e "  Connect OpenClaw to Gmail, Calendar, Drive, Contacts, and more.\n"
  echo -e "  ${BOLD}Integration methods:${NC}"
  echo -e "  ${BOLD}gog${NC}       — gogcli tool. Full control: Gmail, Calendar, Drive, Contacts,"
  echo -e "              Tasks, Sheets, Docs. OAuth via CLI. Best for power users."
  echo -e "  ${BOLD}mcp${NC}       — Google Workspace MCP. Zero Cloud Console setup. OAuth via"
  echo -e "              browser sign-in. Easiest option."
  echo -e "  ${BOLD}oauth${NC}     — Full custom OAuth via Google Cloud Console. Most control,"
  echo -e "              custom scopes. Best for Workspace admin accounts."
  echo ""

  GOOGLE_WS_METHOD=$(ask_choice "Select integration method:" "gog" "mcp" "oauth")
  success "Method: $GOOGLE_WS_METHOD"

  # ── Google account ──
  echo ""
  echo -e "  ${CYAN}Security recommendation:${NC} Use a ${BOLD}dedicated Google account${NC},"
  echo -e "  not your personal one. This isolates OpenClaw from your main data."
  echo ""

  GOOGLE_WS_EMAIL=$(ask_input "Google account email for this instance" "")

  # ── Service selection (gog and oauth methods) ──
  if [[ "$GOOGLE_WS_METHOD" == "gog" || "$GOOGLE_WS_METHOD" == "oauth" ]]; then
    echo ""
    echo -e "  ${BOLD}Select Google services to enable:${NC}"

    local services=(
      "gmail:Gmail (read, send, manage email)"
      "calendar:Google Calendar (events, scheduling)"
      "drive:Google Drive (files, folders)"
      "contacts:Google Contacts"
      "tasks:Google Tasks"
      "sheets:Google Sheets (read, write spreadsheets)"
      "docs:Google Docs (read, export documents)"
    )

    GOOGLE_WS_SERVICES=()
    for svc_line in "${services[@]}"; do
      IFS=':' read -r svc_id svc_desc <<< "$svc_line"
      # Default gmail, calendar, drive to yes
      local default="n"
      case "$svc_id" in
        gmail|calendar|drive) default="y" ;;
      esac
      if ask_yn "  $svc_desc" "$default"; then
        GOOGLE_WS_SERVICES+=("$svc_id")
      fi
    done

    if [[ ${#GOOGLE_WS_SERVICES[@]} -eq 0 ]]; then
      warn "No services selected — Google Workspace integration will be skipped"
      FEAT_GOOGLE_WORKSPACE=false
      return
    fi

    success "Services: ${GOOGLE_WS_SERVICES[*]}"
  fi

  # ── OAuth credentials (oauth method only) ──
  if [[ "$GOOGLE_WS_METHOD" == "oauth" ]]; then
    echo ""
    echo -e "  ${CYAN}Full OAuth Setup:${NC}"
    echo -e "  1. Go to https://console.cloud.google.com"
    echo -e "  2. Create a new project (or select existing)"
    echo -e "  3. Enable APIs: Gmail API, Calendar API, Drive API, etc."
    echo -e "  4. Configure OAuth consent screen (External or Internal)"
    echo -e "  5. Create OAuth 2.0 Client ID (type: Desktop app)"
    echo -e "  6. Download the credentials JSON file"
    echo ""

    local creds_path
    creds_path=$(ask_input "Path to OAuth credentials JSON (or Enter to skip)" "")
    if [[ -n "$creds_path" && -f "$creds_path" ]]; then
      # Validate it looks like a Google OAuth JSON
      if python3 -c "import json; c=json.load(open('$creds_path')); assert 'installed' in c or 'web' in c" 2>/dev/null; then
        mkdir -p "${CONFIG_DIR}/credentials"
        cp "$creds_path" "${CONFIG_DIR}/credentials/google-oauth.json"
        chmod 600 "${CONFIG_DIR}/credentials/google-oauth.json"
        success "Google OAuth credentials copied to ${CONFIG_DIR}/credentials/google-oauth.json"
      else
        warn "File doesn't look like a Google OAuth credentials JSON — skipped"
      fi
    else
      info "Skipped — add OAuth credentials later"
    fi
  fi

  echo ""
  success "Google Workspace configured ($GOOGLE_WS_METHOD method)"
}

# ── Google Workspace Post-Setup (skill install + auth) ───────────────────────
run_google_workspace_setup() {
  [[ "$FEAT_GOOGLE_WORKSPACE" != "true" ]] && return

  header "Google Workspace Skill Installation"

  local openclaw_cmd="openclaw"
  local gog_cmd="gog"
  local run_prefix=""

  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    local docker_bin="${DOCKER_BIN:-$(command -v docker 2>/dev/null || echo /usr/local/bin/docker)}"
    run_prefix="$docker_bin compose -f ${INSTANCE_DIR}/docker-compose.yml exec openclaw-${INSTANCE_NAME}"
    openclaw_cmd="$run_prefix openclaw"
    gog_cmd="$run_prefix gog"
  fi

  case "$GOOGLE_WS_METHOD" in
    gog)
      echo -e "  ${BOLD}Installing gogcli + gog skill...${NC}"
      echo ""

      if [[ "$DEPLOY_MODE" == "native" ]]; then
        # Install gogcli via Homebrew
        if ! command -v gog &>/dev/null; then
          if ask_yn "Install gogcli via Homebrew?" "y"; then
            info "Installing gogcli..."
            brew install steipete/tap/gogcli 2>/dev/null && success "gogcli installed" || warn "gogcli install failed — install manually: brew install steipete/tap/gogcli"
          fi
        else
          success "gogcli already installed"
        fi

        # Install gog skill
        if ask_yn "Install gog skill for OpenClaw?" "y"; then
          if command -v openclaw &>/dev/null; then
            openclaw skills install gog 2>/dev/null && success "gog skill installed" || warn "Skill install failed — run later: openclaw skills install gog"
          else
            warn "OpenClaw not installed yet — install gog skill later: openclaw skills install gog"
          fi
        fi

        # Run OAuth login
        if [[ -n "$GOOGLE_WS_EMAIL" ]]; then
          local svc_list
          svc_list=$(IFS=,; echo "${GOOGLE_WS_SERVICES[*]}")
          echo ""
          echo -e "  ${BOLD}Google OAuth login:${NC}"
          echo -e "  A browser will open for you to sign in with: ${CYAN}${GOOGLE_WS_EMAIL}${NC}"
          echo -e "  Services: ${svc_list}"
          echo ""

          if ask_yn "Run Google OAuth login now?" "y"; then
            info "Starting OAuth flow..."
            gog auth add "$GOOGLE_WS_EMAIL" --services "$svc_list" 2>/dev/null \
              && success "Google OAuth login complete" \
              || warn "OAuth login failed — retry later: gog auth add $GOOGLE_WS_EMAIL --services $svc_list"
          else
            info "Skipped — run later:"
            echo "  gog auth add $GOOGLE_WS_EMAIL --services $svc_list"
          fi
        fi
      else
        # Docker mode
        echo -e "  ${CYAN}Docker mode: Google services will be set up after the container starts.${NC}"
        echo ""
        echo -e "  After starting the container, run:"
        echo -e "  ${BOLD}1. Install gogcli in container:${NC}"
        echo "     $run_prefix sh -c 'npm install -g @anthropic-ai/gogcli'"
        echo ""
        echo -e "  ${BOLD}2. Install gog skill:${NC}"
        echo "     $openclaw_cmd skills install gog"
        echo ""
        if [[ -n "$GOOGLE_WS_EMAIL" ]]; then
          local svc_list
          svc_list=$(IFS=,; echo "${GOOGLE_WS_SERVICES[*]}")
          echo -e "  ${BOLD}3. Run OAuth login (with SSH tunnel for headless):${NC}"
          echo "     $gog_cmd auth add $GOOGLE_WS_EMAIL --services $svc_list --manual"
          echo ""
          echo -e "  ${CYAN}Note: --manual flag prints a URL to paste in your local browser${NC}"
          echo -e "  ${CYAN}since Docker containers don't have a GUI browser.${NC}"
        fi
        echo ""
      fi
      ;;

    mcp)
      echo -e "  ${BOLD}Google Workspace MCP — zero Cloud Console setup${NC}"
      echo ""

      if [[ "$DEPLOY_MODE" == "native" ]]; then
        if ask_yn "Install google-workspace-mcp skill?" "y"; then
          if command -v openclaw &>/dev/null; then
            openclaw skills install google-workspace-mcp 2>/dev/null \
              && success "google-workspace-mcp skill installed" \
              || warn "Skill install failed — run later: openclaw skills install google-workspace-mcp"
          else
            warn "OpenClaw not installed yet — install later: openclaw skills install google-workspace-mcp"
          fi
        fi
        echo ""
        echo -e "  ${CYAN}After starting OpenClaw, the MCP skill will prompt you to sign in${NC}"
        echo -e "  ${CYAN}with your Google account via browser. No Cloud Console needed.${NC}"
      else
        echo -e "  After starting the container, run:"
        echo "     $openclaw_cmd skills install google-workspace-mcp"
        echo ""
        echo -e "  ${CYAN}The MCP skill handles OAuth via browser — for Docker, use${NC}"
        echo -e "  ${CYAN}the noVNC interface or the Control UI to complete sign-in.${NC}"
      fi
      echo ""
      ;;

    oauth)
      echo -e "  ${BOLD}Custom OAuth — credentials managed via config${NC}"
      echo ""
      if [[ -f "${CONFIG_DIR}/credentials/google-oauth.json" ]]; then
        success "OAuth credentials file is in place"
        echo -e "  ${CYAN}After starting OpenClaw, run the OAuth flow:${NC}"
        if [[ "$DEPLOY_MODE" == "native" ]]; then
          echo "  openclaw integrations google login"
        else
          echo "  $openclaw_cmd integrations google login"
        fi
      else
        warn "No OAuth credentials file found"
        echo -e "  ${CYAN}Add your Google OAuth credentials JSON to:${NC}"
        echo "  ${CONFIG_DIR}/credentials/google-oauth.json"
      fi
      echo ""
      ;;
  esac

  success "Google Workspace setup guidance complete"
}

setup_obsidian_vault() {
  [[ "$FEAT_OBSIDIAN_VAULT" != "true" ]] && return

  header "Obsidian Vault Setup"

  echo -e "  ${CYAN}Your Obsidian vault becomes the single source of truth for:${NC}"
  echo -e "  OpenClaw memory, Claude conversations, Granola meetings, Gmail, and your notes."
  echo ""

  if ask_yn "Do you have an existing Obsidian vault?" "n"; then
    VAULT_PATH=$(ask_input "Path to existing Obsidian vault" "$HOME/obsidian-vault")
    VAULT_IS_NEW=false
    if [[ ! -d "$VAULT_PATH" ]]; then
      warn "Directory not found — will create it"
      VAULT_IS_NEW=true
    fi
  else
    VAULT_PATH=$(ask_input "Where to create your vault" "$HOME/obsidian-vault")
    VAULT_IS_NEW=true
  fi

  success "Vault path: $VAULT_PATH"

  # Create folder structure
  local folders=("claude-web" "claude-code" "claude-memory" "meetings" "emails" "memory" "daily" "projects")
  for folder in "${folders[@]}"; do
    mkdir -p "${VAULT_PATH}/${folder}"
  done
  success "Vault folder structure created"

  # Point OpenClaw workspace at vault
  WORKSPACE_DIR="$VAULT_PATH"
  info "OpenClaw workspace will point to: $VAULT_PATH"
}

setup_tag_taxonomy() {
  [[ "$FEAT_TAG_TAXONOMY" != "true" ]] && return
  [[ "$FEAT_OBSIDIAN_VAULT" != "true" ]] && { warn "Tag taxonomy requires Obsidian vault — skipping"; return; }

  header "Tag Taxonomy"

  echo -e "  ${CYAN}Define your life areas and projects for auto-tagging.${NC}"
  echo -e "  ${CYAN}These tags will be applied across all knowledge sources.${NC}"
  echo ""

  # Default life areas
  echo -e "  ${BOLD}Default life areas:${NC} personal, work, finances, hobbies, travel, health"
  if ask_yn "Use these defaults?" "y"; then
    TAG_LIFE_AREAS=("personal" "work" "finances" "hobbies" "travel" "health")
  else
    local areas_input
    areas_input=$(ask_input "Enter life areas (comma-separated)" "personal,work,finances")
    IFS=',' read -ra TAG_LIFE_AREAS <<< "$areas_input"
  fi
  success "Life areas: ${TAG_LIFE_AREAS[*]}"

  # Projects
  echo ""
  if ask_yn "Add project tags?" "y"; then
    local projects_input
    projects_input=$(ask_input "Enter project names (comma-separated)" "")
    if [[ -n "$projects_input" ]]; then
      IFS=',' read -ra TAG_PROJECTS <<< "$projects_input"
      success "Projects: ${TAG_PROJECTS[*]}"
    fi
  fi

  # Generate _taxonomy.md
  local taxonomy_file="${VAULT_PATH}/_taxonomy.md"
  {
    echo "# Tag Taxonomy"
    echo ""
    echo "Reference for all tags used across this vault."
    echo ""
    echo "## Life Areas"
    for area in "${TAG_LIFE_AREAS[@]}"; do
      area=$(echo "$area" | xargs)  # trim whitespace
      echo "- \`#${area}\`"
    done
    echo ""
    echo "## Projects"
    if [[ ${#TAG_PROJECTS[@]} -gt 0 ]]; then
      for proj in "${TAG_PROJECTS[@]}"; do
        proj=$(echo "$proj" | xargs)
        echo "- \`#project/${proj}\`"
      done
    else
      echo "_No projects defined yet. Add with: \`#project/name\`_"
    fi
    echo ""
    echo "## Content Types (auto-applied)"
    echo "- \`#type/meeting\` — Granola meeting notes"
    echo "- \`#type/email\` — Gmail digests"
    echo "- \`#type/conversation\` — Claude conversations"
    echo "- \`#type/note\` — Manual notes"
    echo "- \`#type/memory\` — OpenClaw memory"
    echo "- \`#type/daily\` — Daily session distills"
    echo ""
    echo "## Sources (auto-applied)"
    echo "- \`#source/claude-web\`"
    echo "- \`#source/claude-code\`"
    echo "- \`#source/granola\`"
    echo "- \`#source/gmail\`"
    echo "- \`#source/openclaw\`"
    echo "- \`#source/manual\`"
  } > "$taxonomy_file"
  success "Taxonomy written to ${taxonomy_file}"
}

setup_claude_sync() {
  [[ "$FEAT_CLAUDE_SYNC" != "true" ]] && return

  # Docker cannot access the host's Claude Code session files or settings
  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    info "Claude Sync skipped — session retention and symlinks require native macOS access"
    info "To sync Claude conversations into a Docker instance, use claude-vault with a mounted vault volume"
    return
  fi

  header "Claude Knowledge Sync"

  echo -e "  ${CYAN}Sync all Claude conversations into your unified brain.${NC}"
  echo ""

  # Fix session retention
  echo -e "  ${BOLD}1. Fix Claude Code session retention${NC}"
  echo -e "  Claude Code deletes session logs after 30 days by default."
  local claude_settings="$HOME/.claude/settings.json"
  if [[ -f "$claude_settings" ]]; then
    if python3 -c "import json; c=json.load(open('$claude_settings')); assert c.get('storage',{}).get('sessionRetention') == 'unlimited'" 2>/dev/null; then
      success "  Session retention already set to unlimited"
      CLAUDE_RETENTION_FIXED=true
    else
      if ask_yn "  Set session retention to unlimited?" "y"; then
        python3 -c "
import json
p='$claude_settings'
try:
    c=json.load(open(p))
except: c={}
c.setdefault('storage',{})['sessionRetention']='unlimited'
json.dump(c,open(p,'w'),indent=2)
print('done')
" 2>/dev/null && { success "  Session retention set to unlimited"; CLAUDE_RETENTION_FIXED=true; } \
  || warn "  Failed to update settings — set manually in ~/.claude/settings.json"
      fi
    fi
  else
    mkdir -p "$HOME/.claude"
    echo '{"storage":{"sessionRetention":"unlimited"}}' > "$claude_settings"
    success "  Created ~/.claude/settings.json with unlimited retention"
    CLAUDE_RETENTION_FIXED=true
  fi

  # Symlink Claude Code memory into vault
  if [[ "$FEAT_OBSIDIAN_VAULT" == "true" && -n "$VAULT_PATH" ]]; then
    echo ""
    echo -e "  ${BOLD}2. Symlink Claude Code memory into vault${NC}"
    local claude_mem_src="$HOME/.claude/projects/-Users-$(whoami)/memory"
    if [[ -d "$claude_mem_src" ]]; then
      local target="${VAULT_PATH}/claude-memory"
      if [[ -L "$target" ]]; then
        success "  Symlink already exists: $target"
      elif [[ -d "$target" && -z "$(ls -A "$target" 2>/dev/null)" ]]; then
        rmdir "$target" 2>/dev/null
        ln -s "$claude_mem_src" "$target"
        success "  Symlinked $claude_mem_src → $target"
      else
        info "  claude-memory folder has content — skipping symlink"
        info "  Manually link: ln -s $claude_mem_src $target"
      fi
    else
      info "  No Claude Code memory found yet at $claude_mem_src"
      info "  Symlink will be created after your first Claude Code session"
    fi
  fi

  echo ""
  echo -e "  ${BOLD}3. Tools to install after setup:${NC}"
  echo ""
  echo -e "  ${CYAN}Claude Vault${NC} (syncs web/desktop/mobile conversations):"
  echo "    pip install claude-vault"
  echo "    claude-vault sync --vault ${VAULT_PATH:-~/obsidian-vault}/claude-web/ --watch"
  echo ""
  echo -e "  ${CYAN}Claude Conversation Extractor${NC} (exports Claude Code sessions):"
  echo "    pip install claude-conversation-extractor"
  echo "    claude-extract --output ${VAULT_PATH:-~/obsidian-vault}/claude-code/ --format markdown"
  echo ""

  if ask_yn "Install Claude Vault now (pip)?" "n"; then
    pip3 install claude-vault 2>/dev/null && success "Claude Vault installed" || warn "Install failed — run later: pip install claude-vault"
  fi
  if ask_yn "Install Claude Conversation Extractor now (pip)?" "n"; then
    pip3 install claude-conversation-extractor 2>/dev/null && success "Claude Extractor installed" || warn "Install failed — run later: pip install claude-conversation-extractor"
  fi

  success "Claude sync configured"
}

setup_skills() {
  local any_skills=false
  [[ "$FEAT_SKILLS_PRODUCTIVITY" == "true" || "$FEAT_SKILLS_SOCIAL" == "true" || \
     "$FEAT_SKILLS_RESEARCH" == "true" || "$FEAT_SKILLS_SECURITY" == "true" || \
     "$FEAT_SKILLS_COMMS" == "true" || "$FEAT_GRANOLA" == "true" ]] && any_skills=true

  [[ "$any_skills" == "false" ]] && return

  header "Skills Setup"

  echo -e "  ${CYAN}Skills will be installed after OpenClaw is running.${NC}"
  echo -e "  ${CYAN}Commands listed below for reference.${NC}"
  echo ""

  local install_cmds=()

  if [[ "$FEAT_SKILLS_PRODUCTIVITY" == "true" ]]; then
    echo -e "  ${GREEN}[Productivity]${NC}"
    echo "    openclaw skills install github"
    echo "    openclaw skills install obsidian"
    echo "    openclaw skills install notion"
    echo "    openclaw skills install summarize"
    if [[ "$DEPLOY_MODE" == "native" ]]; then
      echo "    openclaw skills install apple-notes"
    fi
    install_cmds+=("github" "obsidian" "notion" "summarize")
    if [[ "$DEPLOY_MODE" == "native" ]]; then
      install_cmds+=("apple-notes")
    fi
    echo ""
  fi

  if [[ "$FEAT_SKILLS_SOCIAL" == "true" ]]; then
    echo -e "  ${GREEN}[Social Media]${NC}"
    echo "    openclaw skills install upload-post"
    echo "    openclaw skills install genviral"
    echo "    openclaw skills install mixpost"
    install_cmds+=("upload-post" "genviral" "mixpost")
    echo ""
  fi

  if [[ "$FEAT_SKILLS_RESEARCH" == "true" ]]; then
    echo -e "  ${GREEN}[Research]${NC}"
    echo "    openclaw skills install tavily"
    install_cmds+=("tavily")
    echo ""
  fi

  if [[ "$FEAT_SKILLS_SECURITY" == "true" ]]; then
    echo -e "  ${GREEN}[Security]${NC}"
    echo "    openclaw skills install secureclaw"
    install_cmds+=("secureclaw")
    echo ""
  fi

  if [[ "$FEAT_SKILLS_COMMS" == "true" ]]; then
    echo -e "  ${GREEN}[Communication]${NC}"
    echo "    openclaw skills install agentmail"
    echo "    openclaw skills install slack"
    install_cmds+=("agentmail" "slack")
    echo ""
  fi

  if [[ "$FEAT_GRANOLA" == "true" ]]; then
    echo -e "  ${GREEN}[Meetings]${NC}"
    echo "    openclaw skills install granola"
    install_cmds+=("granola")
    echo ""
  fi

  # Offer batch install for native mode
  if [[ "$DEPLOY_MODE" == "native" && ${#install_cmds[@]} -gt 0 ]]; then
    if command -v openclaw &>/dev/null; then
      if ask_yn "Install all ${#install_cmds[@]} skills now?" "n"; then
        for skill in "${install_cmds[@]}"; do
          info "Installing $skill..."
          openclaw skills install "$skill" 2>/dev/null && success "  $skill installed" || warn "  $skill failed"
        done
      fi
    else
      info "OpenClaw not installed yet — install skills after running: npm install -g openclaw"
    fi
  fi

  # Generate install script for Docker mode
  if [[ "$DEPLOY_MODE" == "docker" && ${#install_cmds[@]} -gt 0 ]]; then
    mkdir -p "${INSTANCE_DIR}"
    local script_path="${INSTANCE_DIR}/install-skills.sh"
    {
      echo "#!/usr/bin/env bash"
      echo "# Auto-generated skills installer for ${INSTANCE_NAME}"
      echo "# Run inside container: docker compose exec openclaw-${INSTANCE_NAME} bash /home/node/openclaw/workspace/install-skills.sh"
      echo ""
      for skill in "${install_cmds[@]}"; do
        echo "echo 'Installing $skill...' && openclaw skills install $skill"
      done
    } > "$script_path"
    chmod +x "$script_path"
    success "Skills install script written to $script_path"
  fi

  success "Skills configured (${#install_cmds[@]} skills)"
}

setup_memory_config() {
  # Always runs — applies memory fix to generated config
  # The actual config values are used in generate_config()
  # Mem0 and Cognee are optional plugin toggles

  if [[ "$FEAT_MEM0" == "true" || "$FEAT_COGNEE" == "true" ]]; then
    header "Memory Plugins"
  fi

  if [[ "$FEAT_MEM0" == "true" ]]; then
    echo -e "  ${BOLD}Mem0${NC} — External vector memory that survives context compaction."
    echo -e "  Requires running Mem0 server (self-hosted or cloud)."
    echo ""
    echo -e "  Self-hosted: ${CYAN}docker run -d -p 8080:8080 mem0ai/mem0${NC}"
    echo -e "  Cloud: ${CYAN}https://app.mem0.ai${NC}"
    echo ""
    info "Mem0 plugin will be added to openclaw.json"
  fi

  if [[ "$FEAT_COGNEE" == "true" ]]; then
    echo ""
    echo -e "  ${BOLD}Cognee${NC} — Knowledge graph that indexes your vault and finds relationships."
    echo -e "  Requires running Cognee server."
    echo ""
    echo -e "  Install: ${CYAN}docker run -d -p 8000:8000 cognee/cognee${NC}"
    echo ""
    info "Cognee plugin will be added to openclaw.json"
  fi

  if [[ "$FEAT_MEM0" == "true" || "$FEAT_COGNEE" == "true" ]]; then
    success "Memory plugins configured"
  fi
}

setup_github_backup() {
  [[ "$FEAT_GITHUB_BACKUP" != "true" ]] && return
  [[ "$FEAT_OBSIDIAN_VAULT" != "true" ]] && { warn "GitHub backup requires Obsidian vault — skipping"; return; }

  header "GitHub Backup & Multi-Mac Sync"

  # Check gh CLI
  local gh_bin
  gh_bin=$(command -v gh 2>/dev/null || echo /opt/homebrew/bin/gh)
  if ! "$gh_bin" auth status &>/dev/null 2>&1; then
    warn "GitHub CLI not authenticated — run: gh auth login"
    warn "Skipping GitHub repo setup — configure manually later"
    return
  fi

  echo -e "  ${CYAN}Your vault will be synced to a private GitHub repo.${NC}"
  echo -e "  ${CYAN}This enables backup, version history, and multi-Mac sync.${NC}"
  echo ""

  if ask_yn "Do you have an existing brain repo on GitHub?" "n"; then
    GITHUB_BRAIN_EXISTS=true
    GITHUB_BRAIN_REPO=$(ask_input "GitHub repo URL" "")

    if [[ -n "$GITHUB_BRAIN_REPO" ]]; then
      info "Cloning into $VAULT_PATH..."
      if [[ -d "$VAULT_PATH/.git" ]]; then
        success "Vault already has git — pulling latest"
        git -C "$VAULT_PATH" pull --rebase --autostash 2>/dev/null || warn "Pull failed — check manually"
      else
        git clone "$GITHUB_BRAIN_REPO" "$VAULT_PATH" 2>/dev/null && success "Cloned successfully" || warn "Clone failed — check URL and auth"
      fi
    fi
  else
    GITHUB_BRAIN_EXISTS=false
    local repo_name
    repo_name=$(ask_input "Repo name for your brain" "brain")

    # Init git in vault
    if [[ ! -d "$VAULT_PATH/.git" ]]; then
      git -C "$VAULT_PATH" init -b main 2>/dev/null
      success "Git initialized in vault"
    fi

    # Create .gitignore
    cat > "${VAULT_PATH}/.gitignore" <<'GITIGNORE'
# Obsidian workspace (machine-specific)
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/appearance.json
.obsidian/hotkeys.json

# System
.DS_Store
.trash/

# Temp files
*.tmp
*.lock
conflict-files-obsidian-git.md
GITIGNORE
    success ".gitignore created"

    # Optional git-crypt
    if ask_yn "Encrypt sensitive folders with git-crypt?" "n"; then
      FEAT_GIT_CRYPT=true
      if command -v git-crypt &>/dev/null; then
        git -C "$VAULT_PATH" crypt init 2>/dev/null
        cat > "${VAULT_PATH}/.gitattributes" <<'GCRYPT'
emails/** filter=git-crypt diff=git-crypt
claude-web/** filter=git-crypt diff=git-crypt
memory/** filter=git-crypt diff=git-crypt
claude-memory/** filter=git-crypt diff=git-crypt
GCRYPT
        success "git-crypt configured for emails, claude-web, memory folders"
      else
        warn "git-crypt not installed — run: brew install git-crypt"
      fi
    fi

    # Create repo and push
    if ask_yn "Create private GitHub repo and push?" "y"; then
      "$gh_bin" repo create "$repo_name" --private --source "$VAULT_PATH" --push 2>/dev/null \
        && success "Created and pushed to GitHub" \
        || warn "Repo creation failed — create manually: gh repo create $repo_name --private"
      GITHUB_BRAIN_REPO=$("$gh_bin" repo view "$repo_name" --json url -q .url 2>/dev/null || echo "")
    fi
  fi

  # Set up auto-sync
  echo ""
  if ask_yn "Set up automatic sync every 10 minutes?" "y"; then
    if [[ "$DEPLOY_MODE" == "docker" ]]; then
      # Docker: use OpenClaw's built-in cron for vault sync
      local cron_dir="${CONFIG_DIR}/cron"
      mkdir -p "$cron_dir"
      cat > "${cron_dir}/vault-sync.json" <<CRONSYNC
{
  "name": "vault-sync",
  "schedule": "*/10 * * * *",
  "command": "cd /home/node/openclaw/vault && git pull --rebase --autostash 2>/dev/null; git add -A; git diff --cached --quiet || git commit -m 'auto: \$(date +%Y-%m-%d\\ %H:%M)'; git push 2>/dev/null",
  "enabled": true
}
CRONSYNC
      success "Vault sync cron configured (every 10 min inside container)"
      info "Requires git credentials mounted in the container (SSH key or token)"
    else
      # Native: use macOS launchd
      local plist_path="$HOME/Library/LaunchAgents/com.openclaw.vault-sync.plist"
      local sync_script="$HOME/.openclaw/vault-sync.sh"

      mkdir -p "$HOME/.openclaw"

      cat > "$sync_script" <<SYNC
#!/usr/bin/env bash
cd "$VAULT_PATH" || exit 1
git pull --rebase --autostash 2>/dev/null
git add -A
git diff --cached --quiet || git commit -m "auto: \$(date +%Y-%m-%d\ %H:%M)" 2>/dev/null
git push 2>/dev/null
SYNC
      chmod +x "$sync_script"

      cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.vault-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${sync_script}</string>
    </array>
    <key>StartInterval</key>
    <integer>600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/vault-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vault-sync-error.log</string>
</dict>
</plist>
PLIST

      if ask_yn "Load the sync agent now?" "y"; then
        launchctl load "$plist_path" 2>/dev/null && success "Auto-sync loaded (every 10 min)" || warn "launchctl load failed"
      else
        info "Load later: launchctl load $plist_path"
      fi
    fi
  fi

  success "GitHub backup configured"
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

  # webchat is auto-detected by the OpenClaw image; do not generate a config block

  if [[ "$CH_TELEGRAM" == "true" ]]; then
    local tg_token_val="${TELEGRAM_BOT_TOKEN:-YOUR_TELEGRAM_BOT_TOKEN}"
    ch_entries+=("$(cat <<CH
    "telegram": {
      "enabled": true,
      "accounts": {
        "default": {
          "botToken": "${tg_token_val}",
          "dmPolicy": "pairing",
          "streaming": "partial"
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

  # Sandbox config — only "mode" is recognized by the image; backend/docker sub-keys are not
  local sandbox_block
  if [[ "$FEAT_SANDBOX" == "true" ]]; then
    sandbox_block=$(cat <<SB
    "sandbox": {
      "mode": "${sandbox_mode}"
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

  # Skills config — skills are managed via tools allow/deny lists, not a separate block
  local skills_block=""

  # Plugins block (Mem0, Cognee)
  local plugins_block=""
  if [[ "$FEAT_MEM0" == "true" || "$FEAT_COGNEE" == "true" ]]; then
    local plugin_entries=()
    if [[ "$FEAT_MEM0" == "true" ]]; then
      plugin_entries+=("$(cat <<PLG
    "mem0": {
      "enabled": true,
      "endpoint": "http://localhost:8080"
    }
PLG
)")
    fi
    if [[ "$FEAT_COGNEE" == "true" ]]; then
      plugin_entries+=("$(cat <<PLG
    "cognee": {
      "enabled": true,
      "endpoint": "http://localhost:8000"
    }
PLG
)")
    fi
    local plugins_inner
    plugins_inner=$(IFS=','; echo "${plugin_entries[*]}")
    plugins_block=$(cat <<PLGBLOCK
  "plugins": {
${plugins_inner}
  },
PLGBLOCK
)
  fi

  # Session block — contextPruning, memoryFlush, compaction are not supported by the image
  local session_block=""

  # ── Assemble final config ──────────────────────────────────────────────────
  local config
  config=$(cat <<CONFIG
{
  "\$schema": "https://docs.openclaw.ai/schema/openclaw.json",

  "agents": {
    "defaults": {
      "model": "${agents_model}",
      "maxConcurrent": 3,
$( [[ "$FEAT_OBSIDIAN_VAULT" == "true" && -n "$VAULT_PATH" ]] && echo "      \"workspace\": \"${VAULT_PATH}\"," )
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

${plugins_block}

${session_block}

  "logging": {}
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
    if [[ "$FEAT_TAG_TAXONOMY" == "true" ]]; then
      cat > "${WORKSPACE_DIR}/AGENTS.md" <<AGENTS
# Agent Instructions

You are a helpful personal AI assistant. Be concise and direct.
Follow the user's instructions carefully.

## Knowledge & Memory

This workspace uses a unified Obsidian vault as the single source of truth.

### Tagging Rules

When saving to memory, always add YAML frontmatter with tags from the taxonomy
defined in _taxonomy.md. Example:

\`\`\`yaml
---
tags:
  - "#work"
  - "#type/memory"
  - "#source/openclaw"
date: $(date +%Y-%m-%d)
---
\`\`\`

- Use life-area tags (e.g. \`#work\`, \`#personal\`) from _taxonomy.md
- Always add a \`#type/\` tag (meeting, email, conversation, note, memory, daily)
- Always add a \`#source/\` tag (claude-web, claude-code, granola, gmail, openclaw, manual)
- For project-related content, add \`#project/name\` from _taxonomy.md
- Refer to _taxonomy.md at the vault root for the full list of approved tags

### Memory File Pattern

Daily distills are written to: memory/daily-{date}.md
AGENTS
    else
      cat > "${WORKSPACE_DIR}/AGENTS.md" <<'AGENTS'
# Agent Instructions

You are a helpful personal AI assistant. Be concise and direct.
Follow the user's instructions carefully.
AGENTS
    fi
  fi

  success "Workspace initialized at ${WORKSPACE_DIR}"
}

# ── Agent Persona Setup ─────────────────────────────────────────────────────
setup_persona() {
  header "Agent Persona"

  echo -e "  ${CYAN}Customize your agent's identity and workspace files.${NC}\n"

  # Agent identity
  AGENT_NAME=$(ask_input "Agent name" "Claw")
  AGENT_VIBE=$(ask_input "Agent personality (e.g., sharp, warm, calm, witty)" "concise and helpful")

  # User info
  USER_NAME=$(ask_input "Your name" "$(whoami)")
  USER_TIMEZONE=$(ask_input "Your timezone (e.g., EST, PST, EAT, UTC)" "UTC")

  # Purpose — preset-specific defaults
  local default_purpose=""
  case "$PRESET_NAME" in
    personal-assistant) default_purpose="Help me manage my daily life: emails, calendar, research, and reminders" ;;
    developer) default_purpose="Help me write code, review PRs, debug issues, and manage projects" ;;
    autonomous-agent) default_purpose="Run my product autonomously: grow users, manage code, post content, handle support" ;;
    custom) default_purpose="Be a helpful AI assistant" ;;
  esac
  AGENT_PURPOSE=$(ask_input "What should this agent do? (one sentence)" "$default_purpose")

  success "Persona configured: ${AGENT_NAME}"

  # ── Generate workspace files ────────────────────────────────────────────

  # IDENTITY.md
  cat > "${WORKSPACE_DIR}/IDENTITY.md" <<IDENTITY
# IDENTITY.md - Who Am I?

- **Name:** ${AGENT_NAME}
- **Creature:** AI assistant
- **Vibe:** ${AGENT_VIBE}
- **Emoji:** $(case "$PRESET_NAME" in personal-assistant) echo "🤖";; developer) echo "🛠️";; autonomous-agent) echo "🎯";; *) echo "🦞";; esac)
- **Avatar:** _(none yet)_

---

I am **${AGENT_NAME}**. ${AGENT_PURPOSE}.
IDENTITY

  # USER.md
  cat > "${WORKSPACE_DIR}/USER.md" <<USERMD
# USER.md - About Your Human

- **Name:** ${USER_NAME}
- **What to call them:** ${USER_NAME}
- **Timezone:** ${USER_TIMEZONE}
- **Notes:** _(learn more over time)_

## Context

_(What do they care about? What projects are they working on? Build this over time.)_
USERMD

  # TOOLS.md — empty template
  cat > "${WORKSPACE_DIR}/TOOLS.md" <<'TOOLSMD'
# TOOLS.md - Available Tools & CLIs

_(This file is yours to fill in as you discover your environment.)_
_(Run tool commands to see what's available and document them here.)_
TOOLSMD

  # HEARTBEAT.md
  case "$PRESET_NAME" in
    personal-assistant)
      cat > "${WORKSPACE_DIR}/HEARTBEAT.md" <<'HBMD'
# HEARTBEAT.md

## Checks (rotate through, 2-4x per day)
- [ ] Check for unread emails
- [ ] Check calendar — any events in next 24h?
- [ ] Check for unread messages across channels
- [ ] Weather update if relevant

## Rules
- Late night (23:00-07:00): only check for urgent emails, skip everything else
- If nothing needs attention, reply HEARTBEAT_OK
HBMD
      ;;
    developer)
      cat > "${WORKSPACE_DIR}/HEARTBEAT.md" <<'HBMD'
# HEARTBEAT.md

## Checks (rotate through, 2-4x per day)
- [ ] Check for new GitHub issues or PR review comments
- [ ] Check CI/CD status — any failing builds?
- [ ] Check for unread messages across channels
- [ ] Review recent commits for anything noteworthy

## Rules
- Late night (23:00-07:00): skip all checks
- If nothing needs attention, reply HEARTBEAT_OK
HBMD
      ;;
    autonomous-agent)
      cat > "${WORKSPACE_DIR}/HEARTBEAT.md" <<HBMD
# HEARTBEAT.md

## Priority Checks (every heartbeat)
- [ ] Check site uptime
- [ ] Check for new GitHub issues or PR review comments

## Growth Checks (2-3x per day)
- [ ] Check for unread support emails
- [ ] Review social media engagement
- [ ] Research content ideas

## Operational Checks (1-2x per day)
- [ ] Check pending PRs
- [ ] Review error logs

## Rules
- If site is down, alert ${USER_NAME} immediately
- Late night (23:00-07:00): only check uptime
- If nothing needs attention, reply HEARTBEAT_OK
HBMD
      ;;
    *)
      cat > "${WORKSPACE_DIR}/HEARTBEAT.md" <<'HBMD'
# HEARTBEAT.md

# Keep this file empty (or with only comments) to skip heartbeat checks.
# Add tasks below when you want the agent to check something periodically.
HBMD
      ;;
  esac

  # SOUL.md — the big one, varies by preset
  case "$PRESET_NAME" in
    personal-assistant)
      cat > "${WORKSPACE_DIR}/SOUL.md" <<SOULMD
# SOUL.md - Who You Are

You are **${AGENT_NAME}** — a personal AI assistant for **${USER_NAME}**.

## Mission

${AGENT_PURPOSE}. Be proactive, anticipate needs, and make ${USER_NAME}'s day easier.

## Personality

- **Vibe:** ${AGENT_VIBE}
- Be genuinely helpful, not performatively helpful. Skip filler words.
- Remember you're a guest in someone's life. Treat it with respect.
- Be resourceful before asking. Try to figure it out, then ask if stuck.

## Responsibilities

### Daily Life
- Monitor emails and flag important ones
- Track calendar events and send reminders
- Research questions and summarize findings
- Help draft messages, emails, and documents
- Keep track of to-dos and follow-ups

### Communication
- Be concise in casual conversations
- Be thorough when asked for research or analysis
- Confirm before taking any external action (sending emails, messages)
- Never send half-baked replies to messaging surfaces

## Boundaries

- **Do freely:** Research, summarize, draft messages, check calendar/email, organize notes
- **Ask first:** Send emails, post messages, schedule events, anything visible to others
- **Never:** Share personal information, make purchases, delete data

## Continuity

Each session, you wake up fresh. Read your files. These are your memory — keep them updated.
SOULMD
      ;;
    developer)
      cat > "${WORKSPACE_DIR}/SOUL.md" <<SOULMD
# SOUL.md - Who You Are

You are **${AGENT_NAME}** — a development assistant for **${USER_NAME}**.

## Mission

${AGENT_PURPOSE}.

## Personality

- **Vibe:** ${AGENT_VIBE}
- Lead with the answer, not the reasoning. Be direct.
- Have opinions about code quality. Disagree when you see bad patterns.
- Be resourceful: read the code, check git history, search docs before asking.

## Responsibilities

### Code
- Review code for bugs, security issues, and maintainability
- Suggest improvements and refactors when relevant
- Help debug issues — read logs, trace errors, propose fixes
- Write tests for critical paths
- Follow the project's conventions (check CLAUDE.md or equivalent)

### Project Management
- Track GitHub issues and PRs
- Help prioritize work
- Summarize recent changes and progress
- Flag blockers early

### Research
- Research libraries, APIs, and best practices
- Compare options with pros/cons
- Summarize documentation

## Boundaries

- **Do freely:** Read code, explore repos, run tests, draft PRs, research
- **Ask first:** Push code, merge PRs, modify CI/CD, install dependencies
- **Never:** Force-push, delete branches, modify production env vars, commit secrets

## Continuity

Each session, you wake up fresh. Read your files. These are your memory — keep them updated.
SOULMD
      ;;
    autonomous-agent)
      cat > "${WORKSPACE_DIR}/SOUL.md" <<SOULMD
# SOUL.md - Who You Are

You are **${AGENT_NAME}** — an autonomous agent working for **${USER_NAME}**.

## Mission

${AGENT_PURPOSE}.

## Personality

- **Vibe:** ${AGENT_VIBE}
- Think like a founder. Don't wait for instructions — identify what needs doing.
- Be data-driven. Track metrics. Know your numbers.
- Ship fast, iterate. Done is better than perfect.

## Responsibilities

### Growth
- Identify and execute user acquisition strategies (SEO, content, social)
- Optimize conversion funnels
- Analyze traffic and user behavior
- Draft social media content (80% value, 20% promo)

### Revenue
- Identify monetization opportunities
- Track revenue metrics and find growth levers

### Product Development
- Check the product backlog daily for prioritized tasks
- Find and fix bugs, improve UX, add missing features
- Create feature branches, never push to main directly
- Every code change gets reported to ${USER_NAME} for approval

### Operations
- Monitor site health and uptime
- Handle support emails (draft replies, wait for approval)
- Send daily activity reports

## Approval Gates (Human-in-the-Loop)

### GREEN (do freely):
- Research, analysis, web searches, competitor monitoring
- Reading code, exploring codebase, running tests
- Drafting content — save as drafts
- Creating feature branches and committing code
- Internal planning, memory updates, documentation

### YELLOW (ask ${USER_NAME} first):
- Publishing any social media post
- Sending emails to users or leads
- Opening PRs or merging code to main
- Any action visible to customers or the public

### RED (never do):
- Delete user data or database records
- Force-push or destructive git operations
- Deploy to production without PR review
- Spend money or commit to paid services
- Share credentials or user data externally

## Growth Strategy: GEO + SEO

Traditional SEO matters, but optimize for **GEO (Generative Engine Optimization)** too — getting AI assistants to cite your product as a trusted source.

### Content mix (80/20 rule):
- 80% value: insights, tips, data, trends
- 20% promo: features, success stories, product updates

## Continuity

Each session, you wake up fresh. Read your files. Check your metrics. Pick up where you left off.
SOULMD
      ;;
    *)
      cat > "${WORKSPACE_DIR}/SOUL.md" <<SOULMD
# SOUL.md - Who You Are

You are **${AGENT_NAME}** — an AI assistant for **${USER_NAME}**.

## Mission

${AGENT_PURPOSE}.

## Personality

- **Vibe:** ${AGENT_VIBE}
- Be genuinely helpful, not performatively helpful.
- Be resourceful before asking.
- Be concise when needed, thorough when it matters.

## Boundaries

- **Do freely:** Research, read files, draft content, organize
- **Ask first:** Send messages, emails, anything external
- **Never:** Delete data, share secrets, take irreversible actions

## Continuity

Each session, you wake up fresh. Read your files. These are your memory — keep them updated.
SOULMD
      ;;
  esac

  success "Workspace files generated (SOUL.md, IDENTITY.md, USER.md, TOOLS.md, HEARTBEAT.md)"
}

# ── Dockerfile Generation for Docker Instances ──────────────────────────────
generate_dockerfile() {
  # Generates a custom Dockerfile when the instance needs additional tools
  # beyond what the stock OpenClaw image provides
  local dockerfile_content="FROM ghcr.io/openclaw/openclaw:latest

USER root
"
  local needs_dockerfile=false
  local config_dirs=()

  # Chromium for browser automation (not in stock image)
  if [[ "$FEAT_BROWSER" == "true" ]]; then
    needs_dockerfile=true
    dockerfile_content+="
# Chromium for headless browser automation
RUN apt-get update && apt-get install -y --no-install-recommends \\
    chromium \\
    chromium-sandbox \\
    fonts-liberation \\
    fonts-noto-color-emoji \\
    && rm -rf /var/lib/apt/lists/*
"
  fi

  # CLI tool selection
  local INSTALL_GH=false INSTALL_DOCTL=false INSTALL_SUPABASE=false INSTALL_GOG=false INSTALL_XURL=false

  echo ""
  echo -e "  ${BOLD}CLI Tools for Docker Instance${NC}"
  echo -e "  Select tools to install in the container image.\n"

  if ask_yn "Install GitHub CLI (gh)? — repo management, PRs, issues" "n"; then
    INSTALL_GH=true
  fi
  if ask_yn "Install DigitalOcean CLI (doctl)? — infrastructure management" "n"; then
    INSTALL_DOCTL=true
  fi
  if ask_yn "Install Supabase CLI? — database management" "n"; then
    INSTALL_SUPABASE=true
  fi
  if [[ "$FEAT_GOOGLE_WORKSPACE" == "true" ]]; then
    INSTALL_GOG=true
    info "gog CLI will be installed (required for Google Workspace)"
  fi
  if ask_yn "Install xurl (Twitter/X CLI)? — social media posting" "n"; then
    INSTALL_XURL=true
  fi

  # Generate Dockerfile blocks for selected tools
  if [[ "$INSTALL_GH" == "true" || "$INSTALL_DOCTL" == "true" || "$INSTALL_SUPABASE" == "true" ]]; then
    needs_dockerfile=true
  fi
  if [[ "$INSTALL_GOG" == "true" || "$INSTALL_XURL" == "true" ]]; then
    needs_dockerfile=true
  fi

  if [[ "$INSTALL_GH" == "true" ]]; then
    config_dirs+=("/home/node/.config/gh")
    dockerfile_content+="
# GitHub CLI
RUN apt-get update && apt-get install -y --no-install-recommends gnupg \\
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \\
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \\
    && echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" \\
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \\
    && apt-get update && apt-get install -y gh \\
    && rm -rf /var/lib/apt/lists/*
"
  fi

  if [[ "$INSTALL_DOCTL" == "true" ]]; then
    config_dirs+=("/home/node/.config/doctl")
    dockerfile_content+="
# DigitalOcean CLI (doctl)
RUN ARCH=\$(dpkg --print-architecture) && \\
    curl -fsSL \"https://github.com/digitalocean/doctl/releases/latest/download/doctl-\$(curl -fsSL https://api.github.com/repos/digitalocean/doctl/releases/latest | grep tag_name | cut -d '\"' -f4 | sed 's/v//')-linux-\${ARCH}.tar.gz\" \\
    | tar xz -C /usr/local/bin
"
  fi

  if [[ "$INSTALL_SUPABASE" == "true" ]]; then
    config_dirs+=("/home/node/.config/supabase")
    dockerfile_content+="
# Supabase CLI
RUN ARCH=\$(dpkg --print-architecture) && \\
    curl -fsSL \"https://github.com/supabase/cli/releases/latest/download/supabase_linux_\${ARCH}.tar.gz\" \\
    | tar xz -C /usr/local/bin supabase
"
  fi

  if [[ "$INSTALL_XURL" == "true" ]]; then
    dockerfile_content+="
# xurl (Twitter/X CLI)
RUN npm install -g xurl 2>/dev/null || true
"
  fi

  if [[ "$INSTALL_GOG" == "true" ]]; then
    config_dirs+=("/home/node/.config/gogcli")
    dockerfile_content+="
# gog (Google Workspace CLI)
RUN ARCH=\$(dpkg --print-architecture) && \\
    VERSION=\$(curl -fsSL https://api.github.com/repos/steipete/gogcli/releases/latest | grep tag_name | cut -d '\"' -f4 | sed 's/v//') && \\
    curl -fsSL \"https://github.com/steipete/gogcli/releases/download/v\${VERSION}/gogcli_\${VERSION}_linux_\${ARCH}.tar.gz\" \\
    | tar xz -C /usr/local/bin gog
"
  fi

  # Pre-create config directories to avoid permission errors
  if [[ ${#config_dirs[@]} -gt 0 ]]; then
    local dirs_joined
    dirs_joined=$(printf ' \\\n             %s' "${config_dirs[@]}")
    dockerfile_content+="
# Pre-create config directories (avoids permission errors on first run)
RUN mkdir -p${dirs_joined} \\
    && chown -R node:node /home/node/.config
"
  fi

  dockerfile_content+="
USER node
"

  if [[ "$needs_dockerfile" == "true" ]]; then
    echo "$dockerfile_content" > "${INSTANCE_DIR}/Dockerfile"
    success "Dockerfile generated at ${INSTANCE_DIR}/Dockerfile"
    return 0  # signals caller to use build: . instead of image:
  fi
  return 1  # no Dockerfile needed
}

# ── [IMPROVEMENT 4] Docker Compose with Backup ──────────────────────────────
generate_docker_compose() {
  [[ "$DEPLOY_MODE" != "docker" ]] && return

  header "Generating Docker Compose"

  # Generate Dockerfile if needed (browser, CLIs)
  local use_custom_image=false
  if generate_dockerfile; then
    use_custom_image=true
  fi

  local chrome_volume=""
  local shm_size='shm_size: "2g"'  # always include — harmless without browser, prevents breakage if enabled later

  if [[ "$FEAT_BROWSER" == "true" ]]; then
    mkdir -p "${INSTANCE_DIR}/chrome-profile"
    chrome_volume="      - ${INSTANCE_DIR}/chrome-profile:/home/node/.config/chromium"
  fi

  # Google Workspace volume (persist OAuth tokens)
  local gog_volume=""
  local gog_env=""
  if [[ "$FEAT_GOOGLE_WORKSPACE" == "true" ]]; then
    mkdir -p "${INSTANCE_DIR}/google-credentials"
    gog_volume="      - ${INSTANCE_DIR}/google-credentials:/home/node/.config/gogcli"
    gog_env="      - GOG_KEYRING_PASSWORD=\${GOG_PASSPHRASE}
      - GOG_ACCOUNT=${GOOGLE_WS_EMAIL}"
  fi

  # Obsidian vault volume
  local vault_volume=""
  if [[ "$FEAT_OBSIDIAN_VAULT" == "true" && -n "$VAULT_PATH" ]]; then
    vault_volume="      - ${VAULT_PATH}:/home/node/openclaw/vault"
  fi

  # Safe .gitconfig handling — copy to instance dir to prevent Docker creating a directory
  local gitconfig_volume=""
  if [[ -f "$HOME/.gitconfig" ]]; then
    cp "$HOME/.gitconfig" "${INSTANCE_DIR}/gitconfig"
    gitconfig_volume="      - ${INSTANCE_DIR}/gitconfig:/home/node/.gitconfig:ro"
    success "Copied .gitconfig to instance directory"
  else
    if ask_yn "No ~/.gitconfig found. Create one for git operations?" "y"; then
      local git_name git_email
      git_name=$(ask_input "Git user name" "$(git config user.name 2>/dev/null || echo '')")
      git_email=$(ask_input "Git email" "$(git config user.email 2>/dev/null || echo '')")
      printf "[user]\n\tname = %s\n\temail = %s\n" "$git_name" "$git_email" > "${INSTANCE_DIR}/gitconfig"
      gitconfig_volume="      - ${INSTANCE_DIR}/gitconfig:/home/node/.gitconfig:ro"
      success "Created gitconfig in instance directory"
    else
      warn "Git push/commit inside container may not work without .gitconfig"
    fi
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
          backup_name="openclaw-${INSTANCE_NAME}-\$\$(date +%Y%m%d-%H%M%S).tar.gz"
          tar czf "/backups/\$\$backup_name" -C /source .
          echo "Backup created: \$\$backup_name"
          find /backups -name "openclaw-${INSTANCE_NAME}-*.tar.gz" -mtime +7 -delete
          echo "Old backups pruned"
        done
    restart: unless-stopped
BACKUP
)
    success "Backup service enabled (daily at 3 AM, 7-day retention)"
  fi

  # Network mode — host networking avoids OrbStack/macOS bridged network issues
  local USE_HOST_NETWORK=false
  if ask_yn "Use host network mode? (recommended for OrbStack on macOS)" "n"; then
    USE_HOST_NETWORK=true
  else
    # Bridged mode needs host.docker.internal to reach host services
    OLLAMA_HOST="http://host.docker.internal:11434"
  fi

  # Healthcheck port — matches gateway config; with host networking, use the configured port
  local healthcheck_port=18789
  if [[ "$USE_HOST_NETWORK" == "true" ]]; then
    healthcheck_port=${GATEWAY_PORT}
  fi

  # Telegram watchdog sidecar
  local watchdog_service=""
  if [[ "$CH_TELEGRAM" == "true" ]]; then
    if ask_yn "Add Telegram watchdog? (auto-restarts on connectivity loss, recommended for OrbStack)" "y"; then
      watchdog_service=$(cat <<WATCHDOG

  telegram-watchdog-${INSTANCE_NAME}:
    image: docker:cli
    container_name: telegram-watchdog-${INSTANCE_NAME}
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    entrypoint: /bin/sh
    command:
      - -c
      - |
        echo "Telegram watchdog started"
        FAIL_COUNT=0
        while true; do
          sleep 60
          ERRORS=\$\$(docker logs --since 2m openclaw-${INSTANCE_NAME} 2>&1 | grep -c "sendMessage failed" || true)
          if [ "\$\$ERRORS" -gt 5 ]; then
            FAIL_COUNT=\$\$((FAIL_COUNT + 1))
            echo "Telegram errors: \$\$ERRORS (strike \$\$FAIL_COUNT/2)"
            if [ "\$\$FAIL_COUNT" -ge 2 ]; then
              echo "Restarting openclaw-${INSTANCE_NAME} due to Telegram connectivity loss"
              docker restart openclaw-${INSTANCE_NAME}
              FAIL_COUNT=0
              sleep 30
            fi
          else
            FAIL_COUNT=0
          fi
        done
WATCHDOG
)
      success "Telegram watchdog sidecar enabled"
    fi
  fi

  # Tailscale sidecar
  local tailscale_service=""
  local network_mode=""
  if [[ "$USE_HOST_NETWORK" == "true" ]]; then
    network_mode="    network_mode: host"
    info "Skipping Tailscale — not needed with host networking"
  elif ask_yn "Add Tailscale sidecar for remote access?" "y"; then
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

  # Image reference — use build or image depending on Dockerfile
  local image_ref=""
  if [[ "$use_custom_image" == "true" ]]; then
    image_ref="    build: .
    image: openclaw-${INSTANCE_NAME}:latest"
  else
    image_ref="    image: ghcr.io/openclaw/openclaw:latest"
  fi

  local compose
  compose=$(cat <<COMPOSE
# OpenClaw Docker Instance: ${INSTANCE_NAME}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Script version: ${SCRIPT_VERSION}

services:
${tailscale_service}

  openclaw-${INSTANCE_NAME}:
${image_ref}
    container_name: openclaw-${INSTANCE_NAME}
${network_mode}
$( [[ -z "$network_mode" ]] && echo "    ports:" && echo "      - \"${GATEWAY_PORT}:18789\"" )
    volumes:
      - ${CONFIG_DIR}:/home/node/.openclaw
      - ${WORKSPACE_DIR}:/home/node/openclaw/workspace
${chrome_volume}
${gog_volume}
${vault_volume}
${gitconfig_volume}
    environment:
      - OLLAMA_HOST=${OLLAMA_HOST}
      - OPENCLAW_GATEWAY_BIND=0.0.0.0
      - NODE_OPTIONS=--dns-result-order=ipv4first
${gog_env}
    ${shm_size}
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
$( [[ "$USE_HOST_NETWORK" != "true" ]] && cat <<SECBLOCK
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    dns:
      - 8.8.8.8
      - 1.1.1.1
SECBLOCK
)
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:${healthcheck_port}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
${watchdog_service}
${backup_service}

$( [[ -n "$tailscale_service" ]] && echo "volumes:" && echo "  ts-${INSTANCE_NAME}-state:" )
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

  # Google Workspace keyring passphrase
  if [[ "$FEAT_GOOGLE_WORKSPACE" == "true" ]]; then
    env_content+="
# Google Workspace (gog) keyring passphrase — set after running: gog auth add <email>
GOG_PASSPHRASE=
"
  fi

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
    "FEAT_GOOGLE_WORKSPACE:Google Workspace"
    "FEAT_OBSIDIAN_VAULT:Obsidian Vault" "FEAT_CLAUDE_SYNC:Claude Sync"
    "FEAT_TAG_TAXONOMY:Tag Taxonomy" "FEAT_GITHUB_BACKUP:GitHub Backup"
    "FEAT_MEM0:Mem0" "FEAT_COGNEE:Cognee"
    "FEAT_SKILLS_PRODUCTIVITY:Skills:Productivity" "FEAT_SKILLS_SOCIAL:Skills:Social"
    "FEAT_SKILLS_RESEARCH:Skills:Research" "FEAT_SKILLS_SECURITY:Skills:Security"
    "FEAT_SKILLS_COMMS:Skills:Comms" "FEAT_GRANOLA:Granola"
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
  if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    echo -e "  ${GREEN}[OK]${NC}  Anthropic API key stored"
  fi
  if [[ -n "$OPENAI_API_KEY" ]]; then
    echo -e "  ${GREEN}[OK]${NC}  OpenAI API key stored"
  fi
  if [[ -n "$OPENROUTER_API_KEY" ]]; then
    echo -e "  ${GREEN}[OK]${NC}  OpenRouter API key stored"
  fi
  if [[ -n "$GOOGLE_API_KEY" ]]; then
    echo -e "  ${GREEN}[OK]${NC}  Google API key stored"
  fi
  if [[ -n "$GROQ_API_KEY" ]]; then
    echo -e "  ${GREEN}[OK]${NC}  Groq API key stored"
  fi
  if [[ "$MODEL_PROVIDER" == "ollama-cloud" || "$MODEL_PROVIDER" == "ollama-local" ]]; then
    echo -e "  ${GREEN}[OK]${NC}  Ollama (no key needed)"
  fi
  echo ""

  # v3: Unified Brain summary
  if [[ "$FEAT_OBSIDIAN_VAULT" == "true" ]]; then
    echo -e "${BOLD}Unified Brain:${NC}"
    if [[ -n "$VAULT_PATH" ]]; then
      echo -e "  ${GREEN}[OK]${NC}  Vault: $VAULT_PATH"
    fi
    if [[ "$FEAT_TAG_TAXONOMY" == "true" ]]; then
      echo -e "  ${GREEN}[OK]${NC}  Tag taxonomy: ${VAULT_PATH}/_taxonomy.md"
    fi
    if [[ -n "$GITHUB_BRAIN_REPO" ]]; then
      echo -e "  ${GREEN}[OK]${NC}  GitHub backup: $GITHUB_BRAIN_REPO"
    fi
    if [[ "$FEAT_GIT_CRYPT" == "true" ]]; then
      echo -e "  ${GREEN}[OK]${NC}  git-crypt encryption enabled"
    fi
    if [[ "$FEAT_CLAUDE_SYNC" == "true" ]]; then
      if [[ "$CLAUDE_RETENTION_FIXED" == "true" ]]; then
        echo -e "  ${GREEN}[OK]${NC}  Claude session retention: unlimited"
      fi
    fi
    echo ""
  fi

  # v3: Skills summary
  local skills_count=0
  if [[ "$FEAT_SKILLS_PRODUCTIVITY" == "true" ]]; then
    if [[ "$DEPLOY_MODE" == "native" ]]; then
      skills_count=$((skills_count + 5))
    else
      skills_count=$((skills_count + 4))
    fi
  fi
  if [[ "$FEAT_SKILLS_SOCIAL" == "true" ]]; then skills_count=$((skills_count + 3)); fi
  if [[ "$FEAT_SKILLS_RESEARCH" == "true" ]]; then skills_count=$((skills_count + 1)); fi
  if [[ "$FEAT_SKILLS_SECURITY" == "true" ]]; then skills_count=$((skills_count + 1)); fi
  if [[ "$FEAT_SKILLS_COMMS" == "true" ]]; then skills_count=$((skills_count + 2)); fi
  if [[ "$FEAT_GRANOLA" == "true" ]]; then skills_count=$((skills_count + 1)); fi

  if [[ $skills_count -gt 0 ]]; then
    echo -e "${BOLD}Skills:${NC}       ${skills_count} skills configured"
    echo ""
  fi

  # v3: Memory plugins summary
  if [[ "$FEAT_MEM0" == "true" || "$FEAT_COGNEE" == "true" ]]; then
    echo -e "${BOLD}Memory Plugins:${NC}"
    if [[ "$FEAT_MEM0" == "true" ]]; then
      echo -e "  ${GREEN}[ON]${NC}  Mem0 (endpoint: http://localhost:8080)"
    fi
    if [[ "$FEAT_COGNEE" == "true" ]]; then
      echo -e "  ${GREEN}[ON]${NC}  Cognee (endpoint: http://localhost:8000)"
    fi
    echo ""
  fi

  echo -e "${BOLD}Next Steps:${NC}"
  if [[ "$DEPLOY_MODE" == "native" ]]; then
    echo "  1. Review config:  cat ${CONFIG_DIR}/openclaw.json"
    echo "  2. Start:          openclaw"
    echo "  3. Open UI:        http://localhost:${GATEWAY_PORT}"
    if [[ "$CH_WHATSAPP" == "true" ]]; then
      echo "  4. WhatsApp pair:  openclaw channels login whatsapp"
    fi
    if [[ "$CH_SIGNAL" == "true" ]]; then
      echo "  5. Signal pair:    openclaw channels login signal"
    fi
  else
    echo "  1. Review config:  cat ${CONFIG_DIR}/openclaw.json"
    echo "  2. Edit .env:      vim ${INSTANCE_DIR}/.env  (add Tailscale key)"
    echo "  3. Start:          cd ${INSTANCE_DIR} && docker compose up -d"
    echo "  4. View logs:      docker compose logs -f openclaw-${INSTANCE_NAME}"
    echo "  5. Open UI:        http://localhost:${GATEWAY_PORT}"
    if [[ "$CH_WHATSAPP" == "true" ]]; then
      echo "  6. WhatsApp pair:  docker compose exec openclaw-${INSTANCE_NAME} openclaw channels login whatsapp"
    fi
    if [[ "$FEAT_OBSIDIAN_VAULT" == "true" && -n "$VAULT_PATH" ]]; then
      echo "  7. Vault mounted:  $VAULT_PATH → /home/node/openclaw/vault"
    fi
  fi
  if [[ "$FEAT_GOOGLE_WORKSPACE" == "true" ]]; then
    echo ""
    echo -e "${BOLD}Google Workspace:${NC}"
    echo -e "  Method:   $GOOGLE_WS_METHOD"
    if [[ -n "$GOOGLE_WS_EMAIL" ]]; then
      echo -e "  Account:  $GOOGLE_WS_EMAIL"
    fi
    if [[ ${#GOOGLE_WS_SERVICES[@]} -gt 0 ]]; then
      echo -e "  Services: ${GOOGLE_WS_SERVICES[*]}"
    fi
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
  setup_google_workspace
  setup_obsidian_vault
  setup_tag_taxonomy
  setup_claude_sync
  setup_skills
  setup_memory_config
  setup_github_backup
  generate_config
  setup_persona

  if [[ "$DEPLOY_MODE" == "docker" ]]; then
    generate_docker_compose
  else
    install_native
  fi

  # [IMPROVEMENT 1] Channel pairing (WhatsApp QR, Signal linking)
  run_channel_pairing

  # Google Workspace skill install + OAuth
  run_google_workspace_setup

  # [IMPROVEMENT 3] Post-setup verification
  run_health_check

  print_summary
}

main "$@"
