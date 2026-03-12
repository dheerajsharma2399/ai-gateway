#!/usr/bin/env sh
set -eu

HOME="/home/ai-gateway"
export HOME

OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${HOME}/.config/opencode}"
export OPENCODE_CONFIG_DIR

SSH_DIR="${HOME}/.ssh"
SSH_PRIVATE_KEY_PATH="${SSH_DIR}/id_ed25519"
SSH_PUBLIC_KEY_PATH="${SSH_PRIVATE_KEY_PATH}.pub"

echo "[entrypoint] AI Gateway starting..."

# --- SSH Key Setup ---
mkdir -p "${SSH_DIR}"
if ! chmod 700 "${SSH_DIR}" 2>/dev/null; then
  echo "[entrypoint] warning: cannot chmod ${SSH_DIR}, continuing with existing permissions"
fi

if [ ! -f "${SSH_PRIVATE_KEY_PATH}" ] || [ ! -f "${SSH_PUBLIC_KEY_PATH}" ]; then
  if [ ! -w "${SSH_DIR}" ]; then
    echo "[entrypoint] error: ssh key missing and ${SSH_DIR} is not writable" >&2
    exit 1
  fi

  echo "[entrypoint] generating SSH key..."
  ssh-keygen -t ed25519 -N "" -f "${SSH_PRIVATE_KEY_PATH}" >/dev/null
fi

if ! chmod 600 "${SSH_PRIVATE_KEY_PATH}" 2>/dev/null; then
  echo "[entrypoint] warning: cannot chmod ${SSH_PRIVATE_KEY_PATH}, continuing"
fi

if ! chmod 644 "${SSH_PUBLIC_KEY_PATH}" 2>/dev/null; then
  echo "[entrypoint] warning: cannot chmod ${SSH_PUBLIC_KEY_PATH}, continuing"
fi

echo "[entrypoint] SSH public key:"
cat "${SSH_PUBLIC_KEY_PATH}"

# --- Claude Code Setup ---
echo "[entrypoint] checking Claude Code..."
if [ ! -f "${HOME}/.claude/settings.json" ]; then
  echo "[entrypoint] Claude Code not authenticated. Run: docker exec -it ai-gateway claude"
fi

# --- MCP Config Setup ---
if [ -f "${HOME}/.mcp.json.template" ] && [ ! -f "${HOME}/.mcp.json" ]; then
  echo "[entrypoint] setting up MCP config..."
  cp "${HOME}/.mcp.json.template" "${HOME}/.mcp.json"
fi

# --- OpenCode Setup & LiteLLM Injection ---
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"
mkdir -p "${OPENCODE_CONFIG_DIR}"

if [ ! -w "${OPENCODE_CONFIG_DIR}" ]; then
  echo "[entrypoint] warning: ${OPENCODE_CONFIG_DIR} is not writable; skipping OpenCode config injection"
else
  echo "[entrypoint] configuring OpenCode providers & plugins..."
  
  # Ensure LiteLLM models exist in environment variables (or fallbacks)
  LITELLM_BASE_URL="${LITELLM_BASE_URL:-http://host.docker.internal:4000}/v1"
  OPENCODE_DEFAULT_MODEL="${OPENCODE_DEFAULT_MODEL:-drdash/anthropic/claude-3.5-sonnet}"
  
  # Create a temporary JSON with the LiteLLM provider and our models
  cat > /tmp/litellm_provider.json <<EOF
{
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "${LITELLM_BASE_URL}",
        "apiKey": "${LITELLM_API_KEY:-dummy_key}"
      },
      "models": {
        "${OPENCODE_DEFAULT_MODEL}": {
          "name": "Primary (Claude)"
        },
        "deepak/meta/llama-3.1-405b-instruct": {
          "name": "Deepak - Llama 405B"
        },
        "deepak/nvidia/nemotron-4-340b-instruct": {
          "name": "Deepak - Nemotron 340B"
        },
        "deepak/z-ai/glm5": {
          "name": "Deepak - GLM5"
        },
        "deepak/qwen/qwen3.5-397b-a17b": {
          "name": "Deepak - Qwen 3.5 397B"
        },
        "dheeru/moonshotai/kimi-k2.5": {
          "name": "Dheeru - Kimi K2.5"
        },
        "drdash/google/gemma-3-27b-it:free": {
          "name": "DrDash - Gemma 3 27B (free)"
        },
        "akhil/anthropic/claude-3.5-sonnet": {
          "name": "Akhil - Claude 3.5 Sonnet"
        },
        "dhanesh/google/gemma-3-27b-it:free": {
          "name": "Dhanesh - Gemma 3 27B (free)"
        }
      }
    }
  },
  "model": "${OPENCODE_DEFAULT_MODEL}"
}
EOF

  if [ -f "${OPENCODE_CONFIG_FILE}" ]; then
      # Merge new provider block and ensure oh-my-opencode is in plugins
      jq -s '.[0] * .[1] | if (.plugin // []) | index("oh-my-opencode") == null then .plugin = ((.plugin // []) + ["oh-my-opencode"]) else . end' \
          "${OPENCODE_CONFIG_FILE}" /tmp/litellm_provider.json > "${OPENCODE_CONFIG_FILE}.tmp" && \
          mv "${OPENCODE_CONFIG_FILE}.tmp" "${OPENCODE_CONFIG_FILE}"
  else
      # Create fresh mapping config
      echo '{"$schema": "https://opencode.ai/config.json", "plugin": ["oh-my-opencode"]}' | jq -s '.[0] * .[1]' - /tmp/litellm_provider.json > "${OPENCODE_CONFIG_FILE}"
  fi
  rm -f /tmp/litellm_provider.json
  echo "[entrypoint] OpenCode configured with LiteLLM provider and oh-my-opencode plugin"
