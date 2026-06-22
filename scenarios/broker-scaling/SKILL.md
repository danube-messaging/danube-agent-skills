---
name: broker-scaling
description: "Scale a Danube cluster up and down — add node (learner → voter → activate), rebalance topics, unload broker, remove node, and verify zero message loss during reliable topic moves."
---

# Scenario: Broker Scaling & Rebalancing

## Objective

Test the full cluster scaling lifecycle — scaling up (add a 4th broker via join mode), rebalancing topics across brokers, unloading a broker, scaling down (remove from Raft + stop), and verifying that reliable topics maintain offset continuity during moves.

## When to Use

- User wants to test "scaling", "add broker", "remove broker", "rebalance"
- User wants to verify topic redistribution after scaling
- User wants to test reliable topic move (offset continuity) during rebalancing
- User wants to test the learner → voter → activate workflow

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | — | ✅ | Requires 3-node cluster + a 4th broker for scale-up |
| Local Source | — | ✅ | Same |

Scaling tests require a **cluster** (3+ nodes). Docker Compose and Kubernetes are not listed because dynamic node addition (--join) and Raft membership commands are easiest to test on local binary/source.

## AI Decision Flow

### 1. Which scaling aspect to test?

Present these options to the user **exactly as listed**:

1. **Scale Up**: Start a new (4th) broker, join the Raft cluster as learner, promote to voter, activate, and rebalance existing topics so the new broker receives its share. Verifies the full `join → learner → voter → activate` lifecycle.

2. **Scale Down**: Safely decommission a broker: unload its topics, remove it from the Raft cluster, stop the process. Verify the remaining cluster is healthy and all topics are preserved.

3. **Reliable Topic Move**: Produce messages before and after a topic moves between brokers (triggered by unload). Verify zero message loss, no duplicates, and continuous offsets across the move.

Each aspect maps to the corresponding `Step 2x` in Execution Steps below.

### 2. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "python", "rust", "go", "java" | **Client library** — needed for reliable topic move verification (produce/consume around the move) |
| *(unclear)* | Default: **danube-admin CLI** for scaling operations, **Python** for topic move verification |

**Note:** Scale Up and Scale Down use `danube-admin` CLI exclusively. Client libraries are only needed for the Reliable Topic Move aspect.

### AI Reference: Rebalance & Unload Commands

These commands are used *within* the aspects above (e.g., rebalance after Scale Up, unload during Scale Down). They are documented here for AI reference, not as user-facing aspects.

```bash
# Rebalance: redistribute topics evenly across all active brokers
danube-admin brokers rebalance              # execute
danube-admin brokers rebalance --dry-run    # preview only
danube-admin brokers rebalance --max-moves 4  # limit moves per cycle

# Unload: drain all topics from a specific broker
danube-admin brokers unload --broker-id <ID>

# Balance check: verify distribution
danube-admin brokers balance
danube-admin brokers balance --output json | jq '.coefficient_of_variation'
```

## Predefined Scripts

This scenario ships with helper scripts in `scenarios/broker-scaling/scripts/`:

- **`scale_up.sh`** — Automates the full scale-up sequence: start broker with `--join` → add as learner → promote to voter → activate → rebalance. Usage:
  ```bash
  ./scenarios/broker-scaling/scripts/scale_up.sh <BROKER_BINARY> <CONFIG_FILE> <DATA_DIR> [ADMIN_ENDPOINT]
  # Example:
  ./scenarios/broker-scaling/scripts/scale_up.sh ./bin/v0.15.0/danube-broker $TEST_RUN/danube_broker.yml $TEST_RUN/data
  ```

- **`scale_down.sh`** — Automates the safe scale-down: unload topics → auto-discover Raft leader → remove from Raft → stop process. Handles the leader-forwarding requirement automatically. Usage:
  ```bash
  ./scenarios/broker-scaling/scripts/scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]
  # Example:
  ./scenarios/broker-scaling/scripts/scale_down.sh ./bin/v0.15.0/danube-admin 5046216364513136080 $TEST_RUN/broker_2.pid
  ```

## Execution Steps

### Step 1: Create Topics for Distribution

```bash
# Create 12 topics so they distribute across brokers (4 per broker in a 3-node cluster)
for i in $(seq 1 12); do
  danube-admin topics create /default/scale-test-$i
done

# Verify distribution
danube-admin brokers balance
danube-admin brokers balance --output json | jq '.coefficient_of_variation'
```

