# Hindsight

Temporal semantic memory system for Claude Code.

- **Control Plane (dashboard):** port 9999 — exposed via traefik at `hindsight.jaw.dev`
- **API Server:** port 8888 — Claude Code plugin connects here

## Claude Code Setup

```bash
# add marketplace + install plugin
claude plugin marketplace add vectorize-io/hindsight
claude plugin install hindsight-memory
```

Then create `~/.hindsight/claude-code.json`:

```json
{
  "hindsightApiUrl": "http://192.168.4.161:8888",
  "hindsightApiToken": "<HINDSIGHT_API_MCP_AUTH_TOKEN from .env.sops>"
}
```

Restart Claude Code. Plugin auto-recalls/retains memory via hooks.
