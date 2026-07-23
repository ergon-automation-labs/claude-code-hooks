#!/bin/bash
# PreToolUse hook: Blocks destructive commands and writes to system directories
# Receives JSON via stdin: { "tool_name": "Bash|Edit|Write", "tool_input": { "command": "..." | "file_path": "..." } }

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Block writes to system directories (Edit/Write tools)
if [ "$tool_name" = "Edit" ] || [ "$tool_name" = "Write" ]; then
  if [[ "$file_path" =~ ^(/var/log|/etc|/opt)/ ]]; then
    echo "BLOCKED: System directories (/var/log, /etc, /opt) are provisioned by Salt, not by Claude." >&2
    echo "File: $file_path" >&2
    exit 2
  fi
  exit 0
fi

# Only check Bash commands beyond this point
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

# Check for NATS prod port in dev context — allow PARA writes, GTD commands, Claude triggers, and diagnostic tools
if echo "$command" | grep -q "nats://localhost:4222"; then
  # Allow: para.* (PARA filesystem writes), bridge.* (project/task/goal management), GTD operations, Claude triggers, diagnostic commands
  if ! echo "$command" | grep -qE "(para\.|bridge\.|gtd\.|gtd_bot|bot_army\.claude\.|nats-helper|nats (stream|consumer|server|top|subscribe|pub|req|kv|account|sub|add|rm|create|pub|sub|consumer|ls|info|view|jsz)|nats --server)"; then
    echo "BLOCKED: Prod NATS port (4222) detected. Use 4223 for dev." >&2
    exit 2
  fi
fi

# Warn on stale graphify cache before test commands
if echo "$command" | grep -qE "^(mix test|make test)"; then
  cache_file="/Users/abby/code/elixir_bots/.graphify-cache/graph.json"
  if [ -f "$cache_file" ]; then
    cache_age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$cache_age" -gt 86400 ]; then
      echo "WARN: Graphify cache is stale (>24h). Run 'make graphify-refresh' before testing." >&2
    fi
  else
    echo "WARN: Graphify cache missing. Run 'make graphify-refresh' before testing." >&2
  fi
fi

# Block WRITES to Salt-provisioned system directories — must use Salt states instead
# Only block explicit writes (>, >>, touch path, mkdir path, etc), not reads or mentions
# Skip git, echo, and common read-only diagnostics
case "$command" in
  git*|echo*|nats*|grep*|cat*|head*|tail*|ls*|find*|stat*|ps*|curl*|wget*)
    # Allowed: git commits, echo messages, diagnostic reads
    ;;
  *)
    # Block actual write operations to system directories
    if echo "$command" | grep -qE "^[^#]*(>|>>|tee) *(/var/log|/etc|/opt)/"; then
      echo "BLOCKED: System directories (/var/log, /etc, /opt) are provisioned by Salt, not by commands." >&2
      echo "Use Salt states (state.apply) to manage system configuration." >&2
      exit 2
    fi
    if echo "$command" | grep -qE "(mkdir|touch|chmod|sed -i|cp|mv) .*(/var/log|/etc|/opt)/"; then
      echo "BLOCKED: System directories (/var/log, /etc, /opt) are provisioned by Salt, not by commands." >&2
      echo "Use Salt states (state.apply) to manage system configuration." >&2
      exit 2
    fi
    ;;
esac

# Check for destructive git commands
destructive_patterns=(
  "git push --force"
  "git push -f"
  "git push --force-with-lease"
  "git reset --hard"
  "git checkout -- ."
  "git restore ."
  "git clean -f"
  "rm -rf /"
)

for pattern in "${destructive_patterns[@]}"; do
  if echo "$command" | grep -q "$pattern"; then
    echo "BLOCKED: Destructive command detected: $pattern" >&2
    echo "If you really need to run this, use it directly in your terminal." >&2
    exit 2
  fi
done

# Check for git push to main/master
if echo "$command" | grep -q "^git push"; then
  # Get current branch
  branch=$(git branch --show-current 2>/dev/null)
  #if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
  #    echo "BLOCKED: Direct push to $branch branch is not recommended."
  #    echo "Create a feature branch and push there instead."
  #    exit 2
  #fi
fi

# --- Live status bar message injection (long-running commands only) ---
LIVE_MSG_FILE="/tmp/.claude_live_msg.${CLAUDE_CODE_SESSION_ID}"
if echo "$command" | grep -qE "^(mix test|make test|mix compile|make compile|make deploy|git push|git commit)"; then
  short_cmd=$(echo "$command" | awk '{print $1" "$2}')
  echo "⏳ ${short_cmd}..." > "$LIVE_MSG_FILE"
fi

exit 0

