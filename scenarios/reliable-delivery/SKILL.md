---
name: reliable-delivery
description: "Test Danube's reliable dispatch: NACK redelivery, ack timeout, failure policies (block/drop/dead-letter), and consumer reconnection failover."
---

# Scenario: Reliable Delivery

## Objective

Test Danube's reliable dispatch mechanics — at-least-once delivery guarantees, NACK handling, ack timeouts, failure policies, and consumer reconnection behavior. These are the features that ensure no message is lost in production.

## When to Use

- User wants to test "reliable", "at-least-once", "NACK", "redelivery", "dead letter"
- User wants to verify message redelivery after consumer failure
- User wants to test failure policies (block, drop, dead-letter)
- User wants to verify consumer reconnection behavior

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | ✅ | ✅ | `danube-admin` needed for topic creation and failure policy setup |
| Local Source | ✅ | ✅ | Same |
| Docker Compose | ✅ | ✅ | Use exposed ports |
| Kubernetes | — | ✅ | Use port-forwarded addresses |

All tests work on standalone. Reconnection failover is more meaningful with Shared subscriptions (multiple consumers).

## AI Decision Flow

### 1. Which reliable delivery aspect to test?

| User says | Test Flow |
|-----------|-----------|
| "basic", "simple", "at-least-once" | **Basic Reliable** — reliable produce/consume, verify ack-based delivery |
| "nack", "negative ack", "redelivery", "retry" | **NACK Redelivery** — consumer NACKs a message, verify it's redelivered |
| "timeout", "ack timeout", "no ack" | **Ack Timeout** — consumer doesn't ack, verify broker redelivers after timeout |
| "poison", "failure policy", "block", "drop" | **Failure Policies** — test block (stops progress) vs drop (skips message) vs dead-letter (routes to DLQ) |
| "dead letter", "dlq", "dead-letter queue" | **Dead Letter Queue** — poison message routed to DLQ with metadata |
| "reconnect", "disconnect", "failover" | **Consumer Reconnection** — consumer disconnects, pending messages resent to another consumer |
| "all", "everything" | **All flows** in sequence |
| *(unclear)* | Default: **Basic Reliable** |

### 2. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "python", "rust", "go", "java" | **Client library** — read `clients/<lang>/SKILL.md` |
| *(unclear)* | Default: **Python** |

**Note:** All reliable delivery tests require a client library. The CLI cannot NACK messages or control ack timing. Auto-install the library.

### 3. Subscription type?

| User says | Type |
|-----------|------|
| "exclusive", "single" | **Exclusive** — single consumer, ordered redelivery |
| "shared", "queue", "multiple" | **Shared** — multiple consumers, failover on disconnect |
| *(unclear)* | Default: **Exclusive** for NACK/timeout/policy tests, **Shared** for reconnection tests |

## Execution Steps

### Step 1: Create a Reliable Topic

All reliable delivery tests require a topic created with `--dispatch-strategy reliable`:

```bash
danube-admin topics create /default/reliable-test --dispatch-strategy reliable
```

### Step 2a: Basic Reliable (if selected)

1. Create a reliable producer (`.with_reliable_dispatch()` / `.with_dispatch_strategy(RELIABLE)`)
2. Create a consumer and subscribe
3. Send N messages
4. Consumer receives and acks each message
5. Verify: all messages received, producer got message IDs (acknowledgments)

### Step 2b: NACK Redelivery (if selected)

1. Create reliable producer + consumer
2. Send 1 message
3. Consumer receives the message but calls `consumer.nack(message, delay_ms=0, reason="retry")`
4. Consumer receives the SAME message again (redelivery)
5. Consumer acks the redelivered message
6. Verify: same payload and same `topic_offset` on redelivery

**Before running:** Set a failure policy to allow retries:

```bash
danube-admin topics set-failure-policy /default/reliable-test \
  --subscription test-sub \
  --max-redelivery-count 2 \
  --ack-timeout-ms 5000 \
  --base-redelivery-delay-ms 50 \
  --max-redelivery-delay-ms 50 \
  --backoff-strategy fixed \
  --poison-policy block
```

### Step 2c: Ack Timeout Redelivery (if selected)

1. Create reliable producer + consumer
2. Set failure policy with short ack timeout (e.g., 200ms)
3. Send 1 message
4. Consumer receives the message but does NOT ack it
5. Wait for timeout — broker redelivers the same message
6. Consumer acks the redelivered message
7. Verify: same payload and same `topic_offset`

```bash
danube-admin topics set-failure-policy /default/reliable-test \
  --subscription test-sub \
  --max-redelivery-count 2 \
  --ack-timeout-ms 200 \
  --base-redelivery-delay-ms 50 \
  --max-redelivery-delay-ms 50 \
  --backoff-strategy fixed \
  --poison-policy block
```

### Step 2d: Failure Policies (if selected)

Three sub-flows depending on which policy the user wants:

#### Block Policy

Stops subscription progress when a message exhausts its retry budget:

1. Create reliable topic + set failure policy with `--max-redelivery-count 0 --poison-policy block`
2. Send message A, consumer NACKs it
3. Send message B
4. Verify: message B is NOT delivered (subscription is stalled)

#### Drop Policy

Skips the poisoned message and continues:

1. Create reliable topic + set failure policy with `--max-redelivery-count 0 --poison-policy drop`
2. Send message A, consumer NACKs it
3. Send message B
4. Verify: message B IS delivered (poisoned message was skipped)

#### Dead Letter Queue

Routes poisoned messages to a separate DLQ topic:

1. Create main topic + DLQ topic (both reliable)
2. Set failure policy with `--poison-policy dead_letter --dead-letter-topic /default/reliable-test-dlq`
3. Send message, consumer NACKs it
4. Verify: message appears on DLQ with metadata attributes (`x-original-topic`, `x-original-subscription`, `x-poison-policy`, `x-failure-reason`)
5. Verify: main subscription continues with next message

```bash
# Create DLQ topic
danube-admin topics create /default/reliable-test-dlq --dispatch-strategy reliable

# Set dead-letter policy
danube-admin topics set-failure-policy /default/reliable-test \
  --subscription test-sub \
  --max-redelivery-count 0 \
  --ack-timeout-ms 5000 \
  --base-redelivery-delay-ms 50 \
  --max-redelivery-delay-ms 50 \
  --backoff-strategy fixed \
  --poison-policy dead_letter \
  --dead-letter-topic /default/reliable-test-dlq
```

### Step 2e: Consumer Reconnection (if selected)

1. Create reliable producer + 2 Shared consumers on same subscription
2. Send message, consumer A receives it
3. Disconnect consumer A (drop the consumer object)
4. Verify: broker resends the pending message to consumer B
5. Consumer B acks it

## Verification

| Test | Pass Criteria |
|------|--------------|
| **Basic Reliable** | All messages received and acked, producer got IDs |
| **NACK Redelivery** | Same message redelivered after NACK (same offset) |
| **Ack Timeout** | Same message redelivered after timeout (same offset) |
| **Block Policy** | Subscription stalls — no new messages after poison |
| **Drop Policy** | Next message delivered — poisoned message skipped |
| **Dead Letter** | Message on DLQ with origin metadata, main subscription continues |
| **Reconnection** | Pending message resent to surviving consumer |

```bash
# Inspect topic state
danube-admin topics describe /default/reliable-test

# Check failure policy
danube-admin topics get-failure-policy /default/reliable-test \
  --subscription test-sub --output json
```

## Cleanup

This scenario only cleans up topics it created. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
danube-admin topics delete /default/reliable-test
danube-admin topics delete /default/reliable-test-dlq  # if DLQ was created
```
