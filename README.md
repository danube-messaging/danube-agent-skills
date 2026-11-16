# Danube Agent Skills

Lightweight skills for AI agents that run and build on [Danube](https://github.com/danube-messaging/danube). You only need the `danube` binary and these three skills, no Danube source checkout required.

## Why only three skills?

Danube ships a built-in MCP server (`danube mcp`) with 71 admin, schema, RBAC, diagnostic, log, and metric tools. Agents learn those tools directly from MCP.

These three skills cover everything outside MCP:

- **[danube-bootstrap](skills/danube-bootstrap/SKILL.md):** start standalone nodes, Raft clusters, edge MQTT gateways, TLS/auto-TLS, and wire `danube mcp`.
- **[danube-messaging](skills/danube-messaging/SKILL.md):** produce and consume messages from the CLI (`danube produce`, `danube consume`).
- **[danube-sdk](skills/danube-sdk/SKILL.md):** build producers, consumers, and agent workers in Rust, Go, Java, or Python (with parity notes and Rust agent primitives).

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
4. Ask your agent to start a node, create a `task_queue` topic, stream test messages, diagnose a stalled consumer, or write a worker in Rust, Go, Java, or Python.

## License

Apache 2.0. See [LICENSE](LICENSE).
