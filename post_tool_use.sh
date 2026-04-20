#!/bin/bash
# PostToolUse hook: Auto-format Elixir files after edits
# Receives JSON via stdin: { "tool_name": "Edit"|"Write", "tool_input": { "file_path": "..." } }

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only format after Edit or Write operations
if [ "$tool_name" != "Edit" ] && [ "$tool_name" != "Write" ]; then
    exit 0
fi

# Only format Elixir files
if [[ "$file_path" == *.ex ]] || [[ "$file_path" == *.exs ]]; then
    # Find the mix.exs directory for proper format context
    mix_dir=$(dirname "$file_path")
    while [ "$mix_dir" != "/" ]; do
        if [ -f "$mix_dir/mix.exs" ]; then
            # Run mix format relative to the project root
            cd "$mix_dir" && /Users/abby/.local/share/mise/shims/mix format "$file_path" 2>/dev/null
            break
        fi
        mix_dir=$(dirname "$mix_dir")
    done
fi

exit 0