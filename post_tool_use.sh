#!/bin/bash
# PostToolUse hook: Format Elixir files and emit architecture warnings
# Receives JSON via stdin: { "tool_name": "Edit"|"Write", "tool_input": { "file_path": "..." } }

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [ "$tool_name" != "Edit" ] && [ "$tool_name" != "Write" ]; then
    exit 0
fi

warnings=()

# ── Elixir file checks ──────────────────────────────────────────────────────
if [[ "$file_path" == *.ex ]] || [[ "$file_path" == *.exs ]]; then
    is_test=false
    [[ "$file_path" == */test/* ]] && is_test=true

    # Auto-format
    mix_dir=$(dirname "$file_path")
    while [ "$mix_dir" != "/" ]; do
        if [ -f "$mix_dir/mix.exs" ]; then
            cd "$mix_dir" && /Users/abby/.local/share/mise/shims/mix format "$file_path" 2>/dev/null
            break
        fi
        mix_dir=$(dirname "$mix_dir")
    done

    if [ "$is_test" = false ]; then
        # Application.get_env in non-test code breaks release config pattern
        if grep -q "Application\.get_env" "$file_path" 2>/dev/null; then
            warnings+=("Application.get_env detected — use compile-time @env Mix.env() instead")
        fi

        # Bare Mix.env() at runtime is unavailable in releases
        if grep -qE "Mix\.env\(\)" "$file_path" 2>/dev/null; then
            if ! grep -qE "@env\s+Mix\.env\(\)" "$file_path" 2>/dev/null; then
                warnings+=("Bare Mix.env() detected — assign to @env at compile time: @env Mix.env()")
            fi
        fi

        # NATS connection in bot supervisors/application — bot_army_runtime owns this
        basename_file=$(basename "$file_path")
        if [[ "$basename_file" == "application.ex" ]] || [[ "$basename_file" == *_supervisor.ex ]]; then
            if grep -qE "(Gnat\.start_link|:nats\.connect|Nats\.connect)" "$file_path" 2>/dev/null; then
                warnings+=("NATS connection in $(basename "$file_path") — bot_army_runtime owns the NATS connection, don't duplicate it in bot supervisors")
            fi
        fi
    fi

    # Schema migration reminder
    if [[ "$file_path" == *_schema.ex ]] || [[ "$file_path" =~ /schemas/ ]]; then
        warnings+=("Schema edited — check if a migration is needed")
    fi

    # Consumer/handler sync check
    if [[ "$basename_file" == "consumer.ex" ]] || [[ "$(basename "$file_path")" == "consumer.ex" ]]; then
        bot_root=$(dirname "$file_path")
        while [ "$bot_root" != "/" ]; do
            [ -f "$bot_root/mix.exs" ] && break
            bot_root=$(dirname "$bot_root")
        done

        if [ -d "$bot_root/lib" ]; then
            handler_dir=$(find "$bot_root/lib" -type d -name "handlers" 2>/dev/null | head -1)
            if [ -n "$handler_dir" ] && [ -d "$handler_dir" ]; then
                handler_files=$(find "$handler_dir" -name "*_handler.ex" -exec basename {} .ex \; 2>/dev/null | sort)
                if [ -n "$handler_files" ]; then
                    unregistered=""
                    while IFS= read -r handler_name; do
                        if ! grep -q "$handler_name" "$file_path" 2>/dev/null; then
                            unregistered="${unregistered:+$unregistered, }$handler_name"
                        fi
                    done <<< "$handler_files"
                    [ -n "$unregistered" ] && warnings+=("Unregistered handlers in consumer: $unregistered")
                fi
            fi
        fi
    fi
fi

# ── Go TUI file checks ───────────────────────────────────────────────────────
if [[ "$file_path" == *.go ]]; then
    if grep -qE '"nats://localhost:[0-9]+"' "$file_path" 2>/dev/null || \
       grep -qE "localhost:[42][24][234]" "$file_path" 2>/dev/null; then
        warnings+=("NATS localhost in Go TUI — use host.docker.internal instead (TUIs run inside Docker)")
    fi
fi

# ── Verification block reminder for lib/ edits ────────────────────────────────
if [ "$is_test" = false ] && [[ "$file_path" == */lib/* ]]; then
    mix_dir=$(dirname "$file_path")
    while [ "$mix_dir" != "/" ]; do
        if [ -f "$mix_dir/mix.exs" ]; then
            warnings+=("If this change closes a GTD task, ensure the task has a Verification block and run 'make mark-task-test-pass'")
            break
        fi
        mix_dir=$(dirname "$mix_dir")
    done
fi

# ── Emit combined system message ─────────────────────────────────────────────
if [ ${#warnings[@]} -gt 0 ]; then
    msg=$(printf '%s | ' "${warnings[@]}")
    msg="${msg% | }"
    printf '{"systemMessage": "%s", "continue": true}' "$msg"
fi

# ── Live status bar message injection (completion / warnings) ──────────────────
LIVE_MSG_FILE="/tmp/.claude_live_msg.${CLAUDE_CODE_SESSION_ID}"
if [ ${#warnings[@]} -gt 0 ]; then
    echo "⚠️  ${#warnings[@]} warning(s) — see systemMessage" > "$LIVE_MSG_FILE"
elif [ "$tool_name" = "Edit" ] || [ "$tool_name" = "Write" ]; then
    filename=$(basename "$file_path")
    echo "✅ ${tool_name}: ${filename}" > "$LIVE_MSG_FILE"
fi

exit 0
