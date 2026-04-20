#!/bin/bash
# PostToolUse hook: Run focused tests matching the edited source file
# Input: JSON on stdin with tool_name and tool_input.file_path
# Determines the feature tag from the file path, runs matching tests with --only

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

# Skip test files themselves
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

# Get relative path from bot root
rel_path="${file_path#$bot_root/}"

# Extract feature tag from the source path
feature=""
if [[ "$rel_path" =~ lib/bot_army_[^/]+/([^/]+)/ ]]; then
  category_dir="${BASH_REMATCH[1]}"
  case "$category_dir" in
    handlers)      feature="handlers" ;;
    stores)        feature="stores" ;;
    nats)          feature="nats" ;;
    schemas)       feature="schemas" ;;
    pipeline)      feature="pipeline" ;;
    ingestion)     feature="ingestion" ;;
    integrations)  feature="integrations" ;;
    runbooks)      feature="runbooks" ;;
    workers)       feature="workers" ;;
    http)          feature="http" ;;
    skills)        feature="skills" ;;
    api_clients)   feature="api_clients" ;;
    investigation) feature="investigations" ;;
    *)             feature="core" ;;
  esac
else
  # Top-level file under lib/bot_army_<name>/
  basename=$(basename "$file_path")
  case "$basename" in
    *_handler.ex)     feature="handlers" ;;
    *_store.ex)       feature="stores" ;;
    *_scheduler.ex)   feature="scheduler" ;;
    formatter.ex)     feature="format" ;;
    *_client.ex)      feature="client" ;;
    personality.ex)   feature="handlers" ;;
    application.ex)   feature="core" ;;
    repo.ex)          feature="stores" ;;
    *)                feature="core" ;;
  esac
fi

if [ -z "$feature" ]; then
  exit 0
fi

# Run focused tests for this feature tag
cd "$bot_root"

# Try tag-based first
output=$(MIX_ENV=test /Users/abby/.local/share/mise/shims/mix test --only "$feature" --trace 2>&1)
exit_code=$?

# Check if any tests actually ran (tag might not exist yet)
test_count=$(echo "$output" | grep -o '[0-9]* tests,' | head -1 | grep -o '[0-9]*' || echo "0")

if [ "$test_count" = "0" ] || [ -z "$test_count" ]; then
  # Fall back to path-based test discovery
  test_pattern=""
  case "$feature" in
    handlers)      test_pattern="handlers" ;;
    stores)        test_pattern="stores" ;;
    nats)          test_pattern="nats" ;;
    schemas)       test_pattern="schemas" ;;
    pipeline)      test_pattern="pipeline" ;;
    ingestion)     test_pattern="ingestion" ;;
    integrations)  test_pattern="integrations" ;;
    runbooks)      test_pattern="runbooks" ;;
    workers)       test_pattern="workers" ;;
    http)          test_pattern="http" ;;
    skills)        test_pattern="skills" ;;
    api_clients)   test_pattern="api_clients" ;;
    investigations) test_pattern="investigations" ;;
    scheduler)     test_pattern="scheduler" ;;
    format)        test_pattern="format" ;;
    client)        test_pattern="client" ;;
    *)             test_pattern="" ;;
  esac

  if [ -n "$test_pattern" ]; then
    test_files=$(find test -path "*/${test_pattern}/*_test.exs" -o -name "*${test_pattern}*_test.exs" 2>/dev/null | tr '\n' ' ')
    if [ -n "$test_files" ]; then
      bot_name=$(basename "$bot_root")
      echo "Running path-matched tests for :${feature} in ${bot_name}..."
      MIX_ENV=test /Users/abby/.local/share/mise/shims/mix test $test_files --trace 2>&1 | tail -20
      exit 0
    fi
  fi

  # No tests found at all — silent exit
  exit 0
fi

# Tag-based tests ran — show results
bot_name=$(basename "$bot_root")
echo "Running :${feature} tests in ${bot_name}..."
echo "$output" | tail -20

exit 0