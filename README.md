# AI Gateway

A self-hosted AI development environment combining **OpenCode** + **9Router** + **Playwright** in a single Docker container.

## Features

- **OpenCode** - AI coding assistant (OpenCode CLI)
- **9Router** - Local AI endpoint proxy
- **Playwright** - Headless browser automation
- **OpenChamber** - Web UI for OpenCode
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

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCHAMBER_DOMAIN` | OpenChamber domain for Traefik | `opencode.mooh.me` |
| `OPENCHAMBER_PORT` | OpenChamber UI port | `7802` |
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
| `/home/ubuntu/agents/9router` | `/home/ai-gateway/.9router` | 9router auth/settings |
| `/home/ubuntu/agents/openchamber` | `/home/ai-gateway/.config/openchamber` | OpenChamber config |
| `/home/ubuntu/agents/opencode-config` | `/home/ai-gateway/.config/opencode` | OpenCode config |
| `/home/ubuntu/agents/opencode` | `/home/ai-gateway/.local/share/opencode` | OpenCode data |
| `/home/ubuntu/agents/workspace` | `/workspace` | Shared workspace |

## Architecture

```
Browser → OpenChamber (:7802)
              │
              ├── OpenCode CLI
              ├── Playwright MCP (on demand)
              └── 9router (:20128, local)
```

## Resource Usage

| Component | RAM |
|-----------|-----|
| OpenChamber | ~200MB |
| OpenCode | ~200MB |
| Playwright Chromium | ~300-500MB per session |
| **Total** | **~700MB + browser** |

## VPS Deployment

### Prerequisites

- Docker + Docker Compose on ARM64 VPS
- Traefik reverse proxy (for domain routing)
- Node.js (for running OpenChamber locally)

### Deploy with Docker Compose

```bash
# Clone the repository
git clone https://github.com/dheerajsharma2399/ai-gateway.git
cd ai-gateway

# Copy environment template
cp env.example .env

# Edit .env and set your passwords
nano .env

# Build and start
docker compose build ai-gateway
docker compose up -d ai-gateway

# View logs
docker compose logs -f ai-gateway
```

### Access

- **OpenChamber UI**: http://localhost:7802
