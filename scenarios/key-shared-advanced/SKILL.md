---
name: key-shared-advanced
description: "Advanced Key-Shared subscription tests: glob key filtering, partitioned key-shared, and poison message handling with failure policies."
---

# Scenario: Key-Shared Advanced

## Objective

Test advanced Key-Shared subscription features beyond basic per-key affinity — including glob-based key filtering, Key-Shared on partitioned topics, and poison message handling with failure policies.

## When to Use

- User wants to test "key filtering", "glob filter", "key-shared filter", "routing filter"
- User wants to test Key-Shared on partitioned topics
- User wants to test poison message handling with Key-Shared
- User wants to test consumer eviction for inactive Key-Shared consumers
- User has already tested basic Key-Shared (via `core-messaging`) and wants to go deeper

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | ✅ | ✅ | `danube-admin` needed for topic creation and failure policies |
| Local Source | ✅ | ✅ | Same |
| Docker Compose | ✅ | ✅ | Use exposed ports |
| Kubernetes | — | ✅ | Use port-forwarded addresses |

Key filtering and poison handling work on standalone. Partitioned Key-Shared benefits from a cluster for better distribution but works on standalone.

## AI Decision Flow

### 1. Which Key-Shared feature to test?

Present these options to the user **exactly as listed**:

1. **Key Filtering**: Consumers with glob-based key filters receive only matching keys. Tests both pure filtering (all consumers have filters) and mixed mode (one filtered, one unfiltered — the unfiltered consumer gets remaining keys). Verify total messages across all consumers equals total sent.

2. **Partitioned Key-Shared**: Key-Shared subscription on a partitioned topic. Verify per-key affinity is maintained across partitions and messages distribute across consumers. Includes consumer churn — a new consumer joins mid-traffic, keys may redistribute but per-key ordering is preserved.

3. **Poison Handling**: Test failure policies on Key-Shared with reliable dispatch — drop (poisoned message skipped, key unblocked for new messages) and block (only the affected key stalls, other keys continue). Also verifies NACK redelivery preserves key affinity (same key → same consumer).

Each aspect maps to the corresponding `Step 2x` in Execution Steps below.

### 2. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "python", "rust", "go", "java" | **Client library** — read `clients/<lang>/SKILL.md` |
| *(unclear)* | Default: **Python** |

**Note:** All Key-Shared advanced tests require a client library. The CLI does not support Key-Shared subscriptions, key filters, or programmatic NACK.

### 3. Reliable or non-reliable?

| User says | Choice |
|-----------|------|
| "reliable", "at-least-once" | **Reliable** — topic created with `--dispatch-strategy reliable`, producer uses `.with_reliable_dispatch()` |
| "non-reliable", "fire and forget", "fast" | **Non-reliable** — default dispatch |
| *(unclear)* | Default: **Non-reliable** for filtering, **Reliable** for poison handling |

## Execution Steps

### Step 1: Create the Topic

```bash
# Non-reliable
danube-admin topics create /default/ks-advanced-test

# Reliable (required for poison handling)
danube-admin topics create /default/ks-advanced-test --dispatch-strategy reliable

# Partitioned
danube-admin topics create /default/ks-advanced-test --partitions 3

# Partitioned + reliable
danube-admin topics create /default/ks-advanced-test --dispatch-strategy reliable --partitions 3
```

### Step 2a: Key Filtering (if selected)

#### Pure Filtering

Two consumers with different glob filters on the same Key-Shared subscription.

Generate a script that:
1. Creates a producer
2. Creates Consumer A with `.with_key_filter("user-*")` (or `with_key_filters(["eu-*", "ap-*"])`)
3. Creates Consumer B with `.with_key_filter("order-*")` (or `with_key_filters(["us-*", "af-*"])`)
4. Both consumers use the same subscription name with `SubType::KeyShared`
5. Producer sends messages with keys: `user-1`, `user-2`, `order-1`, `order-2` (or `eu-west`, `ap-tokyo`, `us-east`, `af-cape`)
6. Verify: Consumer A only receives `user-*` messages, Consumer B only receives `order-*` messages

