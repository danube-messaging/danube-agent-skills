---
name: core-messaging
description: "Test Danube's core messaging features: subscriptions, schemas, reliable delivery, and partitioned topics. Use when the user wants to test produce/consume with specific features."
---

# Scenario: Core Messaging

## Objective

Test Danube's core messaging features by producing and consuming messages with the user's choice of subscription type, reliability, partitioning, and schema validation. This is a guided scenario — the AI asks what the user wants, then generates and runs the appropriate test.

## When to Use

- User wants to "send messages", "test subscriptions", "try schemas", "test reliable delivery"
- User wants to verify that produce/consume works end-to-end
- User wants to explore subscription types (Exclusive, Shared, Key-Shared)
- User wants to test partitioned topics or schema validation

## Compatible Infrastructure

This scenario requires a running Danube broker. It works with any setup method and any mode:

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | ✅ | ✅ | `danube-cli` and `danube-admin` must be in PATH or `bin/` |
| Local Source | ✅ | ✅ | Same as binary |
| Docker Compose | ✅ | ✅ | Use exposed ports (default: 6650, 50051) |
| Kubernetes | — | ✅ | Use port-forwarded or NodePort addresses |

**Key-Shared subscription** works best with a cluster (2+ brokers) where consistent hashing distributes keys across consumers. With a standalone broker, all keys may route to the same consumer — this is valid but doesn't demonstrate distribution.

## AI Decision Flow

Ask the user these questions. Use defaults if the user says "just test it" or "whatever works".

### 1. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "cli", "command line", "quick test" | **danube-cli** (no code needed) |
| "rust", "cargo" | **Rust** — read `clients/rust/SKILL.md` |
| "python", "pip" | **Python** — read `clients/python/SKILL.md` |
| "go", "golang" | **Go** — read `clients/go/SKILL.md` |
| "java", "maven", "gradle" | **Java** — read `clients/java/SKILL.md` |
| *(unclear)* | Default: **danube-cli** |

If a client language is chosen, auto-install the library (e.g., `pip install danube-client`).

### 2. Subscription Type?

| User says | Type | Behavior |
|-----------|------|----------|
| "exclusive", "ordered", "single consumer" | **Exclusive** | 1 consumer, guaranteed ordering |
| "shared", "load balance", "parallel" | **Shared** | N consumers, round-robin distribution |
| "key-shared", "per-key", "routing" | **Key-Shared** | N consumers, per-key ordering |
| "failover", "HA", "standby" | **Failover** | 1 active + standby |
| *(unclear)* | Default: **Exclusive** |

### 3. Reliable Delivery?

| User says | Choice | What Changes |
|-----------|--------|-------------|
| "reliable", "at-least-once", "critical", "ack" | **Yes** | Producer uses `--reliable` / `.with_reliable_dispatch()`. Topic must be created with `--dispatch-strategy reliable` |
| "fire and forget", "non-reliable", "fast" | **No** | Default behavior, no special flags |
| *(unclear)* | Default: **No** |

**If reliable = yes**, the AI must first create the topic with reliable dispatch:
```bash
danube-admin topics create /default/test-topic --dispatch-strategy reliable
```

### 4. Partitioned Topic?

| User says | Choice | What Changes |
|-----------|--------|-------------|
| "partitioned", "partitions", "scale" | **Yes** | Producer uses `--partitions N` / `.with_partitions(N)`. Ask for partition count (default: 3) |
| "single", "no partitions" | **No** | Default behavior |
| *(unclear)* | Default: **No** |

### 5. Schema Validation?

| User says | Choice | What Changes |
|-----------|--------|-------------|
| "schema", "json schema", "avro", "typed", "validated" | **Yes** | Register a schema, link producer to it, send typed JSON |
| "raw", "bytes", "no schema", "untyped" | **No** | Send plain text messages |
| *(unclear)* | Default: **No** |

## Execution Steps

### Step 1: Create the Topic

**Always create the topic before starting consumers.** Client library consumers will fail with `"no partitions found"` if the topic doesn't exist. Use `danube-admin`:

```bash
# Default (non-reliable)
danube-admin topics create /default/test-topic

# With reliable delivery
danube-admin topics create /default/test-topic --dispatch-strategy reliable

# Reliable + partitioned
danube-admin topics create /default/test-topic --dispatch-strategy reliable --partitions 3

# With schema (register first, then create topic)
danube-cli schema register test-schema \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"id":{"type":"string"},"value":{"type":"integer"}},"required":["id","value"]}'

danube-admin topics create /default/test-topic --schema-subject test-schema --dispatch-strategy reliable
```

