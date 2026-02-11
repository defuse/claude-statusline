#!/bin/bash
# Fetches Claude Max usage data with caching.
# Outputs JSON with utilization percentages.

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

# Get OAuth token
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo '{"error":"no credentials"}'
    exit 1
fi

TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$CREDENTIALS_FILE")
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo '{"error":"no token"}'
    exit 1
fi

# Fetch usage data
RESPONSE=$(curl -s --max-time 5 \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage")

if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    # On failure, return stale cache if available, otherwise error
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
    else
        echo '{"error":"api failed"}'
    fi
    exit 1
fi

# Cache and output
echo "$RESPONSE" > "$CACHE_FILE"
echo "$RESPONSE"
