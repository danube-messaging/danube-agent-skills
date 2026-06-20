---
name: subscription-patterns
description: "Test Danube's two fundamental messaging patterns: pub-sub fan-out and queue work distribution. Validates message routing behavior with Exclusive and Shared subscriptions."
---

# Scenario: Subscription Patterns

## Objective

Test the two fundamental messaging patterns in Danube — **pub-sub fan-out** (broadcast) and **queue work distribution** (load balancing) — and verify correct message routing behavior.

## When to Use

- User wants to understand the difference between Exclusive and Shared subscriptions
- User wants to test "fan-out", "broadcast", "pub-sub", "round-robin", "load balance", "queue"
- User wants to verify message distribution across multiple consumers
- User wants to test consumer churn (join/leave during traffic)

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | ✅ | ✅ | |
| Local Source | ✅ | ✅ | |
| Docker Compose | ✅ | ✅ | |
| Kubernetes | — | ✅ | Use port-forwarded addresses |

All tests work on standalone. Consumer churn tests benefit from but don't require a cluster.

## AI Decision Flow

### 1. Which pattern to test?

| User says | Test Flow |
|-----------|-----------|
| "fan-out", "broadcast", "pub-sub", "every consumer gets all" | **Fan-out** — multiple unique Exclusive subscriptions, each receives ALL messages |
| "queue", "work distribution", "round-robin", "load balance", "split" | **Queue** — multiple consumers on the SAME Shared subscription, messages split evenly |
| "both", "compare", "side by side" | **Both** — run fan-out then queue, compare results |
| "churn", "join", "leave", "dynamic consumers" | **Consumer Churn** — consumers join/leave mid-traffic, verify no message loss |
| *(unclear)* | Default: **Both** (compare fan-out vs queue) |

### 2. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "cli", "command line" | **danube-cli** — works for fan-out and basic queue |
| "python", "rust", "go", "java" | **Client library** — read the appropriate `clients/<lang>/SKILL.md` |
| *(unclear)* | Default: **danube-cli** for fan-out/queue, **Python** for churn tests |

**Note:** Consumer churn tests require a client library (CLI can't dynamically join/leave).

### 3. How many consumers?

| User says | Count |
|-----------|-------|
| "2", "pair" | **2 consumers** |
| "3", "standard" | **3 consumers** (default) |
| "more", "5", "scale" | **5 consumers** |
| *(unclear)* | Default: **3** |

### 4. How many messages?

| User says | Count |
|-----------|-------|
| "few", "quick" | **12 messages** |
| "medium", "standard" | **36 messages** (default — divisible by 3 for even split) |
| "many", "stress", "100" | **100 messages** |
| *(unclear)* | Default: **36** |

## Execution Steps

### Step 1: Create the Topic

```bash
danube-admin topics create /default/pattern-test
```

### Step 2: Fan-Out Test (Pub-Sub)

Each consumer uses a **unique subscription name** with `SubType::Exclusive`. Each consumer receives ALL messages.

#### Using danube-cli

```bash
# Terminal 1: Consumer A (unique subscription)
danube-cli consume -s http://localhost:6650 -t /default/pattern-test \
  -m fanout-sub-1 --sub-type exclusive

# Terminal 2: Consumer B (unique subscription)
danube-cli consume -s http://localhost:6650 -t /default/pattern-test \
  -m fanout-sub-2 --sub-type exclusive

# Terminal 3: Consumer C (unique subscription)
danube-cli consume -s http://localhost:6650 -t /default/pattern-test \
  -m fanout-sub-3 --sub-type exclusive

# Terminal 4: Producer
danube-cli produce -s http://localhost:6650 -t /default/pattern-test \
  -m "broadcast message" --count 36
```

#### Using Client Libraries

Generate a script that:
1. Creates 3 consumers with unique subscription names + `Exclusive` type
2. Creates 1 producer
3. Sends N messages
4. Collects per-consumer message counts
5. Asserts: each consumer received ALL N messages

### Step 3: Queue Test (Work Distribution)

All consumers use the **same subscription name** with `SubType::Shared`. Messages are distributed round-robin.

#### Using danube-cli

```bash
# Terminal 1-3: All use same subscription name
danube-cli consume -s http://localhost:6650 -t /default/pattern-test \
  -m queue-sub --sub-type shared

# Terminal 4: Producer
danube-cli produce -s http://localhost:6650 -t /default/pattern-test \
  -m "work item" --count 36
```

#### Using Client Libraries

Generate a script that:
1. Creates 3 consumers with the SAME subscription name + `Shared` type
2. Creates 1 producer
3. Sends N messages
4. Collects per-consumer message counts
5. Asserts: total received = N, each consumer received approximately N/3

### Step 4: Consumer Churn Test (if selected)

Requires client library. Tests consumers joining mid-traffic:
1. Start with 2 consumers on a Shared subscription
2. Send first batch of messages
3. A 3rd consumer joins
4. Send second batch of messages
5. Verify: all messages delivered exactly once, no duplicates, all 3 consumers got messages after the join

## Verification

| Test | Pass Criteria |
|------|--------------|
| **Fan-out** | Each consumer received ALL N messages (N × consumers total deliveries) |
| **Queue** | Total received = N, each consumer received approximately N/3 (± 1) |
| **Consumer Churn** | Total unique messages = N, no duplicates, all consumers got some messages |

```bash
# Check topic state
danube-admin topics describe /default/pattern-test
danube-admin topics subscriptions /default/pattern-test
```

## Cleanup

This scenario only cleans up topics it created. See `scenarios/SKILL.md` → **Infrastructure Lifecycle** for cluster teardown.

```bash
danube-admin topics delete /default/pattern-test
```
