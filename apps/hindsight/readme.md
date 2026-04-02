# Hindsight

Temporal semantic memory system for Claude Code.

- **Control Plane (dashboard):** port 9999 — exposed via traefik at `hindsight.jaw.dev`
- **MCP Server:** port 8888 — Claude Code connects here

## Claude Code Setup

```bash
# remove global config if exists
claude mcp remove hindsight

# add project-scoped (stored in .claude/settings.json)
claude mcp add --scope project hindsight --transport sse http://192.168.4.161:8888/mcp/sse
```

Verify with `/mcp` in Claude Code — hindsight should show as connected.
