#!/bin/bash
# PostToolUse hook: Remind to bump version in mix.exs when lib files change
# Receives JSON via stdin: { "tool_name": "Edit"|"Write", "tool_input": { "file_path": "..." } }

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only check after Edit or Write
if [ "$tool_name" != "Edit" ] && [ "$tool_name" != "Write" ]; then
  exit 0
fi

# Only check Elixir files
if [[ "$file_path" != *.ex ]] && [[ "$file_path" != *.exs ]]; then
  exit 0
fi

# Skip mix.exs itself — editing it IS the bump
if [[ "$(basename "$file_path")" == "mix.exs" ]]; then
  exit 0
fi

# Skip test files
if [[ "$file_path" == */test/* ]]; then
  exit 0
fi

# Find the project root (directory containing mix.exs)
project_dir=$(dirname "$file_path")
while [ "$project_dir" != "/" ]; do
  if [ -f "$project_dir/mix.exs" ]; then
    break
  fi
  project_dir=$(dirname "$project_dir")
done

# If no mix.exs found, not an Elixir project — skip
if [ ! -f "$project_dir/mix.exs" ]; then
  exit 0
fi

# Check if mix.exs version was already bumped in this session
if git diff "$project_dir/mix.exs" 2>/dev/null | grep -q '@version'; then
  # Version already changed — suppress reminder
  exit 0
fi

# Set a note that appears in the status bar for 60 seconds
echo "bump mix.exs version" > /tmp/.claude_note

exit 0