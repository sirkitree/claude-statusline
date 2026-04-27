#!/bin/bash
# Symlink statusline.sh and statusline-config.json into ~/.claude/.
# Existing files are backed up to ~/.claude/<name>.backup-<timestamp>.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CLAUDE_DIR"

link_file() {
    local src="$1"
    local dest="$2"

    if [ -L "$dest" ]; then
        rm "$dest"
    elif [ -e "$dest" ]; then
        local backup="${dest}.backup-${TIMESTAMP}"
        echo "Backing up existing $dest -> $backup"
        mv "$dest" "$backup"
    fi

    ln -s "$src" "$dest"
    echo "Linked $dest -> $src"
}

link_file "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
link_file "$REPO_DIR/statusline-config.json" "$CLAUDE_DIR/statusline-config.json"

echo
echo "Done. Make sure ~/.claude/settings.json has:"
echo '  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }'