**Filter pattern examples:**
- `"user-*"` — matches `user-1`, `user-admin`, `user-anything`
- `"eu-*"` — matches `eu-west`, `eu-east`
- `"ship?"` — matches `ship1`, `shipA` (single char wildcard)

#### Mixed Filters

One consumer with a filter, one without (accepts all keys):

1. Consumer A: no filter (accepts all keys)
2. Consumer B: `.with_key_filter("vip-*")` (only VIP keys)
3. Producer sends: `vip-gold`, `vip-platinum`, `regular-1`, `regular-2`
4. Verify: Consumer B gets all `vip-*` messages, Consumer A gets `regular-*` messages
5. Total messages across both consumers = total sent

### Step 2b: Partitioned Key-Shared (if selected)

Key-Shared on a partitioned topic:

1. Create topic with `--partitions 3`
2. Create 2 Key-Shared consumers on the same subscription
3. Producer sends messages with routing keys across partitions
4. Verify: per-key affinity maintained (same key → same consumer across all partitions)
5. Verify: messages distributed across multiple consumers

**With consumer churn:**

1. Start with 1 consumer
2. Send first batch of messages
3. 2nd consumer joins the same Key-Shared subscription
4. Send second batch of messages
5. Verify: keys may be redistributed, but per-key ordering is preserved within each consumer

### Step 2c: Poison Handling (if selected)

Key-Shared with failure policies — tests what happens when a consumer NACKs a message until retries are exhausted.

#### NACK Redelivery (Key Affinity)

1. Set failure policy with retries allowed
2. Send message with key, consumer NACKs
3. Verify: same message redelivered to the SAME consumer (key affinity preserved)
4. Consumer acks on second attempt

#### Drop Policy (skip poisoned message, continue with same key)

```bash
danube-admin topics set-failure-policy /default/ks-advanced-test \
  --subscription ks-test-sub \
  --max-redelivery-count 1 \
  --ack-timeout-ms 5000 \
  --base-redelivery-delay-ms 50 \
  --max-redelivery-delay-ms 50 \
  --backoff-strategy fixed \
  --poison-policy drop
```

1. Create reliable producer + Key-Shared consumer
2. Send message with key "payment", consumer NACKs it
3. Message is redelivered (1 retry allowed)
4. Consumer NACKs again → retries exhausted, message dropped
5. Send another message with same key "payment"
6. Verify: new message delivered (key is unblocked)

#### Block Policy (stalls only the affected key)

```bash
danube-admin topics set-failure-policy /default/ks-advanced-test \
  --subscription ks-test-sub \
  --max-redelivery-count 0 \
  --ack-timeout-ms 5000 \
  --base-redelivery-delay-ms 50 \
  --max-redelivery-delay-ms 50 \
  --backoff-strategy fixed \
  --poison-policy block
```

1. Create reliable producer + 2 Key-Shared consumers
2. Send message with key "poison-key", consumer NACKs it → blocked
3. Send message with different key "healthy-key"
4. Verify: "healthy-key" message IS delivered (different key, different slot)
5. Verify: "poison-key" is stalled (blocked)

## Verification

| Test | Pass Criteria |
|------|--------------|
| **Key Filtering (Pure)** | Each consumer only receives messages matching its glob pattern |
| **Key Filtering (Mixed)** | Filtered consumer gets matching keys, unfiltered gets the rest, total = sent |
| **Partitioned Key-Shared** | Per-key affinity across partitions, distribution across consumers |
| **Consumer Churn** | Keys redistributed, per-key ordering preserved |
| **NACK Redelivery** | Same message redelivered to same consumer (key affinity) |
| **Drop Policy** | Poisoned message skipped, key unblocked for new messages |
| **Block Policy** | Only affected key stalled, other keys continue normally |

```bash
# Inspect topic state
danube-admin topics describe /default/ks-advanced-test
danube-admin topics subscriptions /default/ks-advanced-test

# Check failure policy
danube-admin topics get-failure-policy /default/ks-advanced-test \
  --subscription ks-test-sub --output json
```

## Cleanup

This scenario only cleans up topics it created. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
danube-admin topics delete /default/ks-advanced-test
```
