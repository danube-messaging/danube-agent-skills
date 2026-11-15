# AGENTS.md

Instructions for AI agents operating a Danube deployment without needing the Danube source repository.

## How Skills and MCP Work Together

Danube splits agent capabilities into two parts:

1. **Skills (this repo):** cover what MCP cannot do on its own: starting nodes, bootstrapping clusters/TLS, and sending or receiving messages through the CLI or SDK.
2. **MCP (`danube mcp`):** exposes 71 admin, schema, RBAC, diagnostic, log, and metric tools plus 4 guided prompts and `danube://metrics`. Once a node is running, MCP tool schemas teach you how to operate the cluster directly.

## Routing Rule: Use the Right Surface

- **Starting, stopping, or joining nodes (`danube up ...`):** use `skills/danube-bootstrap/SKILL.md`.
- **Producing or consuming messages (`danube produce`, `danube consume`, or `danube-client`):** use `skills/danube-messaging/SKILL.md`.
- **Operating and inspecting a running cluster:** prefer **`danube mcp` tools** over shell admin commands whenever MCP is connected:
  - Cluster & nodes: `cluster_status`, `list_brokers`, `get_leader`, `get_cluster_balance`, `trigger_rebalance`, `unload_broker`, `activate_broker`, `add_cluster_node`, `promote_cluster_node`, `remove_cluster_node`, `apply_desired_state`.
  - Namespaces & topics: `list_namespaces`, `create_namespace`, `list_topics`, `describe_topic`, `create_topic` (with `intent`), `list_subscriptions`, `branch_topic`, `seek_subscription`, `replay_dlq`.
  - Schemas & RBAC: `register_schema`, `check_schema_compatibility`, `create_role`, `create_binding`, `create_token`, `validate_token`.
  - Diagnostics, logs & metrics: `health_check`, `analyze_consumer_lag`, `explain_consumer_stall`, `get_recommendations`, `get_broker_logs`, `get_cluster_metrics`, `get_topic_metrics`.

If MCP is not connected yet, use `skills/danube-bootstrap/SKILL.md` to start a node and connect `danube mcp` first.

## Safety Rules

- Preview node starts with `danube up <mode> --dry-run` when unsure of ports or data directories.
- Never reuse a `--data-dir` across different modes (`standalone`, `cluster`, `edge`); Danube writes `danube-node.json` and rejects mismatched modes.
- On MCP destructive operations (`delete_topic`, `delete_namespace`, `unload_broker`, `remove_cluster_node`, `seek_subscription`, `replay_dlq`, etc.), preview with `dry_run: true` where supported and confirm intent before passing `confirm_destructive: true`.
- `peek_messages` and `infer_topic_schema` require the `ReadPayload` permission on secured clusters.
- `danube consume` defaults to `--limit 0` (runs forever). Always pass `--limit <N>` or run it in the background with a bounded check.
