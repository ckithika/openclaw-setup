#!/usr/bin/env bash
# agent-security-audit.sh — Daily security audit for all OpenClaw Docker agents
# Checks credentials exposure, container health, permissions, and suspicious activity
#
# Install: crontab -e → 0 5 * * * /path/to/agent-security-audit.sh >> /tmp/agent-security-audit.log 2>&1
# Manual: ./agent-security-audit.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
ISSUES=0
WARNINGS=0

pass()  { echo -e "  ${GREEN}[PASS]${NC} $*"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $*"; WARNINGS=$((WARNINGS + 1)); }
fail()  { echo -e "  ${RED}[FAIL]${NC} $*"; ISSUES=$((ISSUES + 1)); }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }

echo -e "\n${BOLD}${CYAN}═══ OpenClaw Agent Security Audit ═══${NC}"
echo -e "${CYAN}${TIMESTAMP}${NC}\n"

# ── 1. Container Health ──────────────────────────────────────────────────
header "Container Health"

docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null | while IFS=$'\t' read -r name status; do
  if [[ "$name" == *"openclaw-"* || "$name" == *"agent-"* ]] && \
     [[ "$name" != *"backup"* && "$name" != *"watchdog"* && "$name" != *"autoheal"* && "$name" != *"sbx"* ]]; then
    if [[ "$status" == *"Up"* ]]; then
      if [[ "$status" == *"healthy"* ]]; then
        pass "$name: running (healthy)"
      elif [[ "$status" == *"Restarting"* ]]; then
        fail "$name: crash-looping"
      else
        pass "$name: running"
      fi
    else
      fail "$name: not running ($status)"
    fi
  fi
done

# ── 2. Credentials File Permissions ──────────────────────────────────────
header "Credential Permissions"

for instance_dir in ~/openclaw-instances/*/; do
  local_name=$(basename "$instance_dir")

  # Check .env permissions
  if [[ -f "${instance_dir}.env" ]]; then
    perms=$(stat -f "%Lp" "${instance_dir}.env" 2>/dev/null || stat -c "%a" "${instance_dir}.env" 2>/dev/null)
    if [[ "$perms" == "600" ]]; then
      pass "${local_name}/.env: chmod 600"
    else
      fail "${local_name}/.env: chmod ${perms} (should be 600)"
    fi
  fi

  # Check credentials directory
  if [[ -d "${instance_dir}config/credentials" ]]; then
    perms=$(stat -f "%Lp" "${instance_dir}config/credentials" 2>/dev/null || stat -c "%a" "${instance_dir}config/credentials" 2>/dev/null)
    if [[ "$perms" == "700" ]]; then
      pass "${local_name}/credentials: chmod 700"
    else
      warn "${local_name}/credentials: chmod ${perms} (should be 700)"
    fi
  fi

  # Check for credentials-log.md (should not be world-readable)
  if [[ -f "${instance_dir}workspace/credentials-log.md" ]]; then
    perms=$(stat -f "%Lp" "${instance_dir}workspace/credentials-log.md" 2>/dev/null || stat -c "%a" "${instance_dir}workspace/credentials-log.md" 2>/dev/null)
    if [[ "$perms" == "600" ]]; then
      pass "${local_name}/credentials-log.md: chmod 600"
    else
      warn "${local_name}/credentials-log.md: chmod ${perms} (should be 600)"
    fi
  fi
done

# ── 3. Exposed Secrets in Config ─────────────────────────────────────────
header "Secret Exposure"

for instance_dir in ~/openclaw-instances/*/; do
  local_name=$(basename "$instance_dir")

  # Check for API keys in openclaw.json (should be in credentials/ not inline)
  if [[ -f "${instance_dir}config/openclaw.json" ]]; then
    if grep -qiE '"(apiKey|api_key|secret|password)"' "${instance_dir}config/openclaw.json" 2>/dev/null; then
      # Bot tokens in channel config are expected, but API keys should be in credentials/
      inline_keys=$(grep -ciE '"apiKey"' "${instance_dir}config/openclaw.json" 2>/dev/null || echo 0)
      if [[ "$inline_keys" -gt 0 ]]; then
        warn "${local_name}: ${inline_keys} inline API key(s) in openclaw.json (move to credentials/)"
      fi
    else
      pass "${local_name}: no inline API keys in config"
    fi
  fi

  # Check docker-compose.yml for hardcoded secrets
  if [[ -f "${instance_dir}docker-compose.yml" ]]; then
    if grep -qE '(sk-|ghp_|gho_|tskey-|xoxb-|xapp-)' "${instance_dir}docker-compose.yml" 2>/dev/null; then
      fail "${local_name}: hardcoded tokens in docker-compose.yml (use .env variables)"
    else
      pass "${local_name}: no hardcoded tokens in docker-compose.yml"
    fi
  fi
