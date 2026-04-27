#!/bin/bash
set -uo pipefail
DEBUG_LOG="/tmp/statusline_debug.log"
echo "=== Statusline called at $(date) ===" >> "$DEBUG_LOG"
input=$(cat)
echo "Input received: ${#input} chars" >> "$DEBUG_LOG"

# Configuration file path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/statusline-config.json"

# Load configuration from JSON file if it exists
if [ -f "$CONFIG_FILE" ]; then
    CONFIG=$(cat "$CONFIG_FILE")

    # User Configuration
    USER_PLAN=$(echo "$CONFIG" | jq -r '.user.plan // "max5x"')

    # Limits
    WEEKLY_LIMIT_PRO=$(echo "$CONFIG" | jq -r '.limits.weekly.pro // 300')
    WEEKLY_LIMIT_MAX5X=$(echo "$CONFIG" | jq -r '.limits.weekly.max5x // 500')
    WEEKLY_LIMIT_MAX20X=$(echo "$CONFIG" | jq -r '.limits.weekly.max20x // 850')
    CONTEXT_LIMIT=$(echo "$CONFIG" | jq -r '.limits.context // 168')
    COST_LIMIT=$(echo "$CONFIG" | jq -r '.limits.cost // 140')
    TOKEN_LIMIT=$(echo "$CONFIG" | jq -r '.limits.token // 220000')

    # Paths
    CLAUDE_PROJECTS_PATH=$(echo "$CONFIG" | jq -r '.paths.claude_projects // "~/.claude/projects/"')

    # Display settings
    BAR_LENGTH=$(echo "$CONFIG" | jq -r '.display.bar_length // 10')
    TRANSCRIPT_TAIL_LINES=$(echo "$CONFIG" | jq -r '.display.transcript_tail_lines // 200')
    SESSION_ACTIVITY_THRESHOLD=$(echo "$CONFIG" | jq -r '.display.session_activity_threshold_minutes // 5')

    # ccusage version
    CCUSAGE_VERSION=$(echo "$CONFIG" | jq -r '.ccusage_version // "17.1.0"')

    # Multi-layer settings - load thresholds
    LAYER1_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer1.threshold_percent // 30')
    LAYER2_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer2.threshold_percent // 50')
    LAYER3_THRESHOLD=$(echo "$CONFIG" | jq -r '.multi_layer.layer3.threshold_percent // 100')

    # Calculate multipliers dynamically based on thresholds
    LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
    LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
    LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")

    # Section toggles
    SHOW_DIRECTORY=$(echo "$CONFIG" | jq -r '.sections.show_directory // true')
    SHOW_MODEL=$(echo "$CONFIG" | jq -r '.sections.show_model // true')
    SHOW_EFFORT=$(echo "$CONFIG" | jq -r '.sections.show_effort // true')
    SHOW_GIT_BRANCH=$(echo "$CONFIG" | jq -r '.sections.show_git_branch // true')
    SHOW_CONTEXT=$(echo "$CONFIG" | jq -r '.sections.show_context // true')
    SHOW_COST=$(echo "$CONFIG" | jq -r '.sections.show_cost // true')
    SHOW_WEEKLY=$(echo "$CONFIG" | jq -r '.sections.show_weekly // true')
    SHOW_TIMER=$(echo "$CONFIG" | jq -r '.sections.show_timer // true')
    SHOW_SESSIONS=$(echo "$CONFIG" | jq -r '.sections.show_sessions // true')

    # Color codes
    ORANGE_CODE=$(echo "$CONFIG" | jq -r '.colors.orange // "\\033[1;38;5;208m"' | sed 's/\\\\/\\/g')
    RED_CODE=$(echo "$CONFIG" | jq -r '.colors.red // "\\033[1;31m"' | sed 's/\\\\/\\/g')
    PINK_CODE=$(echo "$CONFIG" | jq -r '.colors.pink // "\\033[38;5;225m"' | sed 's/\\\\/\\/g')
    GREEN_CODE=$(echo "$CONFIG" | jq -r '.colors.green // "\\033[38;5;194m"' | sed 's/\\\\/\\/g')
    PURPLE_CODE=$(echo "$CONFIG" | jq -r '.colors.purple // "\\033[35m"' | sed 's/\\\\/\\/g')
    CYAN_CODE=$(echo "$CONFIG" | jq -r '.colors.cyan // "\\033[96m"' | sed 's/\\\\/\\/g')
    YELLOW_CODE=$(echo "$CONFIG" | jq -r '.colors.yellow // "\\033[33m"' | sed 's/\\\\/\\/g')
    RESET_CODE=$(echo "$CONFIG" | jq -r '.colors.reset // "\\033[0m"' | sed 's/\\\\/\\/g')
