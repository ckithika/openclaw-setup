#!/usr/bin/env bash
# browser-restart-cron.sh — Daily browser memory cleanup for OpenClaw agents
# Stops Chromium in all running agent containers. Browser auto-relaunches on next use.
# Agent process, channels, CLI auth — all unaffected.
#
# Install: crontab -e → 0 4 * * * /path/to/browser-restart-cron.sh >> /tmp/browser-restart.log 2>&1

set -euo pipefail

LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# Find all running agent containers
for container in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^(openclaw-|agent-)'); do
  # Check if browser is running in this container
  browser_status=$(docker exec "$container" openclaw browser status 2>/dev/null | grep "running:" | awk '{print $2}' || echo "unknown")

  if [[ "$browser_status" == "true" ]]; then
    echo "${LOG_PREFIX} Stopping browser in ${container}..."
    docker exec "$container" openclaw browser stop 2>/dev/null \
      && echo "${LOG_PREFIX} Browser stopped in ${container}" \
      || echo "${LOG_PREFIX} Failed to stop browser in ${container}"
  fi
done

echo "${LOG_PREFIX} Browser restart cron complete"
