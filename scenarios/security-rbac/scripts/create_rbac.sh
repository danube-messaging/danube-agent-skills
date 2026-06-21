#!/usr/bin/env bash
# =============================================================================
# Create RBAC — Set up standard roles and bindings for testing
#
# Usage:
#   ./scripts/create_rbac.sh <SECRET_KEY> [ADMIN_ENDPOINT]
#
# Example:
#   ./scripts/create_rbac.sh "test-secret-key" http://127.0.0.1:50051
#
# Creates:
#   - Roles: producer, consumer, operator
#   - Service account tokens: payments-producer, analytics-consumer
#   - Bindings: bind to /default namespace
# =============================================================================
set -euo pipefail

SECRET_KEY="${1:?Usage: create_rbac.sh <SECRET_KEY> [ADMIN_ENDPOINT]}"
ADMIN_ENDPOINT="${2:-http://127.0.0.1:50051}"

export DANUBE_ADMIN_ENDPOINT="$ADMIN_ENDPOINT"

# Try to find danube-admin in PATH or common locations
ADMIN_BIN="${DANUBE_ADMIN_BIN:-danube-admin}"

echo "=== Creating RBAC Roles & Bindings ==="
echo "  Admin endpoint: $ADMIN_ENDPOINT"
echo ""

# Step 1: Create roles
echo "[1/3] Creating roles..."

"$ADMIN_BIN" security roles create producer \
  --permissions Produce,Lookup
echo "  ✅ Role 'producer': Produce, Lookup"

"$ADMIN_BIN" security roles create consumer \
  --permissions Consume,Lookup
echo "  ✅ Role 'consumer': Consume, Lookup"

"$ADMIN_BIN" security roles create operator \
  --permissions ManageNamespace,ManageTopic,ManageSchema,Lookup
echo "  ✅ Role 'operator': ManageNamespace, ManageTopic, ManageSchema, Lookup"

# Step 2: Create service account tokens
echo ""
echo "[2/3] Creating service account tokens..."

PRODUCER_TOKEN=$("$ADMIN_BIN" security tokens create \
  --subject payments-producer --secret-key "$SECRET_KEY")
echo "  ✅ Token 'payments-producer': ${PRODUCER_TOKEN:0:40}..."

CONSUMER_TOKEN=$("$ADMIN_BIN" security tokens create \
  --subject analytics-consumer --secret-key "$SECRET_KEY")
echo "  ✅ Token 'analytics-consumer': ${CONSUMER_TOKEN:0:40}..."

UNAUTHORIZED_TOKEN=$("$ADMIN_BIN" security tokens create \
  --subject unauthorized-user --secret-key "$SECRET_KEY")
echo "  ✅ Token 'unauthorized-user': ${UNAUTHORIZED_TOKEN:0:40}..."

# Step 3: Create bindings
echo ""
echo "[3/3] Creating bindings..."

"$ADMIN_BIN" security bindings create bind-payments-producer \
  --principal-type service_account \
  --principal-name payments-producer \
  --roles producer \
  --scope namespace \
  --resource /default
echo "  ✅ Binding: payments-producer → producer role → /default namespace"

"$ADMIN_BIN" security bindings create bind-analytics-consumer \
  --principal-type service_account \
  --principal-name analytics-consumer \
  --roles consumer \
  --scope namespace \
  --resource /default
echo "  ✅ Binding: analytics-consumer → consumer role → /default namespace"

# No binding for unauthorized-user — used to test PermissionDenied

# Save tokens for test scripts
echo ""
echo "=== Tokens ==="
echo "  export PRODUCER_TOKEN=\"$PRODUCER_TOKEN\""
echo "  export CONSUMER_TOKEN=\"$CONSUMER_TOKEN\""
echo "  export UNAUTHORIZED_TOKEN=\"$UNAUTHORIZED_TOKEN\""

echo ""
echo "✅ RBAC setup complete."
echo ""
echo "Test expectations:"
echo "  - payments-producer + PRODUCER_TOKEN → can Produce to /default/*"
echo "  - analytics-consumer + CONSUMER_TOKEN → can Consume from /default/*"
echo "  - unauthorized-user + UNAUTHORIZED_TOKEN → PermissionDenied on everything"
