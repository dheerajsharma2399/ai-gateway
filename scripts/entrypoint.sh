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

# --- Git Safe Directory (fix 'dubious ownership' on volume-mounted workspaces) ---
git config --global --add safe.directory '*' 2>/dev/null || true

## --- Startup Diagnostics ---
echo "[entrypoint] User: $(id)"
echo "[entrypoint] Node environment: $(node -v)"
echo "[entrypoint] Working directory: $(pwd)"
echo "[entrypoint] Checking binary permissions..."
ls -la $(which node) $(which opencode) $(which claude) 2>/dev/null || echo "[entrypoint] warning: some binaries not in PATH"

# --- OpenCode Setup & LiteLLM Injection ---
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"
mkdir -p "${OPENCODE_CONFIG_DIR}"

if [ ! -w "${OPENCODE_CONFIG_DIR}" ]; then
  echo "[entrypoint] warning: ${OPENCODE_CONFIG_DIR} is not writable; skipping OpenCode config injection"
else
  echo "[entrypoint] configuring OpenCode providers & plugins..."

  _LITELLM_URL="${LITELLM_BASE_URL:-http://host.docker.internal:4000}/v1"
  _OPENCODE_MODEL="${OPENCODE_DEFAULT_MODEL:-drdash/anthropic/claude-3.5-sonnet}"
  _LITELLM_KEY="${LITELLM_API_KEY:-sk-dummy}"

  # Write the new provider block to a temp file
  cat > /tmp/litellm_provider.json <<OCLITELLMEOF
{
  "plugin": ["oh-my-opencode"],
  "model": "litellm/${_OPENCODE_MODEL}",
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LiteLLM",
      "options": {
        "baseURL": "${_LITELLM_URL}",
        "apiKey": "${_LITELLM_KEY}"
      },
      "models": {
        "litellm/${_OPENCODE_MODEL}": { "name": "Primary (Claude)" }
      }
    }
  }
}
OCLITELLMEOF

  # Robust merge: preserve existing user config if valid, else write fresh.
  # If valid, we merge the LiteLLM provider block but let user models/agents win.
  if [ -f "${OPENCODE_CONFIG_FILE}" ] && jq empty "${OPENCODE_CONFIG_FILE}" 2>/dev/null; then
    echo "[entrypoint] OpenCode config already exists; merging LiteLLM provider..."
    # Merging: .[0] is existing config, .[1] is our injection.
    # We use * to merge, but we want to make sure 'litellm' provider exists.
    # We also ensure model prefixes are added if missing to prevent "model not found" errors.
    TEMP_CONF=$(mktemp)
    jq -s '.[0] * .[1] |
          if (.plugin // []) | index("oh-my-opencode") == null then .plugin += ["oh-my-opencode"] else . end |
          (.provider.litellm.models // {}) |= with_entries(.key |= if startswith("litellm/") then . else "litellm/" + . end) |
          if .model and (.model | startswith("litellm/") | not) then .model = "litellm/" + .model else . end
          ' "${OPENCODE_CONFIG_FILE}" /tmp/litellm_provider.json > "${TEMP_CONF}"
    mv "${TEMP_CONF}" "${OPENCODE_CONFIG_FILE}"
  else
    cp /tmp/litellm_provider.json "${OPENCODE_CONFIG_FILE}"
    echo "[entrypoint] OpenCode config written fresh"
  fi

  rm -f /tmp/litellm_provider.json

  # OpenCode resolves "npm" providers from the config dir's node_modules.
  # Symlink the globally-installed @ai-sdk/openai-compatible in there so it's found.
  GLOBAL_SDK="${NPM_CONFIG_PREFIX:-/home/ai-gateway/.npm-global}/lib/node_modules/@ai-sdk/openai-compatible"
  LOCAL_SDK="${OPENCODE_CONFIG_DIR}/node_modules/@ai-sdk/openai-compatible"
  if [ -d "${GLOBAL_SDK}" ] && [ ! -e "${LOCAL_SDK}" ]; then
    mkdir -p "${OPENCODE_CONFIG_DIR}/node_modules/@ai-sdk"
    ln -sf "${GLOBAL_SDK}" "${LOCAL_SDK}"
    echo "[entrypoint] Linked @ai-sdk/openai-compatible"
  fi
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
