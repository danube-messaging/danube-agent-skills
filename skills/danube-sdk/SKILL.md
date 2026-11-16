---
name: danube-sdk
description: Build Danube producers, consumers, schema-typed clients, and AI agent workers using official Danube SDKs (Rust, Go, Java, Python). Includes SDK feature parity notes (Rust-only agent primitives) and per-language references.
---

# Danube SDK

Use this skill when writing application or worker code with a Danube client library (`Rust`, `Go`, `Java`, or `Python`). Keep using `danube mcp` for cluster, topic, schema, RBAC, and diagnostic operations, and `danube-messaging` for quick CLI tests.

## Feature parity across languages

**Supported in all 4 SDKs (Rust, Go, Java, Python):**
- Connection over plain gRPC (`http://`), TLS (`https://` + CA), mTLS, static JWT (`DANUBE_TOKEN`), and token supplier / rotation.
- Producers: `create()`, `send()`, `send_with_key()`, attributes, partitioned topics, reliable dispatch, and Schema Registry integration.
- Consumers: `subscribe()`, `receive()`, `ack()`, `nack()`, `Exclusive` / `Shared` / `Failover` / `Key-Shared` subscriptions, and Key-Shared glob filters.
- Schema Registry client: register, retrieve, list versions, check compatibility.

**Rust-only in v0.17 (`danube-client`):**
- `consumer.extend_lease(&msg, extension_ms)`: push back ack timeout for long tool calls.
- `consumer.report_progress(&msg, checkpoint_bytes, extension_ms)`: save up to 64 KiB in broker dispatcher memory; redelivery on worker crash carries `x-danube-checkpoint-b64`.
- `consumer.cancel_task_tree(topic, root_msg_id, reason)`: evict queued and in-flight subtasks sharing `x-danube-root-msg-id`.
- `client.request_reply(req_topic, reply_topic, payload, attrs, timeout)`: correlated RPC over a `Non-Reliable` reply topic.
- Typed `StreamMessage` helpers (`danube-core`): `correlation_id()`, `reply_to()`, `parent_msg_id()`, `root_msg_id()`, `deadline_ms()`, `compute_cost_units()`, `checkpoint_b64()`. *(Go, Java, and Python can still pass raw `x-danube-*` keys in message `attributes`, without the broker RPC wrappers above.)*

## Universal SDK rules

1. **Subscribe before producing on a new reliable topic:** brand-new subscriptions start at the **end** of the stream.
2. **Pre-create topics via MCP `create_topic` with `intent`:** `event_stream`, `task_queue`, and `audit_log` create reliable topics with retries/DLQ. On an existing topic, the topic's strategy wins; a reliable producer attached to a `Non-Reliable` (`realtime`) topic is rejected.
3. **Partitioned topics:** omit `with_partitions` if the topic already exists; `create()` and `subscribe()` discover and attach to all partitions automatically using the base topic name.
4. **Always `ack()` or `nack()` on reliable topics:** unacked messages redeliver after `ack_timeout_ms`.
5. **Never hardcode tokens:** read JWTs from env vars (`DANUBE_TOKEN`) or files (`bootstrap_admin.token`), or pass a token supplier.

## Pick the reference for your target language

Read ONLY the reference file for the language you are writing:

- **Rust (`danube-client`):** [references/rust.md](references/rust.md)
- **Go (`github.com/danube-messaging/danube-go`):** [references/go.md](references/go.md)
- **Java (`com.danube-messaging:danube-client`):** [references/java.md](references/java.md)
- **Python (`danube-client` on PyPI):** [references/python.md](references/python.md)
