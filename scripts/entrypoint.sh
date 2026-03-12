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

# --- oh-my-opencode Plugin Setup ---
# oh-my-opencode is installed globally; register it in opencode.json on first run
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"
mkdir -p "${OPENCODE_CONFIG_DIR}"
if [ ! -w "${OPENCODE_CONFIG_DIR}" ]; then
  echo "[entrypoint] warning: ${OPENCODE_CONFIG_DIR} is not writable; skipping oh-my-opencode config injection"
elif [ ! -f "${OPENCODE_CONFIG_FILE}" ] && ! echo '{}' > "${OPENCODE_CONFIG_FILE}"; then
  echo "[entrypoint] warning: failed to create ${OPENCODE_CONFIG_FILE}; skipping oh-my-opencode config injection"
elif command -v jq >/dev/null 2>&1; then
  # Inject plugin entry (idempotent: only adds if not already present)
  if jq 'if (.plugin // []) | index("oh-my-opencode") == null
        then .plugin = ((.plugin // []) + ["oh-my-opencode"])
        else . end' \
      "${OPENCODE_CONFIG_FILE}" > "${OPENCODE_CONFIG_FILE}.tmp" && \
      mv "${OPENCODE_CONFIG_FILE}.tmp" "${OPENCODE_CONFIG_FILE}"; then
    echo "[entrypoint] oh-my-opencode plugin enabled in opencode.json"
  else
    echo "[entrypoint] warning: failed to update ${OPENCODE_CONFIG_FILE}; skipping oh-my-opencode config injection"
    rm -f "${OPENCODE_CONFIG_FILE}.tmp"
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

OPENCHAMBER_PORT="${OPENCHAMBER_PORT:-3010}"
OPENCODE_WORKSPACE="${OPENCODE_WORKSPACE:-/workspace}"
exec env OPENCODE_WORKSPACE="${OPENCODE_WORKSPACE}" bun packages/web/bin/cli.js --port "${OPENCHAMBER_PORT}" ${OPENCHAMBER_ARGS}