### Step 2: Produce Messages

#### Using danube-cli

```bash
# Basic
danube-cli produce -s http://localhost:6650 -t /default/test-topic \
  -m "Hello Danube!" --count 10

# With reliable delivery
danube-cli produce -s http://localhost:6650 -t /default/test-topic \
  -m "Hello Danube!" --count 10 --reliable

# With partitions
danube-cli produce -s http://localhost:6650 -t /default/test-topic \
  -m "Hello Danube!" --count 10 --partitions 3

# With schema
danube-cli produce -s http://localhost:6650 -t /default/test-topic \
  --schema-subject test-schema \
  -m '{"id":"msg-1","value":42}'
```

#### Using Client Libraries

Generate a producer script using the chosen language's SKILL.md. The script should:
1. Create a client connected to `http://127.0.0.1:6650`
2. Create a producer with the topic, and optionally: partitions, reliable dispatch, schema subject
3. Send 10 messages in a loop
4. Print each message ID

### Step 3: Consume Messages

#### Using danube-cli

```bash
# Exclusive (default)
danube-cli consume -s http://localhost:6650 -t /default/test-topic \
  -m test-sub --sub-type exclusive

# Shared (run multiple instances)
danube-cli consume -s http://localhost:6650 -t /default/test-topic \
  -m test-sub --sub-type shared

# Key-Shared (requires producer to use send_with_key or attributes)
danube-cli consume -s http://localhost:6650 -t /default/test-topic \
  -m test-sub --sub-type shared  # Key-Shared not available in CLI, use client library
```

#### Using Client Libraries

Generate a consumer script using the chosen language's SKILL.md. The script should:
1. Create a client connected to `http://127.0.0.1:6650`
2. Create a consumer with the topic, subscription name, and chosen subscription type
3. Subscribe and receive messages in a loop
4. Print each message payload (and routing key if Key-Shared)
5. Acknowledge each message

### Step 4: Verify

| Check | How |
|-------|-----|
| Messages received | Consumer printed all sent messages |
| Subscription type behavior | Shared: messages distributed across consumers. Exclusive: only one consumer receives. Key-Shared: same key always goes to same consumer |
| Reliable delivery | Producer got acknowledgments (message IDs returned). Consumer acks work without errors |
| Schema validation | Messages accepted (if valid). Invalid messages rejected |
| Partitioned topics | Messages distributed across partitions (visible in admin: `danube-admin topics describe /default/test-topic`) |

```bash
# Verify topic state
danube-admin topics describe /default/test-topic

# List subscriptions
danube-admin topics subscriptions /default/test-topic
```

## Feature Combinations Reference

| Feature | danube-cli Flag | Rust Client | Python Client | Go Client | Java Client |
|---------|----------------|-------------|---------------|-----------|-------------|
| Reliable | `--reliable` | `.with_reliable_dispatch()` | `.with_dispatch_strategy(DispatchStrategy.RELIABLE)` | `.WithDispatchStrategy(danube.NewReliableDispatchStrategy())` | `.withDispatchStrategy(DispatchStrategy.RELIABLE)` |
| Partitions | `--partitions N` | `.with_partitions(N)` | `.with_partitions(N)` | `.WithPartitions(N)` | `.withPartitions(N)` |
| Schema | `--schema-subject S` | `.with_schema_subject("S")` | `.with_schema_subject("S")` | `.WithSchemaSubject("S")` | `.withSchemaLatest("S")` |
| Sub: Exclusive | `--sub-type exclusive` | `SubType::Exclusive` | `SubType.EXCLUSIVE` | `danube.Exclusive` | `SubType.EXCLUSIVE` |
| Sub: Shared | `--sub-type shared` | `SubType::Shared` | `SubType.SHARED` | `danube.Shared` | `SubType.SHARED` |
| Sub: Key-Shared | *(use client library)* | `SubType::KeyShared` | `SubType.KEY_SHARED` | `danube.KeyShared` | `SubType.KEY_SHARED` |
| Sub: Failover | `--sub-type fail-over` | `SubType::FailOver` | `SubType.FAIL_OVER` | `danube.FailOver` | `SubType.FAIL_OVER` |
| Send with key | *(use client library)* | `.send_with_key(...)` | `.send_with_key(...)` | `.SendWithKey(...)` | `.sendWithKey(...)` |

## Cleanup

This scenario only cleans up topics it created. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
danube-admin topics delete /default/test-topic
```
