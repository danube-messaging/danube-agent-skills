---
name: cluster-health
description: "Test cluster resilience under broker failures — follower restart, leader restart with re-election, topic reconciliation, and broker failover with topic reassignment."
---

# Scenario: Cluster Health & Broker Restart

## Objective

Test cluster resilience when brokers fail and restart — verify Raft re-election, topic reconciliation after restart, and broker failover with automatic topic reassignment.

## When to Use

- User wants to test "broker restart", "failover", "re-election", "cluster health"
- User wants to verify cluster recovery after a broker crash
- User wants to test leader election when the Raft leader goes down
- User wants to verify topic reconciliation after broker restart

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | — | ✅ | Requires 3-node cluster to test failover and re-election |
| Local Source | — | ✅ | Same |

Cluster health tests require a **cluster** (3 nodes minimum) to test Raft re-election and topic redistribution. Standalone has no failover to test.

## AI Decision Flow

### 1. Which cluster health aspect to test?

Present these options to the user **exactly as listed**:

1. **Follower Restart**: Kill a non-leader broker, restart it with the same data directory. Verify it rejoins the Raft cluster, resumes as a voter, and its topics are reconciled — tests fast restart within the TTL window.

2. **Leader Restart**: Kill the Raft leader, verify a new leader is elected by the remaining voters, then restart the old leader. Verify it rejoins as a follower, all topics are intact, and the cluster returns to full strength.

3. **Broker Failover**: Simulate a permanent broker failure — remove from Raft and kill the process (without graceful unloading). Verify topics from the failed broker are reassigned to surviving brokers and no topics are lost.

Each aspect maps to the corresponding `Step 2x` in Execution Steps below.

### 2. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "python", "rust", "go", "java" | **Client library** — for producing/consuming around restarts to verify no message loss |
| *(unclear)* | Default: **danube-admin CLI** (all verification uses admin commands) |

**Note:** Most cluster health tests use `danube-admin` CLI exclusively. Client libraries are only needed if the user wants to verify produce/consume continuity across restarts.

### AI Reference: Health Check Commands

The `cluster_health_check.sh` script and the commands below are used *within* the aspects above for verification. They are documented here for AI reference, not as a user-facing aspect.

```bash
# Run the predefined health check script
./scenarios/cluster-health/scripts/cluster_health_check.sh [ADMIN_ENDPOINT] [LOG_DIR]

# Or manually:
danube-admin cluster status                          # Raft state, leader, voters
danube-admin brokers list                             # Broker states
danube-admin brokers balance                          # Load distribution
danube-admin topics list --namespace default           # Topic assignments
grep -iE "error|panic|fatal" $TEST_RUN/logs/*.log     # Log errors
```

## Predefined Scripts

This scenario ships with a helper script in `scenarios/cluster-health/scripts/`:

- **`cluster_health_check.sh`** — Runs comprehensive diagnostics: Raft status, broker states, load balance, topic distribution, and log error scanning. Usage:
  ```bash
  ./scenarios/cluster-health/scripts/cluster_health_check.sh [ADMIN_ENDPOINT] [LOG_DIR]
  # Example:
  ./scenarios/cluster-health/scripts/cluster_health_check.sh http://127.0.0.1:50051 $TEST_RUN/logs
  ```

## Execution Steps

### Step 1: Create Test Topics

```bash
# Create 3 topics so each broker gets at least one
for i in 1 2 3; do
  danube-admin topics create /default/health-test-$i
done
sleep 3

# Record initial distribution
danube-admin brokers balance
danube-admin topics list --namespace default
```

### Step 2a: Follower Restart (if selected)

1. **Identify leader and pick a follower:**
```bash
# Check each broker's admin endpoint to find the leader
for port in 50051 50052 50053; do
  DANUBE_ADMIN_ENDPOINT=http://127.0.0.1:$port danube-admin cluster status
done
# Pick any broker that is NOT the leader
```

2. **Record follower's topics before kill:**
```bash
danube-admin topics list --broker <FOLLOWER_NODE_ID> --output json
```

3. **Kill the follower broker:**
```bash
kill <FOLLOWER_PID>
```

4. **Restart with same data-dir (preserves node_id → fast restart within TTL):**
```bash
danube-broker --config-file $TEST_RUN/danube_broker.yml \
  --broker-addr 0.0.0.0:<port> --admin-addr 0.0.0.0:<admin_port> \
  --raft-addr 0.0.0.0:<raft_port> --data-dir $TEST_RUN/data/raft-<N> \
  --seed-nodes "..." --prom-exporter 0.0.0.0:<prom_port>
```

5. **Verify:**
   - `danube-admin cluster status` → 3 voters intact
   - `danube-admin brokers list` → restarted broker status is "active" (fast restart within TTL)
   - Topics on restarted broker ≥ topics before kill (reconciliation)
   - Total topics in cluster unchanged

### Step 2b: Leader Restart (if selected)

1. **Identify the current Raft leader** (same as Step 2a)

2. **Record leader's topics and identify a survivor admin port**

3. **Kill the leader broker**

4. **Verify re-election on survivors:**
```bash
# Use a surviving broker's admin endpoint
DANUBE_ADMIN_ENDPOINT=http://127.0.0.1:<SURVIVOR_ADMIN_PORT>
danube-admin cluster status
# Should show a NEW leader (different node_id)
```

5. **Restart the killed leader with same data-dir**

6. **Verify:**
   - New leader elected (different node_id than old leader)
   - 3 voters intact after rejoin
   - Restarted broker status is "active"
   - All topics still exist

### Step 2c: Broker Failover (if selected)

This tests what happens when a broker is permanently removed (not just restarted):

1. **Pick a broker to remove and record its topics**

2. **Remove from Raft membership first (before killing!):**
```bash
danube-admin cluster remove-node --node-id <ID>
```

3. **Kill the broker process**

4. **Wait for topic reassignment:**
   - Topics from the removed broker should be redistributed to survivors
   - Check with `danube-admin topics list --namespace default`

5. **Verify:**
   - Cluster has N-1 voters
   - All topics reassigned to remaining brokers
   - No topics lost


## Verification

| Test | Pass Criteria |
|------|--------------|
| **Follower Restart** | 3 voters intact, broker "active" (fast restart), topics reconciled, total topics unchanged |
| **Leader Restart** | New leader elected, 3 voters after rejoin, broker "active", all topics exist |
| **Broker Failover** | N-1 voters, all topics reassigned to survivors, no topics lost |

```bash
# Key verification commands
danube-admin cluster status
danube-admin brokers list
danube-admin brokers list --output json
danube-admin brokers balance
danube-admin topics list --namespace default --output json
```

## Cleanup

This scenario only cleans up topics it created. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
for i in 1 2 3; do
  danube-admin topics delete /default/health-test-$i
done
```
