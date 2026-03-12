# AI Gateway

A self-hosted AI development environment combining **OpenCode** + **Claude Code** + **ClaudeCodeUI** + **Task Master** + **Playwright** in a single Docker container.

## Features

- **OpenCode** - AI coding assistant (OpenCode CLI)
- **Claude Code** - Anthropic's AI coding CLI
- **ClaudeCodeUI** - Web UI for Claude Code
- **Task Master** - MCP server for task management & PRD parsing
- **Playwright** - Headless browser automation
- **Cloudflare Tunnel** - Remote access via QR code

## Quick Start

### 1. Build

```bash
docker compose build ai-gateway
```

### 2. Run

```bash
docker compose up -d ai-gateway
```

### 3. Access

- **OpenChamber UI:** `https://opencode.mooh.me` (or `http://localhost:7802` from host)
- **ClaudeCodeUI:** `https://claude.mooh.me` (or `http://localhost:3011` from host)

### 4. First-time Claude Code Auth

```bash
docker exec -it ai-gateway claude
```

Follow the Anthropic browser auth flow. The auth persists in the volume.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCHAMBER_DOMAIN` | OpenChamber domain for Traefik | `opencode.mooh.me` |
| `CLAUDEUI_DOMAIN` | ClaudeCodeUI domain for Traefik | `claude.mooh.me` |
| `OPENCHAMBER_PORT` | OpenChamber UI port | `7802` |
| `CLAUDEUI_PORT` | ClaudeCodeUI port | `3011` |
| `UI_PASSWORD` | OpenChamber UI password | - |
| `LITELLM_BASE_URL` | LiteLLM proxy URL | `http://litellm:4000` |
| `LITELLM_MASTER_KEY` | LiteLLM master key | - |
| `LITELLM_API_KEY` | LiteLLM API key | - |
| `NINE_ROUTER_ENABLED` | Start 9router side service | `true` |
| `NINE_ROUTER_PORT` | 9router local port | `20128` |
| `OPENCODE_DEFAULT_MODEL` | Default OpenCode model | `drdash/anthropic/claude-3.5-sonnet` |
| `PLAYWRIGHT_BROWSERS_PATH` | Browser cache path | `/home/ai-gateway/.cache/ms-playwright` |

## MCP Servers

The container includes MCP servers pre-configured. Add this to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "task-master": {
      "command": "node",
      "args": ["/home/ai-gateway/.npm-global/lib/node_modules/task-master-ai/dist/mcp-server.js"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-playwright"]
    }
  }
}
```

## Volumes (Bind Mounts)

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `/home/ubuntu/agents/claude` | `/home/ai-gateway/.claude` | Claude Code auth |
| `/home/ubuntu/agents/9router` | `/home/ai-gateway/.9router` | 9router auth/settings |
| `/home/ubuntu/agents/openchamber` | `/home/ai-gateway/.config/openchamber` | OpenChamber config |
| `/home/ubuntu/agents/opencode-config` | `/home/ai-gateway/.config/opencode` | OpenCode config |
| `/home/ubuntu/agents/opencode` | `/home/ai-gateway/.local/share/opencode` | OpenCode data |
| `/home/ubuntu/agents/workspace` | `/workspace` | Shared workspace |

## Architecture

```
Browser → OpenChamber (:7802) / ClaudeCodeUI (:3011)
              │
              ├── OpenCode CLI
              ├── Claude Code CLI
              ├── Task Master MCP (on demand)
              ├── Playwright MCP (on demand)
              └── 9router (:20128, local)
```

## Resource Usage

| Component | RAM |
|-----------|-----|
| OpenChamber | ~200MB |
| OpenCode | ~200MB |
| Claude Code | ~200MB |
| ClaudeCodeUI | ~200MB |
| Task Master MCP | ~100MB (on demand) |
| Playwright Chromium | ~300-500MB per session |
| **Total** | **~1.2-1.5GB** |
