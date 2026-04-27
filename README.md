# claude-statusline

My Claude Code status line — shared across machines via symlinks.

Renders the current directory, model, git branch, context usage, session
cost, weekly burn, 5-hour block timer, and active session count.

## Install

```bash
git clone git@github.com:sirkitree/claude-statusline.git ~/repos/claude-statusline
cd ~/repos/claude-statusline
./install.sh
```

The installer symlinks `statusline.sh` and `statusline-config.json`
into `~/.claude/`, backing up any existing files to
`~/.claude/<name>.backup-<timestamp>`.

Then make sure `~/.claude/settings.json` points at the script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

## Update

```bash
cd ~/repos/claude-statusline && git pull
```

Symlinks pick up changes automatically — no reinstall needed.

## Configure

Edit `statusline-config.json` (or the symlinked copy at
`~/.claude/statusline-config.json` — same file). Common knobs:

- `user.plan` — `pro`, `max5x`, or `max20x`
- `limits.weekly.<plan>` — weekly cost cap in USD
- `limits.context` — context window threshold (in thousands)
- `limits.cost` — per-5-hour-block cost limit
- `sections.*` — toggle individual statusline sections on/off
- `colors.*` — ANSI color codes for each element

## Requirements

- `bash`, `jq`, `awk`
- `npx` (used to invoke
  [`ccusage`](https://www.npmjs.com/package/ccusage) for block/cost data)
