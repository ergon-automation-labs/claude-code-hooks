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

# Check for NATS prod port in dev context
if echo "$command" | grep -q "nats://localhost:4222"; then
  echo "BLOCKED: Prod NATS port (4222) detected. Use 4223 for dev." >&2
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

