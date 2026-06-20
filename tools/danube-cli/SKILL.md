---
name: danube-cli
description: "Data plane operations with danube-cli. Use for producing messages, consuming messages, and managing schemas from the command line."
---

# Skill: danube-cli — Data Plane Operations

## Objective

Complete reference for `danube-cli` — the command-line tool for producing, consuming, and testing messages with Danube. This is the fastest way to interact with Danube without writing code.

## Quick Start

**Terminal 1** — produce 5 messages:

```bash
danube-cli produce \
  -s http://localhost:6650 \
  -t /default/demo \
  -m "Hello from Danube CLI!" \
  --count 5
```

```text
✅ Producer 'test_producer' created successfully
📤 Message 1/5 sent successfully (ID: ...)
📤 Message 2/5 sent successfully (ID: ...)
📤 Message 3/5 sent successfully (ID: ...)
📤 Message 4/5 sent successfully (ID: ...)
📤 Message 5/5 sent successfully (ID: ...)
📊 Summary:
   ✅ Success: 5
```

**Terminal 2** — consume those messages:

```bash
danube-cli consume \
  -s http://localhost:6650 \
  -t /default/demo \
  -m my-first-subscription
```

```text
🔍 Checking for schema associated with topic...
ℹ️  Topic has no schema - consuming raw bytes
Received message: Hello from Danube CLI!
Size: 24 bytes, Total received: 24 bytes
```

## Producing Messages

### Text and JSON

```bash
# Text message
danube-cli produce -s http://localhost:6650 -t /default/events -m "Hello!"

# JSON message
danube-cli produce -s http://localhost:6650 -t /default/events \
  -m '{"user_id":"123","action":"login","timestamp":"2024-01-15T10:30:00Z"}'
```

### Multiple Messages

```bash
# 10 messages with 500ms interval
danube-cli produce -s http://localhost:6650 \
  -m "Message" --count 10 --interval 500

# Rapid fire (100ms minimum interval)
danube-cli produce -s http://localhost:6650 \
  -m "Fast" --count 1000 --interval 100
```

### Message Attributes

```bash
danube-cli produce -s http://localhost:6650 \
  -m "Alert!" \
  --attributes "priority:high,region:us-west,env:production"
```

### Reliable Delivery

```bash
danube-cli produce -s http://localhost:6650 \
  -m "Critical message" --reliable
```

### Partitioned Topics

```bash
danube-cli produce -s http://localhost:6650 \
  -t /default/events --partitions 4 \
  -m "Partitioned message"
```

### Schema-Validated Producing

```bash
# Use latest schema version
danube-cli produce -s http://localhost:6650 \
  -t /default/orders --schema-subject orders \
  -m '{"order_id":"ord_123","amount":99.99}'

# Pin to specific version
danube-cli produce -s http://localhost:6650 \
  -t /default/orders --schema-subject orders --schema-version 2 \
  -m '{"order_id":"ord_456","amount":149.99}'

# Auto-register schema from file
danube-cli produce -s http://localhost:6650 \
  -t /default/events --schema-file event-schema.json --schema-type json_schema \
  -m '{"event":"signup","user_id":"u_789"}'
```

## Consuming Messages

### Basic Consumer

```bash
danube-cli consume \
  -s http://localhost:6650 \
  -t /default/orders \
  -m order-processors
```

The consumer automatically detects and validates against the topic's schema if one is configured.

### Subscription Types

```bash
# Shared (default): load balanced across consumers
danube-cli consume -s http://localhost:6650 \
  -t /default/events -m shared-sub --sub-type shared

# Exclusive: single consumer, ordered processing
danube-cli consume -s http://localhost:6650 \
  -t /default/orders -m exclusive-sub --sub-type exclusive

# Failover: active/standby with automatic failover
danube-cli consume -s http://localhost:6650 \
  -t /default/critical -m ha-sub --sub-type fail-over
```

### Worker Pool Pattern (Shared Subscription)

```bash
for i in {1..4}; do
  danube-cli consume \
    -s http://localhost:6650 \
    -t /default/tasks \
    -n "worker-$i" \
    -m task-workers \
    --sub-type shared &
done
```

### Fan-Out Pattern (Multiple Subscriptions)

Multiple subscriptions on the same topic for different processing pipelines:

```bash
danube-cli consume -t /default/orders -m order-processing &
danube-cli consume -t /default/orders -m order-analytics &
danube-cli consume -t /default/orders -m order-notifications &
```