else
    # Default configuration (fallback if config file doesn't exist)
    USER_PLAN="max5x"
    WEEKLY_LIMIT_PRO=300
    WEEKLY_LIMIT_MAX5X=500
    WEEKLY_LIMIT_MAX20X=850
    CONTEXT_LIMIT=168
    COST_LIMIT=140
    TOKEN_LIMIT=220000
    CLAUDE_PROJECTS_PATH="~/.claude/projects/"
    BAR_LENGTH=10
    TRANSCRIPT_TAIL_LINES=200
    SESSION_ACTIVITY_THRESHOLD=5
    CCUSAGE_VERSION="17.1.0"
    LAYER1_THRESHOLD=30
    LAYER2_THRESHOLD=50
    LAYER3_THRESHOLD=100
    # Calculate multipliers dynamically
    LAYER1_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / $LAYER1_THRESHOLD}")
    LAYER2_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER2_THRESHOLD - $LAYER1_THRESHOLD)}")
    LAYER3_MULTIPLIER=$(awk "BEGIN {printf \"%.2f\", 100 / ($LAYER3_THRESHOLD - $LAYER2_THRESHOLD)}")
    # Default section toggles
    SHOW_DIRECTORY=true
    SHOW_MODEL=true
    SHOW_EFFORT=true
    SHOW_GIT_BRANCH=true
    SHOW_CONTEXT=true
    SHOW_COST=true
    SHOW_WEEKLY=true
    SHOW_TIMER=true
    SHOW_SESSIONS=true
    # Default color codes
    ORANGE_CODE='\033[1;38;5;208m'
    RED_CODE='\033[1;31m'
    PINK_CODE='\033[38;5;225m'
    GREEN_CODE='\033[38;5;194m'
    PURPLE_CODE='\033[35m'
    CYAN_CODE='\033[96m'
    YELLOW_CODE='\033[33m'
    RESET_CODE='\033[0m'
fi

# Abbreviate model display name: "Claude 3.5 Sonnet" → "s3.5", "Claude Opus 4" → "o4"
# Appends "(1m)" suffix when context window is 1,000,000 tokens.
_abbreviate_model() {
    local _name="$1"
    local _ctx_size="${2:-200000}"

    # Determine tier prefix
    local _prefix=""
    case "$_name" in
        *[Oo]pus*)   _prefix="o" ;;
        *[Ss]onnet*) _prefix="s" ;;
        *[Hh]aiku*)  _prefix="h" ;;
        *)           echo "$_name"; return ;;
    esac

    # Extract version number (e.g. "4.7", "3.5", "4")
    local _ver=""
    _ver=$(echo "$_name" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -z "$_ver" ]; then
        _ver=$(echo "$_name" | grep -oE '[0-9]+' | tail -1)
    fi

    # 1M context suffix
    local _suffix=""
    if [ "$_ctx_size" -ge 900000 ] 2>/dev/null; then
        _suffix="(1m)"
    fi

    echo "${_prefix}${_ver}${_suffix}"
}

# Abbreviate /effort level: low→lo, medium→md, high→hi, xhigh→xh, max→mx.
# Empty input (model doesn't expose effort) returns empty.
_abbreviate_effort() {
    case "$1" in
        low)    echo "lo" ;;
        medium) echo "md" ;;
        high)   echo "hi" ;;
        xhigh)  echo "xh" ;;
        max)    echo "mx" ;;
        *)      echo "" ;;
    esac
}

