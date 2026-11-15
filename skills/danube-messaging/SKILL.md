---
name: danube-messaging
description: Publish and consume Danube messages via danube produce and danube consume (reliable and non-reliable topics, stream intents, schemas, keys, subscriptions), or danube-client Rust agent primitives. Use for data-plane messaging; use danube mcp tools for topic creation, inspection, branching, seeking, and DLQ replay.
---

# Danube Messaging

`danube mcp` handles admin, schemas, diagnostics, `peek_messages`, `branch_topic`, `seek_subscription`, and `replay_dlq`. Use `danube produce` and `danube consume` (or the `danube-client` SDK) to send and receive real message streams.

## Two critical runtime rules for agents

1. **Always bound `danube consume` with `--limit <N>`:** by default `--limit 0` streams until Ctrl-C, which will block an agent shell command indefinitely. Use `--limit <N>` and `-o jsonl` for structured output.
2. **Start the consumer BEFORE producing on a new reliable topic:** a brand-new subscription on a reliable topic starts at the **end** of the stream. If you produce before subscribing, the consumer receives nothing unless you rewind with MCP `seek_subscription` (to offset `0`) first.

## Create topics with `--intent` first (via MCP)

Prefer MCP `create_topic` with an explicit `intent` before producing:

- `realtime`: in-memory, non-reliable, best effort (tokens, telemetry).
- `event_stream`: reliable WAL (`os_cache_flush`), 3 retries, DLQ `<topic>-dlq`.
- `task_queue`: reliable WAL (`fsync_batch`), 5 retries, DLQ `<topic>-dlq`.
- `audit_log`: reliable WAL (`fsync_batch`), 10 retries, poison policy `block` (no DLQ).

## Reliable vs non-reliable producing (`danube produce`)

- **Existing topic:** `danube produce` follows the topic's dispatch strategy automatically. No `-r` flag is needed on a topic created with `event_stream`, `task_queue`, `audit_log`, or `dispatch_strategy: reliable`.
- **Auto-created topic:** `-r` (`--reliable`) only applies when the topic does not exist yet and broker auto-creation is enabled. Passing `-r` against an existing non-reliable topic is rejected.

### `danube produce` quick reference

```bash
# Single UTF-8 message
danube produce /default/orders -m '{"id":1}'

# Burst of messages
danube produce /default/events -m '{"tick":1}' --count 10 --interval 50

# Auto-create a reliable, 3-partition topic on publish
danube produce /default/orders -m 'hello' -r -p 3

# Routing key (Key-Shared) + attributes
danube produce /default/orders -m '{"id":7}' --key customer-42 --attr source:cli,env:test

# Payload from file
danube produce /default/orders -f ./order.json

# Publish with an existing registered schema
danube produce /default/orders -f ./order.json --schema-subject orders-value
danube produce /default/orders -f ./order.json --schema-subject orders-value --schema-version 2
danube produce /default/orders -f ./order.json --schema-subject orders-value --schema-min-version 2

# Register schema from file on the fly and publish
danube produce /default/orders -m '{"id":1}' --schema-file ./schema.json --schema-type json-schema
```

Flags:
- `-m, --message <TEXT>` or `-f, --file <FILE>` (one is required)
- `-c, --count <N>` (default `1`), `-i, --interval <MS>` (min `10`, default `500`), `-n, --producer-name <NAME>`
- `-k, --key <KEY>`, `-a, --attr <K:V,...>`
- `-p, --partitions <N>`, `-r, --reliable` (auto-creation only)
- `--schema-subject`, `--schema-version`, `--schema-min-version`, `--schema-file`, `--schema-type` (`bytes` | `string` | `number` | `json-schema` | `avro` | `protobuf`)

## Consuming messages (`danube consume`)

```bash
# Receive 5 messages as JSON lines and exit cleanly
danube consume /default/orders -s workers --limit 5 -o jsonl

# Exclusive, failover, shared (default), or key-shared
danube consume /default/events -s analytics --type exclusive --limit 5 -o jsonl
danube consume /default/events -s standby   --type fail-over --limit 5 -o jsonl
danube consume /default/orders -s workers   --type key-shared --key-filter 'customer-4*' --limit 5 -o jsonl
```

Flags:
- `-s, --subscription <NAME>` (default `danube-sub`)
- `-t, --type <TYPE>`: `exclusive`, `shared` (default), `fail-over`, `key-shared`
- `--key-filter <GLOB>` (repeatable; `key-shared` only)
- `-n, --consumer-name <NAME>`
- `-l, --limit <N>` (default `0` = stream forever; **always set `> 0` for one-shot commands**)
- `-o, --output <FMT>`: `text` (default) or `jsonl`

Note: `danube consume` calls `ack` automatically on every message received and decodes/validates registered schemas.

## Standard pattern for agent send + receive verification

```bash
# 1. Start bounded consumer in background before producing
danube consume /default/orders -s verify-sub --limit 3 -o jsonl > /tmp/consumed.jsonl 2>&1 &
CONSUMER_PID=$!
sleep 1

# 2. Produce 3 messages
danube produce /default/orders -m '{"seq":1}' --count 3 --interval 20

# 3. Wait for consumer to finish and inspect JSONL output
wait $CONSUMER_PID
cat /tmp/consumed.jsonl
```

## Connection & auth flags

Both `produce` and `consume` accept `--endpoint`, `--context`, `--token`, `--tls`, `--tls-ca`, `--tls-cert`, `--tls-key`, `--tls-domain` (or `DANUBE_ENDPOINT`, `DANUBE_CONTEXT`, `DANUBE_TOKEN`, `DANUBE_TLS_CA`, etc.). Flag > env var > saved context > default `http://127.0.0.1:6650`.

## When to use `danube-client` (Rust SDK) instead of CLI

`danube consume` always sends `ack`. Use `danube-client` in Rust when testing or running:

- **Explicit NACKs / DLQ routing:** `consumer.nack(&msg, Some(1000), Some("reason".into())).await?`
- **Long task lease extension:** `consumer.extend_lease(&msg, 30_000).await?`
- **Progress checkpoints (up to 64 KiB):** `consumer.report_progress(&msg, checkpoint_bytes, 30_000).await?`
- **Task tree cancellation:** `consumer.cancel_task_tree("/agents/subtasks", root_id, Some("reason".into())).await?`
- **Request/Reply RPC:** `client.request_reply("/agents/rpc", "/agents/rpc-replies", payload, None, Duration::from_secs(10)).await?`
