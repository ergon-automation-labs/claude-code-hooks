#!/bin/bash
set -o pipefail

# Safety: fail gracefully on any error
{
input=$(cat 2>/dev/null || echo "{}")

# --- Dim label style ---
lbl="\033[0;2m"  # dim/faint text for labels
rst="\033[0m"
sep="  "         # spacer between sections

# --- Safely extract JSON fields with fallback ---
# Use /usr/bin/jq explicitly; check availability first
if ! command -v jq >/dev/null 2>&1; then
  echo "${lbl}status${rst} \033[1;32mready\033[0m"
  exit 0
fi

# Parse JSON with error handling
mode=$(echo "$input" 2>/dev/null | jq -r ".vim.mode // empty" 2>/dev/null || echo "")
remaining=$(echo "$input" 2>/dev/null | jq -r ".context_window.remaining_percentage // empty" 2>/dev/null || echo "")
used=$(echo "$input" 2>/dev/null | jq -r ".context_window.used_percentage // empty" 2>/dev/null || echo "")
total_in=$(echo "$input" 2>/dev/null | jq -r ".context_window.total_input_tokens // empty" 2>/dev/null || echo "")
total_out=$(echo "$input" 2>/dev/null | jq -r ".context_window.total_output_tokens // empty" 2>/dev/null || echo "")
ctx_size=$(echo "$input" 2>/dev/null | jq -r ".context_window.context_window_size // empty" 2>/dev/null || echo "")
duration_ms=$(echo "$input" 2>/dev/null | jq -r ".cost.total_duration_ms // 0" 2>/dev/null || echo "0")
api_duration_ms=$(echo "$input" 2>/dev/null | jq -r ".cost.total_api_duration_ms // 0" 2>/dev/null || echo "0")
cost=$(echo "$input" 2>/dev/null | jq -r ".cost.total_cost_usd // 0" 2>/dev/null || echo "0")
lines_added=$(echo "$input" 2>/dev/null | jq -r ".cost.total_lines_added // 0" 2>/dev/null || echo "0")
lines_removed=$(echo "$input" 2>/dev/null | jq -r ".cost.total_lines_removed // 0" 2>/dev/null || echo "0")
current_time=$(date "+%a %b %d %H:%M" 2>/dev/null || echo "")
session_name=$(echo "$input" 2>/dev/null | jq -r ".session_name // empty" 2>/dev/null || echo "")
model=$(echo "$input" 2>/dev/null | jq -r ".model.display_name // empty" 2>/dev/null || echo "")
exceeds=$(echo "$input" 2>/dev/null | jq -r ".exceeds_200k_tokens // false" 2>/dev/null || echo "false")
rate_5h=$(echo "$input" 2>/dev/null | jq -r ".rate_limits.five_hour.used_percentage // empty" 2>/dev/null || echo "")
rate_7d=$(echo "$input" 2>/dev/null | jq -r ".rate_limits.seven_day.used_percentage // empty" 2>/dev/null || echo "")
rate_5h_reset=$(echo "$input" 2>/dev/null | jq -r ".rate_limits.five_hour.resets_at // empty" 2>/dev/null || echo "")
rate_7d_reset=$(echo "$input" 2>/dev/null | jq -r ".rate_limits.seven_day.resets_at // empty" 2>/dev/null || echo "")
cwd=$(echo "$input" 2>/dev/null | jq -r ".workspace.current_dir // empty" 2>/dev/null || echo "")

# --- Mode indicator ---
if [ -f /tmp/.claude_thinking ]; then
    mode_val="\033[1;32mthinking\033[0m"
elif [ -n "$mode" ]; then
    if [ "$mode" = "NORMAL" ]; then
        mode_val="\033[1;33mstopped\033[0m"
    else
        mode_val="\033[1;32mthinking\033[0m"
    fi
else
    mode_val="\033[1;32mready\033[0m"
fi

# --- Model name ---
if [ -n "$model" ] && [ "$model" != "null" ]; then
    if [ "$model" = "Opus" ]; then
        model_val="\033[1;35m${model}\033[0m"
    elif [ "$model" = "Sonnet" ]; then
        model_val="\033[1;36m${model}\033[0m"
    elif [ "$model" = "Haiku" ]; then
        model_val="\033[0;90m${model}\033[0m"
    else
        model_val="\033[1;37m${model}\033[0m"
    fi
else
    model_val=""
fi

# --- Clock ---
time_val="\033[0;36m${current_time}\033[0m"

# --- Note from Claude (file-based, auto-expires after 60s) ---
note_file="/tmp/.claude_note"
note_val=""
if [ -f "$note_file" ]; then
    note_age=$(( $(date +%s 2>/dev/null || echo 0) - $(stat -f %m "$note_file" 2>/dev/null || echo 0) ))
    if [ "$note_age" -lt 60 ] 2>/dev/null; then
        note_text=$(cat "$note_file" 2>/dev/null)
        if [ -n "$note_text" ]; then
            note_val="\033[1;33m${note_text}\033[0m"
        fi
    else
        rm -f "$note_file" 2>/dev/null || true
    fi
fi

# --- Session name ---
if [ -n "$session_name" ] && [ "$session_name" != "null" ]; then
    name_val="\033[1;35m${session_name}\033[0m"
else
    name_val=""
fi

# --- Context progress bar + warning ---
if [ -n "$remaining" ] && [ "$remaining" != "null" ]; then
    used_pct=${used:-0}
    filled=$((used_pct / 10)) 2>/dev/null || filled=0
    [ $filled -gt 10 ] 2>/dev/null && filled=10

    bar=""
    for i in $(seq 1 $filled 2>/dev/null); do
        bar="${bar}\033[1;32m█\033[0m"
    done
    for i in $(seq 1 $((10 - filled)) 2>/dev/null); do
        bar="${bar}\033[0;90m░\033[0m"
    done

    ctx_warn=""
    if [ "$exceeds" = "true" ]; then
        ctx_warn="\033[1;31m !!\033[0m"
    fi

    context_val="${bar}${ctx_warn} \033[0;36m${remaining}%\033[0m"
else
    context_val=""
fi

# --- Token counts ---
token_val=""
if [ -n "$total_in" ] && [ "$total_in" != "null" ] && [ -n "$total_out" ] && [ "$total_out" != "null" ]; then
    # Format with k suffix for readability
    if [ "$total_in" -ge 1000 ] 2>/dev/null; then
        in_fmt="$((total_in / 1000))k"
    else
        in_fmt="$total_in"
    fi
    if [ "$total_out" -ge 1000 ] 2>/dev/null; then
        out_fmt="$((total_out / 1000))k"
    else
        out_fmt="$total_out"
    fi
    token_val="\033[0;32m${in_fmt}\033[0m\033[0;2m/\033[0m\033[0;36m${out_fmt}\033[0m"
fi

# --- Cost counter ---
cost_fmt=$(printf "%.2f" "$cost" 2>/dev/null || echo "0.00")
cost_val="\033[0;33m\$${cost_fmt}\033[0m"

# --- Lines changed ---
if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
    lines_val="\033[1;32m+${lines_added}\033[0m \033[1;31m-${lines_removed}\033[0m"
else
    lines_val=""
fi

# --- API vs wall time ---
if [ "$duration_ms" != "0" ]; then
    wall_sec=$((duration_ms / 1000)) 2>/dev/null || wall_sec=0
    api_sec=$((api_duration_ms / 1000)) 2>/dev/null || api_sec=0
    tool_sec=$((wall_sec - api_sec)) 2>/dev/null || tool_sec=0
    duration_val="\033[0;37m${wall_sec}s\033[0m \033[0;36m${api_sec}s api\033[0m \033[0;35m${tool_sec}s tools\033[0m"
else
    duration_val=""
fi

# --- Git branch (with timeout) ---
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd/.git" ] 2>/dev/null; then
    git_branch=$(timeout 1s git -C "$cwd" branch --show-current 2>/dev/null || echo "")
fi
if [ -n "$git_branch" ]; then
    git_val="\033[1;36m${git_branch}\033[0m"
else
    git_val=""
fi

# --- Project directory ---
project_dir=""
project_val=""
if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
    project_dir=$(basename "$cwd" 2>/dev/null)
    if [ -n "$project_dir" ]; then
        project_val="\033[0;37m${project_dir}\033[0m"
    fi
fi

# --- Clickable repo link (with timeout) ---
repo_url=""
if [ -n "$cwd" ]; then
    repo_url=$(timeout 1s git -C "$cwd" remote get-url origin 2>/dev/null | sed -E "s|git@([^:]+):(.+?)(\.git)?\$|https://\1/\2|; s|https://||; s|^|https://|" 2>/dev/null || echo "")
fi
if [ -n "$repo_url" ]; then
    repo_name=$(basename "$repo_url" .git 2>/dev/null)
    repo_val="\e]8;;${repo_url}\a\033[4;34m${repo_name}\033[0m\e]8;;\a"
else
    repo_val=""
fi

# --- Rate limit gauge ---
rate_val=""
if [ -n "$rate_5h" ] && [ "$rate_5h" != "null" ]; then
    pct_5h=$(printf "%.0f" "$rate_5h" 2>/dev/null || echo "0")
    if [ "$pct_5h" -lt 50 ] 2>/dev/null; then
        color_5h="\033[1;32m"
    elif [ "$pct_5h" -lt 80 ] 2>/dev/null; then
        color_5h="\033[1;33m"
    else
        color_5h="\033[1;31m"
    fi
    rate_val="${color_5h}${pct_5h}%\033[0m"

    if [ -n "$rate_7d" ] && [ "$rate_7d" != "null" ]; then
        pct_7d=$(printf "%.0f" "$rate_7d" 2>/dev/null || echo "0")
        if [ "$pct_7d" -lt 50 ] 2>/dev/null; then
            color_7d="\033[1;32m"
        elif [ "$pct_7d" -lt 80 ] 2>/dev/null; then
            color_7d="\033[1;33m"
        else
            color_7d="\033[1;31m"
        fi
        rate_val="${rate_val} ${color_7d}${pct_7d}%\033[0m"
    fi
else
    rate_val=""
fi

# --- Build line 1: status overview ---
line1="${lbl}status${rst} ${mode_val}"
[ -n "$model_val" ] && line1="${line1}${sep}${lbl}model${rst} ${model_val}"
line1="${line1}${sep}${lbl}time${rst} ${time_val}"
[ -n "$name_val" ] && line1="${line1}${sep}${lbl}session${rst} ${name_val}"
[ -n "$project_val" ] && line1="${line1}${sep}${lbl}dir${rst} ${project_val}"
[ -n "$git_val" ] && line1="${line1}${sep}${lbl}branch${rst} ${git_val}"
[ -n "$repo_val" ] && line1="${line1}${sep}${lbl}repo${rst} ${repo_val}"
[ -n "$note_val" ] && line1="${line1}  ${note_val}"

# --- Bot Army hits feed (recent tasks + active projects) ---
hits_val=""

# Every 5s, query bridge for real activity
# Alternate: active tasks → active projects → bot health
cycle=$(($(date +%s) / 5 % 3))

# Bot Army hits (query NATS bridge for real traffic + random facts)
cycle=$(($(date +%s) / 5 % 4))

case $cycle in
    0)
        # Show recent active task
        task_response=$(nats request --server nats://localhost:4222 bridge.task.search '{}' 2>/dev/null | jq -r '.data.tasks[0].title // empty' 2>/dev/null)
        if [ -n "$task_response" ] && [ "$task_response" != "null" ]; then
            task_trunc=$(echo "$task_response" | cut -c1-45)
            hits_val="\033[0;33m→ ${task_trunc}\033[0m"
        else
            hits_val="\033[0;33m→ Bot Army active\033[0m"
        fi
        ;;
    1)
        # Show project count
        project_response=$(nats request --server nats://localhost:4222 bridge.project.list '{}' 2>/dev/null | jq '.data.projects | length' 2>/dev/null)
        if [ -n "$project_response" ] && [ "$project_response" != "null" ]; then
            hits_val="\033[0;36m◆ ${project_response} projects\033[0m"
        else
            hits_val="\033[0;36m◆ checking projects...\033[0m"
        fi
        ;;
    2)
        # Show active bot count
        bot_response=$(nats request --server nats://localhost:4222 bridge.world.snapshot '{}' 2>/dev/null | jq '.active_bots | length' 2>/dev/null)
        if [ -n "$bot_response" ] && [ "$bot_response" != "null" ]; then
            hits_val="\033[0;35m✨ ${bot_response} bots online\033[0m"
        else
            hits_val="\033[0;35m✨ checking bots...\033[0m"
        fi
        ;;
    3)
        # Show random fact from bridge
        fact_response=$(nats request --server nats://localhost:4222 bridge.system.fact '{}' 2>/dev/null | jq -r '.data.fact // empty' 2>/dev/null | cut -c1-60)
        if [ -n "$fact_response" ]; then
            hits_val="\033[0;35m💡 ${fact_response}\033[0m"
        else
            hits_val="\033[0;35m💡 Bridge facts loading...\033[0m"
        fi
        ;;
esac

# --- Build line 2: metrics ---
line2=""
[ -n "$context_val" ] && line2="${lbl}context${rst} ${context_val}"
[ -n "$token_val" ] && line2="${line2}${sep}${lbl}tokens${rst} ${token_val}"
[ -n "$cost_val" ] && line2="${line2}${sep}${lbl}cost${rst} ${cost_val}"
[ -n "$lines_val" ] && line2="${line2}${sep}${lbl}lines${rst} ${lines_val}"
[ -n "$duration_val" ] && line2="${line2}${sep}${lbl}time${rst} ${duration_val}"
[ -n "$rate_val" ] && line2="${line2}${sep}${lbl}rate${rst} ${rate_val}"

# --- Build line 3: Bot Army hits ---
line3=""
[ -n "$hits_val" ] && line3="${lbl}bot army${rst} ${hits_val}"

echo -e "$line1"
[ -n "$line2" ] && echo -e "$line2"
[ -n "$line3" ] && echo -e "$line3"
} || echo "[status] ready"