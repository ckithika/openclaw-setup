#!/bin/zsh
# Auto-run setup when config template changes
# Usage: ./watch-and-setup.sh

echo "Watching ~/code/openclaw-setup/config-template.yaml..."

if command -v fswatch > /dev/null; then
    fswatch -o ~/code/openclaw-setup/config-template.yaml | while read; do
        echo "Config changed! Running setup..."
        ~/code/openclaw-setup/setup.sh --force
    done
else
    echo "Install fswatch first: brew install fswatch"
fi
