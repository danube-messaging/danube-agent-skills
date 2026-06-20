---
name: danube-admin
description: "Control plane operations with danube-admin. Use for cluster management, broker operations, topic/namespace management, schema administration, and security."
---

# Skill: danube-admin — Control Plane Operations

## Objective

Complete reference for `danube-admin` — the CLI tool for managing Danube clusters, brokers, topics, namespaces, schemas, and security. This operates on the control plane (admin gRPC port 50051).

## Connection

```bash
# Set endpoint globally
export DANUBE_BROKER_ENDPOINT=http://localhost:50051

# Or per command
danube-admin --broker-endpoint http://broker1:50051 brokers list
```

## Cluster (Raft Consensus)

### Status

```bash
danube-admin cluster status
```

```text
Raft Cluster Status:
  Self Node ID:  9823746501928374
  Raft Address:  127.0.0.1:7650
  Leader:        9823746501928374
  Term:          3
  Last Applied:  142
  Voters:        [9823746501928374, 1048209374659182, 7391028374651029]
  Learners:      [5829103746519283]
```

| Field | Description |
|-------|-------------|
| Self Node ID | The node you connected to |
| Leader | Current leader (`none` if no leader elected) |
| Term | Raft election counter |
| Last Applied | Last log entry applied |
| Voters | Nodes that participate in consensus |
| Learners | Nodes replicating but not voting |

### Add Node (Learner)

```bash
danube-admin cluster add-node --node-addr http://new-broker:50054
```

### Promote Node (Learner → Voter)

```bash
danube-admin cluster promote-node --node-id <NODE_ID>
```

### Remove Node

```bash
danube-admin cluster remove-node --node-id <NODE_ID>
```

### Scale-Up Workflow

```bash
# 1. Check current cluster
danube-admin cluster status

# 2. Add as learner
danube-admin cluster add-node --node-addr http://new-broker:50054

# 3. Verify learner added
danube-admin cluster status

# 4. Promote to voter
danube-admin cluster promote-node --node-id <NODE_ID>

# 5. Activate for traffic
danube-admin brokers activate <BROKER_ID>

# 6. Verify balance
danube-admin brokers balance
```

### Scale-Down Workflow

```bash
# 1. Drain topics
danube-admin brokers unload <BROKER_ID>

# 2. Remove from cluster
danube-admin cluster remove-node --node-id <NODE_ID>

# 3. Verify
danube-admin cluster status
```

## Brokers

### List Brokers

```bash
danube-admin brokers list
```

```text
BROKER ID       STATUS   ADDRESS             ROLE             ADMIN ADDR          METRICS ADDR
----------------------------------------------------------------------------------------------
broker-001      active   127.0.0.1:6650      Cluster_Leader   127.0.0.1:50051     127.0.0.1:9040
broker-002      active   127.0.0.1:6651      Cluster_Follower 127.0.0.1:50052     127.0.0.1:9041
broker-003      active   127.0.0.1:6652      Cluster_Follower 127.0.0.1:50053     127.0.0.1:9042
```

### Get Leader

```bash
danube-admin brokers leader
```

### List Namespaces

```bash
danube-admin brokers namespaces
```

### Cluster Balance

```bash
danube-admin brokers balance
```

```text
Status:                    ✅ Well Balanced
Coefficient of Variation:  15.23%
Broker Details:
Broker ID       Load       Topics     Status
--------------------------------------------------
broker-001      5.00       5          OK
broker-002      4.00       4          OK
```

| CV | Status |
|----|--------|
| < 20% | Well Balanced |
| 20–30% | Balanced |
| 30–40% | Imbalanced — consider rebalancing |
| > 40% | Severely Imbalanced — rebalance recommended |

### Rebalance

```bash
# Preview moves first (always do this)
danube-admin brokers rebalance --dry-run

# Execute
danube-admin brokers rebalance

# Limit scope
danube-admin brokers rebalance --max-moves 10
```

### Unload Broker (Drain Topics)

```bash
danube-admin brokers unload <BROKER_ID>

# Preview
danube-admin brokers unload <BROKER_ID> --dry-run

# With filters
danube-admin brokers unload <BROKER_ID> \
  --max-parallel 5 \
  --namespace-include default \
  --timeout 30
```

### Activate Broker

```bash
danube-admin brokers activate <BROKER_ID> --reason "Maintenance completed"
```

## Namespaces

### List Topics in Namespace

```bash
danube-admin namespaces topics <NAMESPACE>
```

### View Policies

```bash
danube-admin namespaces policies <NAMESPACE>
```

### Create Namespace

```bash
danube-admin namespaces create production
```

### Delete Namespace

```bash
danube-admin namespaces delete old-namespace
```

**Warning**: Deleting a namespace removes all topics within it. This is immediate and irreversible.

## Topics

### List Topics

```bash
danube-admin topics list --namespace default
danube-admin topics list --broker broker-001
```

### Create Topic

```bash
# Simple topic (non-reliable delivery)
danube-admin topics create /default/logs

# With reliable delivery
danube-admin topics create /default/events --dispatch-strategy reliable

# Partitioned with schema
danube-admin topics create /default/orders \
  --partitions 5 \
  --schema-subject order-events \
  --dispatch-strategy reliable
```

| Option | Description | Default |
|--------|-------------|---------|
| `--namespace` | Namespace (if not in topic path) | — |
| `--partitions` | Number of partitions | `1` |
| `--schema-subject` | Schema subject from registry | None |
| `--dispatch-strategy` | `reliable` or `non_reliable` | `non_reliable` |

**Dispatch strategies:**