done

# ── 4. Git Safety ────────────────────────────────────────────────────────
header "Git Safety"

for instance_dir in ~/openclaw-instances/*/; do
  local_name=$(basename "$instance_dir")

  # Check if credentials-log.md is tracked by git (it shouldn't be)
  if [[ -d "${instance_dir}.git" ]]; then
    if git -C "$instance_dir" ls-files --error-unmatch workspace/credentials-log.md 2>/dev/null; then
      fail "${local_name}: credentials-log.md is tracked by git!"
    fi
  fi
done

# Check workspace dirs mounted into containers for .env files
for instance_dir in ~/openclaw-instances/*/; do
  local_name=$(basename "$instance_dir")
  if find "${instance_dir}workspace" -name ".env" -o -name "*.key" -o -name "*.pem" 2>/dev/null | grep -q .; then
    warn "${local_name}: sensitive files found in workspace/ (accessible to agent)"
  else
    pass "${local_name}: no sensitive files in workspace/"
  fi
done

# ── 5. Network Exposure ──────────────────────────────────────────────────
header "Network Exposure"

for instance_dir in ~/openclaw-instances/*/; do
  local_name=$(basename "$instance_dir")

  if [[ -f "${instance_dir}config/openclaw.json" ]]; then
    bind=$(python3 -c "import json; c=json.load(open('${instance_dir}config/openclaw.json')); print(c.get('gateway',{}).get('bind','loopback'))" 2>/dev/null || echo "unknown")
    if [[ "$bind" == "loopback" || "$bind" == "127.0.0.1" ]]; then
      pass "${local_name}: gateway bound to loopback only"
    else
      warn "${local_name}: gateway bound to ${bind} (exposed to network)"
    fi
  fi
done

# ── 6. Container Security Options ────────────────────────────────────────
header "Container Security"

docker ps --format '{{.Names}}' 2>/dev/null | while read -r name; do
  if [[ "$name" == *"openclaw-"* || "$name" == *"agent-"* ]] && \
     [[ "$name" != *"backup"* && "$name" != *"watchdog"* && "$name" != *"autoheal"* && "$name" != *"sbx"* ]]; then
    # Check if running as root
    user=$(docker exec "$name" whoami 2>/dev/null || echo "unknown")
    if [[ "$user" == "root" ]]; then
      fail "${name}: running as root"
    else
      pass "${name}: running as ${user}"
    fi

    # Check no-new-privileges
    security=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$name" 2>/dev/null || echo "[]")
    if [[ "$security" == *"no-new-privileges"* ]]; then
      pass "${name}: no-new-privileges set"
    else
      warn "${name}: no-new-privileges not set"
    fi
  fi
done

# ── 7. Recent Suspicious Activity ────────────────────────────────────────
header "Activity Check (last 24h)"

docker ps --format '{{.Names}}' 2>/dev/null | while read -r name; do
  if [[ "$name" == *"openclaw-"* || "$name" == *"agent-"* ]] && \
     [[ "$name" != *"backup"* && "$name" != *"watchdog"* && "$name" != *"autoheal"* && "$name" != *"sbx"* ]]; then
    # Check for force-push attempts
    force_push=$(docker logs --since 24h "$name" 2>&1 | grep -ci "force-push\|--force\|reset --hard" || true)
    if [[ "$force_push" -gt 0 ]]; then
      fail "${name}: ${force_push} force-push/reset attempts in last 24h"
    fi

    # Check for rm -rf or destructive commands
    destructive=$(docker logs --since 24h "$name" 2>&1 | grep -ci "rm -rf\|DROP TABLE\|DELETE FROM\|truncate" || true)
    if [[ "$destructive" -gt 0 ]]; then
      warn "${name}: ${destructive} potentially destructive commands in last 24h"
    fi

    # Check for credential access patterns
    cred_access=$(docker logs --since 24h "$name" 2>&1 | grep -ci "\.env\|api_key\|secret_key\|password" || true)
    if [[ "$cred_access" -gt 5 ]]; then
      warn "${name}: ${cred_access} credential-related log entries in last 24h (review)"
    fi
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ Summary ═══${NC}"
if [[ "$ISSUES" -eq 0 && "$WARNINGS" -eq 0 ]]; then
  echo -e "${GREEN}All checks passed. No issues found.${NC}"
elif [[ "$ISSUES" -eq 0 ]]; then
  echo -e "${YELLOW}${WARNINGS} warning(s), no critical issues.${NC}"
else
  echo -e "${RED}${ISSUES} issue(s), ${WARNINGS} warning(s). Review above.${NC}"
fi
echo ""
