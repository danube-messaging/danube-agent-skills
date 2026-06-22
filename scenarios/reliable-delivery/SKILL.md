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

Present these options to the user **exactly as listed**:

1. **Basic Reliable**: Produce and consume messages with reliable dispatch (at-least-once). Verify all messages are received, each is explicitly acknowledged, and the producer receives message IDs as confirmation.

2. **Redelivery (NACK & Timeout)**: Test both redelivery triggers — consumer explicitly NACKs a message (immediate redelivery) and consumer fails to ack within the timeout (broker-initiated redelivery). Verify the same message is redelivered with the same offset in both cases.

3. **Failure Policies**: Test what happens when a message exhausts its retry budget — block (subscription stalls), drop (message skipped, next delivered), or dead-letter (message routed to a DLQ topic with origin metadata). Covers all three poison message strategies.

4. **Consumer Reconnection**: Two consumers share a Shared subscription. When one consumer disconnects, verify the broker resends its pending (unacked) messages to the surviving consumer. Tests failover behavior.

Each aspect maps to the corresponding `Step 2x` in Execution Steps below.

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

### Step 2b: Redelivery — NACK & Timeout (if selected)

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

#### Part 1: NACK Redelivery

1. Create reliable producer + consumer
2. Send 1 message
3. Consumer receives the message but calls `consumer.nack(message, delay_ms=0, reason="retry")`
4. Consumer receives the SAME message again (redelivery)
5. Consumer acks the redelivered message
6. Verify: same payload and same `topic_offset` on redelivery

#### Part 2: Ack Timeout Redelivery

1. Update failure policy with short ack timeout:
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
2. Send 1 message
3. Consumer receives the message but does NOT ack it
4. Wait for timeout — broker redelivers the same message
5. Consumer acks the redelivered message
6. Verify: same payload and same `topic_offset`

### Step 2c: Failure Policies (if selected)

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
4. Verify: message appears on DLQ with these metadata attributes:
   - `x-original-topic` — source topic name (e.g., `/default/reliable-test`)
   - `x-original-subscription` — subscription that NACKed the message
   - `x-poison-policy` — `dead_letter`
   - `x-failure-reason` — the reason string passed in the NACK call
   - `x-original-broker-addr` — broker address that handled the message
   - `x-original-producer-id` — ID of the producer that sent the message
   - `x-original-topic-offset` — offset of the message on the original topic
   - `x-delivery-attempt` — number of delivery attempts before DLQ routing
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

### Step 2d: Consumer Reconnection (if selected)

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
