#!/bin/bash
# Probes Claude Code's /context command to extract the autocompact buffer size.
# Caches result per claude version + model so we only spawn once per upgrade.
# Usage: autocompact-buffer.sh <version> <model_id>
#   Prints buffer size in tokens (e.g. 33000) to stdout, or nothing on failure.

CLAUDE_VER="${1:-unknown}"
MODEL_ID="${2:-unknown}"
CACHE_DIR="$HOME/.claude/cache"
CACHE_FILE="$CACHE_DIR/autocompact_buffer_${CLAUDE_VER}_${MODEL_ID}.val"

# Check cache
if [ -f "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
    exit 0
fi

# Cache miss: print nothing and probe in the background.
# Next statusline refresh will pick up the cached value.
LOCK_FILE="${CACHE_DIR}/autocompact_buffer.lock"

# Clear stale locks (older than 60s = probe should finish in ~20s)
if [ -d "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
    [ "$LOCK_AGE" -gt 60 ] && rmdir "$LOCK_FILE" 2>/dev/null
fi

if mkdir "$LOCK_FILE" 2>/dev/null; then
    (
        trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT

        RAW=$(python3 -c "
import pty, os, select, time, sys, re

pid, fd = pty.fork()
if pid == 0:
    os.environ['CLAUDE_AUTO_UPDATE'] = '0'
    os.chdir('/tmp')
    # TODO: MODEL_ID is shell-interpolated into Python; would break on single quotes
    os.execvp('claude', ['claude', '--model', '$MODEL_ID'])
    os._exit(1)
else:
    buf = []
    def read_all(t=0.5):
        while True:
            r, _, _ = select.select([fd], [], [], t)
            if r:
                try: buf.append(os.read(fd, 8192))
                except: return
            else: return
    time.sleep(5)
    read_all()
    for c in '/context':
        os.write(fd, c.encode())
        time.sleep(0.1)
    time.sleep(0.5)
    os.write(fd, b'\r')
    time.sleep(8)
    read_all(1.0)
    for c in '/exit':
        os.write(fd, c.encode())
        time.sleep(0.1)
    time.sleep(0.5)
    os.write(fd, b'\r')
    time.sleep(3)
    read_all()
    try: os.kill(pid, 15)
    except: pass
    for _ in range(10):
        try:
            p, _ = os.waitpid(pid, os.WNOHANG)
            if p: break
        except: break
        time.sleep(0.5)
    else:
        try: os.kill(pid, 9)
        except: pass
        try: os.waitpid(pid, 0)
        except: pass
    output = b''.join(buf)
    clean = re.sub(rb'\x1b\[[0-9;]*[a-zA-Z]|\x1b\]\d*;?[^\x07]*\x07?', b'', output)
    sys.stdout.buffer.write(clean)
" 2>/dev/null)

        BUFFER_K=$(echo "$RAW" | grep -oP 'Autocompact\s*buffer[^0-9]*(\d+\.?\d*)k' | grep -oP '[\d.]+(?=k)' | head -1)
        if [ -n "$BUFFER_K" ]; then
            BUFFER_TOKENS=$(awk "BEGIN {printf \"%.0f\", $BUFFER_K * 1000}")
            mkdir -p "$CACHE_DIR"
            printf '%s' "$BUFFER_TOKENS" > "$CACHE_FILE"
        fi
    ) &>/dev/null &
    disown
fi
