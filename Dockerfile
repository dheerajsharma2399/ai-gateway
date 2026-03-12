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

# Create ai-gateway user
RUN useradd -m -s /bin/bash ai-gateway

ENV HOME="/home/ai-gateway"
ENV NPM_CONFIG_PREFIX=/home/ai-gateway/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}
ENV PLAYWRIGHT_BROWSERS_PATH=/home/ai-gateway/.cache/ms-playwright
ENV XDG_CONFIG_HOME=/home/ai-gateway/.config
ENV XDG_DATA_HOME=/home/ai-gateway/.local/share
ENV XDG_STATE_HOME=/home/ai-gateway/.local/state

WORKDIR /home/ai-gateway

# Install all CLI tools globally
# opencode-ai → `opencode` CLI
# @anthropic/claude-code → `claude` CLI
# @openchamber/web → `openchamber` web server
# oh-my-opencode → opencode plugin
# 9router → local AI endpoint proxy
# task-master-ai → `task-master-mcp` server
# playwright → browser automation CLI + MCP
RUN npm config set prefix /home/ai-gateway/.npm-global && \
 mkdir -p /home/ai-gateway/.npm-global \
 /home/ai-gateway/.local \
 /home/ai-gateway/.config \
 /home/ai-gateway/.ssh && \
 npm install -g \
 opencode-ai@latest \
 @anthropic-ai/claude-code@latest \
 @openchamber/web@latest \
 oh-my-opencode@latest \
 9router@latest \
 task-master-ai@latest \
 playwright@latest && \
 npx playwright install --with-deps chromium && \
 chown -R ai-gateway:ai-gateway /home/ai-gateway

USER ai-gateway

# Copy MCP server config template
COPY --chmod=644 .mcp.json /home/ai-gateway/.mcp.json.template

# Copy entrypoint script
COPY --chmod=755 scripts/entrypoint.sh /app/entrypoint.sh

# Create required directories
RUN mkdir -p /home/ai-gateway/workspaces \
 /home/ai-gateway/.claude \
 /home/ai-gateway/.taskmaster \
 /home/ai-gateway/.cache/ms-playwright

EXPOSE 3010 3011

ENTRYPOINT ["/app/entrypoint.sh"]
