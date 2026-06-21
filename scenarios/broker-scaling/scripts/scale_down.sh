#!/usr/bin/env bash
# =============================================================================
# Scale Down Helper — Remove a broker from a Danube cluster
#
# Automates: unload topics → remove from Raft → stop process
#
# Usage:
#   ./scripts/scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]
#
# Example:
#   ./scripts/scale_down.sh ./bin/v0.15.0/danube-admin 4 $TEST_RUN/broker_4.pid http://127.0.0.1:50051
#
# IMPORTANT: Always remove from Raft BEFORE stopping the process to avoid quorum loss.
# =============================================================================
set -euo pipefail

ADMIN_BIN="${1:?Usage: scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]}"
NODE_ID="${2:?Usage: scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]}"
PID_FILE="${3:?Usage: scale_down.sh <ADMIN_BIN> <NODE_ID> <PID_FILE> [ADMIN_ENDPOINT]}"
ADMIN_ENDPOINT="${4:-http://127.0.0.1:50051}"

echo "=== Scale Down: Removing broker $NODE_ID ==="

# Step 1: Unload all topics
echo "[1/3] Unloading all topics from broker $NODE_ID..."
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers unload --broker-id "$NODE_ID" --dry-run || true
echo ""
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers unload --broker-id "$NODE_ID"

echo "  Waiting for topic migration..."
sleep 5

# Step 2: Remove from Raft
echo "[2/3] Removing from Raft cluster..."
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" cluster remove-node --node-id "$NODE_ID"
echo "  ✅ Removed from Raft membership."
sleep 2

# Step 3: Stop the process
echo "[3/3] Stopping broker process..."
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || echo "  Process already stopped."
  sleep 2
  kill -9 "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "  ✅ Broker process stopped."
else
  echo "  ⚠ PID file not found: $PID_FILE"
fi

# Verify
echo ""
echo "=== Verification ==="
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" cluster status
echo ""
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers balance

echo ""
echo "✅ Scale down complete. Broker $NODE_ID removed."
