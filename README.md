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
docker build -t ai-gateway:local .
```

### 2. Run

```bash
docker run -d \
  --name ai-gateway \
  -p 3000:3000 \
  -p 3001:3001 \
  -v ai-gateway-config:/home/ai-gateway/.config \
  -v ai-gateway-opencode:/home/ai-gateway/.local/share/opencode \
  -v ai-gateway-state:/home/ai-gateway/.local/state \
  -v ai-gateway-claude:/home/ai-gateway/.claude \
  -v ai-gateway-taskmaster:/home/ai-gateway/.taskmaster \
  -v ai-gateway-playwright:/home/ai-gateway/.cache/ms-playwright \
  -v ai-gateway-workspaces:/home/ai-gateway/workspaces \
  -e UI_PASSWORD=your_secure_password \
  ai-gateway:local
```

### 3. Access

- **OpenChamber UI:** http://localhost:3000
- **ClaudeCodeUI:** http://localhost:3001

### 4. First-time Claude Code Auth

```bash
docker exec -it ai-gateway claude
```

Follow the Anthropic browser auth flow. The auth persists in the volume.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCHAMBER_PORT` | OpenChamber UI port | `3000` |
| `CLAUDEUI_PORT` | ClaudeCodeUI port | `3001` |
| `UI_PASSWORD` | OpenChamber UI password | - |
| `CF_TUNNEL` | Enable Cloudflare Tunnel (`true`/`qr`/`password`) | - |
| `ANTHROPIC_API_KEY` | Anthropic API key for Claude Code | - |
| `CLAUDE_MODEL` | Claude model to use | `sonnet` |
| `PLAYWRIGHT_BROWSERS_PATH` | Browser cache path | `/home/ai-gateway/.cache/ms-playwright` |

## MCP Servers

The container includes MCP servers pre-configured. Add this to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "task-master": {
      "command": "node",
      "args": ["/home/ai-gateway/.npm-global/lib/node_modules/claude-task-master/dist/index.js"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-playwright"]
    }
  }
}
```

## Volumes

| Volume | Path | Purpose |
|--------|------|---------|
| `ai-gateway-config` | `/home/ai-gateway/.config` | OpenChamber & OpenCode config |
| `ai-gateway-opencode` | `/home/ai-gateway/.local/share/opencode` | OpenCode data |
| `ai-gateway-state` | `/home/ai-gateway/.local/state` | OpenCode state |
| `ai-gateway-claude` | `/home/ai-gateway/.claude` | Claude Code auth |
| `ai-gateway-taskmaster` | `/home/ai-gateway/.taskmaster` | Task Master data |
| `ai-gateway-playwright` | `/home/ai-gateway/.cache/ms-playwright` | Chromium browser cache |
| `ai-gateway-workspaces` | `/home/ai-gateway/workspaces` | Project files |

## Architecture

```
Browser → OpenChamber (:3000) / ClaudeCodeUI (:3001)
              │
              ├── OpenCode CLI
              ├── Claude Code CLI
              ├── Task Master MCP (on demand)
              └── Playwright MCP (on demand)
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