### Step 2a: Scale Up (if selected)

**Use the predefined script** (recommended):
```bash
./scenarios/broker-scaling/scripts/scale_up.sh \
  ./bin/v0.15.0/danube-broker $TEST_RUN/danube_broker.yml $TEST_RUN/data
```

Or manually — start a 4th broker in join mode and add it to the cluster:

```bash
# 1. Start 4th broker with --join (uses the port allocation for index 3)
#    broker=6653, admin=50054, raft=7653, prom=9043
danube-broker --config-file $TEST_RUN/danube_broker.yml \
  --broker-addr 0.0.0.0:6653 --admin-addr 0.0.0.0:50054 \
  --raft-addr 0.0.0.0:7653 --data-dir $TEST_RUN/data/raft-4 \
  --prom-exporter 0.0.0.0:9043 --join

# 2. Add as learner
danube-admin cluster add-node --node-addr http://127.0.0.1:50054

# 3. Discover node_id
DANUBE_ADMIN_ENDPOINT=http://127.0.0.1:50054 danube-admin cluster status
# Note the Self Node ID

# 4. Promote to voter
danube-admin cluster promote-node --node-id <ID>

# 5. Activate
danube-admin brokers activate --broker-id <ID> --reason "scale-up-test"

# 6. Rebalance existing topics to include the new broker
danube-admin brokers rebalance
```

Verify:
- `danube-admin cluster status` shows 4 voters
- `danube-admin brokers list` shows 4 active brokers
- `danube-admin brokers balance` shows topics distributed across 4 brokers (CV < 0.25)

### Step 2b: Scale Down (if selected)

**Use the predefined script** (recommended):
```bash
./scenarios/broker-scaling/scripts/scale_down.sh \
  ./bin/v0.15.0/danube-admin <NODE_ID> $TEST_RUN/broker_4.pid
```

Or manually:

```bash
# 1. Unload all topics from the broker to decommission
danube-admin brokers unload --broker-id <ID>

# 2. Remove from Raft cluster (MUST be done before stopping the process!)
#    IMPORTANT: This command must be sent to the Raft LEADER.
#    If the target broker IS the leader, send the request directly to it.
#    If the target broker is a follower, send to the leader's admin endpoint.
#    Sending to a non-leader returns: "has to forward request to: Some(...)"
danube-admin cluster remove-node --node-id <ID>

# 3. Stop the broker process
kill $(cat broker.pid)

# 4. Verify cluster is healthy with N-1 nodes
danube-admin cluster status    # should show N-1 voters
danube-admin brokers list      # removed broker no longer listed
danube-admin topics list --namespace default
# Note: topics from the removed broker may show as "unassigned" (no broker_id)
# until accessed by a client — this is expected (Danube uses lazy assignment).
```

### Step 2c: Reliable Topic Move (if selected)

This flow verifies that topics maintain offset continuity when moved between brokers.

Generate a script that:
1. Creates a reliable topic: `danube-admin topics create /default/move-test --dispatch-strategy reliable`
2. Identifies which broker owns the topic: `danube-admin topics describe /default/move-test`
3. Starts a producer that sends 100 messages with sequential payloads
4. Starts a consumer that tracks received offsets
5. Triggers a topic move by unloading the owner broker: `danube-admin brokers unload --broker-id <owner-id>`
6. Continues producing 100 more messages after the move
7. Verifies: all 200 messages received, offsets are continuous (no gaps, no duplicates), consumer sees seamless transition

## Verification

| Test | Pass Criteria |
|------|--------------| 
| **Scale Up** | 4 voters in cluster, 4 active brokers, topics distributed (CV < 0.25) |
| **Scale Down** | Cluster healthy with N-1 voters, removed broker not listed, all 12 topics still exist (some may be unassigned until accessed — this is expected) |
| **Reliable Topic Move** | All messages received, offset continuity preserved, no gaps or duplicates |

```bash
# Key verification commands
danube-admin cluster status
danube-admin brokers list
danube-admin brokers balance
danube-admin brokers balance --output json
danube-admin topics list --namespace default
danube-admin topics describe /default/scale-test-1
```

## Cleanup

This scenario only cleans up topics it created. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
for i in $(seq 1 12); do
  danube-admin topics delete /default/scale-test-$i
done
danube-admin topics delete /default/move-test  # if reliable topic move was tested
```
