#!/bin/bash
# PostToolUse hook: Suggest related files when editing source code
# Input: JSON on stdin with tool_name and tool_input.file_path
# Outputs a system message suggesting related test and source files

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Only fire on Edit or Write operations
if [ "$tool_name" != "Edit" ] && [ "$tool_name" != "Write" ]; then
  exit 0
fi

# Only process Elixir source files
if [[ "$file_path" != *.ex ]] && [[ "$file_path" != *.exs ]]; then
  exit 0
fi

# Skip test files
if [[ "$file_path" == */test/* ]]; then
  exit 0
fi

# Find the bot root (directory with mix.exs)
bot_root=$(dirname "$file_path")
while [ "$bot_root" != "/" ]; do
  if [ -f "$bot_root/mix.exs" ]; then
    break
  fi
  bot_root=$(dirname "$bot_root")
done

if [ ! -f "$bot_root/mix.exs" ]; then
  exit 0
fi

# Get the basename and relative path
basename=$(basename "$file_path")
rel_path="${file_path#$bot_root/}"

# Build suggestions
suggestions=""

# Map source file to test file
if [[ "$rel_path" =~ ^lib/(.*/)([^/]+)\.ex$ ]]; then
  dir_part="${BASH_REMATCH[1]}"
  name_part="${BASH_REMATCH[2]}"
  # Source: lib/bot_army_x/handlers/foo_handler.ex → test/bot_army_x/handlers/foo_handler_test.exs
  test_path="${bot_root}/test/${dir_part}${name_part}_test.exs"
  if [ -f "$test_path" ]; then
    suggestions="${suggestions}Test: ${test_path}"
  fi
fi

# For handler files, also suggest the consumer
if [[ "$basename" == *_handler.ex ]]; then
  consumer_path="${bot_root}/lib/$(echo "$rel_path" | sed 's|/handlers/.*||' | sed 's|^lib/||')/nats/consumer.ex"
  # Reconstruct path properly
  bot_lib_dir=$(echo "$rel_path" | sed 's|/handlers/.*||')
  consumer_path="${bot_root}/${bot_lib_dir}/nats/consumer.ex"
  if [ -f "$consumer_path" ]; then
    if [ -n "$suggestions" ]; then
      suggestions="${suggestions} | "
    fi
    suggestions="${suggestions}Consumer: ${consumer_path}"
  fi
fi

# For consumer files, suggest all handlers
if [[ "$basename" == "consumer.ex" ]]; then
  handler_dir=$(dirname "$file_path")
  handler_dir="${handler_dir%/nats}/handlers"
  if [ -d "$handler_dir" ]; then
    handler_count=$(find "$handler_dir" -name '*_handler.ex' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$handler_count" -gt 0 ]; then
      if [ -n "$suggestions" ]; then
        suggestions="${suggestions} | "
      fi
      suggestions="${suggestions}Handlers: ${handler_count} files in ${handler_dir}"
    fi
  fi
fi

# For store files, suggest the behaviour file
if [[ "$basename" == *_store.ex ]]; then
  behaviour_name=$(echo "$basename" | sed 's/\.ex$/_behaviour.ex/')
  # Try to find the behaviour
  behaviour_path=$(find "$bot_root/lib" -name "$behaviour_name" 2>/dev/null | head -1)
  if [ -n "$behaviour_path" ]; then
    if [ -n "$suggestions" ]; then
      suggestions="${suggestions} | "
    fi
    suggestions="${suggestions}Behaviour: ${behaviour_path}"
  fi
fi

# Output as system message if we found anything
if [ -n "$suggestions" ]; then
  printf '{"systemMessage": "Related: %s", "continue": true}' "$suggestions"
fi

exit 0