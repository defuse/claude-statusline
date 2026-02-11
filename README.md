![my statusline](https://raw.githubusercontent.com/defuse/claude-statusline/refs/heads/main/statusline.png)

## Installation

Add these scripts to `~/.claude` and add the `statusline.sh` script to your `~/.claude/settings.json`, e.g:

```json
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

## Dependencies

- `jq` - JSON parsing
- `python3` with `pty` module (stdlib) - used by `autocompact-buffer.sh` to probe Claude Code's `/context` command in a fake TTY
- `/tmp` must be a trusted workspace in Claude Code (run `claude` once in `/tmp` and accept the trust prompt). The probe runs there to avoid polluting session history in your actual projects.
- `git` - branch display (optional, degrades gracefully)

## Scripts

- **statusline.sh** - Main statusline renderer. Shows model, vim mode, directory, git branch, a 3-section context bar (used/free/autocompact buffer), rate limit usage, and cost.
- **autocompact-buffer.sh** - Probes Claude Code's `/context` command to discover the autocompact buffer size. Caches the result per claude version + model. On cache miss, returns immediately and probes in the background; the next statusline refresh picks up the cached value.
- **usage.sh** - Fetches rate limit utilization (5h and 7d windows).

## Context bar

The context bar has three sections:

```
░░░░░░░░░░░░████████████████████████████░░░░░░░░░░
  used          free before compaction      buffer
```

The displayed percentage is free space before autocompact triggers, matching the "Free space" shown by `/context`. Colors shift from green to yellow (60%) to red (80%) as context fills up.
