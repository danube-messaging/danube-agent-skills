#!/usr/bin/env bash
# ============================================================================
# cleanup.sh — Stop all Danube processes and containers
#
# Usage:
#   ./scripts/cleanup.sh              # Stop everything
#   ./scripts/cleanup.sh --all        # Stop everything AND remove test-run dirs
#
# What it does:
#   1. Kills all local danube-broker processes
#   2. Stops all Docker Compose Danube services (in any runs/ directory)
#   3. Removes orphaned Docker containers/networks
#   4. Optionally removes test-run directories
# ============================================================================
set -euo pipefail

REMOVE_RUNS="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "═══════════════════════════════════════════════════════════"
echo "  Danube Cleanup"
echo "═══════════════════════════════════════════════════════════"

# ── Step 1: Kill local broker processes ─────────────────────────────────────
echo ""
echo "▸ Step 1: Stopping local danube-broker processes..."
PIDS=$(pgrep -la danube-broker 2>/dev/null || true)
if [ -n "$PIDS" ]; then
  echo "$PIDS" | sed 's/^/  Killing: /'
  pkill -f danube-broker 2>/dev/null || true
  sleep 2
  # Verify
  REMAINING=$(pgrep -la danube-broker 2>/dev/null || true)
  if [ -n "$REMAINING" ]; then
    echo "  ⚠ Force-killing remaining processes..."
    pkill -9 -f danube-broker 2>/dev/null || true
  fi
  echo "  ✓ All broker processes stopped"
else
  echo "  No local broker processes found"
fi

# ── Step 2: Stop Docker Compose services ────────────────────────────────────
echo ""
echo "▸ Step 2: Stopping Docker Compose services..."
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

# ── Step 3: Clean orphaned Docker resources ─────────────────────────────────
echo ""
echo "▸ Step 3: Cleaning orphaned Docker resources..."
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

# ── Step 4: Optionally remove test-run directories ──────────────────────────
if [[ "$REMOVE_RUNS" == "--all" ]]; then
  echo ""
  echo "▸ Step 4: Removing test-run directories..."
  if [ -d "runs" ]; then
    rm -rf runs/test_*
    echo "  ✓ All test-run directories removed"
  else
    echo "  No runs/ directory found"
  fi
fi

# ── Verify ──────────────────────────────────────────────────────────────────
echo ""
echo "▸ Final check..."
BROKER_PROCS=$(pgrep -la danube-broker 2>/dev/null || true)
DOCKER_PROCS=$(docker ps --filter "name=danube" --format "{{.Names}}" 2>/dev/null || true)

if [ -z "$BROKER_PROCS" ] && [ -z "$DOCKER_PROCS" ]; then
  echo "  ✅ All Danube processes and containers cleaned up"
else
  [ -n "$BROKER_PROCS" ] && echo "  ⚠ Still running: $BROKER_PROCS"
  [ -n "$DOCKER_PROCS" ] && echo "  ⚠ Still running: $DOCKER_PROCS"
fi
echo ""
