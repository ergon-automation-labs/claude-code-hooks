#!/bin/bash
set -o pipefail

{
input=$(cat 2>/dev/null || echo "{}")

# --- Per-session task ID & title ---
TASK_CACHE="/tmp/.claude_active_task.${CLAUDE_CODE_SESSION_ID}"
TASK_ID=""
TASK_TITLE=""
if [ -f "$TASK_CACHE" ]; then
  CACHE_CONTENT=$(cat "$TASK_CACHE" 2>/dev/null)
  # Format is: id|title
  TASK_ID="${CACHE_CONTENT%%|*}"
  TASK_TITLE="${CACHE_CONTENT#*|}"
fi
TASK_SHORT="${TASK_ID:0:8}"
TITLE_SHORT="${TASK_TITLE:0:40}"

# --- ANSI color codes ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[0;36m'
RST='\033[0m'
MAGENTA='\033[1;35m'
BOLD_CYAN='\033[1;36m'
GRAY='\033[0;90m'
DIM='\033[0;2m'

# --- Parse JSON from Claude Code ---
if ! command -v jq >/dev/null 2>&1; then
  printf "status ready\n"
  exit 0
fi

current_time=$(date "+%a %b %d %H:%M" 2>/dev/null || echo "")
model=$(echo "$input" 2>/dev/null | jq -r ".model.display_name // empty" 2>/dev/null || echo "")
cost=$(echo "$input" 2>/dev/null | jq -r ".cost.total_cost_usd // 0" 2>/dev/null || echo "0")
rate_5h_raw=$(echo "$input" 2>/dev/null | jq -r ".rate_limits.five_hour.used_percentage // empty" 2>/dev/null || echo "")
rate_7d_raw=$(echo "$input" 2>/dev/null | jq -r ".rate_limits.seven_day.used_percentage // empty" 2>/dev/null || echo "")

# Format rate limits to 2 decimal places
rate_5h=""
if [ -n "$rate_5h_raw" ]; then
  rate_5h=$(printf "%.2f" "$rate_5h_raw" 2>/dev/null || echo "$rate_5h_raw")
fi
rate_7d=""
if [ -n "$rate_7d_raw" ]; then
  rate_7d=$(printf "%.2f" "$rate_7d_raw" 2>/dev/null || echo "$rate_7d_raw")
fi
remaining=$(echo "$input" 2>/dev/null | jq -r ".context_window.remaining_percentage // empty" 2>/dev/null || echo "")
used=$(echo "$input" 2>/dev/null | jq -r ".context_window.used_percentage // empty" 2>/dev/null || echo "")
total_in=$(echo "$input" 2>/dev/null | jq -r ".context_window.total_input_tokens // empty" 2>/dev/null || echo "")
total_out=$(echo "$input" 2>/dev/null | jq -r ".context_window.total_output_tokens // empty" 2>/dev/null || echo "")
lines_added=$(echo "$input" 2>/dev/null | jq -r ".cost.total_lines_added // 0" 2>/dev/null || echo "0")
lines_removed=$(echo "$input" 2>/dev/null | jq -r ".cost.total_lines_removed // 0" 2>/dev/null || echo "0")

# --- Check NATS health ---
nats_status="${RED}⚫${RST}"
if (echo "PING" | nc -w 1 localhost 4222 >/dev/null 2>&1) || \
   (nats request --server nats://localhost:4222 bridge.system.fact '{}' >/dev/null 2>&1); then
  nats_status="${GREEN}🟢${RST}"
fi

# --- Check PostgreSQL health (fail fast if port-forward is down) ---
db_status="${RED}⚫${RST}"
if PGCONNECT_TIMEOUT=2 psql -h 127.0.0.1 -p 35432 -U postgres -d ergon_gtd -c "SELECT 1" >/dev/null 2>&1; then
  db_status="${GREEN}🟢${RST}"
fi

# --- Model color ---
if [ -n "$model" ] && [ "$model" != "null" ]; then
    if [ "$model" = "Opus" ]; then
        model_color="$MAGENTA"
    elif [ "$model" = "Sonnet" ]; then
        model_color="$BOLD_CYAN"
    elif [ "$model" = "Haiku" ]; then
        model_color="$GRAY"
    else
        model_color=""
    fi
    model_display="${model_color}${model}${RST}"
else
    model_display=""
fi

# --- FIXED PREFIX (always visible) ---
cost_display=$(printf "%.4f" "$cost" 2>/dev/null || echo "$cost")

# Color-code rate limits based on usage
rate_5h_color="$GREEN"
rate_7d_color="$GREEN"
if [ -n "$rate_5h" ]; then
  rate_5h_int="${rate_5h%.*}"  # Extract integer part from formatted value
  if [ -n "$rate_5h_int" ] && [ "$rate_5h_int" -gt 80 ] 2>/dev/null; then
    rate_5h_color="$RED"
  elif [ -n "$rate_5h_int" ] && [ "$rate_5h_int" -gt 50 ] 2>/dev/null; then
    rate_5h_color="$YELLOW"
  fi
fi
if [ -n "$rate_7d" ]; then
  rate_7d_int="${rate_7d%.*}"  # Extract integer part from formatted value
  if [ -n "$rate_7d_int" ] && [ "$rate_7d_int" -gt 80 ] 2>/dev/null; then
    rate_7d_color="$RED"
  elif [ -n "$rate_7d_int" ] && [ "$rate_7d_int" -gt 50 ] 2>/dev/null; then
    rate_7d_color="$YELLOW"
  fi
fi

# Build rate limit display
if [ -n "$rate_5h" ] && [ -n "$rate_7d" ]; then
  fixed_suffix=$(printf '%b' "${rate_5h_color}5h:${rate_5h}%%${RST} ${rate_7d_color}7d:${rate_7d}%%${RST}")
elif [ -n "$rate_5h" ]; then
  fixed_suffix=$(printf '%b' "${rate_5h_color}5h:${rate_5h}%%${RST}")
else
  fixed_suffix="\$${cost_display}"
fi

# Build task indicator for always-on display
task_indicator=""
if [ -n "$TASK_SHORT" ]; then
  if [ -n "$TITLE_SHORT" ]; then
    task_indicator=$(printf '%b' " ${DIM}|${RST} 🎯 ${YELLOW}${TASK_SHORT}${RST} ${CYAN}${TITLE_SHORT}${RST}")
  else
    task_indicator=$(printf '%b' " ${DIM}|${RST} 🎯 ${YELLOW}${TASK_SHORT}${RST}")
  fi
fi

prefix=$(printf '%b' "NATS:${nats_status} DB:${db_status} ${DIM}|${RST} ${model_display} ${CYAN}${current_time}${RST} ${DIM}|${RST} ${fixed_suffix}${task_indicator}")

# --- ROTATING DISPLAYS (with task title featured) ---
cycle_time=$(( $(date +%s 2>/dev/null || echo 0) / 3 ))
display=$(( cycle_time % 6 ))

case $display in
  0)
    # Display 0: Current Task (primary - shows full title via scrolling)
    if [ -n "$TASK_TITLE" ]; then
      rotating=$(printf '%b' "${YELLOW}📌 Task:${RST} ${CYAN}${TASK_TITLE}${RST}")
    else
      rotating=$(printf '%b' "${YELLOW}📌 No task assigned${RST}")
    fi
    ;;
  1)
    # Display 1: Context Window + Tokens (combined line)
    if [ -n "$remaining" ]; then
      remaining_int="${remaining%.*}"
      if [ "$remaining_int" -lt 20 ]; then
        ctx_color="$RED"
      elif [ "$remaining_int" -lt 50 ]; then
        ctx_color="$YELLOW"
      else
        ctx_color="$GREEN"
      fi
      ctx_part=$(printf '%b' "${ctx_color}context${RST}: ${used}%% used")
    else
      ctx_part="context: loading"
    fi
    tok_part=$(printf '%b' "${BOLD_CYAN}in:${total_in}${RST} ${MAGENTA}out:${total_out}${RST} ${GREEN}+${lines_added}${RST}/${RED}-${lines_removed}${RST}")
    rotating=$(printf '%b' "${ctx_part} ${DIM}|${RST} ${tok_part}")
    ;;
  2)
    # Display 2: Tasks + Projects (combined line)
    task_count=$(nats request --server nats://localhost:4222 --timeout 2s bridge.task.list '{"limit":1}' 2>/dev/null | jq '.data.total_count // 0' 2>/dev/null)
    project_count=$(nats request --server nats://localhost:4222 --timeout 2s bridge.project.list '{}' 2>/dev/null | jq '.data.projects | length' 2>/dev/null)

    # Color code task count
    task_color="$GREEN"
    if [ -n "$task_count" ]; then
      task_count_int="${task_count%.*}"
      if [ "$task_count_int" -gt 500 ]; then
        task_color="$RED"
      elif [ "$task_count_int" -gt 200 ]; then
        task_color="$YELLOW"
      fi
    fi

    rotating=$(printf '%b' "${task_color}📋 ${task_count} tasks${RST} ${DIM}|${RST} ${BOLD_CYAN}◆ ${project_count} projects${RST}")
    ;;
  3)
    # Display 3: Bot Fleet Health (NEW)
    reg_count=$(nats request --server nats://localhost:4222 --timeout 2s bot_army.registry.bots.list '{}' 2>/dev/null | jq -r '.data.count // empty' 2>/dev/null)
    subj_count=$(nats request --server nats://localhost:4222 --timeout 2s bot_army.registry.subjects.list '{}' 2>/dev/null | jq -r '.data.subjects | length // empty' 2>/dev/null)

    if [ -n "$reg_count" ]; then
      bot_color="$GREEN"
      if [ "$reg_count" -lt 30 ] 2>/dev/null; then bot_color="$YELLOW"; fi
      if [ "$reg_count" -lt 20 ] 2>/dev/null; then bot_color="$RED"; fi
      rotating=$(printf '%b' "🤖 ${bot_color}${reg_count} bots${RST} ${DIM}|${RST} 📡 ${subj_count:-?} subjects")
    else
      rotating=$(printf '%b' "${GRAY}🤖 registry offline${RST}")
    fi
    ;;
  4)
    # Display 4: Bot Army facts
    fact_response=$(nats request --server nats://localhost:4222 --timeout 2s bridge.system.fact '{}' 2>/dev/null | jq -r '.data.fact // empty' 2>/dev/null | cut -c1-60)
    if [ -n "$fact_response" ]; then
      rotating=$(printf '%b' "${MAGENTA}💡 ${fact_response}${RST}")
    else
      rotating=$(printf '%b' "${MAGENTA}💡 facts...${RST}")
    fi
    ;;
  5)
    # Display 5: Smart Reminders — highest-priority alert wins
    # Checks critical infra → fleet health → workflow guards → rate limits
    reminder=""

    # 1. Critical infrastructure alerts (always win)
    if [ "$nats_status" = "${RED}⚫${RST}" ]; then
      reminder=$(printf '%b' "${RED}🔴 NATS down — make nats-status or launchctl load${RST}")
    elif [ "$db_status" = "${RED}⚫${RST}" ]; then
      reminder=$(printf '%b' "${YELLOW}🛢  DB down — make doctor or kubectl port-forward${RST}")
    fi

    # 2. Fleet health (thin registry)
    if [ -z "$reminder" ]; then
      reg_quick=$(nats request --server nats://localhost:4222 --timeout 1s bot_army.registry.bots.list '{}' 2>/dev/null | jq -r '.data.count // empty' 2>/dev/null)
      if [ -n "$reg_quick" ] && [ "$reg_quick" -lt 25 ] 2>/dev/null; then
        reminder=$(printf '%b' "${YELLOW}⚠️  $reg_quick bots (was ~46) — make health-check-dev${RST}")
      fi
    fi

    # 3. Workflow guards
    if [ -z "$reminder" ]; then
      if [ -z "$TASK_SHORT" ]; then
        reminder=$(printf '%b' "${CYAN}🎯 No active task — checkout one via GTD or /task-complete${RST}")
      fi
    fi

    # 4. Rate-limit warnings
    if [ -z "$reminder" ]; then
      if [ -n "$rate_5h" ]; then
        rate_5h_int="${rate_5h%.*}"
        if [ "$rate_5h_int" -gt 80 ] 2>/dev/null; then
          reminder=$(printf '%b' "${RED}⛽ 5h rate ${rate_5h}% — consider slowing down${RST}")
        fi
      fi
    fi

    # 5. Default: actionable hygiene reminder (cycles through tips)
    if [ -z "$reminder" ]; then
      tip_cycle=$(( $(date +%s 2>/dev/null || echo 0) / 9 ))
      case $((tip_cycle % 4)) in
        0) reminder=$(printf '%b' "${MAGENTA}💰 Builder > CEO${RST} ${DIM}|${RST} ${CYAN}Bill, don't SKU${RST}") ;;
        1) reminder=$(printf '%b' "${GREEN}📝${RST} ${CYAN}Bump mix.exs version before push${RST}") ;;
        2) reminder=$(printf '%b' "${YELLOW}🚫${RST} ${CYAN}Never --no-verify — hooks run compile→test→release${RST}") ;;
        3) reminder=$(printf '%b' "${MAGENTA}🔄${RST} ${CYAN}make task-refresh keeps descriptions current${RST}") ;;
      esac
    fi

    rotating="$reminder"
    ;;
esac

# --- OUTPUT: Fixed header on line 1, rotating marquee on line 2 ---
printf '%b\n' "$prefix"
printf '  %s\n' "$rotating"

} 2>/dev/null || printf "status ready\n"