# Basic statusline when ccusage has no active block
_show_basic_statusline() {
    local _input="$1"
    local _model="$2"
    local _cwd="$3"
    local _dir="$4"

    # Git branch
    local _branch=""
    if [ -d "${_cwd}/.git" ]; then
        _branch=$(cd "$_cwd" && git --no-optional-locks branch --show-current 2>/dev/null)
    fi

    # Context window from JSON input
    local _ctx_used_pct
    _ctx_used_pct=$(echo "$_input" | jq -r '.context_window.used_percentage // empty')
    local _ctx_window_size
    _ctx_window_size=$(echo "$_input" | jq -r '.context_window.context_window_size // 200000')

    # Abbreviate model name
    local _model_abbr
    _model_abbr=$(_abbreviate_model "$_model" "$_ctx_window_size")
    local _ctx_input
    _ctx_input=$(echo "$_input" | jq -r '.context_window.current_usage.input_tokens // 0')
    local _ctx_cache_create
    _ctx_cache_create=$(echo "$_input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
    local _ctx_cache_read
    _ctx_cache_read=$(echo "$_input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
    local _ctx_actual_k
    _ctx_actual_k=$(awk "BEGIN {printf \"%.0f\", ($_ctx_input + $_ctx_cache_create + $_ctx_cache_read) / 1000}")
    local _ctx_window_k
    _ctx_window_k=$(awk "BEGIN {printf \"%.0f\", $_ctx_window_size / 1000}")
    if [ -z "$_ctx_used_pct" ]; then
        _ctx_used_pct=$(awk "BEGIN {printf \"%.0f\", (($_ctx_input + $_ctx_cache_create + $_ctx_cache_read) / $_ctx_window_size) * 100}")
    else
        _ctx_used_pct=$(printf "%.0f" "$_ctx_used_pct")
    fi
    local _ctx_filled
    _ctx_filled=$(awk "BEGIN {printf \"%.0f\", ($_ctx_used_pct / 100) * $BAR_LENGTH}")
    if [ "$_ctx_filled" -gt "$BAR_LENGTH" ]; then _ctx_filled=$BAR_LENGTH; fi
    local _ctx_bar="["
    for ((i=0; i<_ctx_filled; i++)); do _ctx_bar="${_ctx_bar}█"; done
    for ((i=_ctx_filled; i<BAR_LENGTH; i++)); do _ctx_bar="${_ctx_bar}░"; done
    _ctx_bar="${_ctx_bar}]"

    # /effort level (only present on models that support it)
    local _effort_level _effort_abbr
    _effort_level=$(echo "$_input" | jq -r '.effort.level // empty')
    if [ -z "$_effort_level" ] && [ -f "$HOME/.claude/settings.json" ]; then
        _effort_level=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
    fi
    _effort_abbr=$(_abbreviate_effort "$_effort_level")

    # Build sections
    local _parts=()
    [[ "$SHOW_DIRECTORY" == "true" ]] && _parts+=("${ORANGE_CODE}${_dir}${RESET_CODE}")
    [[ "$SHOW_MODEL" == "true" && -n "$_model" ]] && _parts+=("${CYAN_CODE}${_model_abbr}${RESET_CODE}")
    [[ "$SHOW_EFFORT" == "true" && -n "$_effort_abbr" ]] && _parts+=("${YELLOW_CODE}${_effort_abbr}${RESET_CODE}")
    [[ "$SHOW_GIT_BRANCH" == "true" && -n "$_branch" ]] && _parts+=("${GREEN_CODE}${_branch}${RESET_CODE}")
    [[ "$SHOW_CONTEXT" == "true" ]] && _parts+=("${PINK_CODE}${_ctx_actual_k}k/${_ctx_window_k}k ${_ctx_bar}${RESET_CODE}")

    local _line=""
    local _first=true
    for _s in "${_parts[@]}"; do
        if [[ "$_first" == "true" ]]; then _line="$_s"; _first=false
        else _line="$_line | $_s"; fi
    done
    printf '%b\n' "$_line"
}

# Determine weekly limit based on plan
case "$USER_PLAN" in
    "pro")
        WEEKLY_LIMIT=$WEEKLY_LIMIT_PRO
        ;;
    "max5x")
        WEEKLY_LIMIT=$WEEKLY_LIMIT_MAX5X
        ;;
    "max20x")
        WEEKLY_LIMIT=$WEEKLY_LIMIT_MAX20X
        ;;
    *)
        WEEKLY_LIMIT=$WEEKLY_LIMIT_MAX5X  # Default fallback
        ;;
esac

