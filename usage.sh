#!/bin/bash
# Fetches Claude Max usage data with caching.
# On cache miss, returns stale cache (or nothing) immediately and fetches in background.

CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_MAX_AGE=120
CREDENTIALS_FILE="$HOME/.claude/.credentials.json"

# Check if cache is fresh
if [ -f "$CACHE_FILE" ]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    if [ "$AGE" -lt "$CACHE_MAX_AGE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Cache miss: return stale cache immediately (if any), then refresh in background
if [ -f "$CACHE_FILE" ]; then
    cat "$CACHE_FILE"
fi

# Get OAuth token (needed before backgrounding)
if [ ! -f "$CREDENTIALS_FILE" ]; then
    exit 0
fi

TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$CREDENTIALS_FILE")
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    exit 0
fi

# Lock to prevent concurrent background fetches
LOCK_FILE="/tmp/claude-usage-cache.lock"
if [ -d "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
    [ "$LOCK_AGE" -gt 15 ] && rmdir "$LOCK_FILE" 2>/dev/null
fi
mkdir "$LOCK_FILE" 2>/dev/null || exit 0

# Background fetch
(
    trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT

    RESPONSE=$(curl -s --max-time 5 \
        -H "Authorization: Bearer $TOKEN" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage")

    if [ $? -eq 0 ] && [ -n "$RESPONSE" ] && echo "$RESPONSE" | jq -e . >/dev/null 2>&1; then
        echo "$RESPONSE" > "$CACHE_FILE"
    fi
) &>/dev/null &
disown
