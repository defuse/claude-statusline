#!/bin/bash
input=$(cat)

IFS=$'\t' read -r MODEL MODEL_ID VERSION CTX_SIZE USED_PCT COST VIM_MODE DIR < <(
    echo "$input" | jq -r '[
        .model.display_name,
        .model.id,
        (.version // ""),
        (.context_window.context_window_size // 200000),
        ((.context_window.used_percentage // 0) | floor),
        (.cost.total_cost_usd // 0),
        (.vim.mode // ""),
        (.workspace.current_dir // "")
    ] | @tsv'
)

# Autocompact buffer (cached, non-blocking background probe on miss)
BUFFER_TOKENS=$("$HOME/.claude/autocompact-buffer.sh" "$VERSION" "$MODEL_ID" 2>/dev/null)
GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
CYAN='\033[36m'; MAGENTA='\033[35m'; BRIGHT_GREEN='\033[92m'; DIM='\033[2m'; GRAY='\033[90m'; RESET='\033[0m'

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

# Context bar: 3-section [used ░░░][free ███][buffer ░░░]
BAR_W=52
if [ -n "$BUFFER_TOKENS" ] && [ "$BUFFER_TOKENS" -gt 0 ] 2>/dev/null; then
    BUF_PCT=$((BUFFER_TOKENS * 100 / CTX_SIZE))
    REMAINING=$((100 - USED_PCT - BUF_PCT))
    [ "$REMAINING" -lt 0 ] && REMAINING=0
    PCT=$((100 - REMAINING))
    USED_W=$((USED_PCT * BAR_W / 100))
    BUF_W=$((BUFFER_TOKENS * BAR_W / CTX_SIZE))
    FREE_W=$((BAR_W - USED_W - BUF_W))
    [ "$FREE_W" -lt 0 ] && FREE_W=0
else
    PCT=$USED_PCT
    REMAINING=$((100 - PCT))
    USED_W=$((PCT * BAR_W / 100))
    FREE_W=$((BAR_W - USED_W))
    BUF_W=0
fi
if [ "$PCT" -ge 80 ]; then     USED_CLR='\033[2;31m'; FREE_CLR="$RED"
elif [ "$PCT" -ge 65 ]; then   USED_CLR='\033[2;33m'; FREE_CLR="$YELLOW"
else                            USED_CLR='\033[2;32m'; FREE_CLR="$GREEN"
fi
printf -v _U '%*s' "$USED_W" ''; printf -v _F '%*s' "$FREE_W" ''; printf -v _B '%*s' "$BUF_W" ''
CTX_BAR="${USED_CLR}${_U// /░}${FREE_CLR}${_F// /█}${RESET}${GRAY}${_B// /░}${RESET}"
CTX_LABEL=$((CTX_SIZE / 1000))k
COST_FMT=$(printf '$%.2f' "$COST")

# Git branch
BRANCH=""
if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
fi

# Line 1: model, vim mode, directory, git branch
MODEL_COLOR="$CYAN"
[[ "$MODEL_ID" == *sonnet* ]] && MODEL_COLOR="$RED"
LINE1="${MODEL_COLOR}[$MODEL]${RESET}"
if [ -n "$VIM_MODE" ]; then LINE1="$LINE1 ${BRIGHT_GREEN}[V]${RESET}"
else LINE1="$LINE1 ${MAGENTA}[N]${RESET}"; fi
LINE1="$LINE1 ${DIR}"
[ -n "$BRANCH" ] && LINE1="$LINE1 ${DIM}on${RESET} ${GREEN}$BRANCH${RESET}"

# Line 2: context window bar
REM_FMT=$(printf '%2s' "$REMAINING")
LINE2="${CTX_BAR} ${REM_FMT}% of ${CTX_LABEL}"

# Line 3: Max plan usage + cost
USAGE=$("$HOME/.claude/usage.sh" 2>/dev/null)
if [ -n "$USAGE" ]; then
    IFS=$'\t' read -r H5 D7 H5_RESET D7_RESET EXTRA_USED < <(
        echo "$USAGE" | jq -r '[
                ((.five_hour.utilization // 0) | round),
                ((.seven_day.utilization // 0) | round),
                (.five_hour.resets_at // ""),
                (.seven_day.resets_at // ""),
                (.extra_usage.used_credits // 0)
            ] | @tsv' 2>/dev/null
    )
fi
if [ -n "$H5" ] && [ "$H5" != "null" ]; then
    H5_COLOR=$(pct_color "$DIM" "$H5")
    D7_COLOR=$(pct_color "$DIM" "$D7")
    H5_BAR=$(make_bar "$H5" 10)
    D7_BAR=$(make_bar "$D7" 10)

    H5_FMT=$(printf '%2s' "$H5")
    D7_FMT=$(printf '%2s' "$D7")

    # Countdown: 5h resets_at -> XhXXm
    NOW=$(date +%s)
    if [ -n "$H5_RESET" ]; then
        H5_EPOCH=$(date -d "$H5_RESET" +%s 2>/dev/null)
        H5_LEFT=$(( H5_EPOCH - NOW ))
        [ "$H5_LEFT" -lt 0 ] && H5_LEFT=0
        H5_CD=$(printf '%dh%02dm' $((H5_LEFT/3600)) $(( (H5_LEFT%3600)/60 )))
    else
        H5_CD="?h??m"
    fi

    # Countdown: 7d resets_at -> XdXXhXXm
    if [ -n "$D7_RESET" ]; then
        D7_EPOCH=$(date -d "$D7_RESET" +%s 2>/dev/null)
        D7_LEFT=$(( D7_EPOCH - NOW ))
        [ "$D7_LEFT" -lt 0 ] && D7_LEFT=0
        D7_CD=$(printf '%dd%02dh%02dm' $((D7_LEFT/86400)) $(( (D7_LEFT%86400)/3600 )) $(( (D7_LEFT%3600)/60 )))
    else
        D7_CD="?d??h??m"
    fi

    LINE3="5h ${H5_COLOR}${H5_BAR}${RESET} ${H5_FMT}% ${DIM}${H5_CD}${RESET}   7d ${D7_COLOR}${D7_BAR}${RESET} ${D7_FMT}% ${DIM}${D7_CD}${RESET}"

    EXTRA_FMT=$(printf '$%.2f' "$EXTRA_USED")
    LINE3="$LINE3 ${DIM}${EXTRA_FMT}${RESET}  ${DIM}${COST_FMT}${RESET}"
else
    LINE3="${DIM}${COST_FMT}${RESET}"
fi

echo -e "$LINE1"
echo -e "$LINE2"
echo -e "$LINE3"
