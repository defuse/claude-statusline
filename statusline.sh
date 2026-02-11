#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
REMAINING=$(echo "$input" | jq -r '.context_window.remaining_percentage // 100' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
CYAN='\033[36m'; MAGENTA='\033[35m'; BRIGHT_GREEN='\033[92m'; DIM='\033[2m'; RESET='\033[0m'

# Build a progress bar: usage $1=pct $2=width
make_bar() {
    local pct=$1 width=$2
    local filled=$((pct * width / 100))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$((width - filled))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+='█'; done
    for ((i=0; i<empty; i++)); do bar+='░'; done
    echo "$bar"
}

# Color for a percentage
pct_color() {
    local default=$1 pct=$2
    if [ "$pct" -ge 80 ]; then echo "$RED"
    elif [ "$pct" -ge 60 ]; then echo "$YELLOW"
    else echo "$default"; fi
}

DARK_GREEN='\033[2;32m'
CTX_COLOR=$(pct_color "$DARK_GREEN" "$PCT")
CTX_BAR_RAW=$(make_bar "$PCT" 52)
CTX_BAR=$(echo "$CTX_BAR_RAW" | tr '█░' '░█')
CTX_LABEL=$((CTX_SIZE / 1000))k
COST_FMT=$(printf '$%.2f' "$COST")

# Git branch
BRANCH=""
if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
fi

# Line 1: model, vim mode, directory, git branch
MODEL_COLOR="$CYAN"
echo "$input" | jq -r '.model.id' | grep -qi sonnet && MODEL_COLOR="$RED"
LINE1="${MODEL_COLOR}[$MODEL]${RESET}"
if [ -n "$VIM_MODE" ]; then LINE1="$LINE1 ${BRIGHT_GREEN}[V]${RESET}"
else LINE1="$LINE1 ${MAGENTA}[N]${RESET}"; fi
LINE1="$LINE1 ${DIR}"
[ -n "$BRANCH" ] && LINE1="$LINE1 ${DIM}on${RESET} ${GREEN}$BRANCH${RESET}"

# Line 2: context window bar
REM_FMT=$(printf '%2s' "$REMAINING")
LINE2="${CTX_COLOR}${CTX_BAR}${RESET} ${REM_FMT}% of ${CTX_LABEL}"

# Line 3: Max plan usage + cost
USAGE=$("$HOME/.claude/usage.sh" 2>/dev/null)
if [ -n "$USAGE" ] && ! echo "$USAGE" | jq -e '.error' > /dev/null 2>&1; then
    H5=$(echo "$USAGE" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    D7=$(echo "$USAGE" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')

    H5_COLOR=$(pct_color "$DIM" "$H5")
    D7_COLOR=$(pct_color "$DIM" "$D7")
    H5_BAR=$(make_bar "$H5" 10)
    D7_BAR=$(make_bar "$D7" 10)

    H5_FMT=$(printf '%2s' "$H5")
    D7_FMT=$(printf '%2s' "$D7")

    # Countdown: 5h resets_at -> XhXXm
    NOW=$(date +%s)
    H5_RESET=$(echo "$USAGE" | jq -r '.five_hour.resets_at // empty')
    if [ -n "$H5_RESET" ]; then
        H5_EPOCH=$(date -d "$H5_RESET" +%s 2>/dev/null)
        H5_LEFT=$(( H5_EPOCH - NOW ))
        [ "$H5_LEFT" -lt 0 ] && H5_LEFT=0
        H5_CD=$(printf '%dh%02dm' $((H5_LEFT/3600)) $(( (H5_LEFT%3600)/60 )))
    else
        H5_CD="?h??m"
    fi

    # Countdown: 7d resets_at -> XdXXhXXm
    D7_RESET=$(echo "$USAGE" | jq -r '.seven_day.resets_at // empty')
    if [ -n "$D7_RESET" ]; then
        D7_EPOCH=$(date -d "$D7_RESET" +%s 2>/dev/null)
        D7_LEFT=$(( D7_EPOCH - NOW ))
        [ "$D7_LEFT" -lt 0 ] && D7_LEFT=0
        D7_CD=$(printf '%dd%02dh%02dm' $((D7_LEFT/86400)) $(( (D7_LEFT%86400)/3600 )) $(( (D7_LEFT%3600)/60 )))
    else
        D7_CD="?d??h??m"
    fi

    LINE3="5h ${H5_COLOR}${H5_BAR}${RESET} ${H5_FMT}% ${DIM}${H5_CD}${RESET}   7d ${D7_COLOR}${D7_BAR}${RESET} ${D7_FMT}% ${DIM}${D7_CD}${RESET}"

    EXTRA_USED=$(echo "$USAGE" | jq -r '.extra_usage.used_credits // 0')
    EXTRA_FMT=$(printf '$%.2f' "$EXTRA_USED")
    LINE3="$LINE3 ${DIM}${EXTRA_FMT}${RESET}  ${DIM}${COST_FMT}${RESET}"
else
    LINE3="${DIM}${COST_FMT}${RESET}"
fi

echo -e "$LINE1"
echo -e "$LINE2"
echo -e "$LINE3"
