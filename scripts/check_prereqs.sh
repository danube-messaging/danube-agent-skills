#!/usr/bin/env bash
# ============================================================================
# check_prereqs.sh — Verify prerequisites for Danube setup
#
# Usage:
#   ./scripts/check_prereqs.sh [binary|source|docker|k8s]
#
# Checks required tools, port availability, and existing processes.
# Exits 0 if all checks pass, 1 if any fail.
# ============================================================================
set -euo pipefail

METHOD="${1:-binary}"

echo "═══════════════════════════════════════════════════════════"
echo "  Danube Prerequisites Check — ${METHOD} setup"
echo "═══════════════════════════════════════════════════════════"
echo ""

ERRORS=0

# ── Common: Check for existing Danube processes ─────────────────────────────
echo "▸ Checking for existing Danube processes..."
EXISTING=$(pgrep -la danube-broker 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo "  ⚠ Danube brokers already running:"
  echo "$EXISTING" | sed 's/^/    /'
  echo "  → Run './scripts/cleanup.sh binary' to stop them first"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ No existing brokers"
fi

# ── Common: Check port availability ─────────────────────────────────────────
echo "▸ Checking port availability..."
PORTS_IN_USE=""
for port in 6650 6651 6652 50051 50052 50053 7650 7651 7652; do
  if ss -lntp 2>/dev/null | grep -q ":${port} "; then
    PORTS_IN_USE="${PORTS_IN_USE} ${port}"
  fi
done

if [ -n "$PORTS_IN_USE" ]; then
  echo "  ⚠ Ports in use:${PORTS_IN_USE}"
  echo "  → Run './scripts/cleanup.sh binary' or stop the processes using these ports"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ All ports available"
fi

# ── Method-specific checks ──────────────────────────────────────────────────
case "$METHOD" in
  binary)
    echo "▸ Checking tools for local binary setup..."
    for tool in curl tar; do
      if command -v "$tool" &>/dev/null; then
        echo "  ✓ $tool found"
      else
        echo "  ✗ $tool not found — required for downloading binaries"
        ERRORS=$((ERRORS + 1))
      fi
    done
    ;;

  source)
    echo "▸ Checking tools for local source setup..."
    for tool in cargo rustc make; do
      if command -v "$tool" &>/dev/null; then
        echo "  ✓ $tool found ($(command -v "$tool"))"
      else
        echo "  ✗ $tool not found — required for building from source"
        ERRORS=$((ERRORS + 1))
      fi
    done
    if [ ! -d "../danube" ] && [ ! -d "../../danube" ]; then
      echo "  ⚠ Danube source repo not found at ../danube or ../../danube"
      echo "    → Clone it: git clone https://github.com/danube-messaging/danube.git"
      ERRORS=$((ERRORS + 1))
    else
      echo "  ✓ Danube source repo found"
    fi
    ;;

  docker)
    echo "▸ Checking tools for Docker Compose setup..."
    if command -v docker &>/dev/null; then
      echo "  ✓ docker found ($(docker --version 2>/dev/null | head -1))"
    else
      echo "  ✗ docker not found"
      ERRORS=$((ERRORS + 1))
    fi
    if docker compose version &>/dev/null; then
      echo "  ✓ docker compose found ($(docker compose version 2>/dev/null | head -1))"
    else
      echo "  ✗ docker compose not found"
      ERRORS=$((ERRORS + 1))
    fi
    # Check for existing Danube containers
    CONTAINERS=$(docker ps --filter "name=danube" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$CONTAINERS" ]; then
      echo "  ⚠ Existing Danube containers:"
      echo "$CONTAINERS" | sed 's/^/    /'
      echo "  → Run './scripts/cleanup.sh docker' to stop them"
      ERRORS=$((ERRORS + 1))
    fi
    ;;

  k8s)
    echo "▸ Checking tools for Kubernetes setup..."
    for tool in kubectl helm; do
      if command -v "$tool" &>/dev/null; then
        echo "  ✓ $tool found"
      else
        echo "  ✗ $tool not found"
        ERRORS=$((ERRORS + 1))
      fi
    done
    if kubectl cluster-info &>/dev/null; then
      echo "  ✓ Kubernetes cluster reachable"
    else
      echo "  ✗ Cannot connect to Kubernetes cluster"
      ERRORS=$((ERRORS + 1))
    fi
    ;;

  *)
    echo "Usage: $0 <binary|source|docker|k8s>"
    exit 1
    ;;
esac

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "✅ All prerequisites met — ready to set up"
  exit 0
else
  echo "❌ $ERRORS issue(s) found — fix them before running setup"
  exit 1
fi
