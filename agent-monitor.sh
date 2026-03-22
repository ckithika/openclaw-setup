#!/usr/bin/env bash
# agent-monitor.sh — Monitor all OpenClaw Docker agent instances
# Usage: ./agent-monitor.sh [--watch]

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

show_stats() {
  echo -e "\n${BOLD}${CYAN}═══ OpenClaw Agent Monitor ═══${NC}\n"

  # System info
  local ram_gb cpu_cores
  ram_gb=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1073741824}' || echo "?")
  cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "?")
  echo -e "${BOLD}System:${NC} ${ram_gb}GB RAM, ${cpu_cores} CPU cores"

  # Total Docker usage
  local total_mem total_cpu
  total_mem=$(docker stats --no-stream --format "{{.MemUsage}}" 2>/dev/null | awk -F'/' '{
    val=$1; gsub(/[[:space:]]/, "", val)
    if (val ~ /GiB/) { gsub(/GiB/, "", val); sum += val * 1024 }
    else if (val ~ /MiB/) { gsub(/MiB/, "", val); sum += val }
    else if (val ~ /KiB/) { gsub(/KiB/, "", val); sum += val / 1024 }
  } END { printf "%.0f", sum }')
  total_cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" 2>/dev/null | awk -F'%' '{ sum += $1 } END { printf "%.1f", sum }')
  echo -e "${BOLD}Docker total:${NC} ${total_mem}MB RAM ($(( total_mem * 100 / (ram_gb * 1024) ))%), ${total_cpu}% CPU"
  echo ""

  # Agent containers
  echo -e "${BOLD}Agents:${NC}"
  printf "  ${BOLD}%-30s %-8s %-15s %-6s %-10s${NC}\n" "NAME" "CPU" "MEMORY" "MEM%" "STATUS"

  docker ps -a --format "{{.Names}}\t{{.Status}}" 2>/dev/null | while IFS=$'\t' read -r name status; do
    # Only show openclaw/agent containers, skip sidecars
    if [[ "$name" == *"openclaw-"* || "$name" == *"agent-"* ]] && \
       [[ "$name" != *"backup"* && "$name" != *"watchdog"* && "$name" != *"autoheal"* && "$name" != *"sbx"* ]]; then

      local stats_line
      stats_line=$(docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" "$name" 2>/dev/null || echo "-|-|-")
      local cpu="${stats_line%%|*}"
      local rest="${stats_line#*|}"
      local mem="${rest%%|*}"
      local mempct="${rest##*|}"

      # Color based on memory percentage
      local color="$GREEN"
      local pct_num
      pct_num=$(echo "$mempct" | tr -dc '0-9.' | cut -d. -f1)
      pct_num="${pct_num:-0}"
      if (( pct_num > 20 )); then color="$YELLOW"; fi
      if (( pct_num > 40 )); then color="$RED"; fi

      local status_short
      if [[ "$status" == *"Up"* ]]; then status_short="${GREEN}UP${NC}"
      elif [[ "$status" == *"Restarting"* ]]; then status_short="${RED}RESTART${NC}"
      else status_short="${RED}DOWN${NC}"; fi

      printf "  ${color}%-30s %-8s %-15s %-6s${NC} %b\n" "$name" "$cpu" "$mem" "$mempct" "$status_short"
    fi
  done

  # Sidecars summary
  local sidecar_count
  sidecar_count=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -cE "(backup|watchdog|autoheal)" || echo 0)
  echo -e "\n  ${CYAN}Sidecars running: ${sidecar_count} (backups, watchdogs, autoheal)${NC}"

  # Capacity estimate
  local remaining_mb=$(( ram_gb * 1024 - total_mem ))
  local agents_no_browser=$(( remaining_mb / 400 ))
  local agents_with_browser=$(( remaining_mb / 2048 ))
  echo -e "\n${BOLD}Capacity:${NC} ~${remaining_mb}MB free → ${agents_no_browser} more agents (no browser) or ${agents_with_browser} with browser"

  # Disk usage
  local docker_disk
  docker_disk=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1)
  echo -e "${BOLD}Docker disk:${NC} ${docker_disk:-unknown}"
  echo ""
}

if [[ "${1:-}" == "--watch" ]]; then
  while true; do
    clear
    show_stats
    echo -e "${CYAN}Refreshing every 30s... (Ctrl+C to stop)${NC}"
    sleep 30
  done
else
  show_stats
fi
