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

# Migration reminder for schema edits
if [[ "$file_path" == *_schema.ex ]] || [[ "$file_path" =~ /schemas/ ]]; then
    printf '{"systemMessage": "Schema edited — check if a migration is needed", "continue": true}'
    exit 0
fi

# Consumer/handler sync check
if [[ "$(basename "$file_path")" == "consumer.ex" ]]; then
    bot_root=$(dirname "$file_path")
    while [ "$bot_root" != "/" ]; do
        if [ -f "$bot_root/mix.exs" ]; then
            break
        fi
        bot_root=$(dirname "$bot_root")
    done

    if [ -d "$bot_root/lib" ]; then
        handler_dir=$(find "$bot_root/lib" -type d -name "handlers" 2>/dev/null | head -1)
        if [ -n "$handler_dir" ] && [ -d "$handler_dir" ]; then
            handler_files=$(find "$handler_dir" -name "*_handler.ex" -exec basename {} .ex \; 2>/dev/null | sort)
            if [ -n "$handler_files" ]; then
                unregistered=""
                while IFS= read -r handler_name; do
                    # Convert foo_handler to FooHandler
                    module_name=$(echo "$handler_name" | sed 's/_handler$//' | sed 's/_//g' | sed -E 's/^([a-z])/\U\1/; s/_([a-z])/\U\1/g')FooHandler
                    if ! grep -q "$handler_name" "$file_path" 2>/dev/null; then
                        if [ -z "$unregistered" ]; then
                            unregistered="$handler_name"
                        else
                            unregistered="$unregistered, $handler_name"
                        fi
                    fi
                done <<< "$handler_files"

                if [ -n "$unregistered" ]; then
                    printf '{"systemMessage": "Consumer/handler mismatch — unregistered handlers: %s", "continue": true}' "$unregistered"
                fi
            fi
        fi
    fi
    exit 0
fi

exit 0