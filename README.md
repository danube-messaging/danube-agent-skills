# Danube Agent Skills

Lightweight skills for AI agents that run and use [Danube](https://github.com/danube-messaging/danube). You only need the `danube` binary and these two skills, no Rust source checkout required.

## Why only two skills?

Danube ships a built-in MCP server (`danube mcp`) with 71 admin, schema, RBAC, diagnostic, log, and metric tools. Agents learn those tools directly from MCP.

These two skills cover the pieces outside MCP:

- **[danube-bootstrap](skills/danube-bootstrap/SKILL.md):** start standalone nodes, Raft clusters, edge MQTT gateways, TLS/auto-TLS, and wire `danube mcp`.
- **[danube-messaging](skills/danube-messaging/SKILL.md):** produce and consume messages (reliable and realtime) via `danube produce` / `danube consume` and `danube-client` agent primitives.

Read [AGENTS.md](AGENTS.md) for the routing rule between Skills and `danube mcp`.

## Quick Setup

1. Install the `danube` binary from [Danube Releases](https://github.com/danube-messaging/danube/releases) (or use `ghcr.io/danube-messaging/danube`).
2. Clone this repo or install the skills into your agent (Claude Code, Antigravity, Cursor, Codex):
   ```bash
   git clone https://github.com/danube-messaging/danube-agent-skills.git
   ```
   Or install with the Skills CLI:
   ```bash
   npx skills add danube-messaging/danube-agent-skills
   ```
3. Add `danube mcp` to your agent's MCP config:
   ```json
   {
     "mcpServers": {
       "danube": {
         "command": "danube",
         "args": ["mcp", "--endpoint", "http://127.0.0.1:6650"]
       }
     }
   }
   ```
4. Ask your agent to start a node, create a `task_queue` topic, stream test messages, or diagnose a stalled consumer.

## License

Apache 2.0. See [LICENSE](LICENSE).
