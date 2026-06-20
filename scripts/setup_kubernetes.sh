#!/usr/bin/env bash
# ============================================================================
# setup_kubernetes.sh — Deploy Danube to Kubernetes via Helm
#
# Usage:
#   ./scripts/setup_kubernetes.sh              # Deploy Danube
#   ./scripts/setup_kubernetes.sh cleanup      # Remove Danube from the cluster
#
# Prerequisites:
#   - kubectl connected to a running Kubernetes cluster
#   - helm 3.0+ installed
#
# What it does (deploy):
#   1. Validates prerequisites (kubectl, helm, cluster access)
#   2. Adds the Danube Helm repo
#   3. Creates the 'danube' namespace
#   4. Creates a ConfigMap from configs/default.yml
#   5. Installs the Envoy proxy chart
#   6. Installs the Danube core chart (3 brokers + Prometheus)
#   7. Waits for all pods to be ready
#   8. Port-forwards admin API and verifies cluster health
#   9. Prints a summary
# ============================================================================
set -euo pipefail

ACTION="${1:-deploy}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="danube"
HELM_REPO_NAME="danube"
HELM_REPO_URL="https://danube-messaging.github.io/danube_helm"

# ── Cleanup mode — delegate to cleanup.sh ───────────────────────────────────
if [[ "$ACTION" == "cleanup" ]]; then
  exec "$SCRIPT_DIR/cleanup.sh" k8s
fi

# ── Deploy mode ─────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  Danube Kubernetes Setup"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Find danube-admin binary for verification
DANUBE_ADMIN=""
for candidate in bin/*/danube-admin; do
  if [[ -x "$candidate" ]]; then
    DANUBE_ADMIN="$candidate"
    break
  fi
done

# ── Step 1: Check prerequisites ────────────────────────────────────────────
echo "▸ Step 1: Checking prerequisites..."
which kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found."; exit 1; }
which helm >/dev/null 2>&1 || { echo "ERROR: helm not found."; exit 1; }

# Verify cluster access
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Kubernetes cluster."
  echo "Ensure a cluster is running and kubectl is configured."
  exit 1
fi

echo "  ✓ kubectl $(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | head -1 || echo "found")"
echo "  ✓ helm $(helm version --short 2>/dev/null)"
echo "  ✓ Cluster accessible"

# Check if namespace already exists
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ⚠ Namespace '$NAMESPACE' already exists. Run '$0 cleanup' first."
  exit 1
fi

# ── Step 2: Add Helm repo ──────────────────────────────────────────────────
echo ""
echo "▸ Step 2: Adding Danube Helm repository..."
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" 2>/dev/null || true
helm repo update >/dev/null 2>&1
echo "  ✓ Helm repo '$HELM_REPO_NAME' ready"
helm search repo danube --output table 2>/dev/null | head -10

# ── Step 3: Create namespace ───────────────────────────────────────────────
echo ""
echo "▸ Step 3: Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE"
echo "  ✓ Namespace created"

# ── Step 4: Create ConfigMap ───────────────────────────────────────────────
echo ""
echo "▸ Step 4: Creating broker ConfigMap..."
kubectl create configmap danube-broker-config \
  --from-file=danube_broker.yml=configs/default.yml \
  -n "$NAMESPACE"
echo "  ✓ ConfigMap 'danube-broker-config' created"

# ── Step 5: Install Envoy proxy ────────────────────────────────────────────
echo ""
echo "▸ Step 5: Installing Envoy proxy..."
helm install danube-envoy "$HELM_REPO_NAME/danube-envoy" -n "$NAMESPACE"

echo "  Waiting for Envoy pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=danube-envoy \
  -n "$NAMESPACE" --timeout=120s 2>/dev/null || {
  echo "  ⚠ Envoy pod not ready after 120s. Continuing anyway..."
}
echo "  ✓ Envoy proxy installed"

# ── Step 6: Install Danube core ────────────────────────────────────────────
echo ""
echo "▸ Step 6: Installing Danube core (3 brokers + Prometheus)..."
helm install danube-core "$HELM_REPO_NAME/danube-core" -n "$NAMESPACE" \
  --set broker.image.tag=latest \
  --set broker.externalAccess.enabled=true
echo "  Waiting for broker pods to be ready (up to 5 minutes)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=danube-core \
  -n "$NAMESPACE" --timeout=300s 2>/dev/null || {
  echo "  ⚠ Not all broker pods ready after 300s."
  echo "  Check: kubectl get pods -n $NAMESPACE"
}

# ── Step 7: Show pod status ───────────────────────────────────────────────
echo ""
echo "▸ Step 7: Pod status..."
kubectl get pods -n "$NAMESPACE" -o wide

# ── Step 8: Verify cluster health ──────────────────────────────────────────
echo ""
echo "▸ Step 8: Verifying cluster health..."

if [[ -n "$DANUBE_ADMIN" ]]; then
  # Start port-forward in background
  kubectl port-forward danube-core-broker-0 50051:50051 -n "$NAMESPACE" >/dev/null 2>&1 &
  PF_PID=$!
  sleep 3

  echo ""
  echo "── brokers list ──"
  "$DANUBE_ADMIN" brokers list || true

  echo ""
  echo "── cluster status ──"
  "$DANUBE_ADMIN" cluster status || true

  # Cleanup port-forward
  kill $PF_PID 2>/dev/null || true
  wait $PF_PID 2>/dev/null || true
else
  echo "  ⚠ danube-admin not found — skipping cluster verification"
  echo "  Download it with: ./scripts/setup_local_binary.sh standalone <version>"
  echo "  Then verify manually:"
  echo "    kubectl port-forward danube-core-broker-0 50051:50051 -n $NAMESPACE &"
  echo "    danube-admin brokers list"
fi

# ── Step 9: Check logs for errors ──────────────────────────────────────────
echo ""
echo "▸ Step 9: Scanning broker logs for errors..."
ERRORS=""
for i in 0 1 2; do
  POD_ERRORS=$(kubectl logs "danube-core-broker-$i" -n "$NAMESPACE" 2>/dev/null | grep -i "ERROR\|PANIC\|FATAL" | grep -v "transport error" || true)
  if [ -n "$POD_ERRORS" ]; then
    ERRORS="${ERRORS}broker-$i: $POD_ERRORS\n"
  fi
done

if [ -n "$ERRORS" ]; then
  echo "  ⚠ Found errors in logs:"
  echo -e "$ERRORS" | head -10
else
  echo "  ✓ No errors found in broker logs"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Setup complete — Danube on Kubernetes"
echo "═══════════════════════════════════════════════════════════"
echo "  Namespace:    $NAMESPACE"
echo ""
echo "  Pods:"
kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | sed 's/^/    /'
echo ""
echo "  Admin access (port-forward):"
echo "    kubectl port-forward danube-core-broker-0 50051:50051 -n $NAMESPACE &"
echo "    danube-admin brokers list"
echo ""
echo "  Prometheus access:"
echo "    kubectl port-forward svc/danube-core-prometheus 9090:9090 -n $NAMESPACE &"
echo "    # Open http://localhost:9090"
echo ""
echo "  To clean up:"
echo "    ./scripts/cleanup.sh k8s"
echo ""
