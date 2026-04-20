# Claude Code Hooks

Hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that automate the Bot Army development workflow.

## Hooks

### focused_test.sh (PostToolUse: Edit|Write)

Automatically runs focused tests matching the edited source file. Detects the feature area from the file path (handlers, stores, nats, etc.) and runs `mix test --only <tag> --trace` for that area. Falls back to path-based test file discovery if tags don't exist yet.

Requires: Elixir/OTP project with `@moduletag`-based test tagging, `mix` on PATH (or mise shims).

### post_tool_use.sh (PostToolUse: Edit|Write)

Auto-formats Elixir files after edits. Walks up from the edited file to find `mix.exs`, then runs `mix format` from that project root.

### version_bump_check.sh (PostToolUse: Edit|Write)

Reminds to bump `mix.exs` version after editing non-test Elixir source files. Writes a note to `/tmp/.claude_note` that appears in the Claude Code status bar for 60 seconds.

### pre_tool_use.sh (PreToolUse: Bash)

Blocks destructive git commands (`git push --force`, `git reset --hard`, `git checkout -- .`, `git clean -f`, `rm -rf /`). Prevents accidental data loss.

## Setup

```bash
# Clone and link hooks into your Claude config
git clone https://github.com/ergon-automation-labs/claude-code-hooks.git
cd claude-code-hooks

# Link individual hooks (or copy them)
ln -s $(pwd)/focused_test.sh ~/.claude/hooks/focused_test.sh
ln -s $(pwd)/post_tool_use.sh ~/.claude/hooks/post_tool_use.sh
ln -s $(pwd)/pre_tool_use.sh ~/.claude/hooks/pre_tool_use.sh
ln -s $(pwd)/version_bump_check.sh ~/.claude/hooks/version_bump_check.sh
```

Then register hooks in `~/.claude/settings.json` or your project's `.claude/settings.json`.

## Hook Input Format

All hooks receive JSON on stdin:

```json
{"tool_name": "Edit", "tool_input": {"file_path": "/path/to/file.ex"}}
```

PreToolUse hooks can block execution by exiting with code 2 and printing a message to stderr.