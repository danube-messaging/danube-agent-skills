#!/usr/bin/env bash
# ============================================================================
# cleanup.sh — Clean up Danube test environments
#
# Usage:
#   ./scripts/cleanup.sh binary        # Stop local binary broker processes
#   ./scripts/cleanup.sh source        # Stop source-built broker processes
#   ./scripts/cleanup.sh docker        # Stop Docker Compose services
#   ./scripts/cleanup.sh k8s           # Remove Kubernetes deployment
#   ./scripts/cleanup.sh all           # All of the above + remove test-run dirs
#
# Each command cleans up only the resources from the specified setup.
# Use 'all' for a full reset of everything.
# ============================================================================
set -euo pipefail

ACTION="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ── Helper functions ────────────────────────────────────────────────────────

cleanup_local_processes() {
  echo ""
  echo "▸ Stopping local danube-broker processes..."
  PIDS=$(pgrep -la danube-broker 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "$PIDS" | sed 's/^/  Killing: /'
    pkill -f danube-broker 2>/dev/null || true
    sleep 2
    # Force-kill if needed
    REMAINING=$(pgrep -la danube-broker 2>/dev/null || true)
    if [ -n "$REMAINING" ]; then
      echo "  ⚠ Force-killing remaining processes..."
      pkill -9 -f danube-broker 2>/dev/null || true
    fi
    echo "  ✓ All broker processes stopped"
  else
    echo "  No local broker processes found"
  fi
}

cleanup_docker() {
  echo ""
  echo "▸ Stopping Docker Compose services..."
  COMPOSE_FOUND=false
  for dir in runs/*/; do
    if [ -f "$dir/docker-compose.yml" ]; then
      COMPOSE_FOUND=true
      echo "  Stopping: $dir"
      (cd "$dir" && docker compose down -v 2>/dev/null) || true
    fi
  done
  if [ "$COMPOSE_FOUND" = false ]; then
    echo "  No Docker Compose test runs found"
  fi

  echo ""
  echo "▸ Cleaning orphaned Docker resources..."
  DANUBE_CONTAINERS=$(docker ps -a --filter "name=danube" --format "{{.Names}}" 2>/dev/null || true)
  if [ -n "$DANUBE_CONTAINERS" ]; then
    echo "$DANUBE_CONTAINERS" | while read -r name; do
      echo "  Removing container: $name"
      docker rm -f "$name" 2>/dev/null || true
    done
  else
    echo "  No orphaned containers found"
  fi

  DANUBE_NETWORKS=$(docker network ls --filter "name=danube" --format "{{.Name}}" 2>/dev/null || true)
  if [ -n "$DANUBE_NETWORKS" ]; then
    echo "$DANUBE_NETWORKS" | while read -r name; do
      echo "  Removing network: $name"
      docker network rm "$name" 2>/dev/null || true
    done
  fi
}

cleanup_k8s() {
  echo ""
  echo "▸ Stopping Kubernetes port-forward processes..."
  pkill -f "kubectl port-forward.*danube" 2>/dev/null || true
  echo "  ✓ Port-forwards stopped"

  echo ""
  echo "▸ Uninstalling Helm releases..."
  helm uninstall danube-core -n danube 2>/dev/null || true
  helm uninstall danube-envoy -n danube 2>/dev/null || true
  echo "  ✓ Helm releases removed"

  echo ""
  echo "▸ Deleting Kubernetes namespace..."
  kubectl delete namespace danube --timeout=60s 2>/dev/null || true
  echo "  ✓ Namespace deleted"
}

cleanup_runs() {
  echo ""
  echo "▸ Removing test-run directories..."
  if [ -d "runs" ]; then
    rm -rf runs/test_*
    echo "  ✓ All test-run directories removed"
  else
    echo "  No runs/ directory found"
  fi
}

verify_clean() {
  echo ""
  echo "▸ Final check..."
  BROKER_PROCS=$(pgrep -la danube-broker 2>/dev/null || true)
  DOCKER_PROCS=$(docker ps --filter "name=danube" --format "{{.Names}}" 2>/dev/null || true)
  K8S_PODS=$(kubectl get pods -n danube --no-headers 2>/dev/null || true)

  ALL_CLEAN=true
  [ -n "$BROKER_PROCS" ] && echo "  ⚠ Still running: $BROKER_PROCS" && ALL_CLEAN=false
  [ -n "$DOCKER_PROCS" ] && echo "  ⚠ Docker still running: $DOCKER_PROCS" && ALL_CLEAN=false
  [ -n "$K8S_PODS" ] && echo "  ⚠ K8s pods still running:" && echo "$K8S_PODS" | sed 's/^/    /' && ALL_CLEAN=false

  if [ "$ALL_CLEAN" = true ]; then
    echo "  ✅ Cleanup complete"
  fi
  echo ""
}

show_usage() {
  echo "Usage: $0 <command>"
  echo ""
  echo "Commands:"
  echo "  binary    Stop local binary broker processes"
  echo "  source    Stop source-built broker processes"
  echo "  docker    Stop Docker Compose services and containers"
  echo "  k8s       Remove Kubernetes deployment (Helm + namespace)"
  echo "  all       All of the above + remove test-run directories"
  echo ""
  exit 1
}

# ── Main ────────────────────────────────────────────────────────────────────

case "$ACTION" in
  binary)
    echo "═══════════════════════════════════════════════════════════"
    echo "  Danube Cleanup — Local Binary"
    echo "═══════════════════════════════════════════════════════════"
    cleanup_local_processes
    verify_clean
    ;;

  source)
    echo "═══════════════════════════════════════════════════════════"
    echo "  Danube Cleanup — Local Source"
    echo "═══════════════════════════════════════════════════════════"
    cleanup_local_processes
    verify_clean
    ;;

  docker)
    echo "═══════════════════════════════════════════════════════════"
    echo "  Danube Cleanup — Docker Compose"
    echo "═══════════════════════════════════════════════════════════"
    cleanup_docker
    verify_clean
    ;;

  k8s)
    echo "═══════════════════════════════════════════════════════════"
    echo "  Danube Cleanup — Kubernetes"
    echo "═══════════════════════════════════════════════════════════"
    cleanup_k8s
    verify_clean
    ;;

  all)
    echo "═══════════════════════════════════════════════════════════"
    echo "  Danube Cleanup — All"
    echo "═══════════════════════════════════════════════════════════"
    cleanup_local_processes
    cleanup_docker
    cleanup_k8s
    cleanup_runs
    verify_clean
    ;;

  *)
    show_usage
    ;;
esac
