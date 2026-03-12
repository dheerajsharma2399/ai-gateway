# syntax=docker/dockerfile:1
# AI Gateway - Unified AI Development Environment
# All tools installed via npm: OpenCode, Claude Code, OpenChamber, oh-my-opencode, 9router, Task Master, Playwright

FROM node:22-bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
 bash \
 ca-certificates \
 curl \
 wget \
 jq \
 git \
 build-essential \
 openssh-client \
 python3 \
 less \
 unzip \
 && rm -rf /var/lib/apt/lists/*

# Install cloudflared (apt package when available, fallback to official .deb)
RUN apt-get update && \
 (apt-get install -y --no-install-recommends cloudflared || true) && \
 if ! command -v cloudflared >/dev/null 2>&1; then \
 ARCH="$(dpkg --print-architecture)"; \
 curl -fsSL -o /tmp/cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb"; \
 apt-get install -y /tmp/cloudflared.deb; \
 rm -f /tmp/cloudflared.deb; \
 fi && \
 rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

# Create ai-gateway user with UID 1000 to match opc user on Oracle Cloud VPS
# (opc is uid 1000 on Oracle Cloud and owns all the bind-mounted agent data)
# Remove existing node user first to free up UID 1000
RUN userdel -r node && \
 useradd -m -u 1000 -s /bin/bash ai-gateway

ENV HOME="/home/ai-gateway"
ENV NPM_CONFIG_PREFIX=/home/ai-gateway/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}
ENV PLAYWRIGHT_BROWSERS_PATH=/home/ai-gateway/.cache/ms-playwright
ENV XDG_CONFIG_HOME=/home/ai-gateway/.config
ENV XDG_DATA_HOME=/home/ai-gateway/.local/share
ENV XDG_STATE_HOME=/home/ai-gateway/.local/state
# Allow OpenCode to dynamically require() globally-installed npm providers (e.g. @ai-sdk/openai-compatible)
ENV NODE_PATH=/home/ai-gateway/.npm-global/lib/node_modules

WORKDIR /home/ai-gateway

# Install all CLI tools globally
# opencode-ai → `opencode` CLI
# @anthropic/claude-code → `claude` CLI
# @openchamber/web → `openchamber` web server
# oh-my-opencode → opencode plugin
# 9router → local AI endpoint proxy
# task-master-ai → `task-master-mcp` server
# playwright → browser automation CLI + MCP
# Set up NPM global directory
RUN npm config set prefix /home/ai-gateway/.npm-global && \
  mkdir -p /home/ai-gateway/.npm-global \
  /home/ai-gateway/.local \
  /home/ai-gateway/.config \
  /home/ai-gateway/.ssh

# Use Docker Buildx caching for NPM to drastically speed up builds
RUN --mount=type=cache,target=/home/ai-gateway/.npm,uid=1000,gid=1000 \
  npm install -g --prefer-offline --no-audit --no-fund --loglevel=error \
  opencode-ai@latest \
  @anthropic-ai/claude-code@latest \
  @anthropic-ai/claude-agent-sdk@latest \
  @siteboon/claude-code-ui@latest \
  @openchamber/web@latest \
  oh-my-opencode@latest \
  9router@latest \
  task-master-ai@latest \
  @ai-sdk/openai-compatible@latest \
  playwright@latest

# Install Playwright dependencies separately for better caching
RUN npx playwright install --with-deps chromium

# Create required directories and fix cache permissions while still root
RUN mkdir -p /home/ai-gateway/workspaces \
  /home/ai-gateway/.claude \
  /home/ai-gateway/.taskmaster \
  /home/ai-gateway/.config/opencode \
  /home/ai-gateway/.claude-code-ui \
  /home/ai-gateway/.cache/ms-playwright \
  /home/ai-gateway/.cache/opencode && \
  chown -R ai-gateway:ai-gateway /home/ai-gateway

USER ai-gateway

# Copy MCP server config template
COPY --chmod=644 .mcp.json /home/ai-gateway/.mcp.json.template

# Copy entrypoint script
COPY --chmod=755 scripts/entrypoint.sh /app/entrypoint.sh

EXPOSE 3010 3011

ENTRYPOINT ["/app/entrypoint.sh"]