| Strategy | Delivery | Use Case |
|----------|----------|----------|
| `non_reliable` | At-most-once (fire-and-forget) | Logs, metrics, non-critical events |
| `reliable` | At-least-once (with acknowledgments) | Transactions, orders, critical events |

### Describe Topic

```bash
danube-admin topics describe /default/user-events
```

```text
Topic: /default/user-events
Broker ID: broker-001
Delivery: Reliable

📋 Schema Registry:
  Subject: user-events
  Schema ID: 12345
  Version: 2
  Type: json_schema
  Compatibility: BACKWARD

Subscriptions: ["analytics-consumer", "audit-logger"]
```

### List Subscriptions

```bash
danube-admin topics subscriptions /default/orders
```

### Delete Topic

```bash
danube-admin topics delete /default/old-topic
```

### Unsubscribe

```bash
danube-admin topics unsubscribe /default/events --subscription old-consumer
```

### Unload Topic (Reassign)

```bash
danube-admin topics unload /default/events
```

### Dispatch Configuration (Per-Subscription)

```bash
# Set pipelining depth
danube-admin topics set-dispatch-config /default/orders \
  --subscription order-workers \
  --max-unacked-messages 50

# Read current setting
danube-admin topics get-dispatch-config /default/orders \
  --subscription order-workers
```

## Topic Schema Configuration (Admin-Only)

These commands control schema enforcement at the topic level.

### Configure Topic Schema

```bash
danube-admin topics configure-schema /production/orders \
  --subject order-events \
  --validation-policy enforce \
  --enable-payload-validation
```

| Option | Values | Description |
|--------|--------|-------------|
| `--subject` | String | Schema subject from registry |
| `--validation-policy` | `none`, `warn`, `enforce` | Validation strictness |
| `--enable-payload-validation` | Flag | Enable deep payload validation |

### Set Validation Policy

```bash
# Warn mode (for debugging)
danube-admin topics set-validation-policy /production/orders \
  --policy warn --enable-payload-validation

# Enforce (production)
danube-admin topics set-validation-policy /production/orders \
  --policy enforce --enable-payload-validation

# Disable
danube-admin topics set-validation-policy /production/orders \
  --policy none
```

| Policy | Behavior |
|--------|----------|
| `none` | No validation |
| `warn` | Validate and log errors, accept messages |
| `enforce` | Reject invalid messages |

### Get Schema Configuration

```bash
danube-admin topics get-schema-config /production/orders
```

### Full Topic + Schema Workflow

```bash
# 1. Register schema
danube-admin schemas register order-events \
  --schema-type json_schema \
  --file schemas/orders.json \
  --description "Order transaction schema"

# 2. Set compatibility mode
danube-admin schemas set-compatibility order-events --mode backward

# 3. Create topic
danube-admin topics create /production/orders \
  --dispatch-strategy reliable --partitions 5

# 4. Configure schema with strict validation
danube-admin topics configure-schema /production/orders \
  --subject order-events \
  --validation-policy enforce \
  --enable-payload-validation

# 5. Verify
danube-admin topics describe /production/orders
danube-admin topics get-schema-config /production/orders
```

## Schemas

### Register

```bash
danube-admin schemas register user-events \
  --schema-type json_schema \
  --file schemas/user-events.json \
  --description "User event schema" \
  --tags users analytics
```

| Type | Description |
|------|-------------|
| `json_schema` | JSON Schema (Draft 7) |
| `avro` | Apache Avro |
| `protobuf` | Protocol Buffers |
| `string` | Plain text |
| `bytes` | Raw bytes |

### Get Schema

```bash
# By subject (latest version)
danube-admin schemas get --subject user-events

# By schema ID
danube-admin schemas get --id 12345

# JSON output
danube-admin schemas get --subject user-events --output json
```

### List Versions

```bash
danube-admin schemas versions user-events
```

### Check Compatibility

```bash
danube-admin schemas check user-events \
  --file schemas/user-events-v2.json \
  --schema-type json_schema
```

### Set Compatibility Mode

```bash
danube-admin schemas get-compatibility user-events
danube-admin schemas set-compatibility user-events --mode backward
```

| Mode | Description |
|------|-------------|
| `none` | No checks |
| `backward` | New schema reads old data (default) |
| `forward` | Old schema reads new data |
| `full` | Both backward and forward |

### Delete Version

```bash
danube-admin schemas delete user-events --version 1 --confirm
```

### Schema Evolution Workflow

```bash
# 1. Check current schema and compatibility
danube-admin schemas get --subject user-events
danube-admin schemas get-compatibility user-events

# 2. Check compatibility of new version
danube-admin schemas check user-events \
  --file schemas/user-events-v2.json \
  --schema-type json_schema

# 3. Register if compatible
danube-admin schemas register user-events \
  --schema-type json_schema \
  --file schemas/user-events-v2.json \
  --description "Added email field"

# 4. Verify
danube-admin schemas versions user-events
```

## Common Workflows

### Health Check

```bash
danube-admin cluster status      # Raft state
danube-admin brokers list        # All brokers
danube-admin brokers leader      # Current leader
danube-admin brokers balance     # Load distribution
```

### Broker Maintenance

```bash
# 1. Preview drain
danube-admin brokers unload broker-001 --dry-run

# 2. Drain topics
danube-admin brokers unload broker-001

# 3. Perform maintenance

# 4. Reactivate
danube-admin brokers activate broker-001 --reason "Maintenance completed"

# 5. Rebalance if needed
danube-admin brokers balance
danube-admin brokers rebalance --dry-run
```
