#!/bin/bash
# PostToolUse hook: Warn if bot code changed but version didn't
# Runs after mix.exs edits to detect version bumps
# Input: JSON on stdin with tool_name and tool_input.file_path

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only fire on Edit operations to mix.exs
if [ "$tool_name" != "Edit" ]; then
  exit 0
fi

if [[ "$file_path" != */mix.exs ]]; then
  exit 0
fi

# Find the bot root (directory with mix.exs)
bot_root=$(dirname "$file_path")

# Extract bot name from directory
bot_name=$(basename "$bot_root")

# Get current version from mix.exs (staged or working copy)
current_version=$(grep -E '^\s+version:' "$file_path" 2>/dev/null | sed 's/.*version: "\([^"]*\)".*/\1/' | head -1)

if [ -z "$current_version" ]; then
  exit 0
fi

# Get previous version from git HEAD
prev_version=$(git show HEAD:"$file_path" 2>/dev/null | grep -E '^\s+version:' | sed 's/.*version: "\([^"]*\)".*/\1/' | head -1)

if [ -z "$prev_version" ]; then
  # No previous version (first commit), don't warn
  exit 0
fi

# If versions match, no warning needed
if [ "$current_version" = "$prev_version" ]; then
  # Check if any bot code actually changed in the staging area
  # Look for changes in lib/ excluding mix files
  code_changes=$(git diff --cached --name-only "$bot_root" 2>/dev/null | grep -E '^bot_army_[^/]+/lib/' | wc -l)

  if [ "$code_changes" -gt 0 ]; then
    echo "⚠️  Version check: ${bot_name} code changed but version stayed at ${current_version}"
    echo "   Did you mean to bump the version? (Current: $current_version)"
    exit 0
  fi
fi

exit 0
