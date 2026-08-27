#!/bin/bash

# --- Helper for bot health ---
check_bot() {
  local bot=$1
  if nc -z localhost 4222 2>/dev/null && nats request --server nats://localhost:4222 "bot.${bot}.health" '{}' --timeout 1s >/dev/null 2>&1; then
    echo "🟢"
  else
    echo "🔴"
  fi
}

# --- Configuration ---
COMMANDS=(
  "curl -s icanhazip.com"
  "ifconfig en0 2>/dev/null | grep 'inet ' | awk '{print \"en0 \" \$2}'"
  "ifconfig tun0 2>/dev/null | grep 'inet ' | awk '{print \"vpn \" \$2}'"
  "uptime | sed 's/.* load average: //'"
  "uptime -p"
  "vm_stat | grep 'Pages free' | awk '{print \"Free: \" \$3 \" pages\"}'"
  "echo \"🔌 NATS:$(nc -z localhost 4222 && echo '🟢' || echo '🔴') DB:$(nc -z localhost 30003 && echo '🟢' || echo '🔴')\""
  "echo \"🤖 LLM:$(check_bot llm) GTD:$(check_bot gtd) S:$(check_bot synapse)\""
)

INDEX=$(( ($(date +%s) / 5) % ${#COMMANDS[@]} ))
eval "${COMMANDS[$INDEX]}"