fi

# --- OpenChamber Args ---
OPENCHAMBER_ARGS=""

# --- 9router Setup ---
# 9router stores persistent auth/settings at ~/.9router/db.json
NINE_ROUTER_ENABLED="${NINE_ROUTER_ENABLED:-true}"
NINE_ROUTER_PORT="${NINE_ROUTER_PORT:-20128}"
if [ "${NINE_ROUTER_ENABLED}" = "true" ]; then
  echo "[entrypoint] starting 9router on port ${NINE_ROUTER_PORT}..."
  mkdir -p "${HOME}/.9router"
  9router --port "${NINE_ROUTER_PORT}" --no-browser --skip-update > /tmp/9router.log 2>&1 &
  NINE_ROUTER_PID=$!
  echo "[entrypoint] 9router started (PID: ${NINE_ROUTER_PID})"
fi

if [ -n "${UI_PASSWORD:-}" ]; then
  echo "[entrypoint] UI password set, enabling authentication"
  OPENCHAMBER_ARGS="${OPENCHAMBER_ARGS} --ui-password ${UI_PASSWORD}"
fi

# Cloudflare Tunnel
if [ -n "${CF_TUNNEL:-}" ] && [ "${CF_TUNNEL:-false}" != "false" ]; then
  echo "[entrypoint] Cloudflare Tunnel enabled (${CF_TUNNEL})"
  OPENCHAMBER_ARGS="${OPENCHAMBER_ARGS} --try-cf-tunnel"

  case "${CF_TUNNEL}" in
    "qr") OPENCHAMBER_ARGS="${OPENCHAMBER_ARGS} --tunnel-qr" ;;
    "password") OPENCHAMBER_ARGS="${OPENCHAMBER_ARGS} --tunnel-password-url" ;;
  esac
fi

# --- Start ClaudeCodeUI in background ---
CLAUDEUI_PORT="${CLAUDEUI_PORT:-3011}"
echo "[entrypoint] starting ClaudeCodeUI on port ${CLAUDEUI_PORT}..."

# Run ClaudeCodeUI in background
export PORT="${CLAUDEUI_PORT}"
export HOST="0.0.0.0"
claude-code-ui > /tmp/claude-code-ui.log 2>&1 &
CLAUDEUI_PID=$!
echo "[entrypoint] ClaudeCodeUI started (PID: ${CLAUDEUI_PID})"

# --- Start OpenChamber ---
echo "[entrypoint] starting OpenChamber..."

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

# Define graceful shutdown function for ALL tools
cleanup() {
  echo "[entrypoint] Received stop signal. Beginning graceful shutdown of all processes..."

  if [ -n "${CLAUDEUI_PID:-}" ]; then
    echo "[entrypoint] Stopping ClaudeCodeUI (PID: $CLAUDEUI_PID)..."
    kill -TERM "$CLAUDEUI_PID" 2>/dev/null || true
  fi

  if [ -n "${NINE_ROUTER_PID:-}" ]; then
    echo "[entrypoint] Stopping 9router (PID: $NINE_ROUTER_PID)..."
    kill -TERM "$NINE_ROUTER_PID" 2>/dev/null || true
  fi

  if [ -n "${OPENCHAMBER_PID:-}" ]; then
    echo "[entrypoint] Stopping OpenChamber (PID: $OPENCHAMBER_PID)..."
    kill -TERM "$OPENCHAMBER_PID" 2>/dev/null || true
  fi

  # Also nuke any rogue orphaned openchamber/opencode processes running under this user just in case
  pkill -TERM -f openchamber 2>/dev/null || true
  pkill -TERM -f opencode 2>/dev/null || true
  pkill -TERM -f claude-code-ui 2>/dev/null || true
  pkill -TERM -f 9router 2>/dev/null || true

  echo "[entrypoint] Graceful shutdown complete."
  exit 0
}

# Trap docker SIGTERM and Ctrl+C SIGINT
trap cleanup TERM INT

# OpenChamber always runs on port 7802
OPENCHAMBER_PORT="7802"
OPENCODE_WORKSPACE="${OPENCODE_WORKSPACE:-/workspace}"

echo "[entrypoint] OpenChamber port: ${OPENCHAMBER_PORT}"
echo "[entrypoint] OpenCode workspace: ${OPENCODE_WORKSPACE}"

# Run OpenChamber in the background so the trap can catch signals
openchamber --port "${OPENCHAMBER_PORT}" ${OPENCHAMBER_ARGS} &
OPENCHAMBER_PID=$!

# Wait block so script doesn't exit immediately and keeps traps alive
wait
