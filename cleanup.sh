# Manual cleanup helper
pkill -f 'openclaw-setup/setup.sh' 2>/dev/null; rm -f /tmp/openclaw-setup.pid; echo 'Cleaned up'
