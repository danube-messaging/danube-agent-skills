#!/usr/bin/env bash
# =============================================================================
# Cluster Health Check — Run comprehensive cluster diagnostics
#
# Checks: Raft status, broker states, load balance, topic distribution,
#         and scans broker logs for errors.
#
# Usage:
#   ./scripts/cluster_health_check.sh [ADMIN_ENDPOINT] [LOG_DIR]
#
# Example:
#   ./scripts/cluster_health_check.sh http://127.0.0.1:50051 $TEST_RUN/logs
# =============================================================================
set -euo pipefail

ADMIN_ENDPOINT="${1:-http://127.0.0.1:50051}"
LOG_DIR="${2:-}"

export DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT"

# Try to find danube-admin in PATH or common locations
ADMIN_BIN="${DANUBE_ADMIN_BIN:-danube-admin}"

echo "========================================="
echo "  Danube Cluster Health Check"
echo "========================================="
echo "  Admin endpoint: $ADMIN_ENDPOINT"
echo ""

PASS=true

# 1. Raft cluster status
echo "=== 1. Raft Cluster Status ==="
if CLUSTER_STATUS=$("$ADMIN_BIN" cluster status 2>&1); then
  echo "$CLUSTER_STATUS"
  VOTER_COUNT=$(echo "$CLUSTER_STATUS" | grep -o 'Voters:.*' | grep -oP '\d+' | wc -l || echo "0")
  echo ""
  echo "  Voters: $VOTER_COUNT"
  if [ "$VOTER_COUNT" -ge 3 ]; then
    echo "  ✅ Healthy: $VOTER_COUNT voters"
  else
    echo "  ⚠ Warning: only $VOTER_COUNT voters"
  fi
else
  echo "  ❌ FAIL: Cannot reach cluster"
  PASS=false
fi

echo ""

# 2. Broker states
echo "=== 2. Broker States ==="
if BROKERS=$("$ADMIN_BIN" brokers list --output json 2>&1); then
  echo "$BROKERS" | jq -r '.[] | "  Broker \(.broker_id): \(.broker_status)"' 2>/dev/null || echo "$BROKERS"
  INACTIVE=$(echo "$BROKERS" | jq '[.[] | select(.broker_status != "active")] | length' 2>/dev/null || echo "0")
  if [ "$INACTIVE" -eq 0 ]; then
    echo "  ✅ All brokers active"
  else
    echo "  ⚠ $INACTIVE broker(s) not active"
  fi
else
  echo "  ❌ FAIL: Cannot list brokers"
  PASS=false
fi

echo ""

# 3. Load balance
echo "=== 3. Load Balance ==="
if BALANCE=$("$ADMIN_BIN" brokers balance --output json 2>&1); then
  CV=$(echo "$BALANCE" | jq -r '.coefficient_of_variation' 2>/dev/null || echo "N/A")
  echo "  Coefficient of Variation: $CV"
  echo "$BALANCE" | jq -r '.brokers[] | "  Broker \(.broker_id): \(.topic_count) topics"' 2>/dev/null || true
  if [ "$CV" != "N/A" ] && (( $(echo "$CV < 0.30" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ✅ Balanced (CV=$CV)"
  else
    echo "  ⚠ Imbalanced or unable to determine (CV=$CV)"
  fi
else
  echo "  ❌ FAIL: Cannot check balance"
  PASS=false
fi

echo ""

# 4. Topics
echo "=== 4. Topic Distribution ==="
if TOPICS=$("$ADMIN_BIN" topics list --namespace default --output json 2>&1); then
  TOPIC_COUNT=$(echo "$TOPICS" | jq 'length' 2>/dev/null || echo "0")
  echo "  Total topics in /default: $TOPIC_COUNT"
  if [ "$TOPIC_COUNT" -gt 0 ]; then
    echo "  ✅ Topics present"
  else
    echo "  ℹ No topics in /default namespace"
  fi
else
  echo "  ❌ FAIL: Cannot list topics"
  PASS=false
fi

echo ""

# 5. Log errors (if log directory provided)
if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
  echo "=== 5. Recent Log Errors ==="
  ERROR_COUNT=0
  for log in "$LOG_DIR"/broker_*.log; do
    if [ -f "$log" ]; then
      ERRORS=$(grep -ciE "error|panic|fatal" "$log" 2>/dev/null || echo "0")
      if [ "$ERRORS" -gt 0 ]; then
        echo "  ⚠ $(basename "$log"): $ERRORS error lines"
        grep -iE "error|panic|fatal" "$log" | tail -3 | sed 's/^/    /'
        ERROR_COUNT=$((ERROR_COUNT + ERRORS))
      else
        echo "  ✅ $(basename "$log"): no errors"
      fi
    fi
  done
  if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "  ✅ No errors in logs"
  fi
else
  echo "=== 5. Log Errors: skipped (no LOG_DIR provided) ==="
fi

echo ""
echo "========================================="
if [ "$PASS" = true ]; then
  echo "  ✅ Cluster health: HEALTHY"
else
  echo "  ❌ Cluster health: ISSUES DETECTED"
fi
echo "========================================="
