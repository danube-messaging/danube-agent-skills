#!/usr/bin/env bash
# =============================================================================
# Scale Down Helper — Remove a broker from a Danube cluster
#
# Automates: unload topics → find leader → remove from Raft → stop process
#
# Usage:
#   ./scripts/scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]
#
# Example:
#   ./scripts/scale_down.sh ./bin/v0.15.0/danube-admin 5046216364513136080 runs/test_xxx/broker_2.pid
#
# IMPORTANT: Always remove from Raft BEFORE stopping the process to avoid quorum loss.
# NOTE: The remove-node command must be sent to the Raft leader. This script
#       auto-discovers the leader by querying each broker's admin endpoint.
# =============================================================================
set -euo pipefail

ADMIN_BIN="${1:?Usage: scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]}"
NODE_ID="${2:?Usage: scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]}"
PID_FILE="${3:?Usage: scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]}"
ADMIN_ENDPOINT="${4:-http://127.0.0.1:50051}"

echo "=== Scale Down: Removing broker $NODE_ID ==="

# Step 1: Unload all topics
echo "[1/4] Unloading all topics from broker $NODE_ID..."
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers unload --broker-id "$NODE_ID"

echo "  Waiting for topic migration..."
sleep 5

# Step 2: Discover the Raft leader
# The remove-node command must be sent to the leader. Query each known admin
# port to find which broker is the leader.
echo "[2/4] Discovering Raft leader..."
LEADER_ENDPOINT=""
for port in 50051 50052 50053 50054; do
  CANDIDATE="http://127.0.0.1:$port"
  STATUS=$(DANUBE_ADMIN_ENDPOINT="$CANDIDATE" "$ADMIN_BIN" cluster status 2>&1) || continue

  SELF_ID=$(echo "$STATUS" | grep 'Self Node ID' | awk '{print $NF}')
  LEADER_ID=$(echo "$STATUS" | grep 'Leader' | head -1 | awk '{print $NF}')

  if [ -n "$SELF_ID" ] && [ -n "$LEADER_ID" ] && [ "$SELF_ID" = "$LEADER_ID" ]; then
    LEADER_ENDPOINT="$CANDIDATE"
    echo "  ✅ Leader found at $LEADER_ENDPOINT (node $LEADER_ID)"
    break
  fi
done

if [ -z "$LEADER_ENDPOINT" ]; then
  echo "  ⚠ Could not discover leader, using provided endpoint: $ADMIN_ENDPOINT"
  LEADER_ENDPOINT="$ADMIN_ENDPOINT"
fi

# Step 3: Remove from Raft (send to leader)
echo "[3/4] Removing from Raft cluster (via leader at $LEADER_ENDPOINT)..."
DANUBE_ADMIN_ENDPOINT="$LEADER_ENDPOINT" "$ADMIN_BIN" cluster remove-node --node-id "$NODE_ID"
echo "  ✅ Removed from Raft membership."
sleep 2

# Step 4: Stop the process
echo "[4/4] Stopping broker process..."
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || echo "  Process already stopped."
  sleep 2
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "  ✅ Broker process stopped."
else
  echo "  ⚠ PID file not found: $PID_FILE — kill the process manually"
fi

# Verify — use a surviving broker's endpoint (not the one we just removed)
echo ""
echo "=== Verification ==="
VERIFY_ENDPOINT="$LEADER_ENDPOINT"
# If we just removed the leader, fall back to any reachable endpoint
if ! DANUBE_ADMIN_ENDPOINT="$VERIFY_ENDPOINT" "$ADMIN_BIN" cluster status 2>/dev/null; then
  for port in 50051 50052 50053; do
    if DANUBE_ADMIN_ENDPOINT="http://127.0.0.1:$port" "$ADMIN_BIN" cluster status 2>/dev/null; then
      VERIFY_ENDPOINT="http://127.0.0.1:$port"
      break
    fi
  done
fi

DANUBE_ADMIN_ENDPOINT="$VERIFY_ENDPOINT" "$ADMIN_BIN" cluster status
echo ""
DANUBE_ADMIN_ENDPOINT="$VERIFY_ENDPOINT" "$ADMIN_BIN" brokers list
echo ""
DANUBE_ADMIN_ENDPOINT="$VERIFY_ENDPOINT" "$ADMIN_BIN" topics list --namespace default

echo ""
echo "✅ Scale down complete. Broker $NODE_ID removed."
echo ""
echo "Note: Topics previously on the removed broker may show as 'unassigned'"
echo "until they are accessed by a client (Danube uses lazy topic assignment)."
