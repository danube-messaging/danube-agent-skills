#!/usr/bin/env bash
# =============================================================================
# Scale Up Helper — Add a new broker to an existing Danube cluster
#
# Automates: start broker with --join → add as learner → promote to voter →
#            activate → rebalance existing topics
#
# Usage:
#   ./scripts/scale_up.sh <BROKER_BINARY> <CONFIG_FILE> <DATA_DIR> [ADMIN_ENDPOINT]
#
# Example:
#   ./scripts/scale_up.sh ./bin/v0.15.0/danube-broker $TEST_RUN/danube_broker.yml $TEST_RUN/data http://127.0.0.1:50051
#
# The new broker uses port allocation index 3:
#   broker=6653, admin=50054, raft=7653, prom=9043
# =============================================================================
set -euo pipefail

BROKER_BIN="${1:?Usage: scale_up.sh <BROKER_BINARY> <CONFIG_FILE> <DATA_DIR> [ADMIN_ENDPOINT]}"
CONFIG_FILE="${2:?Usage: scale_up.sh <BROKER_BINARY> <CONFIG_FILE> <DATA_DIR> [ADMIN_ENDPOINT]}"
DATA_DIR="${3:?Usage: scale_up.sh <BROKER_BINARY> <CONFIG_FILE> <DATA_DIR> [ADMIN_ENDPOINT]}"
ADMIN_ENDPOINT="${4:-http://127.0.0.1:50051}"

ADMIN_BIN="$(dirname "$BROKER_BIN")/danube-admin"

# New broker ports (index 3)
NEW_BROKER_PORT=6653
NEW_ADMIN_PORT=50054
NEW_RAFT_PORT=7653
NEW_PROM_PORT=9043
NEW_DATA_DIR="${DATA_DIR}/raft-4"

echo "=== Scale Up: Adding broker at ports $NEW_BROKER_PORT/$NEW_ADMIN_PORT ==="

# Step 1: Start new broker with --join
echo "[1/5] Starting new broker with --join..."
mkdir -p "$NEW_DATA_DIR"
nohup "$BROKER_BIN" \
  --config-file "$CONFIG_FILE" \
  --broker-addr "0.0.0.0:${NEW_BROKER_PORT}" \
  --admin-addr "0.0.0.0:${NEW_ADMIN_PORT}" \
  --raft-addr "0.0.0.0:${NEW_RAFT_PORT}" \
  --data-dir "$NEW_DATA_DIR" \
  --prom-exporter "0.0.0.0:${NEW_PROM_PORT}" \
  --join \
  > "${DATA_DIR}/../logs/broker_${NEW_BROKER_PORT}.log" 2>&1 &
echo $! > "${DATA_DIR}/../broker_4.pid"

# Wait for admin port
for i in $(seq 1 20); do
  if nc -zv 127.0.0.1 "$NEW_ADMIN_PORT" 2>/dev/null; then
    echo "  ✅ New broker admin port $NEW_ADMIN_PORT is ready."
    break
  elif [ "$i" -eq 20 ]; then
    echo "  ❌ New broker admin port failed to start."
    exit 1
  fi
  sleep 3
done

# Step 2: Add as learner
echo "[2/5] Adding as Raft learner..."
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" cluster add-node \
  --node-addr "http://127.0.0.1:${NEW_ADMIN_PORT}"
sleep 2

# Step 3: Discover node_id
echo "[3/5] Discovering node_id..."
NODE_ID=$(DANUBE_ADMIN_ENDPOINT="http://127.0.0.1:${NEW_ADMIN_PORT}" \
  "$ADMIN_BIN" cluster status 2>&1 | grep 'Self Node ID' | awk '{print $NF}')
echo "  Node ID: $NODE_ID"

# Step 4: Promote to voter
echo "[4/5] Promoting to voter..."
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" cluster promote-node --node-id "$NODE_ID"

# Wait for broker port (starts after joining cluster)
for i in $(seq 1 15); do
  if nc -zv 127.0.0.1 "$NEW_BROKER_PORT" 2>/dev/null; then
    echo "  ✅ New broker port $NEW_BROKER_PORT is ready."
    break
  elif [ "$i" -eq 15 ]; then
    echo "  ❌ New broker port failed to start after joining."
    exit 1
  fi
  sleep 3
done

# Step 5: Activate
echo "[5/5] Activating broker..."
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers activate \
  --broker-id "$NODE_ID" --reason "scale-up"

sleep 3

# Rebalance
echo ""
echo "=== Rebalancing topics to include new broker ==="
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers rebalance

sleep 5

# Verify
echo ""
echo "=== Verification ==="
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" cluster status
echo ""
DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT" "$ADMIN_BIN" brokers balance

echo ""
echo "✅ Scale up complete. Broker $NODE_ID is active and receiving topics."