# Extract basic information from JSON
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
DIR_NAME="${CURRENT_DIR##*/}"
# Sanitize DIR_NAME to prevent ANSI injection
DIR_NAME=$(printf '%s' "$DIR_NAME" | tr -d '\000-\037\177')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.transcript_path // ""')
MODEL_NAME=$(echo "$input" | jq -r '.model.display_name // ""')
EFFORT_LEVEL=$(echo "$input" | jq -r '.effort.level // empty')
if [ -z "$EFFORT_LEVEL" ] && [ -f "$HOME/.claude/settings.json" ]; then
    EFFORT_LEVEL=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
EFFORT_ABBR=$(_abbreviate_effort "$EFFORT_LEVEL")

# Get 5-hour window data from ccusage
# Use --offline for faster execution with cached pricing
# Filter out npm warnings and capture only the JSON
echo "Calling ccusage..." >> "$DEBUG_LOG"
# Redirect stdin/stdout/stderr properly and use timeout to prevent hanging
WINDOW_DATA=$(cd ~ && npx --yes "ccusage@${CCUSAGE_VERSION}" blocks --active --json --token-limit $TOKEN_LIMIT --offline </dev/null 2>/dev/null | awk '/^{/,0')
echo "ccusage returned: ${#WINDOW_DATA} chars" >> "$DEBUG_LOG"

