# Hindsight

Temporal semantic memory system for Claude Code. Automatically recalls relevant context from past sessions and retains new knowledge.

- **Docs:** https://hindsight.vectorize.io/sdks/integrations/claude-code
- **Best practices:** https://hindsight.vectorize.io/best-practices
- **GitHub:** https://github.com/vectorize-io/hindsight

## Architecture

Single container runs 3 services:

| Service | Port | Purpose |
|---------|------|---------|
| API | 8888 | Memory engine — retain/recall/reflect + internal worker |
| Control Plane | 9999 | Web dashboard — browse banks, entities, memories |
| Worker | (internal) | Background task processor — runs inside API by default |

- Gemini handles fact extraction server-side (configured via `HINDSIGHT_API_LLM_PROVIDER=gemini`)
- Embedded PostgreSQL with pgvector at `~/data/hindsight/pg`
- Local embeddings + reranking included in the full image (~9GB)
- Prometheus metrics at `/metrics` on port 8888
- MCP server built-in at `/mcp/{bank_id}/` on port 8888 (not used — plugin approach is better)

## Claude Code Plugin Setup

```bash
# add marketplace + install plugin
claude plugin marketplace add vectorize-io/hindsight
claude plugin install hindsight-memory
```

Create `~/.hindsight/claude-code.json`:

```json
{
  "hindsightApiUrl": "http://192.168.4.161:8888",
  "hindsightApiToken": "<HINDSIGHT_API_MCP_AUTH_TOKEN from .env.sops>",
  "dynamicBankId": true,
  "dynamicBankGranularity": ["agent", "project"],
  "bankMission": "...",
  "retainMission": "...",
  "debug": true
}
```

Restart Claude Code. Verify with `/plugin` — should show `hindsight-memory` enabled.

## How It Works

- **Auto-recall:** every prompt queries Hindsight for relevant memories from past sessions
- **Auto-retain:** every 10 turns (or on `/exit`) stores conversation context as facts
- **Dynamic banks:** each project gets its own isolated memory bank
- First session has no memories — bank auto-creates on first retain

## Key Config Options

| Setting | Default | Description |
|---------|---------|-------------|
| `bankMission` | generic | Guides what kind of facts to extract — be specific |
| `retainMission` | generic | What to extract vs ignore — list concrete fact types |
| `recallBudget` | `mid` | `low` = fast, `mid` = balanced, `high` = thorough |
| `retainEveryNTurns` | `10` | How often to retain during a session |
| `debug` | `false` | Show `[Hindsight]` prefixed logs |

## Best Practices (from docs)

- **Missions matter** — vague missions produce poor results. Be specific about what to extract and what to ignore
- **Don't pre-summarize** — retain raw content, let the LLM extract facts
- **Use tags** for filtering, not metadata
- **Recall budget** — default `mid` is fine, only use `high` for deep exploration
- **Reflect vs recall** — use reflect when you need synthesized answers, recall when you need raw facts

## Server Env (.env.sops)

```
HINDSIGHT_API_LLM_API_KEY=<gemini-key>
HINDSIGHT_API_LLM_PROVIDER=gemini
HINDSIGHT_API_MCP_AUTH_TOKEN=<auth-token>
BORG_PASSPHRASE=<backup-passphrase>
```

## Useful Endpoints

- Health: `http://192.168.4.161:8888/health`
- Metrics: `http://192.168.4.161:8888/metrics`
- Dashboard: `https://hindsight.jaw.dev` (behind google-auth)