### Consumer Output Formats

```text
# Raw text message
Received message: Hello, World!
Size: 13 bytes, Total received: 13 bytes

# JSON message with schema validation
🔍 Checking for schema associated with topic...
✅ Topic has schema: orders (json_schema, version 2)
📥 Consuming with schema validation...
✅ Message validated against schema 'orders' (version 2)
Received message: {"order_id":"ord_123","amount":99.99}
Size: 42 bytes, Total received: 42 bytes
```

## Schema Management

### Supported Schema Types

| Type | Description |
|------|-------------|
| `json_schema` | JSON Schema (Draft 7) |
| `avro` | Apache Avro |
| `protobuf` | Protocol Buffers |
| `string` | Plain text, no validation |
| `bytes` | Raw bytes, no validation |

### Register a Schema

```bash
# JSON Schema (most common)
danube-cli schema register user-events \
  --schema-type json_schema \
  --file user-schema.json

# Avro schema
danube-cli schema register payment-events \
  --schema-type avro \
  --file payment.avsc

# Inline schema
danube-cli schema register simple \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"id":{"type":"string"}}}'
```

### Get Schema Details

```bash
danube-cli schema get user-events
danube-cli schema get user-events --output json
```

### List Versions

```bash
danube-cli schema versions user-events
```

### Check Compatibility

```bash
danube-cli schema check user-events \
  --schema-type json_schema \
  --file user-schema-v2.json
```

### Schema Evolution Workflow

```bash
# 1. Check current schema
danube-cli schema get orders

# 2. Check compatibility of new version
danube-cli schema check orders \
  --schema-type json_schema \
  --file orders-v2.json

# 3. Register if compatible
danube-cli schema register orders \
  --schema-type json_schema \
  --file orders-v2.json

# 4. Verify
danube-cli schema versions orders
```

## Command Reference

### Producer Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--service-addr` | `-s` | Broker URL | `http://127.0.0.1:6650` |
| `--topic` | `-t` | Topic name | `/default/test_topic` |
| `--message` | `-m` | Message content | Required |
| `--file` | `-f` | Binary file path | — |
| `--producer-name` | `-n` | Producer name | `test_producer` |
| `--schema-subject` | — | Schema subject (latest version) | — |
| `--schema-version` | — | Pin to specific version | — |
| `--schema-min-version` | — | Use minimum version or newer | — |
| `--schema-file` | — | Schema file (auto-register) | — |
| `--schema-type` | — | Schema type | — |
| `--count` | `-c` | Number of messages | `1` |
| `--interval` | `-i` | Interval between messages (ms) | `500` |
| `--partitions` | `-p` | Number of partitions | — |
| `--attributes` | `-a` | Key-value attributes (`key:val,key2:val2`) | — |
| `--reliable` | — | Enable reliable delivery | `false` |

### Consumer Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--service-addr` | `-s` | Broker URL | `http://127.0.0.1:6650` |
| `--topic` | `-t` | Topic name | `/default/test_topic` |
| `--subscription` | `-m` | Subscription name | Required |
| `--consumer-name` | `-n` | Consumer name | `consumer_pubsub` |
| `--sub-type` | — | `shared`, `exclusive`, or `fail-over` | `shared` |

### Schema Commands

| Command | Description |
|---------|-------------|
| `schema register <subject>` | Register or version a schema |
| `schema get <subject>` | Get latest schema details |
| `schema versions <subject>` | List all versions |
| `schema check <subject>` | Check compatibility of new schema |

### danube-cli vs danube-admin Operations

| Operation | `danube-cli` | `danube-admin` |
|-----------|:---:|:---:|
| Register schemas | ✓ | ✓ |
| Get/list schemas | ✓ | ✓ |
| Check compatibility | ✓ | ✓ |
| Set compatibility mode | — | ✓ |
| Delete schema versions | — | ✓ |
| Configure topic schema | — | ✓ |
| Produce/consume messages | ✓ | — |
| Manage brokers/topics/namespaces | — | ✓ |

## Troubleshooting

- **Schema not found**: `danube-cli schema get my-subject` — if not found, register it first
- **Validation failures**: Check message matches schema's required fields: `danube-cli schema get my-subject --output json | jq .`
- **Every command supports `--help`**: `danube-cli produce --help`, `danube-cli consume --help`, `danube-cli schema --help`