if [ -n "$WINDOW_DATA" ] && [ "$WINDOW_DATA" != "null" ]; then
    # Parse window data
    BLOCK=$(echo "$WINDOW_DATA" | jq -r '.blocks[0] // empty')

    if [ -n "$BLOCK" ]; then
        # Calculate context window usage from transcript
        # Use ccusage method: latest assistant message only
        # Separate cached (system overhead) vs fresh (conversation) context
        if [ -f "$TRANSCRIPT_PATH" ]; then
            # Get the LATEST assistant message (last N lines for performance)
            # Extract token types and calculate cached vs fresh
            TOKEN_DATA=$(tail -$TRANSCRIPT_TAIL_LINES "$TRANSCRIPT_PATH" | \
                grep '"role":"assistant"' | \
                tail -1 | \
                awk '
                {
                    input = 0
                    cache_creation = 0
                    cache_read = 0

                    # Extract input_tokens (fresh conversation)
                    if (match($0, /"input_tokens":[0-9]+/)) {
                        input = substr($0, RSTART, RLENGTH)
                        gsub(/.*:/, "", input)
                    }

                    # Extract cache_creation_input_tokens (cached)
                    if (match($0, /"cache_creation_input_tokens":[0-9]+/)) {
                        cache_creation = substr($0, RSTART, RLENGTH)
                        gsub(/.*:/, "", cache_creation)
                    }

                    # Extract cache_read_input_tokens (cached)
                    if (match($0, /"cache_read_input_tokens":[0-9]+/)) {
                        cache_read = substr($0, RSTART, RLENGTH)
                        gsub(/.*:/, "", cache_read)
                    }

                    # Cached = cache_creation + cache_read (system overhead)
                    cached = cache_creation + cache_read
                    # Fresh = input_tokens (active conversation)
                    fresh = input
                    # Total context
                    total = cached + fresh

                    # Output: cached(k) fresh(k) total(k)
                    print int(cached / 1000) " " int(fresh / 1000) " " int(total / 1000)
                }')

            # Parse the output
            CACHED_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $1}')
            FRESH_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $2}')
            CONTEXT_TOKENS=$(echo "$TOKEN_DATA" | awk '{print $3}')

            # Fallback if no data found
            if [ -z "$CONTEXT_TOKENS" ]; then
                CACHED_TOKENS=0
                FRESH_TOKENS=0
                CONTEXT_TOKENS=0
            fi
        else
            CACHED_TOKENS=0
            FRESH_TOKENS=0
            CONTEXT_TOKENS=0
        fi

        # Extract cost and projection
        COST=$(echo "$BLOCK" | jq -r '.costUSD // 0')
        PROJECTED_COST=$(echo "$BLOCK" | jq -r '.projection.totalCost // 0')

        # Get weekly usage from the authoritative rate_limits field provided by Claude Code.
        # This matches what claude.ai/settings/usage reports. The previous approach divided
        # ccusage dollar cost by a hardcoded weekly dollar limit ($500 for max5x), which
        # produced wildly incorrect percentages because Claude Max limits are message-based
        # quotas, not dollar-spend quotas.
        WEEKLY_PCT=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
        if [ -n "$WEEKLY_PCT" ]; then
            WEEKLY_PCT=$(printf "%.0f" "$WEEKLY_PCT")
        else
            WEEKLY_PCT=""
        fi

        # Compute weekly reset display from the 7-day resets_at epoch timestamp.
        # This is the actual claude.ai weekly window reset, NOT the ccusage 5-hour block.
        WEEKLY_RESET_AT=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
        WEEKLY_RESET_DISPLAY=""
        if [ -n "$WEEKLY_RESET_AT" ]; then
            # Convert epoch to local time (macOS date -r)
            WEEKLY_RESET_DISPLAY=$(date -r "$WEEKLY_RESET_AT" "+%-l%p" 2>/dev/null | sed 's/^ *//')
            if [ -z "$WEEKLY_RESET_DISPLAY" ]; then
                # GNU date fallback
                WEEKLY_RESET_DISPLAY=$(date -d "@${WEEKLY_RESET_AT}" "+%-l%p" 2>/dev/null | sed 's/^ *//')
            fi
            # Add time-until-reset in hours/minutes
            NOW_EPOCH=$(date +%s)
            SECS_UNTIL=$(( WEEKLY_RESET_AT - NOW_EPOCH ))
            if [ "$SECS_UNTIL" -gt 0 ]; then
                HRS_UNTIL=$(( SECS_UNTIL / 3600 ))
                MINS_UNTIL=$(( (SECS_UNTIL % 3600) / 60 ))
                if [ "$HRS_UNTIL" -gt 0 ]; then
                    WEEKLY_RESET_DISPLAY="${WEEKLY_RESET_DISPLAY} (${HRS_UNTIL}h ${MINS_UNTIL}m)"
                else
                    WEEKLY_RESET_DISPLAY="${WEEKLY_RESET_DISPLAY} (${MINS_UNTIL}m)"
                fi
            fi
        fi

        # Extract time data
        REMAINING_MINS=$(echo "$BLOCK" | jq -r '.projection.remainingMinutes // 0')
        END_TIME=$(echo "$BLOCK" | jq -r '.endTime // ""')

        # Format countdown
        HOURS=$((REMAINING_MINS / 60))
        MINS=$((REMAINING_MINS % 60))
        TIME_LEFT="${MINS}m"
        if [ $HOURS -gt 0 ]; then
            TIME_LEFT="${HOURS}h ${MINS}m"
        fi

        # Format reset time (simplified format: 2AM, 10PM, etc)
        if [ -n "$END_TIME" ]; then
            # Try GNU date first (Linux), then macOS date
            RESET_TIME=$(date -d "$END_TIME" "+%-l%p" 2>/dev/null)
            if [ -z "$RESET_TIME" ]; then
                # Fallback to macOS date - handle Z suffix
                END_TIME_CLEAN=$(echo "$END_TIME" | sed 's/\.[0-9]*Z$/Z/' | sed 's/Z$//')
                RESET_TIME=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$END_TIME_CLEAN" "+%l%p" 2>/dev/null | sed 's/^ *//' || echo "")
            fi
        else
            RESET_TIME=""
        fi

        # Multi-layer progress bar (using config-defined settings)
        # Calculate actual percentage
        ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($COST / $COST_LIMIT) * 100}")

        # Determine layer and calculate visual progress
        if (( $(awk "BEGIN {print ($ACTUAL_PCT <= $LAYER1_THRESHOLD)}") )); then
            # Layer 1: 0-threshold% actual → 0-100% visual
            VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $ACTUAL_PCT * $LAYER1_MULTIPLIER}")
            BAR_COLOR="GREEN"
        elif (( $(awk "BEGIN {print ($ACTUAL_PCT <= $LAYER2_THRESHOLD)}") )); then
            # Layer 2: threshold1-threshold2% actual → 0-100% visual
            VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($ACTUAL_PCT - $LAYER1_THRESHOLD) * $LAYER2_MULTIPLIER}")
            BAR_COLOR="ORANGE"
        else
            # Layer 3: threshold2-threshold3% actual → 0-100% visual
            VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($ACTUAL_PCT - $LAYER2_THRESHOLD) * $LAYER3_MULTIPLIER}")
            if (( $(awk "BEGIN {print ($VISUAL_PCT > 100)}") )); then
                VISUAL_PCT=100
            fi
            BAR_COLOR="RED"
        fi

        # Calculate filled blocks based on visual percentage
        FILLED=$(awk "BEGIN {printf \"%.0f\", ($VISUAL_PCT / 100) * $BAR_LENGTH}")
        if [ $FILLED -gt $BAR_LENGTH ]; then
            FILLED=$BAR_LENGTH
        fi

        # Calculate projected position using CURRENT layer's multiplier for consistent scale
        PROJECTED_POS=-1
        PROJECTED_BAR_COLOR="GREEN"
        if [ -n "$PROJECTED_COST" ] && [ "$PROJECTED_COST" != "0" ]; then
            PROJECTED_ACTUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_COST / $COST_LIMIT) * 100}")

            # Determine projection color based on which layer it falls into
            if (( $(awk "BEGIN {print ($PROJECTED_ACTUAL_PCT <= $LAYER1_THRESHOLD)}") )); then
                PROJECTED_BAR_COLOR="GREEN"
            elif (( $(awk "BEGIN {print ($PROJECTED_ACTUAL_PCT <= $LAYER2_THRESHOLD)}") )); then
                PROJECTED_BAR_COLOR="ORANGE"
            else
                PROJECTED_BAR_COLOR="RED"
            fi

            # Calculate visual position using CURRENT layer's multiplier (same scale as current bar)
            if [ "$BAR_COLOR" = "GREEN" ]; then
                PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", $PROJECTED_ACTUAL_PCT * $LAYER1_MULTIPLIER}")
            elif [ "$BAR_COLOR" = "ORANGE" ]; then
                PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_ACTUAL_PCT - $LAYER1_THRESHOLD) * $LAYER2_MULTIPLIER}")
            else
                PROJECTED_VISUAL_PCT=$(awk "BEGIN {printf \"%.2f\", ($PROJECTED_ACTUAL_PCT - $LAYER2_THRESHOLD) * $LAYER3_MULTIPLIER}")
            fi

            if (( $(awk "BEGIN {print ($PROJECTED_VISUAL_PCT > 100)}") )); then
                PROJECTED_VISUAL_PCT=100
            fi

            PROJECTED_POS=$(awk "BEGIN {printf \"%.0f\", ($PROJECTED_VISUAL_PCT / 100) * $BAR_LENGTH}")
            if [ $PROJECTED_POS -gt $BAR_LENGTH ]; then
                PROJECTED_POS=$BAR_LENGTH
            fi

            # Don't show separator if it's at same position as current
            if [ $PROJECTED_POS -eq $FILLED ]; then
                PROJECTED_POS=-1
            fi
        fi

        # Set projected separator color
        case "$PROJECTED_BAR_COLOR" in
            "GREEN")
                PROJECTED_COLOR="$GREEN_CODE"
                ;;
            "ORANGE")
                PROJECTED_COLOR="$ORANGE_CODE"
                ;;
            "RED")
                PROJECTED_COLOR="$RED_CODE"
                ;;
            *)
                PROJECTED_COLOR="$GREEN_CODE"
                ;;
        esac

        # Set current progress bar color
        case "$BAR_COLOR" in
            "GREEN")
                CURRENT_COLOR="$GREEN_CODE"
                ;;
            "ORANGE")
                CURRENT_COLOR="$ORANGE_CODE"
                ;;
            "RED")
                CURRENT_COLOR="$RED_CODE"
                ;;
            *)
                CURRENT_COLOR="$GREEN_CODE"
                ;;
        esac

        # Build progress bar with colored projection separator
        PROGRESS_BAR="["
        for ((i=0; i<BAR_LENGTH; i++)); do
            if [ $i -lt $FILLED ]; then
                PROGRESS_BAR="${PROGRESS_BAR}█"
            elif [ $i -eq $PROJECTED_POS ]; then
                # Projection separator with its own layer color
                PROGRESS_BAR="${PROGRESS_BAR}${RESET_CODE}${PROJECTED_COLOR}│${RESET_CODE}${CURRENT_COLOR}"
            else
                PROGRESS_BAR="${PROGRESS_BAR}░"
            fi
        done
        PROGRESS_BAR="${PROGRESS_BAR}]"

        # Use context window data directly from JSON input
        CTX_INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
        CTX_CACHE_CREATION=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
        CTX_CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
        CTX_WINDOW_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
        CTX_USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

        # Abbreviate model name for display
        MODEL_ABBR=$(_abbreviate_model "$MODEL_NAME" "$CTX_WINDOW_SIZE")

        # Calculate actual tokens used (input + cache creation + cache read)
        CTX_ACTUAL_TOKENS=$(awk "BEGIN {printf \"%.0f\", ($CTX_INPUT_TOKENS + $CTX_CACHE_CREATION + $CTX_CACHE_READ) / 1000}")
        CTX_WINDOW_K=$(awk "BEGIN {printf \"%.0f\", $CTX_WINDOW_SIZE / 1000}")

        # Calculate percentage if not provided
        if [ -z "$CTX_USED_PCT" ]; then
            CTX_USED_PCT=$(awk "BEGIN {printf \"%.0f\", (($CTX_INPUT_TOKENS + $CTX_CACHE_CREATION + $CTX_CACHE_READ) / $CTX_WINDOW_SIZE) * 100}")
        else
            CTX_USED_PCT=$(printf "%.0f" "$CTX_USED_PCT")
        fi

        # Create context progress bar (same length as cost bar)
        CTX_BAR_LENGTH=$BAR_LENGTH

        # Calculate total filled blocks based on actual percentage
        CTX_FILLED=$(awk "BEGIN {printf \"%.0f\", ($CTX_USED_PCT / 100) * $CTX_BAR_LENGTH}")
        if [ $CTX_FILLED -gt $CTX_BAR_LENGTH ]; then
            CTX_FILLED=$CTX_BAR_LENGTH
        fi

        CTX_EMPTY=$((CTX_BAR_LENGTH - CTX_FILLED))

        # Build simple progress bar
        CTX_PROGRESS_BAR="["

        # Pink blocks for filled
        for ((i=0; i<CTX_FILLED; i++)); do
            CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}█"
        done

        # Gray blocks for empty
        for ((i=0; i<CTX_EMPTY; i++)); do
            CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}░"
        done

        CTX_PROGRESS_BAR="${CTX_PROGRESS_BAR}]"

        # Format context using actual token counts from JSON input
        CTX_TOTAL=$(printf "%dk/%dk" $CTX_ACTUAL_TOKENS $CTX_WINDOW_K)
        CTX_BREAKDOWN=$(printf "%dk+%dk" $CACHED_TOKENS $FRESH_TOKENS)

        # Calculate cost percentage
        COST_PERCENTAGE=$(awk "BEGIN {printf \"%.0f\", ($COST / $COST_LIMIT) * 100}")

        # Format cost
        COST_FMT=$(printf "\$%.0f/\$%d" $COST $COST_LIMIT)

        # Format reset info
        if [ -n "$RESET_TIME" ]; then
            RESET_INFO="$RESET_TIME ($TIME_LEFT)"
        else
            RESET_INFO="$TIME_LEFT"
        fi

        # Get git branch info (skip optional locks for performance)
        GIT_BRANCH=""
        if [ -d "${CURRENT_DIR}/.git" ]; then
            GIT_BRANCH=$(cd "$CURRENT_DIR" && git --no-optional-locks branch --show-current 2>/dev/null)
        fi

        # Count concurrent Claude Code sessions (projects with activity in last N minutes)
        # Expand tilde in path
        PROJECTS_PATH="${CLAUDE_PROJECTS_PATH/#\~/$HOME}"
        ACTIVE_SESSIONS=$(find "$PROJECTS_PATH" -name "*.jsonl" -type f -mmin -$SESSION_ACTIVITY_THRESHOLD 2>/dev/null | \
            { xargs -I {} dirname {} 2>/dev/null || true; } | sort -u | wc -l | tr -d ' ')

        # Set progress bar color based on layer
        case "$BAR_COLOR" in
            "GREEN")
                PROGRESS_COLOR="$GREEN_CODE"
                ;;
            "ORANGE")
                PROGRESS_COLOR="$ORANGE_CODE"
                ;;
            "RED")
                PROGRESS_COLOR="$RED_CODE"
                ;;
            *)
                PROGRESS_COLOR="$GREEN_CODE"
                ;;
        esac

        # Build statusline conditionally based on section toggles
        STATUSLINE_SECTIONS=()

        [[ "$SHOW_DIRECTORY" == "true" ]] && STATUSLINE_SECTIONS+=("${ORANGE_CODE}${DIR_NAME}${RESET_CODE}")
        [[ "$SHOW_MODEL" == "true" && -n "$MODEL_NAME" ]] && STATUSLINE_SECTIONS+=("${CYAN_CODE}${MODEL_ABBR}${RESET_CODE}")
        [[ "$SHOW_EFFORT" == "true" && -n "$EFFORT_ABBR" ]] && STATUSLINE_SECTIONS+=("${YELLOW_CODE}${EFFORT_ABBR}${RESET_CODE}")
        [[ "$SHOW_GIT_BRANCH" == "true" && -n "$GIT_BRANCH" ]] && STATUSLINE_SECTIONS+=("${GREEN_CODE}${GIT_BRANCH}${RESET_CODE}")
        [[ "$SHOW_CONTEXT" == "true" ]] && STATUSLINE_SECTIONS+=("${PINK_CODE}${CTX_TOTAL} ${CTX_PROGRESS_BAR}${RESET_CODE}")
        [[ "$SHOW_COST" == "true" ]] && STATUSLINE_SECTIONS+=("${PROGRESS_COLOR}${COST_FMT} ${PROGRESS_BAR} ${COST_PERCENTAGE}%${RESET_CODE}")
        if [[ "$SHOW_WEEKLY" == "true" && -n "$WEEKLY_PCT" ]]; then
            STATUSLINE_SECTIONS+=("weekly ${WEEKLY_PCT}%")
        fi

        # 5-hour session usage from Claude Code JSON input (.rate_limits.five_hour)
        SESSION_PCT=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
        SESSION_RESET_AT=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
        SESSION_DISPLAY=""
        if [ -n "$SESSION_PCT" ]; then
            SESSION_PCT_INT=$(printf "%.0f" "$SESSION_PCT")
            SESSION_DISPLAY="session ${SESSION_PCT_INT}%"
            if [ -n "$SESSION_RESET_AT" ]; then
                NOW_EPOCH=$(date +%s)
                SECS_UNTIL_SESSION=$(( SESSION_RESET_AT - NOW_EPOCH ))
                if [ "$SECS_UNTIL_SESSION" -gt 0 ]; then
                    HRS_SESSION=$(( SECS_UNTIL_SESSION / 3600 ))
                    MINS_SESSION=$(( (SECS_UNTIL_SESSION % 3600) / 60 ))
                    if [ "$HRS_SESSION" -gt 0 ]; then
                        SESSION_DISPLAY="${SESSION_DISPLAY} → ${HRS_SESSION}h ${MINS_SESSION}m"
                    else
                        SESSION_DISPLAY="${SESSION_DISPLAY} → ${MINS_SESSION}m"
                    fi
                fi
            fi
        fi
        [[ "$SHOW_TIMER" == "true" && -n "$SESSION_DISPLAY" ]] && STATUSLINE_SECTIONS+=("${PURPLE_CODE}${SESSION_DISPLAY}${RESET_CODE}")
        [[ "$SHOW_SESSIONS" == "true" ]] && STATUSLINE_SECTIONS+=("${CYAN_CODE}×${ACTIVE_SESSIONS}${RESET_CODE}")

        # Join sections with separator
        STATUSLINE=""
        FIRST=true
        for section in "${STATUSLINE_SECTIONS[@]}"; do
            if [[ "$FIRST" == "true" ]]; then
                STATUSLINE="$section"
                FIRST=false
            else
                STATUSLINE="$STATUSLINE | $section"
            fi
        done

        # Display statusline
        echo "Outputting statusline" >> "$DEBUG_LOG"
        printf '%b\n' "$STATUSLINE"
    else
        # No active ccusage block — show basic info from JSON input
        _show_basic_statusline "$input" "$MODEL_NAME" "$CURRENT_DIR" "$DIR_NAME"
    fi
else
    # ccusage failed or returned no data — show basic info from JSON input
    _show_basic_statusline "$input" "$MODEL_NAME" "$CURRENT_DIR" "$DIR_NAME"
fi