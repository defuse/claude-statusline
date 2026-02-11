![my statusline](https://raw.githubusercontent.com/defuse/claude-statusline/refs/heads/main/statusline.png)

To install, add these scripts to `~/.claude` and add the `statusline.sh` script to your `~/.claude/settings.json`, for example:

```
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```