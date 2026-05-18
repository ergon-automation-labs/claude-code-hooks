#!/bin/bash
# PreToolUse hook: Blocks destructive git commands on main/master branches
# Receives JSON via stdin: { "tool_name": "Bash", "tool_input": { "command": "..." } }

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only check Bash commands
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

# Check for NATS prod port in dev context — allow GTD commands, Claude triggers, and diagnostic tools
if echo "$command" | grep -q "nats://localhost:4222"; then
  # Allow: bridge.* subjects (project/task/goal management), GTD task tracking, Claude triggers, diagnostic commands, nats-helper
  if ! echo "$command" | grep -qE "(bridge\.|gtd\.|gtd_bot|bot_army\.claude\.|nats-helper|nats (stream|consumer|server|top|subscribe|pub|req|kv|account|sub|add|rm|create|pub|sub|consumer|ls|info|view|jsz)|nats --server)"; then
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

# Block writes to Salt-provisioned system directories — bots must not create these
if echo "$command" | grep -qE "(mkdir|touch|tee|cp|mv|install)[^|]*(/var/log|/etc|/opt)/"; then
  echo "BLOCKED: System directories (/var/log, /etc, /opt) are provisioned by Salt, not by bots." >&2
  exit 2
fi

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

exit 0

